import Foundation
import Combine
import CoreGraphics

/// 计时器管理器
@MainActor
final class TimerManager: ObservableObject {
    /// 共享实例
    static let shared = TimerManager()
    
    // MARK: - Published Properties
    
    /// 当前状态
    @Published private(set) var state: TimerState = .idle
    
    /// 当前周期已工作时间（秒）
    @Published private(set) var elapsedWorkTime: Int = 0
    
    /// 当前休息已用时间（秒）
    @Published private(set) var elapsedBreakTime: Int = 0

    /// 站立周期累计的工作时间（秒）
    @Published private(set) var elapsedStandWorkSeconds = 0

    /// 站立提醒已发出，等待用户操作
    @Published private(set) var standReminderPending = false
    
    /// 上次活动时间
    @Published private(set) var lastActivityTime: Date = Date()
    
    // MARK: - Private Properties
    
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var stateBeforePause: TimerState?
    private var lastTickDate: Date?
    private var tickRemainder: TimeInterval = 0
    private var didCompleteCurrentBreak = false
    private var now: () -> Date = Date.init
    private var readHIDIdleSeconds: () -> TimeInterval? = TimerManager.hidIdleSeconds
    private var timerEvents: NotificationCenter = .default
    private var standReminderEnabled: Bool
    private var lastStandTickDate: Date?
    private var standTickWasBlocked = false
    private var standTickRemainder: TimeInterval = 0
    private var standSnoozeDeadline: Int?
    private var standLastPresentedAt: Int?
    private var lastStandActivityTime = Date()
    
    // MARK: - Computed Properties
    
    /// 工作时长设置（秒）
    var workDurationSeconds: Int {
        SettingsManager.shared.settings.workDuration * 60
    }
    
    /// 休息时长设置（秒）
    var breakDurationSeconds: Int {
        SettingsManager.shared.settings.breakDuration
    }
    
    /// 预警时间设置（秒）
    var preBreakWarningSeconds: Int {
        SettingsManager.shared.settings.preBreakWarning
    }
    
    /// 工作进度（0-1）
    var workProgress: Double {
        guard workDurationSeconds > 0 else { return 0 }
        return min(1.0, Double(elapsedWorkTime) / Double(workDurationSeconds))
    }
    
    /// 休息进度（0-1）
    var breakProgress: Double {
        guard breakDurationSeconds > 0 else { return 0 }
        return min(1.0, Double(elapsedBreakTime) / Double(breakDurationSeconds))
    }
    
    /// 距离下次休息的剩余时间（秒）
    var remainingWorkTime: Int {
        max(0, workDurationSeconds - elapsedWorkTime)
    }
    
    /// 剩余休息时间（秒）
    var remainingBreakTime: Int {
        max(0, breakDurationSeconds - elapsedBreakTime)
    }

    var remainingStandSeconds: Int {
        guard !standReminderPending else { return 0 }
        return max(0, standDeadline - elapsedStandWorkSeconds)
    }

    var isStandDue: Bool {
        !standReminderPending && remainingStandSeconds == 0 && canCountStandWork(at: now())
    }

    private var standDeadline: Int {
        standSnoozeDeadline ?? (standLastPresentedAt ?? 0) + SettingsManager.shared.settings.standIntervalMinutes * 60
    }
    
    /// 是否处于预警阶段
    var isInPreBreakWarning: Bool {
        remainingWorkTime <= preBreakWarningSeconds && remainingWorkTime > 0
    }
    
    // MARK: - Initialization
    
    private init() {
        standReminderEnabled = SettingsManager.shared.settings.standReminderEnabled
        observeSettingsChanges()
    }
    
    private func observeSettingsChanges() {
        NotificationCenter.default.publisher(for: .settingsDidChange)
            .sink { [weak self] _ in
                // SettingsManager 在主线程同步发布设置变更，避免遗漏短时间的关闭再开启。
                guard let self else { return }
                let enabled = SettingsManager.shared.settings.standReminderEnabled
                guard enabled != self.standReminderEnabled else { return }
                self.standReminderEnabled = enabled
                self.resetStandCycle()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// 开始工作计时
    func start() {
        guard state == .idle || state == .paused else { return }
        
        state = .working
        lastActivityTime = now()
        startTimer()
    }
    
    /// 暂停计时
    func pause() {
        guard state == .working || state == .preBreak || state == .breaking else { return }
        
        updateStandClock(at: now())
        stateBeforePause = state
        state = .paused
        stopTimer()
    }
    
    /// 继续计时
    func resume() {
        guard state == .paused else { return }
        
        state = stateBeforePause ?? .working
        stateBeforePause = nil
        lastActivityTime = now()
        startTimer()
    }
    
    /// 开始休息
    func startBreak() {
        updateStandClock(at: now())
        stateBeforePause = nil
        state = .breaking
        elapsedBreakTime = 0
        didCompleteCurrentBreak = false
        stopTimer()
        startTimer()
    }
    
    /// 跳过休息
    func skipBreak() {
        resetWorkCycle()
    }
    
    /// 延迟休息
    func delayBreak(minutes: Int) {
        updateStandClock(at: now())
        // 减少已工作时间，相当于延迟
        stateBeforePause = nil
        elapsedWorkTime = max(0, workDurationSeconds - minutes * 60)
        state = .working
        stopTimer()
        startTimer()
    }
    
    /// 完成休息
    func completeBreak() {
        resetWorkCycle()
    }
    
    /// 重置工作周期
    func resetWorkCycle() {
        NotificationCenter.default.post(name: .eyeWorkCycleReset, object: self)
        updateStandClock(at: now())
        stopTimer()
        stateBeforePause = nil
        state = .working
        elapsedWorkTime = 0
        elapsedBreakTime = 0
        didCompleteCurrentBreak = false
        lastActivityTime = now()
        startTimer()
    }

    func markStandReminderPresented() {
        guard isStandDue else { return }
        standLastPresentedAt = elapsedStandWorkSeconds
        standSnoozeDeadline = nil
        standReminderPending = true
    }

    func resetStandCycle() {
        resetStandCycle(at: now())
    }

    func snoozeStanding() {
        guard standReminderEnabled else { return }
        standSnoozeDeadline = elapsedStandWorkSeconds + 10 * 60
        standTickRemainder = 0
        if lastStandTickDate != nil {
            lastStandTickDate = now()
        }
        standReminderPending = false
    }

    /// 活动监听启动或恢复时建立新的空闲基准。
    func beginActivityTracking(at date: Date) {
        lastStandActivityTime = date
    }

    func checkStandIdleAfterSuspension(seconds: Int) {
        let date = now()
        let idleThreshold = SettingsManager.shared.settings.idleResetThreshold * 60
        if seconds >= idleThreshold || isStandUserIdle(at: date) {
            resetStandCycle(at: date)
        }
        refreshStandActivity(at: date)
    }
    
    /// 记录用户活动
    func recordActivity(at date: Date? = nil) {
        let date = date ?? now()
        if refreshStandActivity(at: date) == nil {
            recordStandActivity(at: date)
        }
        lastActivityTime = date
    }

    /// Quartz reports only elapsed time since the last HID input, including keyboard input in other apps.
    private nonisolated static func hidIdleSeconds() -> TimeInterval? {
        // kCGAnyInputEventType is a C macro that Swift does not import.
        guard let anyInput = CGEventType(rawValue: UInt32.max) else { return nil }
        let seconds = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
        return seconds.isFinite && seconds >= 0 ? seconds : nil
    }
    
    /// 检查空闲重置
    func checkIdleReset() {
        let date = now()
        refreshStandActivity(at: date)
        if isStandUserIdle(at: date) {
            resetStandCycle(at: date)
        }
        guard state == .working || state == .preBreak else { return }

        let idleThreshold = SettingsManager.shared.settings.idleResetThreshold * 60
        let idleTime = Int(date.timeIntervalSince(lastActivityTime))
        
        if idleTime >= idleThreshold {
            resetWorkCycle()
        }
    }

    /// ActivityMonitor also samples while the work timer is paused or resting.
    func sampleSystemActivity() -> Date? {
        refreshStandActivity(at: now())
    }
    
    // MARK: - Private Methods
    
    private func startTimer() {
        stopTimer()
        // 工作态用 5 秒粒度，休息态保留 1 秒倒计时体验
        let interval = state == .breaking ? 1.0 : 5.0
        let leewayMs: Int = state == .breaking ? 100 : 500

        // 使用 DispatchSourceTimer，减少主线程唤醒和调度成本
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(leewayMs))
        source.setEventHandler { [weak self] in
            self?.tick()
        }
        source.resume()
        dispatchTimer = source
        lastTickDate = now()
        tickRemainder = 0
        if state == .working || state == .preBreak {
            lastStandTickDate = lastTickDate
        }
    }
    
    /// DispatchSource 定时器
    private var dispatchTimer: DispatchSourceTimer?
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        dispatchTimer?.cancel()
        dispatchTimer = nil
        lastTickDate = nil
        tickRemainder = 0
        lastStandTickDate = nil
        standTickWasBlocked = false
    }
    
    private func tick() {
        let now = self.now()
        updateStandClock(at: now)
        let elapsedSinceLastTick: Int
        if let lastTickDate {
            // 累积小数秒，避免 5 秒粒度下重复向下取整导致计时变慢
            let elapsed = max(0, now.timeIntervalSince(lastTickDate))
            let accumulated = tickRemainder + elapsed
            elapsedSinceLastTick = Int(accumulated)
            tickRemainder = accumulated - TimeInterval(elapsedSinceLastTick)
        } else {
            elapsedSinceLastTick = 0
            tickRemainder = 0
        }
        lastTickDate = now

        guard elapsedSinceLastTick > 0 else { return }

        advanceTimer(by: elapsedSinceLastTick)
    }

    private func isStandUserIdle(at date: Date) -> Bool {
        let settings = SettingsManager.shared.settings
        return settings.enableActivityDetection
            && date.timeIntervalSince(lastStandActivityTime) >= TimeInterval(settings.idleResetThreshold * 60)
    }

    @discardableResult
    private func refreshStandActivity(at date: Date) -> Date? {
        guard SettingsManager.shared.settings.enableActivityDetection,
              let idleSeconds = readHIDIdleSeconds() else { return nil }
        let lastInput = date.addingTimeInterval(-idleSeconds)
        recordStandActivity(at: lastInput)
        if lastInput > lastActivityTime {
            lastActivityTime = lastInput
        }
        return lastInput
    }

    private func recordStandActivity(at date: Date) {
        guard date > lastStandActivityTime else { return }
        // If input resumes between ticks, compare the two activity timestamps before replacing the previous one.
        if isStandUserIdle(at: date) {
            resetStandCycle(at: date)
            standTickWasBlocked = false
        }
        lastStandActivityTime = date
    }

    private func canCountStandWork(at date: Date) -> Bool {
        standReminderEnabled
            && (state == .working || state == .preBreak)
            && !isStandUserIdle(at: date)
            && !SystemStateMonitor.shared.isSuspended
            && !AppDetector.shared.shouldPauseReminder
            && !DoNotDisturbManager.shared.isInDoNotDisturbPeriod
    }

    private func updateStandClock(at date: Date) {
        guard lastStandTickDate != nil, standReminderEnabled else { return }
        refreshStandActivity(at: date)
        guard let previousTick = lastStandTickDate else { return }
        let wasBlocked = standTickWasBlocked
        lastStandTickDate = date
        standTickWasBlocked = !canCountStandWork(at: date)

        if isStandUserIdle(at: date) {
            resetStandCycle(at: date)
        } else if !wasBlocked && !standTickWasBlocked {
            accumulateStandWork(max(0, date.timeIntervalSince(previousTick)))
        }
    }

    private func accumulateStandWork(_ seconds: TimeInterval) {
        let elapsed = standTickRemainder + seconds
        let wholeSeconds = Int(elapsed)
        standTickRemainder = elapsed - TimeInterval(wholeSeconds)
        if wholeSeconds > 0 {
            elapsedStandWorkSeconds += wholeSeconds
            if standReminderPending && elapsedStandWorkSeconds >= standDeadline {
                standReminderPending = false
            }
        }
    }

    private func resetStandCycle(at date: Date) {
        standSnoozeDeadline = nil
        standLastPresentedAt = nil
        standTickRemainder = 0
        if lastStandTickDate != nil {
            lastStandTickDate = date
        }
        if elapsedStandWorkSeconds != 0 {
            elapsedStandWorkSeconds = 0
        }
        if standReminderPending {
            standReminderPending = false
        }
    }

    private func advanceTimer(by elapsedSinceLastTick: Int) {
        guard elapsedSinceLastTick > 0 else { return }

        switch state {
        case .working, .preBreak:
            elapsedWorkTime += elapsedSinceLastTick
            
            let enteredWarning = isInPreBreakWarning && state == .working
            if enteredWarning {
                state = .preBreak
            }

            if elapsedWorkTime >= workDurationSeconds {
                timerEvents.post(name: .breakTimeReached, object: nil)
            } else if isStandDue {
                timerEvents.post(
                    name: .standTimeReached,
                    object: nil,
                    userInfo: ["includesEyeWarning": enteredWarning]
                )
            } else if enteredWarning {
                timerEvents.post(name: .preBreakWarning, object: nil)
            }
            
        case .breaking:
            elapsedBreakTime = min(breakDurationSeconds, elapsedBreakTime + elapsedSinceLastTick)
            
            // 检查休息是否完成
            if elapsedBreakTime >= breakDurationSeconds {
                finishCurrentBreakTimer()
            }
            
        case .idle, .paused:
            break
        }
    }

    private func finishCurrentBreakTimer() {
        guard state == .breaking, !didCompleteCurrentBreak else { return }

        didCompleteCurrentBreak = true
        stopTimer()
        timerEvents.post(name: .breakCompleted, object: nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let eyeWorkCycleReset = Notification.Name("com.eyebreather.eyeWorkCycleReset")
    static let preBreakWarning = Notification.Name("com.eyebreather.preBreakWarning")
    static let breakTimeReached = Notification.Name("com.eyebreather.breakTimeReached")
    static let breakCompleted = Notification.Name("com.eyebreather.breakCompleted")
    static let standTimeReached = Notification.Name("com.eyebreather.standTimeReached")
}

#if DEBUG
extension TimerManager {
    func debugSetState(_ newState: TimerState) {
        state = newState
    }

    func debugAdvanceTimer(by seconds: Int) {
        if seconds > 0, canCountStandWork(at: now()) {
            accumulateStandWork(TimeInterval(seconds))
        }
        advanceTimer(by: seconds)
    }

    func debugUseClock(
        _ clock: @escaping () -> Date,
        events: NotificationCenter,
        hidIdleSeconds: @escaping () -> TimeInterval? = { nil }
    ) {
        now = clock
        timerEvents = events
        readHIDIdleSeconds = hidIdleSeconds
        lastStandActivityTime = now()
    }

    func debugTick() {
        tick()
    }

    func debugResetForTests() {
        stopTimer()
        now = Date.init
        timerEvents = .default
        readHIDIdleSeconds = Self.hidIdleSeconds
        lastStandActivityTime = now()
        resetStandCycle()
        stateBeforePause = nil
        state = .idle
        elapsedWorkTime = 0
        elapsedBreakTime = 0
        lastActivityTime = now()
        didCompleteCurrentBreak = false
    }

    func debugSetLastActivityTime(_ date: Date) {
        lastActivityTime = date
        lastStandActivityTime = date
    }
}
#endif
