import XCTest
@testable import EyeBreather

@MainActor
final class StandTimerTests: XCTestCase {
    private let timer = TimerManager.shared
    private let notifications = NotificationCenter()
    private var originalSettings: AppSettings!
    private var clock = Date()

    override func setUp() {
        super.setUp()
        originalSettings = SettingsManager.shared.settings
        var settings = AppSettings.default
        settings.standReminderEnabled = true
        settings.standIntervalMinutes = 10
        settings.standVoiceEnabled = false
        settings.workDuration = 20
        settings.enableActivityDetection = false
        settings.enableMeetingDetection = false
        settings.focusApps = []
        SettingsManager.shared.settings = settings

        clock = Date()
        timer.debugResetForTests()
        timer.debugUseClock({ [unowned self] in clock }, events: notifications)
        timer.start()
    }

    override func tearDown() {
        timer.debugResetForTests()
        SettingsManager.shared.settings = originalSettings
        super.tearDown()
    }

    private func tick(after seconds: TimeInterval) {
        clock += seconds
        timer.debugTick()
    }

    func testCountsWorkAcrossEyeBreakDelaySkipAndRest() {
        tick(after: 100.5)
        timer.delayBreak(minutes: 1)
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 100)

        tick(after: 0.5)
        XCTAssertEqual(timer.state, .working)
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 101)

        tick(after: 1)
        XCTAssertEqual(timer.state, .preBreak)
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 102)

        timer.skipBreak()
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 102)
        timer.startBreak()
        tick(after: 10)
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 102)
        timer.completeBreak()
        tick(after: 10)
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 112)
    }

    func testPauseAndShortSuspensionPreserveProgressLongLockClearsIt() {
        let system = SystemStateMonitor.shared
        system.debugResetState()
        defer { system.debugResetState() }

        tick(after: 120)
        timer.pause()
        tick(after: 40)
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 120)
        timer.resume()

        system.debugSimulateScreenLock()
        tick(after: 40)
        system.debugSimulateScreenUnlock()
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 120)

        system.debugSimulateScreenLock()
        system.debugSetSuspensionDuration(5 * 60)
        system.debugSimulateSystemDidWake()
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 120)
        system.debugSimulateScreenUnlock()
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 0)

        tick(after: 5)
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 5)
    }

    func testInactivityBeforeAndDuringLockCountsTowardOneIdleThreshold() {
        let system = SystemStateMonitor.shared
        system.debugResetState()
        defer { system.debugResetState() }
        SettingsManager.shared.settings.enableActivityDetection = true
        SettingsManager.shared.settings.idleResetThreshold = 5

        tick(after: 3 * 60)
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 3 * 60)
        system.debugSimulateScreenLock()
        clock += 3 * 60
        system.debugSetSuspensionDuration(3 * 60)
        system.debugSimulateScreenUnlock()

        XCTAssertEqual(timer.elapsedStandWorkSeconds, 0)
        tick(after: 5)
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 0)
        timer.recordActivity()
        tick(after: 5)
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 5)
    }

    func testUnlockAndUnrelatedSettingsPreserveIdleTimeJustBelowThreshold() {
        let system = SystemStateMonitor.shared
        system.debugResetState()
        defer { system.debugResetState() }
        SettingsManager.shared.settings.enableActivityDetection = true
        SettingsManager.shared.settings.idleResetThreshold = 5

        tick(after: 3 * 60)
        system.debugSimulateScreenLock()
        clock += 119
        system.debugSetSuspensionDuration(119)
        system.debugSimulateScreenUnlock()
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 3 * 60)
        let handledSettingChange = expectation(description: "activity monitor processed the setting change")
        SettingsManager.shared.settings.customTipsText += "。"
        DispatchQueue.main.async { handledSettingChange.fulfill() }
        wait(for: [handledSettingChange], timeout: 1)

        tick(after: 1)
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 0)
    }

    func testFirstActivityAfterThresholdResetsEvenBeforeIdleCheck() {
        SettingsManager.shared.settings.enableActivityDetection = true
        SettingsManager.shared.settings.idleResetThreshold = 1

        tick(after: 59)
        timer.recordActivity()
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 59)

        tick(after: 59)
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 118)
        clock += 1
        timer.recordActivity()
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 0)

        tick(after: 5)
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 5)
    }

    func testCrossingIdleThresholdClearsDueAndIdleTicksDoNotAccumulate() {
        SettingsManager.shared.settings.enableActivityDetection = true
        SettingsManager.shared.settings.idleResetThreshold = 10

        tick(after: 599)
        XCTAssertEqual(timer.remainingStandSeconds, 1)
        tick(after: 1)
        XCTAssertFalse(timer.isStandDue)
        XCTAssertEqual(timer.remainingStandSeconds, 600)

        timer.checkIdleReset()
        tick(after: 30)
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 0)
        timer.recordActivity()
        tick(after: 5)
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 5)
    }

    func testDisablingAndImmediatelyEnablingStartsFreshAtSettingChange() {
        tick(after: 600)
        timer.markStandReminderPresented()
        XCTAssertTrue(timer.standReminderPending)

        clock += 2
        SettingsManager.shared.settings.standReminderEnabled = false
        XCTAssertFalse(timer.standReminderPending)
        XCTAssertFalse(timer.isStandDue)
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 0)

        clock += 2
        SettingsManager.shared.settings.standReminderEnabled = true
        XCTAssertEqual(timer.remainingStandSeconds, 600)
        tick(after: 1)
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 1)
    }

    func testSnoozeRequiresTenMoreWorkingMinutes() {
        tick(after: 600)
        XCTAssertTrue(timer.isStandDue)
        timer.markStandReminderPresented()
        XCTAssertFalse(timer.isStandDue)

        timer.snoozeStanding()
        XCTAssertFalse(timer.standReminderPending)
        XCTAssertEqual(timer.remainingStandSeconds, 600)
        timer.delayBreak(minutes: 20)
        tick(after: 590)
        timer.pause()
        tick(after: 30)
        XCTAssertEqual(timer.remainingStandSeconds, 10)
        timer.resume()
        tick(after: 10)
        XCTAssertTrue(timer.isStandDue)

        timer.resetStandCycle()
        XCTAssertFalse(timer.isStandDue)
        XCTAssertEqual(timer.remainingStandSeconds, 600)
    }

    func testUnansweredReminderRepeatsAfterOneMoreWorkingInterval() {
        SettingsManager.shared.settings.workDuration = 30
        let events = StandTimerEventRecorder(center: notifications)

        tick(after: 600)
        timer.markStandReminderPresented()
        tick(after: 599)
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 1199)
        XCTAssertTrue(timer.standReminderPending)
        XCTAssertEqual(events.names, [.standTimeReached])
        XCTAssertEqual(events.includesEyeWarning, [false])

        tick(after: 1)
        XCTAssertFalse(timer.standReminderPending)
        XCTAssertTrue(timer.isStandDue)
        XCTAssertEqual(timer.elapsedStandWorkSeconds, 1200)
        XCTAssertEqual(events.names, [.standTimeReached, .standTimeReached])
    }

    func testStandSharesEyeBreakAtDeadlineAndSupersedesPreWarning() {
        let events = StandTimerEventRecorder(center: notifications)
        SettingsManager.shared.settings.workDuration = 10
        tick(after: 600)
        XCTAssertTrue(timer.isStandDue)
        XCTAssertEqual(events.names, [.breakTimeReached])
        XCTAssertTrue(events.includesEyeWarning.isEmpty)

        timer.resetStandCycle()
        timer.resetWorkCycle()
        events.names.removeAll()
        SettingsManager.shared.settings.workDuration = 11
        SettingsManager.shared.settings.preBreakWarning = 60
        tick(after: 600)
        XCTAssertEqual(timer.state, .preBreak)
        XCTAssertEqual(events.names, [.standTimeReached])
        XCTAssertEqual(events.includesEyeWarning, [true])

        timer.markStandReminderPresented()
        tick(after: 5)
        XCTAssertEqual(events.names, [.standTimeReached])
    }
}

@MainActor
private final class StandTimerEventRecorder {
    var names: [Notification.Name] = []
    var includesEyeWarning: [Bool] = []
    private let center: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    init(center: NotificationCenter) {
        self.center = center
        observers = [.standTimeReached, .breakTimeReached, .preBreakWarning].map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] notification in
                let includesEyeWarning = notification.userInfo?["includesEyeWarning"] as? Bool
                MainActor.assumeIsolated {
                    self?.names.append(name)
                    if let includesEyeWarning {
                        self?.includesEyeWarning.append(includesEyeWarning)
                    }
                }
            }
        }
    }

    deinit {
        observers.forEach { center.removeObserver($0) }
    }
}
