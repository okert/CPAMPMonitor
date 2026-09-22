import Foundation
import MonitorCore

private final class ResetProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> [String: Any])?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let payload = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: payload))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

func checkResetAPI() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ResetProtocol.self]
    let client = try APIClient(baseURL: "https://example.test", key: "test-only", configuration: configuration)
    let account = Account(json: ["name": "test.json", "provider": "codex", "auth_index": "idx", "account_id": "acct"])
    var paths: [String] = []
    ResetProtocol.handler = { request in
        expectEqual(request.httpMethod, "POST")
        expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-only")
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        paths.append(request.url!.path)
        if request.url!.path.hasSuffix("reset-quota") {
            expectEqual(body["auth_index"] as? String, "idx")
            return ["status": "ok"]
        }
        expectEqual(body["authIndex"] as? String, "idx")
        let headers = body["header"] as! [String: String]
        expectEqual(headers["Authorization"], "Bearer $TOKEN$")
        expectEqual(headers["Chatgpt-Account-Id"], "acct")
        if body["method"] as? String == "GET" {
            expectEqual(body["url"] as? String, "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")
            expectEqual(headers["OpenAI-Beta"], "codex-1")
            return ["status_code": 200, "body": "{\"available_count\":2,\"credits\":[]}"]
        }
        expectEqual(body["url"] as? String, "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume")
        let redeem = try JSONSerialization.jsonObject(with: (body["data"] as! String).data(using: .utf8)!) as! [String: String]
        expectNotNil(UUID(uuidString: redeem["redeem_request_id"] ?? ""))
        return ["statusCode": 200, "body": ["code": "reset"]]
    }
    let credits = try await client.resetCredits(account)
    expectEqual(credits.count, 2)
    try await client.consumeResetCredit(account)
    try await client.syncQuotaReset(account)
    expectEqual(paths, ["/v0/management/api-call", "/v0/management/api-call", "/v0/management/reset-quota"])
    ResetProtocol.handler = { _ in ["status_code": 200, "body": ["code": "no_credit"]] }
    do {
        try await client.consumeResetCredit(account)
        preconditionFailure("Missing reset outcome validation")
    } catch { expectEqual((error as? MonitorError)?.message, "当前已无可用重置次数。") }
    ResetProtocol.handler = { _ in ["status_code": 429, "body": [:]] }
    do {
        _ = try await client.resetCredits(account)
        preconditionFailure("Missing provider error validation")
    } catch { expectEqual((error as? MonitorError)?.status, 429) }
    ResetProtocol.handler = nil
}
