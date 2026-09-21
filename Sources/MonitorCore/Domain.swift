import Foundation

public struct MonitorError: LocalizedError {
    public let message: String
    public let status: Int?
    public init(_ message: String, status: Int? = nil) { self.message = message; self.status = status }
    public var errorDescription: String? { message }
}

public struct Configuration: Codable, Equatable {
    public var baseURL = ""
    public var name = "CPAMP"
    public var interval = 300
    public var warning = 20
    public var critical = 10
    public var notifications = true
    public var excluded: Set<String> = []
    public var accountOrder: [String] = []
    public var sshHost = ""
    public var sshPort = 18317
    public var localPort = 18318
    public var credentialID: String { sshHost.isEmpty ? baseURL : "ssh://\(sshHost):\(sshPort)" }
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case baseURL, name, interval, warning, critical, notifications, excluded, accountOrder
        case sshHost, sshPort, localPort
    }

    // accountOrder was added after the first released config format. Decode
    // it optionally so existing settings continue to load unchanged.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try values.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "CPAMP"
        interval = try values.decodeIfPresent(Int.self, forKey: .interval) ?? 300
        warning = try values.decodeIfPresent(Int.self, forKey: .warning) ?? 20
        critical = try values.decodeIfPresent(Int.self, forKey: .critical) ?? 10
        notifications = try values.decodeIfPresent(Bool.self, forKey: .notifications) ?? true
        excluded = try values.decodeIfPresent(Set<String>.self, forKey: .excluded) ?? []
        accountOrder = try values.decodeIfPresent([String].self, forKey: .accountOrder) ?? []
        sshHost = try values.decodeIfPresent(String.self, forKey: .sshHost) ?? ""
        sshPort = try values.decodeIfPresent(Int.self, forKey: .sshPort) ?? 18317
        localPort = try values.decodeIfPresent(Int.self, forKey: .localPort) ?? 18318
    }

    public static func normalizeURL(_ input: String) throws -> URL {
        guard var c = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = c.host, !host.isEmpty, ["https", "http"].contains(c.scheme?.lowercased() ?? ""),
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil else {
            throw MonitorError("请输入完整服务地址，不包含密码、查询参数或片段。")
        }
        if c.scheme == "http" && !["localhost", "127.0.0.1", "::1"].contains(host) {
            throw MonitorError("远程服务必须使用 HTTPS，避免管理密钥明文传输。")
        }
        var path = c.path
        while path.hasSuffix("/") { path.removeLast() }
        for suffix in ["/management.html", "/v0/management", "/v1"] where path.hasSuffix(suffix) {
            path.removeLast(suffix.count)
            break
        }
        c.path = path
        c.scheme = c.scheme?.lowercased()
        guard let url = c.url else { throw MonitorError("服务地址无效。") }
        return url
    }

    public func validated() throws -> Configuration {
        var result = self
        if !sshHost.isEmpty {
            guard !sshHost.hasPrefix("-"), sshHost.range(of: "^[A-Za-z0-9_@.-]+$", options: .regularExpression) != nil,
                  (1...65535).contains(sshPort), (1024...65535).contains(localPort) else {
                throw MonitorError("SSH 主机别名或端口无效。")
            }
            result.baseURL = "http://127.0.0.1:\(localPort)"
        } else { result.baseURL = try Self.normalizeURL(baseURL).absoluteString }
        guard (60...3600).contains(interval), critical >= 1, warning <= 99, critical < warning else {
            throw MonitorError("刷新间隔需为 1–60 分钟，阈值需满足 1 ≤ 紧急 < 提醒 ≤ 99。")
        }
        return result
    }
}

public struct Account: Identifiable {
    public var id: String { provider + ":" + filename + ":" + authIndex }
    public let filename: String
    public let provider: String
    public let authIndex: String
    public let email: String
    public let status: String
    public let disabled: Bool
    public let projectID: String
    public let accountID: String
    public let plan: String
    public var title: String { email.isEmpty ? filename : email }
    public var providerName: String {
        ["codex": "Codex", "antigravity": "Antigravity", "xai": "Grok / xAI", "claude": "Claude"][provider] ?? provider
    }
    public init(json: [String: Any]) {
        filename = string(json["name"])
        provider = string(json["provider"] ?? json["type"]).lowercased()
        authIndex = string(json["auth_index"])
        email = string(json["email"])
        status = string(json["status"])
        disabled = json["disabled"] as? Bool ?? false
        projectID = string(json["project_id"])
        let account = json["account"] as? [String: Any] ?? [:]
        accountID = string(account["account_id"] ?? json["account_id"])
        plan = string(account["plan_type"] ?? json["account_type"])
    }
    public var target: [String: Any] {
        var result: [String: Any] = ["row_key": id, "auth_file_snapshot": filename,
                                    "auth_provider_snapshot": provider, "auth_index": authIndex]
        if !accountID.isEmpty { result["auth_account_id_snapshot"] = accountID }
        if !projectID.isEmpty { result["auth_project_id_snapshot"] = projectID }
        return result
    }
}

public struct QuotaWindow: Identifiable, Codable, Equatable {
    public var id: String
    public var title: String
    public var remaining: Double?
    public var reset: Date?
    public var observed: Date
    public init(id: String, title: String, remaining: Double?, reset: Date?, observed: Date) {
        self.id = id; self.title = title; self.remaining = remaining; self.reset = reset; self.observed = observed
    }
    public func fresh(now: Date, maxAge: TimeInterval) -> Bool {
        now.timeIntervalSince(observed) >= -60 && now.timeIntervalSince(observed) <= maxAge && (reset == nil || reset! > now)
    }
}

public struct QuotaResult {
    public var windows: [QuotaWindow]
    public var plan: String
    public init(windows: [QuotaWindow], plan: String = "") { self.windows = windows; self.plan = plan }
}

public func string(_ value: Any?) -> String {
    if let s = value as? String { return s }
    if let n = value as? NSNumber { return n.stringValue }
    return ""
}

public func number(_ value: Any?) -> Double? {
    guard let value, !(value is NSNull), CFGetTypeID(value as CFTypeRef) != CFBooleanGetTypeID() else { return nil }
    let n = (value as? NSNumber)?.doubleValue ?? Double(string(value))
    return n.flatMap { $0.isFinite ? $0 : nil }
}

public func timestamp(_ value: Any?) -> Date? {
    if let n = number(value), n > 0, n < 100_000_000_000_000 {
        return Date(timeIntervalSince1970: n > 100_000_000_000 ? n / 1000 : n)
    }
    let s = string(value)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = formatter.date(from: s) { return d }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: s)
}

import CoreFoundation

public enum QuotaParser {
    static func percent(_ value: Any?) -> Double? {
        number(value).flatMap { (0...100).contains($0) ? $0 : nil }
    }
    public static func parse(provider: String, payload: [String: Any], now: Date = Date()) throws -> QuotaResult {
        var windows: [QuotaWindow] = []
        var plan = ""
        switch provider {
        case "codex":
            plan = string(payload["plan_type"])
            var limits: [(String, String, [String: Any])] = []
            if let main = payload["rate_limit"] as? [String: Any] { limits.append(("main", "", main)) }
            if let review = payload["code_review_rate_limit"] as? [String: Any] { limits.append(("review", "代码审查 ", review)) }
            for (index, extra) in (payload["additional_rate_limits"] as? [[String: Any]] ?? []).enumerated() {
                if let rate = extra["rate_limit"] as? [String: Any] {
                    let name = string(extra["limit_name"] ?? extra["metered_feature"])
                    limits.append(("extra-" + (name.isEmpty ? String(index) : name), name + " ", rate))
                }
            }
            for (id, prefix, limit) in limits {
                for key in ["primary_window", "secondary_window"] {
                    guard let w = limit[key] as? [String: Any] else { continue }
                    let duration = number(w["limit_window_seconds"])
                    let label = duration == 604800 ? "周额度" : duration.map { "\(Int($0 / 3600)) 小时" } ?? "额度"
                    let relative = number(w["reset_after_seconds"]).flatMap { $0 > 0 ? now.addingTimeInterval($0) : nil }
                    windows.append(.init(id: id + ":" + key, title: prefix + label,
                                         remaining: percent(w["used_percent"]).map { 100 - $0 },
                                         reset: timestamp(w["reset_at"]) ?? relative, observed: now))
                }
            }
        case "antigravity":
            for (index, group) in (payload["groups"] as? [[String: Any]] ?? []).enumerated() {
                let label = string(group["displayName"] ?? group["display_name"])
                for (bi, bucket) in (group["buckets"] as? [[String: Any]] ?? []).enumerated() {
                    let window = string(bucket["window"])
                    let suffix = window == "weekly" ? "周额度" : window
                    let fraction = number(bucket["remainingFraction"] ?? bucket["remaining_fraction"])
                    let remaining = fraction.flatMap { (0...1).contains($0) ? $0 * 100 : nil }
                    let bucketID = string(bucket["bucketId"] ?? bucket["bucket_id"])
                    windows.append(.init(id: bucketID.isEmpty ? "\(label)-\(index)-\(window)-\(bi)" : bucketID,
                                         title: "\(label.isEmpty ? "额度组 \(index + 1)" : label) \(suffix)",
                                         remaining: remaining, reset: timestamp(bucket["resetTime"] ?? bucket["reset_time"]), observed: now))
                }
            }
        case "xai":
            let config = payload["config"] as? [String: Any] ?? [:]
            let period = config["currentPeriod"] as? [String: Any] ?? [:]
            let reset = timestamp(period["end"] ?? config["billingPeriodEnd"])
            let isWeekly = string(period["type"]).contains("WEEKLY")
            if let used = percent(config["creditUsagePercent"]) {
                windows.append(.init(id: "billing", title: isWeekly ? "周额度" : "账期额度", remaining: 100 - used, reset: reset, observed: now))
            }
        case "claude":
            for key in payload.keys.sorted() where key.hasPrefix("five_hour") || key.hasPrefix("seven_day") {
                guard let w = payload[key] as? [String: Any] else { continue }
                windows.append(.init(id: key, title: key == "five_hour" ? "5 小时" : key == "seven_day" ? "周额度" : key,
                                     remaining: percent(w["utilization"]).map { 100 - $0 }, reset: timestamp(w["resets_at"]), observed: now))
            }
        default: throw MonitorError("暂不支持此提供商的实时额度。")
        }
        guard !windows.isEmpty, windows.contains(where: { $0.remaining != nil }) else {
            throw MonitorError("未返回可识别的额度；不会按 0% 处理。")
        }
        return QuotaResult(windows: windows, plan: plan)
    }
}

public struct AlertLedger: Codable {
    public struct Entry: Codable {
        var reset: Date?
        var thresholds: Set<Int>
        var touched: Date
    }
    public var entries: [String: Entry] = [:]
    public init() {}
    public mutating func evaluate(key: String, window: QuotaWindow, warning: Int, critical: Int,
                                  now: Date, maxAge: TimeInterval) -> Int? {
        guard window.fresh(now: now, maxAge: maxAge), let remaining = window.remaining else { return nil }
        var entry = entries[key] ?? Entry(reset: window.reset, thresholds: [], touched: now)
        // Providers can move reset timestamps by a few seconds within the same cycle.
        if let old = entry.reset, let new = window.reset, new.timeIntervalSince(old) > 120, now >= old {
            entry.thresholds = []
        } else if entry.reset == nil && window.reset == nil && remaining > Double(warning + 5) {
            entry.thresholds = []
        }
        entry.reset = window.reset
        entry.touched = now
        let threshold = remaining <= Double(critical) ? critical : remaining <= Double(warning) ? warning : nil
        let shouldAlert = threshold.map { !entry.thresholds.contains($0) } ?? false
        if let threshold, shouldAlert {
            entry.thresholds.insert(threshold)
            if threshold == critical { entry.thresholds.insert(warning) }
        }
        entries[key] = entry
        entries = entries.filter { now.timeIntervalSince($0.value.touched) < 90 * 86400 }
        return shouldAlert ? threshold : nil
    }
}
