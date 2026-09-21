import Foundation

// A dependency-free test runner also works with Apple's Command Line Tools,
// which do not include the XCTest framework shipped in full Xcode.
func expectEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T,
                               file: StaticString = #file, line: UInt = #line) {
    do {
        let a = try lhs(), b = try rhs()
        precondition(a == b, "Expected \(b), got \(a)", file: file, line: line)
    } catch { preconditionFailure("Unexpected error: \(error)", file: file, line: line) }
}
func expectEqual(_ lhs: Double, _ rhs: Double, accuracy: Double, file: StaticString = #file, line: UInt = #line) {
    precondition(abs(lhs - rhs) <= accuracy, "Values differ", file: file, line: line)
}
func expectNotEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    precondition(lhs != rhs, "Values unexpectedly equal", file: file, line: line)
}
func expectNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
    precondition(value == nil, "Expected nil", file: file, line: line)
}
func expectNotNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
    precondition(value != nil, "Unexpected nil", file: file, line: line)
}
func expectTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(value, "Expected true", file: file, line: line)
}
func expectNoThrow<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) {
    do { _ = try expression() } catch { preconditionFailure("Unexpected error: \(error)", file: file, line: line) }
}
func expectThrows<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) {
    do { _ = try expression() } catch { return }
    preconditionFailure("Expected an error", file: file, line: line)
}

let suite = MonitorCoreTests()
let cases: [(String, () throws -> Void)] = [
    ("URL normalization and HTTPS enforcement", suite.testURLNormalizationAndTransportSafety),
    ("Settings validation", suite.testConfigurationThresholdValidation),
    ("Codex windows, null handling", suite.testCodexWindowsPlanAndNullSafety),
    ("Antigravity shared quotas", suite.testAntigravitySharedBuckets),
    ("xAI billing semantics", suite.testXaiBillingDoesNotInventProductQuotas),
    ("Missing values are not zero", suite.testMissingAndInvalidQuotaNeverBecomesZero),
    ("Persistent alert deduplication", suite.testAlertCrossingsAndDeduplicationSurviveSerialization),
    ("Critical notification priority", suite.testCriticalFirstDoesNotSendLowerPriorityNotificationLater),
    ("Stale data cannot alert", suite.testStaleExpiredAndUnknownQuotaCannotAlert),
    ("Reset jitter and new cycles", suite.testResetJitterAndNewCycle),
    ("Credential identity", suite.testAccountsKeepDistinctCredentialIdentity),
    ("Account order and tray display migration", suite.testAccountOrderMigratesAndRoundTrips)
]
for (name, run) in cases { try run(); print("PASS \(name)") }
print("\(cases.count) checks passed")
