import AppKit
import XCTest
@testable import SessionMonitor

@MainActor
final class AppLifecycleTests: XCTestCase {
    func testClosingLastWindowDoesNotTerminateApplication() {
        let delegate = AppLifecycleDelegate()
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(.shared))
    }

    func testQuitRepliesOnlyAfterShutdownAndCoalescesRepeatedRequests() async throws {
        let delegate = AppLifecycleDelegate()
        let probe = ShutdownProbe()
        var replies = 0
        delegate.shutdown = { await probe.run() }
        delegate.replyToTermination = { allowed in
            XCTAssertTrue(allowed)
            replies += 1
        }
        XCTAssertEqual(delegate.applicationShouldTerminate(.shared), .terminateLater)
        XCTAssertEqual(delegate.applicationShouldTerminate(.shared), .terminateLater)
        try await eventually { probe.calls == 1 }
        XCTAssertEqual(replies, 0)
        probe.release()
        try await eventually { replies == 1 }
        XCTAssertEqual(probe.calls, 1)
    }

    private func eventually(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !condition() {
            if ContinuousClock.now >= deadline { throw LifecycleFixtureError.timeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class ShutdownProbe {
    private(set) var calls = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func run() async {
        calls += 1
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private enum LifecycleFixtureError: Error { case timeout }
