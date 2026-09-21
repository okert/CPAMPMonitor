import Foundation
import MonitorCore

final class MonitorCoreTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testURLNormalizationAndTransportSafety() throws {
        expectEqual(try Configuration.normalizeURL(" https://host.test/management.html ").absoluteString, "https://host.test")
        expectEqual(try Configuration.normalizeURL("https://host.test/prefix/v1/").absoluteString, "https://host.test/prefix")
        expectNoThrow(try Configuration.normalizeURL("http://127.0.0.1:18317"))
        for input in ["http://remote.test", "https://user:secret@host.test", "https://host.test?key=abc", "file:///tmp/test", "host.test"] {
            expectThrows(try Configuration.normalizeURL(input))
        }
    }

    func testConfigurationThresholdValidation() throws {
        var config = Configuration()
        config.baseURL = "https://host.test"
        expectNoThrow(try config.validated())
        config.critical = config.warning
        expectThrows(try config.validated())
        config.critical = 10; config.interval = 1
        expectThrows(try config.validated())
    }

    func testCodexWindowsPlanAndNullSafety() throws {
        let result = try QuotaParser.parse(provider: "codex", payload: [
            "plan_type": "plus", "rate_limit": [
                "primary_window": ["used_percent": 18, "limit_window_seconds": 18000, "reset_at": 1_790_018_000],
                "secondary_window": ["used_percent": 4, "limit_window_seconds": 604800, "reset_after_seconds": 400000]
            ], "code_review_rate_limit": NSNull()
        ], now: now)
        expectEqual(result.plan, "plus")
        expectEqual(result.windows.map(\.remaining), [82, 96])
        expectEqual(result.windows.map(\.title), ["5 小时", "周额度"])
        expectEqual(result.windows[1].reset, now.addingTimeInterval(400000))
        expectThrows(try QuotaParser.parse(provider: "codex", payload: ["rate_limit": ["primary_window": ["used_percent": NSNull()]]]))
        expectThrows(try QuotaParser.parse(provider: "codex", payload: ["rate_limit": ["primary_window": ["used_percent": true]]]))
    }

    func testAntigravitySharedBuckets() throws {
        let result = try QuotaParser.parse(provider: "antigravity", payload: ["groups": [
            ["displayName": "Gemini", "buckets": [["window": "weekly", "remainingFraction": 0.995672, "resetTime": "2026-09-25T23:03:31Z"]]],
            ["displayName": "Claude", "buckets": [["window": "weekly", "remainingFraction": 0.0]]]
        ]], now: now)
        expectEqual(result.windows.count, 2)
        expectEqual(result.windows[0].remaining!, 99.5672, accuracy: 0.0001)
        expectEqual(result.windows[1].remaining, 0)
        expectNotNil(result.windows[0].reset)
    }

    func testXaiBillingDoesNotInventProductQuotas() throws {
        let result = try QuotaParser.parse(provider: "xai", payload: ["config": [
            "creditUsagePercent": 22.0,
            "currentPeriod": ["type": "USAGE_PERIOD_TYPE_WEEKLY", "end": "2026-09-24T12:06:45.839092+00:00"],
            "productUsage": [["product": "GrokBuild", "usagePercent": 20]]
        ]], now: now)
        expectEqual(result.windows.count, 1)
        expectEqual(result.windows[0].remaining, 78)
        expectNotNil(result.windows[0].reset)
    }

    func testMissingAndInvalidQuotaNeverBecomesZero() {
        for value: Any in [NSNull(), true, -1, 101, "bad"] {
            expectThrows(try QuotaParser.parse(provider: "xai", payload: ["config": ["creditUsagePercent": value]]))
        }
        expectThrows(try QuotaParser.parse(provider: "antigravity", payload: ["groups": []]))
        expectNil(number(NSNull()))
        expectNil(number(false))
    }

    func window(_ remaining: Double, reset: Date? = nil, observed: Date? = nil) -> QuotaWindow {
        .init(id: "weekly", title: "Week", remaining: remaining, reset: reset, observed: observed ?? now)
    }

    func testAlertCrossingsAndDeduplicationSurviveSerialization() throws {
        var ledger = AlertLedger()
        let reset = now.addingTimeInterval(3600)
        func evaluate(_ remaining: Double) -> Int? {
            ledger.evaluate(key: "a", window: window(remaining, reset: reset), warning: 20, critical: 10, now: now, maxAge: 600)
        }
        expectNil(evaluate(80))
        expectEqual(evaluate(20), 20)
        expectNil(evaluate(19))
        expectEqual(evaluate(10), 10)
        ledger = try JSONDecoder().decode(AlertLedger.self, from: JSONEncoder().encode(ledger))
        expectNil(evaluate(5))
        expectNil(evaluate(15))
    }

    func testCriticalFirstDoesNotSendLowerPriorityNotificationLater() {
        var ledger = AlertLedger()
        expectEqual(ledger.evaluate(key: "a", window: window(5), warning: 20, critical: 10, now: now, maxAge: 600), 10)
        expectNil(ledger.evaluate(key: "a", window: window(15), warning: 20, critical: 10, now: now, maxAge: 600))
    }

    func testStaleExpiredAndUnknownQuotaCannotAlert() {
        var ledger = AlertLedger()
        for w in [window(0, observed: now.addingTimeInterval(-601)), window(0, reset: now.addingTimeInterval(-1)),
                  QuotaWindow(id: "nil", title: "nil", remaining: nil, reset: nil, observed: now)] {
            expectNil(ledger.evaluate(key: "a", window: w, warning: 20, critical: 10, now: now, maxAge: 600))
        }
        expectTrue(ledger.entries.isEmpty)
    }

    func testResetJitterAndNewCycle() {
        var ledger = AlertLedger()
        let first = now.addingTimeInterval(300)
        expectEqual(ledger.evaluate(key: "a", window: window(10, reset: first), warning: 20, critical: 10, now: now, maxAge: 600), 10)
        expectNil(ledger.evaluate(key: "a", window: window(10, reset: first.addingTimeInterval(5)), warning: 20, critical: 10, now: now, maxAge: 600))
        let later = now.addingTimeInterval(400)
        expectEqual(ledger.evaluate(key: "a", window: window(10, reset: later.addingTimeInterval(300), observed: later), warning: 20, critical: 10, now: later, maxAge: 600), 10)
    }

    func testAccountsKeepDistinctCredentialIdentity() {
        let one = Account(json: ["name": "one.json", "provider": "codex", "auth_index": 1, "email": "same@example.test"])
        let two = Account(json: ["name": "two.json", "provider": "codex", "auth_index": 2, "email": "same@example.test"])
        expectNotEqual(one.id, two.id)
        expectEqual(one.authIndex, "1")
    }

    func testAccountOrderMigratesAndRoundTrips() {
        let old = Data("{\"baseURL\":\"https://cpam.example\",\"name\":\"OC\",\"interval\":300}".utf8)
        let migrated = try! JSONDecoder().decode(Configuration.self, from: old)
        expectEqual(migrated.accountOrder, [])
        var current = migrated
        current.accountOrder = ["codex:one:1", "xai:two:2"]
        current.displayAccountID = "xai:two:2"
        let roundTrip = try! JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(current))
        expectEqual(roundTrip.accountOrder, current.accountOrder)
        expectEqual(roundTrip.displayAccountID, current.displayAccountID)
        let selected = [window(82), window(37), window(5, observed: now.addingTimeInterval(-601))]
        expectEqual(QuotaWindow.minimumFreshRemaining(selected, now: now, maxAge: 600), 37)
        expectNil(QuotaWindow.minimumFreshRemaining([window(5, observed: now.addingTimeInterval(-601))], now: now, maxAge: 600))
    }
}
