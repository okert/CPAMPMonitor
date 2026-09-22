import AppKit
import SwiftUI
import UserNotifications
import ServiceManagement
import MonitorCore

struct AccountState: Identifiable {
    var id: String { account.id }
    var account: Account
    var windows: [QuotaWindow] = []
    var plan = ""
    var error: String?
    var history: [String: Any] = [:]
    var retryAfter: Date?
    var enabled = true
    var fetched: Date?
}

struct DisplayWindowChoice: Identifiable, Hashable {
    let id: String
    let title: String
}

@MainActor final class MonitorModel: ObservableObject {
    @Published var config = Storage.load(Configuration.self, key: "configuration") ?? Configuration()
    @Published var accounts: [AccountState] = []
    @Published var refreshing = false
    @Published var error: String?
    @Published var historyError: String?
    @Published var lastRefresh: Date?
    @Published var nextRefresh: Date?
    @Published var notificationStatus = "未授权"
    @Published var notificationMessage: String?
    @Published var paused = false
    @Published var now = Date()
    var onChange: (() -> Void)?
    var openSettings: (() -> Void)?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var task: Task<Void, Never>?
    let tunnel = Tunnel()
    private var ledger = Storage.load(AlertLedger.self, key: "alerts") ?? AlertLedger()
    var maxAge: TimeInterval { Double(config.interval * 2 + 60) }
    var configured: Bool { !config.baseURL.isEmpty }
    var freshWindows: [QuotaWindow] {
        guard !paused, error == nil else { return [] }
        return accounts.filter { $0.enabled && $0.error == nil }.flatMap(\.windows).filter { $0.fresh(now: now, maxAge: maxAge) }
    }
    var lowest: Double? { QuotaWindow.minimumFreshRemaining(freshWindows, now: now, maxAge: maxAge) }
    var displayWindowChoices: [DisplayWindowChoice] {
        let rows = accounts.filter { row in
            config.displayAccountID == nil || row.id == config.displayAccountID
        }
        var seen = Set<String>()
        return rows.flatMap { row in
            row.windows.compactMap { window -> DisplayWindowChoice? in
                guard seen.insert(window.id).inserted else { return nil }
                let title = config.displayAccountID == nil
                    ? "\(row.account.providerName) · \(window.title)" : window.title
                return DisplayWindowChoice(id: window.id, title: title)
            }
        }
    }
    var displayLowest: Double? {
        guard !paused, error == nil else { return nil }
        let rows = accounts.filter { row in
            row.enabled && row.error == nil && (config.displayAccountID == nil || row.id == config.displayAccountID)
        }
        return QuotaWindow.minimumFreshRemaining(rows.flatMap(\.windows), id: config.displayWindowID,
                                                 now: now, maxAge: maxAge)
    }
    var displayAccountLabel: String {
        guard let id = config.displayAccountID else { return "所有账号" }
        return accounts.first(where: { $0.id == id })?.account.title ?? "指定账号"
    }
    var displayWindowLabel: String {
        guard config.displayWindowID != nil else { return "所有额度" }
        return displayWindowChoices.first(where: { $0.id == config.displayWindowID })?.title ?? "指定额度"
    }
    var displayLabel: String { "\(displayAccountLabel) · \(displayWindowLabel)" }
    var hasProblems: Bool {
        error != nil || accounts.contains { $0.enabled && ($0.error != nil || $0.windows.isEmpty || $0.windows.contains { !$0.fresh(now: now, maxAge: maxAge) }) }
    }
    var statusText: String {
        if paused { return "监控已暂停" }
        if refreshing { return "正在刷新" }
        if !configured { return "尚未连接" }
        if error != nil { return "连接失败" }
        if hasProblems { return "部分数据不可用" }
        if let lowest, lowest <= Double(config.critical) { return "额度紧张" }
        if let lowest, lowest <= Double(config.warning) { return "额度偏低" }
        if !accounts.contains(where: \.enabled) { return "无监控账号" }
        return "监控中"
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.now = Date()
                self.onChange?()
                if !self.paused, let next = self.nextRefresh, next <= self.now { self.refresh() }
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.now = Date()
                if !self.paused, self.lastRefresh == nil || Date().timeIntervalSince(self.lastRefresh!) > 30 { self.refresh() }
            }
        }
        Task {
            if configured && config.notifications { await requestNotifications() }
            else { await updateNotificationStatus() }
        }
        refresh()
    }

    func refresh() {
        guard configured, !refreshing, !paused else { return }
        refreshing = true
        onChange?()
        task = Task { await performRefresh() }
    }

    private func orderedAccounts(_ remote: [Account]) -> [Account] {
        guard !config.accountOrder.isEmpty else { return remote }
        let byID = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        let preferred = config.accountOrder.compactMap { byID[$0] }
        let known = Set(preferred.map(\.id))
        return preferred + remote.filter { !known.contains($0.id) }
    }

    private func performRefresh() async {
        defer {
            refreshing = false
            now = Date()
            nextRefresh = now.addingTimeInterval(Double(config.interval))
            onChange?()
        }
        do {
            try await tunnel.prepare(config)
            let secret = try Storage.credential(config.credentialID)
            guard !secret.isEmpty else { throw MonitorError("尚未保存管理密钥，请打开设置。") }
            let client = try APIClient(baseURL: config.baseURL, key: secret)
            let remote = try await client.accounts()
            let old = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            accounts = orderedAccounts(remote).map { account in
                var row = old[account.id] ?? AccountState(account: account)
                row.account = account
                row.enabled = !account.disabled && !config.excluded.contains(account.id)
                return row
            }
            error = nil
            for index in accounts.indices where accounts[index].enabled {
                if let retry = accounts[index].retryAfter, retry > Date() { continue }
                do {
                    let quota = try await client.quota(accounts[index].account)
                    accounts[index].windows = quota.windows
                    accounts[index].plan = quota.plan
                    accounts[index].error = nil
                    accounts[index].retryAfter = nil
                    accounts[index].fetched = Date()
                    await notifyIfNeeded(accounts[index])
                } catch {
                    accounts[index].error = safeMessage(error)
                    if (error as? MonitorError)?.status == 429 {
                        accounts[index].retryAfter = Date().addingTimeInterval(900)
                    }
                }
                now = Date()
                onChange?()
            }
            do {
                let history = try await client.history(remote)
                for index in accounts.indices { accounts[index].history = history[accounts[index].id] ?? [:] }
                historyError = nil
            } catch { historyError = "历史用量暂不可用" }
            lastRefresh = Date()
        } catch { self.error = safeMessage(error) }
    }

    func safeMessage(_ error: Error) -> String {
        if let e = error as? MonitorError { return e.message }
        if let e = error as? URLError {
            return e.code == .timedOut ? "网络请求超时。" : "网络连接失败（\(e.code.rawValue)）。"
        }
        return "响应解析失败，请检查服务版本与地址。"
    }

    private func notifyIfNeeded(_ row: AccountState) async {
        guard config.notifications, !paused, row.enabled else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        for window in row.windows {
            var candidate = ledger
            let key = config.credentialID + "|" + row.id + "|" + window.id
            let threshold = candidate.evaluate(key: key, window: window, warning: config.warning,
                                               critical: config.critical, now: Date(), maxAge: maxAge)
            if let threshold {
                let content = UNMutableNotificationContent()
                content.title = threshold == config.critical ? "CPAMP 额度紧急提醒" : "CPAMP 额度提醒"
                content.body = "\(row.account.title) · \(window.title) 剩余 \(Int(window.remaining ?? 0))%"
                content.sound = .default
                do {
                    try await UNUserNotificationCenter.current().add(.init(identifier: UUID().uuidString, content: content, trigger: nil))
                } catch { notificationMessage = "通知发送失败，请检查系统通知设置。"; continue }
            }
            ledger = candidate
            Storage.save(ledger, key: "alerts")
        }
    }

    func updateNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: notificationStatus = "已授权"
        case .denied: notificationStatus = "已被系统关闭"
        default: notificationStatus = "未授权"
        }
    }

    func requestNotifications(test: Bool = false) async {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await updateNotificationStatus()
            guard allowed else { notificationMessage = "请在系统设置 > 通知中允许 CPAMP Monitor。"; return }
            if test {
                let content = UNMutableNotificationContent()
                content.title = "CPAMP Monitor 测试通知"
                content.body = "额度通知已连接。这是一条测试，不代表额度不足。"
                content.sound = .default
                try await UNUserNotificationCenter.current().add(.init(identifier: UUID().uuidString, content: content, trigger: nil))
                notificationMessage = "测试通知已交给系统；显示方式受专注模式和通知设置影响。"
            }
        } catch { notificationMessage = "无法发送通知，请检查系统权限。" }
    }

    func save(_ newConfig: Configuration, secret: String, login: Bool) async throws {
        guard !refreshing else { throw MonitorError("请等待当前刷新完成。") }
        let validated = try newConfig.validated()
        if !secret.isEmpty { try Storage.storeCredential(secret, server: validated.credentialID) }
        guard try !Storage.credential(validated.credentialID).isEmpty else { throw MonitorError("该地址尚未保存管理密钥。") }
        let changedServer = validated.credentialID != config.credentialID
        if login && SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        if !login && SMAppService.mainApp.status == .enabled { try await SMAppService.mainApp.unregister() }
        config = validated
        Storage.save(config, key: "configuration")
        if changedServer { accounts = []; lastRefresh = nil; error = nil }
        if config.notifications { await requestNotifications() }
        paused = false
        refresh()
    }

    func togglePause() {
        paused.toggle()
        if !paused { refresh() }
        onChange?()
    }

    func openDashboard() {
        guard let url = try? Configuration.normalizeURL(config.baseURL) else { return }
        NSWorkspace.shared.open(url.appendingPathComponent("management.html"))
    }
}
