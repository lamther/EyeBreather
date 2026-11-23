import XCTest
@testable import EyeBreather

@MainActor
final class SystemStateMonitorTests: XCTestCase {

    private var systemStateMonitor: SystemStateMonitor!
    private var timerManager: TimerManager!

    override func setUp() {
        super.setUp()
        systemStateMonitor = SystemStateMonitor.shared
        timerManager = TimerManager.shared

        systemStateMonitor.debugResetState()
        BreakWindowController.shared.hideOverlay()
        timerManager.resetWorkCycle()
        timerManager.pause()
    }

    override func tearDown() {
        BreakWindowController.shared.hideOverlay()
        timerManager.resetWorkCycle()
        timerManager.pause()
        systemStateMonitor.debugResetState()
        super.tearDown()
    }

    func testScreenUnlockResumesBreakOnlyAfterUnlock() {
        timerManager.startBreak()

        systemStateMonitor.debugSimulateScreenLock()
        XCTAssertTrue(systemStateMonitor.isScreenLocked)
        XCTAssertEqual(timerManager.state, .paused)

        systemStateMonitor.debugSimulateSystemDidWake()
        XCTAssertEqual(timerManager.state, .paused)
        XCTAssertTrue(systemStateMonitor.isScreenLocked)

        systemStateMonitor.debugSimulateScreenUnlock()
        XCTAssertEqual(timerManager.state, .breaking)
        XCTAssertFalse(systemStateMonitor.isSuspended)
    }

    func testWakeDoesNotResumeWhileScreenStillLocked() {
        timerManager.start()

        systemStateMonitor.debugSimulateScreenLock()
        systemStateMonitor.debugSimulateSystemWillSleep()

        XCTAssertTrue(systemStateMonitor.isScreenLocked)
        XCTAssertTrue(systemStateMonitor.isSystemSleeping)
        XCTAssertEqual(timerManager.state, .paused)

        systemStateMonitor.debugSimulateSystemDidWake()
        XCTAssertFalse(systemStateMonitor.isSystemSleeping)
        XCTAssertTrue(systemStateMonitor.isScreenLocked)
        XCTAssertEqual(timerManager.state, .paused)

        systemStateMonitor.debugSimulateScreenUnlock()
        XCTAssertEqual(timerManager.state, .working)
        XCTAssertFalse(systemStateMonitor.isSuspended)
    }

    func testUnlockDoesNotResumeManualPause() {
        timerManager.start()
        timerManager.pause()

        systemStateMonitor.debugSimulateScreenLock()
        XCTAssertEqual(timerManager.state, .paused)

        systemStateMonitor.debugSimulateScreenUnlock()
        XCTAssertEqual(timerManager.state, .paused)
        XCTAssertFalse(BreakWindowController.shared.isShowingOverlay)
    }

    func testUnlockPreservesRemainingWorkDuringPreBreakWarning() {
        let reachedExpectation = expectation(description: "no early break on unlock")
        reachedExpectation.isInverted = true

        let observer = NotificationCenter.default.addObserver(
            forName: .breakTimeReached,
            object: nil,
            queue: .main
        ) { _ in
            reachedExpectation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        timerManager.start()
        timerManager.debugAdvanceTimer(by: timerManager.workDurationSeconds - 30)
        XCTAssertEqual(timerManager.state, .preBreak)

        systemStateMonitor.debugSimulateScreenLock()
        XCTAssertEqual(timerManager.state, .paused)

        systemStateMonitor.debugSimulateScreenUnlock()

        wait(for: [reachedExpectation], timeout: 0.1)
        XCTAssertEqual(timerManager.remainingWorkTime, 30)
        XCTAssertEqual(timerManager.state, .preBreak)
    }
}
