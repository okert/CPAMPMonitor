import SwiftUI
import ServiceManagement
import MonitorCore

private func compact(_ value: Any?) -> String {
    guard let n = number(value) else { return "--" }
    if n >= 1_000_000_000 { return String(format: "%.1fB", n / 1_000_000_000) }
    if n >= 1_000_000 { return String(format: "%.1fM", n / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fK", n / 1_000) }
    return String(format: "%.0f", n)
}

struct MonitorView: View {
    @ObservedObject var model: MonitorModel
    let maximumHeight: CGFloat
    init(model: MonitorModel, maximumHeight: CGFloat = 760) {
        self.model = model
        self.maximumHeight = maximumHeight
    }
    private var accountListHeight: CGFloat {
        guard !model.accounts.isEmpty else { return 190 }
        // Five accounts fit in the popover on a normal desktop display. More
        // accounts retain scrolling instead of shrinking text.
        let chrome: CGFloat = 150
        return min(660, max(140, min(CGFloat(model.accounts.count) * 112, maximumHeight - chrome)))
    }
    var color: Color {
        if let low = model.lowest, low <= Double(model.config.critical) { return .red }
        if model.hasProblems || (model.lowest ?? 100) <= Double(model.config.warning) { return .orange }
        return model.paused || !model.configured ? .secondary : .green
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.xaxis").font(.system(size: 22)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("CPAMP Monitor").font(.headline)
                    Text(model.config.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if model.refreshing { ProgressView().controlSize(.small) }
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help("刷新额度").disabled(model.refreshing || !model.configured || model.paused)
                Button { model.openSettings?() } label: { Image(systemName: "gearshape") }.help("设置")
            }.buttonStyle(.borderless).padding(18)
            HStack(alignment: .firstTextBaseline) {
                Label(model.statusText, systemImage: model.paused ? "pause.circle" : model.hasProblems ? "exclamationmark.circle" : "circle.fill")
                    .foregroundStyle(color).font(.subheadline)
                Spacer()
                if let low = model.displayLowest {
                    Text(model.displayLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text("\(Int(low))%").font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                }
            }.padding(.horizontal, 18).padding(.bottom, 14)
            Divider()
            if !model.configured {
                VStack(spacing: 14) {
                    Image(systemName: "network").font(.system(size: 36)).foregroundStyle(.secondary)
                    Text("尚未连接 CPAMP").font(.headline)
                    Button("连接服务") { model.openSettings?() }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity).frame(height: 220)
            } else {
                if let error = model.error {
                    Label(error, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    Divider()
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if model.accounts.isEmpty {
                            Text(model.refreshing ? "正在读取账号…" : "暂无账号").foregroundStyle(.secondary).padding(36)
                        }
                        ForEach(model.accounts) { row in
                            AccountView(row: row, now: model.now, maxAge: model.maxAge,
                                        warning: model.config.warning, critical: model.config.critical,
                                        stale: model.error != nil || model.paused)
                            Divider().padding(.horizontal, 18)
                        }
                    }
                }.frame(height: accountListHeight)
            }
            Divider()
            VStack(spacing: 10) {
                HStack {
                    if let last = model.lastRefresh {
                        Text("更新 \(last.formatted(date: .omitted, time: .shortened))")
                    } else { Text("尚未更新") }
                    Spacer()
                    if let error = model.historyError { Text(error).foregroundStyle(.orange) }
                    else if let next = model.nextRefresh, !model.paused {
                        Text("下次 \(next.formatted(date: .omitted, time: .shortened))")
                    }
                }.font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button { model.openDashboard() } label: { Label("后台", systemImage: "arrow.up.right.square") }
                        .disabled(!model.configured)
                    Spacer()
                    Button { model.togglePause() } label: { Image(systemName: model.paused ? "play.fill" : "pause.fill") }
                        .help(model.paused ? "恢复监控" : "暂停监控").disabled(model.refreshing || !model.configured)
                    Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }.help("退出")
                }.buttonStyle(.borderless)
            }.padding(14)
        }.frame(width: 500)
    }
}

struct AccountView: View {
    let row: AccountState
    let now: Date
    let maxAge: TimeInterval
    let warning: Int
    let critical: Int
    let stale: Bool
    var icon: String { ["codex": "terminal", "antigravity": "sparkles", "xai": "bolt", "claude": "sun.max"][row.account.provider] ?? "cloud" }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon).font(.system(size: 17, weight: .medium)).frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.account.title).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        .help(row.account.title)
                    HStack(spacing: 6) {
                        Text(row.account.providerName)
                        let plan = row.plan.isEmpty ? row.account.plan : row.plan
                        if !plan.isEmpty { Text("· " + plan.capitalized) }
                    }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(!row.enabled ? (row.account.disabled ? "已禁用" : "未监控") : row.error != nil ? "查询失败" : row.account.status == "active" ? "可用" : row.account.status)
                    .font(.caption).foregroundStyle(row.error != nil ? .orange : .secondary).lineLimit(1)
            }
            if row.enabled {
                if let error = row.error {
                    Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if row.windows.isEmpty && row.error == nil {
                    Text("等待额度数据").font(.caption).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.flexible(minimum: 0), spacing: 10), GridItem(.flexible(minimum: 0), spacing: 10)], alignment: .leading, spacing: 7) {
                ForEach(row.windows) { window in
                    let fresh = !stale && row.error == nil && window.fresh(now: now, maxAge: maxAge)
                    let remaining = window.remaining
                    let color: Color = !fresh ? .gray : (remaining ?? 100) <= Double(critical) ? .red : (remaining ?? 100) <= Double(warning) ? .orange : .green
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(window.title).font(.system(size: 10)).lineLimit(1).truncationMode(.tail)
                            Spacer(minLength: 8)
                            Text(remaining.map { "\(fresh ? "剩余" : "旧值") \(Int($0))%" } ?? "未知")
                                .font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(fresh ? .primary : .secondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.07))
                                Capsule().fill(color).frame(width: geo.size.width * CGFloat((remaining ?? 0) / 100))
                            }
                        }.frame(height: 4)
                        HStack {
                            if !fresh { Text("非实时").foregroundStyle(.orange) }
                            Spacer()
                            if let reset = window.reset {
                                if reset > now {
                                    Text(reset, style: .relative) + Text("后重置")
                                } else { Text("重置时间已过，待刷新") }
                            } else { Text("重置时间未知") }
                        }.font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                }
            }
            if !row.history.isEmpty {
                HStack(spacing: 12) {
                    Label(compact(row.history["total_requests"]), systemImage: "paperplane")
                    Label(compact(row.history["total_tokens"]), systemImage: "number")
                    Spacer(minLength: 0)
                    if let rate = number(row.history["success_rate"]) {
                        Text(String(format: "成功 %.1f%%", rate * 100))
                    }
                    if let cost = number(row.history["total_cost"]) { Text(String(format: "$%.2f", cost)) }
                }.font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
            }
        }.padding(.horizontal, 14).padding(.vertical, 9).opacity(row.enabled ? 1 : 0.6)
    }
}

struct SettingsView: View {
    @ObservedObject var model: MonitorModel
    @State private var draft: Configuration
    @State private var secret = ""
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var saving = false
    @State private var message: String?
    @State private var success = false

    private var orderedRows: [AccountState] {
        guard !model.accounts.isEmpty else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: model.accounts.map { ($0.id, $0) })
        let preferred = draft.accountOrder.compactMap { byID[$0] }
        let known = Set(preferred.map(\.id))
        return preferred + model.accounts.filter { !known.contains($0.id) }
    }

    private func moveAccount(_ id: String, offset: Int) {
        var ids = orderedRows.map(\.id)
        guard let index = ids.firstIndex(of: id) else { return }
        let destination = index + offset
        guard ids.indices.contains(destination) else { return }
        ids.swapAt(index, destination)
        draft.accountOrder = ids
    }

    init(model: MonitorModel) {
        self.model = model
        _draft = State(initialValue: model.config)
    }
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("连接") {
                    TextField("名称", text: $draft.name)
                    Toggle("SSH 安全通道", isOn: Binding(get: { !draft.sshHost.isEmpty }, set: { draft.sshHost = $0 ? "oc" : "" }))
                    if draft.sshHost.isEmpty {
                        TextField("CPAMP 地址", text: $draft.baseURL, prompt: Text("https://cpamp.example.com"))
                            .autocorrectionDisabled()
                    } else {
                        TextField("SSH 主机别名", text: $draft.sshHost)
                        TextField("远端管理端口", value: $draft.sshPort, format: .number.grouping(.never))
                        TextField("本地通道端口", value: $draft.localPort, format: .number.grouping(.never))
                    }
                    SecureField("管理密钥", text: $secret, prompt: Text("留空保留此地址已存密钥"))
                    LabeledContent("密钥存储", value: "macOS 钥匙串")
                }
                Section("监控") {
                    Picker("刷新间隔", selection: $draft.interval) {
                        ForEach([60, 120, 300, 600, 900, 1800, 3600], id: \.self) { value in
                            Text("\(value / 60) 分钟").tag(value)
                        }
                    }
                    Toggle("开机启动", isOn: $login)
                    Toggle("额度通知", isOn: $draft.notifications)
                    Picker("菜单栏显示", selection: Binding(get: { draft.displayAccountID ?? "" }, set: {
                        draft.displayAccountID = $0.isEmpty ? nil : $0
                    })) {
                        Text("所有账号最低").tag("")
                        if let selected = draft.displayAccountID, !orderedRows.contains(where: { $0.id == selected }) {
                            Text("指定账号（当前不可用）").tag(selected)
                        }
                        ForEach(orderedRows) { row in
                            Text(row.account.title).tag(row.id)
                        }
                    }
                    Stepper("提醒：剩余 ≤ \(draft.warning)%", value: $draft.warning, in: 2...99)
                    Stepper("紧急：剩余 ≤ \(draft.critical)%", value: $draft.critical, in: 1...98)
                    HStack {
                        Text("通知权限：\(model.notificationStatus)").foregroundStyle(.secondary)
                        Spacer()
                        Button("测试通知") { Task { await model.requestNotifications(test: true) } }
                    }
                    if let text = model.notificationMessage { Text(text).font(.caption).foregroundStyle(.secondary) }
                }
                if !model.accounts.isEmpty {
                    Section("账号顺序与监控") {
                        ForEach(Array(orderedRows.enumerated()), id: \.element.id) { index, row in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading) {
                                    Text(row.account.title).lineLimit(1).truncationMode(.middle)
                                    Text(row.account.providerName + (row.account.disabled ? " · 服务端已禁用" : ""))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Button { moveAccount(row.id, offset: -1) } label: {
                                    Image(systemName: "chevron.up")
                                }.buttonStyle(.borderless).help("上移").disabled(index == 0)
                                Button { moveAccount(row.id, offset: 1) } label: {
                                    Image(systemName: "chevron.down")
                                }.buttonStyle(.borderless).help("下移").disabled(index == orderedRows.count - 1)
                                Toggle(isOn: Binding(get: { !draft.excluded.contains(row.id) }, set: { on in
                                    if on { draft.excluded.remove(row.id) } else { draft.excluded.insert(row.id) }
                                })) { EmptyView() }
                                    .labelsHidden().disabled(row.account.disabled)
                            }
                        }
                    }
                }
            }.formStyle(.grouped)
            Divider()
            HStack {
                if let message { Text(message).font(.caption).foregroundStyle(success ? .green : .red).fixedSize(horizontal: false, vertical: true) }
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button("保存并连接") {
                    saving = true; message = nil
                    Task {
                        do {
                            try await model.save(draft, secret: secret, login: login)
                            draft = model.config; secret = ""; success = true; message = "设置已保存，正在验证连接。"
                        } catch { success = false; message = model.safeMessage(error) }
                        saving = false
                    }
                }.buttonStyle(.borderedProminent).disabled(saving || model.refreshing)
            }.padding(16)
        }.frame(width: 540, height: 650)
            .task { await model.updateNotificationStatus() }
    }
}
