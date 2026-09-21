import Foundation

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public final class APIClient {
    private let base: URL
    private let key: String
    private let session: URLSession
    public init(baseURL: String, key: String) throws {
        base = try Configuration.normalizeURL(baseURL)
        self.key = key
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 35
        config.timeoutIntervalForResource = 50
        config.httpCookieStorage = nil
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }

    public func request(_ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw MonitorError("服务器响应无效。") }
        guard (200...299).contains(http.statusCode) else {
            let message: String
            switch http.statusCode {
            case 401, 403: message = "管理认证失败，请检查 CPAMP 管理密钥。"
            case 300...399: message = "服务发生重定向，请填写最终 HTTPS 地址。"
            case 429: message = "请求频率受限，稍后重试。"
            default: message = "CPAMP 请求失败（HTTP \(http.statusCode)）。"
            }
            throw MonitorError(message, status: http.statusCode)
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MonitorError("服务返回的不是 JSON 对象。")
        }
        return object
    }

    public func accounts() async throws -> [Account] {
        let data = try await request("v0/management/auth-files")
        guard let files = data["files"] as? [[String: Any]] else { throw MonitorError("账号列表结构不兼容。") }
        return files.map(Account.init).sorted { $0.provider == $1.provider ? $0.title < $1.title : $0.provider < $1.provider }
    }

    public func history(_ accounts: [Account]) async throws -> [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]
        for offset in stride(from: 0, to: accounts.count, by: 200) {
            let batch = Array(accounts[offset..<min(offset + 200, accounts.count)])
            let data = try await request("v0/management/monitoring/account-history", body: ["accounts": batch.map(\.target)])
            for item in data["items"] as? [[String: Any]] ?? [] { result[string(item["row_key"])] = item }
        }
        return result
    }

    public func quota(_ account: Account) async throws -> QuotaResult {
        guard !account.authIndex.isEmpty else { throw MonitorError("缺少账号 auth_index。") }
        var headers = ["Authorization": "Bearer $TOKEN$", "Content-Type": "application/json"]
        var body: [String: Any] = ["authIndex": account.authIndex, "method": "GET"]
        switch account.provider {
        case "codex":
            body["url"] = "https://chatgpt.com/backend-api/wham/usage"
            headers["User-Agent"] = "codex-tui/0.149.1"
            if !account.accountID.isEmpty { headers["Chatgpt-Account-Id"] = account.accountID }
        case "antigravity":
            body["url"] = "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary"
            body["method"] = "POST"
            body["data"] = String(data: try JSONSerialization.data(withJSONObject: ["project": account.projectID]), encoding: .utf8)!
            headers["User-Agent"] = "antigravity/1.0.13"
        case "xai":
            body["url"] = "https://cli-chat-proxy.grok.com/v1/billing?format=credits"
            headers["x-xai-token-auth"] = "xai-grok-cli"
            headers["x-grok-client-version"] = "0.2.101"
            headers["User-Agent"] = "grok-pager/0.2.101 grok-shell/0.2.101 (macos; aarch64)"
        case "claude":
            body["url"] = "https://api.anthropic.com/api/oauth/usage"
            headers["anthropic-beta"] = "oauth-2025-04-20"
        default: throw MonitorError("暂不支持此提供商的实时额度。")
        }
        body["header"] = headers
        let data = try await request("v0/management/api-call", body: body)
        let status = Int(number(data["status_code"] ?? data["statusCode"]) ?? 0)
        guard (200...299).contains(status) else {
            throw MonitorError(status == 429 ? "额度查询限流，15 分钟后重试。" : "提供商额度查询失败（HTTP \(status)）。", status: status)
        }
        let payload: [String: Any]?
        if let object = data["body"] as? [String: Any] { payload = object }
        else if let raw = (data["body"] as? String)?.data(using: .utf8) { payload = try JSONSerialization.jsonObject(with: raw) as? [String: Any] }
        else { payload = nil }
        guard let payload else { throw MonitorError("额度响应格式无法识别。") }
        return try QuotaParser.parse(provider: account.provider, payload: payload)
    }
}
