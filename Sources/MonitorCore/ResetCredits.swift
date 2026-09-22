import Foundation

public struct ResetCredit: Identifiable, Equatable {
    public let id: String
    public let expires: Date?
}

public struct ResetCredits: Equatable {
    public let count: Int?
    public let credits: [ResetCredit]
    public let detailsAvailable: Bool
    public let observed: Date

    public static func parse(_ payload: [String: Any], now: Date = Date()) throws -> ResetCredits {
        let rawCount = number(payload["available_count"] ?? payload["availableCount"])
        let count = rawCount.flatMap { $0 >= 0 && $0 < Double(Int.max) && $0.rounded() == $0 ? Int($0) : nil }
        let raw = payload["credits"] as? [[String: Any]]
        guard count != nil || raw != nil else { throw MonitorError("重置次数响应无法识别。") }
        let credits = (raw ?? []).enumerated().compactMap { index, item -> ResetCredit? in
            guard string(item["reset_type"] ?? item["resetType"]) == "codex_rate_limits",
                  string(item["status"]) == "available" else { return nil }
            let expires = timestamp(item["expires_at"] ?? item["expiresAt"])
            guard expires == nil || expires! > now else { return nil }
            return ResetCredit(id: "\(index):\(string(item["id"]))", expires: expires)
        }.sorted { ($0.expires ?? .distantFuture) < ($1.expires ?? .distantFuture) }
        return ResetCredits(count: count ?? (raw != nil ? credits.count : nil),
                            credits: count == 0 ? [] : credits, detailsAvailable: raw != nil, observed: now)
    }

    public static func validateOutcome(_ payload: [String: Any]) throws {
        switch string(payload["code"]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "reset", "already_redeemed": return
        case "no_credit": throw MonitorError("当前已无可用重置次数。")
        case "nothing_to_reset": throw MonitorError("当前额度无需重置。")
        default: throw MonitorError("服务未确认重置成功，请刷新核实，勿重复提交。")
        }
    }
}
