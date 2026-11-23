import XCTest
import UserNotifications
@testable import EyeBreather

@MainActor
final class StandPresentationTests: XCTestCase {
    func testStandActionsRegisteredAlongsideEyeActions() throws {
        let categories = StandNotification.categories()
        let stand = try XCTUnwrap(categories.first { $0.identifier == StandNotification.stand })
        XCTAssertEqual(stand.actions.map(\.title), ["已起身", "10 分钟后提醒"])
        XCTAssertTrue(categories.contains { $0.identifier == StandNotification.eyes })
        let combined = try XCTUnwrap(categories.first { $0.identifier == StandNotification.combined })
        XCTAssertTrue(combined.actions.contains { $0.identifier == StandNotification.snooze })
        XCTAssertTrue(combined.actions.contains { $0.identifier == "START_BREAK" })
    }

    func testCombinedDeadlineAcceptsOnlyCurrentNotificationAndPreservesEyeClock() throws {
        let coordinator = BreakCoordinator.shared
        let timer = TimerManager.shared
        let saved = SettingsManager.shared.settings
        defer {
            coordinator.suspendPendingBreak()
            timer.debugResetForTests()
            SettingsManager.shared.settings = saved
        }
        var settings = AppSettings.default
        settings.standReminderEnabled = true
        settings.standIntervalMinutes = 10
        settings.workDuration = 10
        settings.enableActivityDetection = false
        settings.enableMeetingDetection = false
        settings.focusApps = []
        settings.standVoiceEnabled = false
        SettingsManager.shared.settings = settings
        timer.debugResetForTests()
        timer.start()
        timer.debugAdvanceTimer(by: 600)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(coordinator.combinedStandOverlay)
        let cycle = try XCTUnwrap(coordinator.standCycle)
        let delegate = AppDelegate()
        delegate.handleNotificationAction(actionIdentifier: StandNotification.confirm,
                                          categoryIdentifier: StandNotification.combined, standCycle: "stale")
        XCTAssertTrue(timer.standReminderPending)
        delegate.handleNotificationAction(actionIdentifier: StandNotification.snooze,
                                          categoryIdentifier: StandNotification.combined, standCycle: cycle)
        XCTAssertFalse(timer.standReminderPending)
        XCTAssertEqual(timer.remainingStandSeconds, 600)
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 600)
        XCTAssertEqual(timer.remainingWorkTime, 0)
        coordinator.confirmStanding()
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 0)
        XCTAssertEqual(timer.remainingWorkTime, 0)
    }
}
