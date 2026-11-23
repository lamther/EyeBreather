import Foundation
import AppKit
import UserNotifications
import Combine

/// 休息协调器
/// 负责监听计时器事件并协调休息流程
@MainActor
final class BreakCoordinator: ObservableObject {
    @Published private(set) var combinedStandOverlay = false
    private(set) var standCycle: String?
    /// 共享实例
    static let shared = BreakCoordinator()
    
    private var cancellables = Set<AnyCancellable>()
    
    /// 温和模式自动开始休息的定时器
    private var autoBreakTimer: Timer?
    
    /// 温和模式等待时间（秒）- 发送通知后多久自动开始休息
    private let gentleModeWaitSeconds: TimeInterval = 30
    
    /// 是否已经触发过休息（防止重复触发）
    private var breakTriggered = false

    /// 当前暂停是否由智能暂停触发，避免恢复用户手动暂停的计时器
    private var didPauseForReminder = false
    
    private init() {
        setupObservers()
        requestNotificationPermission()
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        let timer = TimerManager.shared
        timer.$standReminderPending.removeDuplicates().filter { !$0 }
            .sink { [weak self] _ in self?.clearStandPresentation() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .standTimeReached)
            .sink { [weak self] _ in self?.handleStandTimeReached() }
            .store(in: &cancellables)

        // 监听休息预警
        NotificationCenter.default.publisher(for: .preBreakWarning)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handlePreBreakWarning()
            }
            .store(in: &cancellables)
        
        // 监听休息时间到达
        NotificationCenter.default.publisher(for: .breakTimeReached)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleBreakTimeReached()
            }
            .store(in: &cancellables)
        
        // 监听休息完成
        NotificationCenter.default.publisher(for: .breakCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleBreakCompleted()
            }
            .store(in: &cancellables)
        
        // 监听是否应该暂停提醒
        NotificationCenter.default.publisher(for: .shouldPauseReminder)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleShouldPause()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .shouldResumeReminder)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleShouldResume()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Notification Permission
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("通知权限请求失败: \(error)")
            }
        }
    }
    
    // MARK: - Event Handlers
    
    private func handlePreBreakWarning() {
        // 检查是否应该暂停
        guard !AppDetector.shared.shouldPauseReminder else { return }
        
        // 发送系统通知
        sendNotification(
            title: "即将休息",
            body: "还有 \(SettingsManager.shared.settings.preBreakWarning) 秒就要休息了"
        )
    }
    
    private func handleBreakTimeReached() {
        guard canStartBreakNow else { return }
        
        // A stand deadline can fall during the gentle reminder’s 30-second grace period.
        guard !breakTriggered else {
            handleStandTimeReached()
            return
        }
        breakTriggered = true
        
        // 检查新的一天，重置统计
        BreakStatisticsManager.shared.resetConsecutiveSkipsIfNewDay()
        
        let settings = SettingsManager.shared.settings
        
        let timer = TimerManager.shared
        let includeStand = timer.isStandDue
        if includeStand {
            beginStandPresentation(combined: true)
            combinedStandOverlay = true
        }

        switch settings.reminderMode {
        case .forced:
            // 强制模式：直接显示遮罩
            startBreak(withStanding: includeStand)
            
        case .gentle:
            // 温和模式：发送通知，30秒后自动开始休息
            sendBreakNotification(includingStand: includeStand)
            scheduleAutoBreak()
            
        case .progressive:
            // 渐进模式：根据连续跳过次数决定
            if BreakStatisticsManager.shared.shouldForceBreak {
                // 跳过次数达到阈值，强制休息
                startBreak(withStanding: includeStand)
            } else {
                // 还可以跳过，发送通知
                sendBreakNotification(includingStand: includeStand)
                scheduleAutoBreak()
            }
        }
    }
    
    /// 安排自动开始休息（温和模式）
    private func scheduleAutoBreak() {
        cancelAutoBreak()
        
        // 性能优化：设置 tolerance 允许系统合并唤醒
        let timer = Timer(timeInterval: gentleModeWaitSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.canStartBreakNow else {
                    self.breakTriggered = false
                    return
                }
                // 如果还没有开始休息，自动开始
                if TimerManager.shared.state != .breaking {
                    self.startBreak()
                }
            }
        }
        timer.tolerance = 2.0  // 允许 2 秒误差
        RunLoop.main.add(timer, forMode: .common)
        autoBreakTimer = timer
    }
    
    /// 取消自动休息定时器
    private func cancelAutoBreak() {
        autoBreakTimer?.invalidate()
        autoBreakTimer = nil
    }
    
    private func handleBreakCompleted() {
        breakTriggered = false
        combinedStandOverlay = false
        BreakWindowController.shared.hideOverlay()
        TimerManager.shared.completeBreak()
        recordBreakCompleted()
        SoundManager.shared.playBreakEndSound()
        
        sendNotification(
            title: "休息完成",
            body: "休息完成，继续工作吧！"
        )
    }
    
    private func handleShouldPause() {
        cancelAutoBreak()
        breakTriggered = false

        // 全屏应用或白名单应用激活，暂停计时
        if TimerManager.shared.state == .working
            || TimerManager.shared.state == .preBreak
            || TimerManager.shared.state == .breaking {
            didPauseForReminder = true
            TimerManager.shared.pause()
        }
        
        // 如果正在显示休息遮罩，隐藏它
        if BreakWindowController.shared.isShowingOverlay {
            BreakWindowController.shared.hideOverlay()
        }
    }
    
    private func handleShouldResume() {
        guard !SystemStateMonitor.shared.isSuspended else { return }
        guard !AppDetector.shared.shouldPauseReminder else { return }
        guard didPauseForReminder else { return }

        // 恢复计时
        if TimerManager.shared.state == .paused {
            TimerManager.shared.resume()
            didPauseForReminder = false

            if TimerManager.shared.state == .breaking {
                BreakWindowController.shared.showOverlay()
            } else if TimerManager.shared.state == .preBreak || TimerManager.shared.remainingWorkTime == 0 {
                NotificationCenter.default.post(name: .breakTimeReached, object: nil)
            }
        } else {
            didPauseForReminder = false
        }
    }
    
    // MARK: - Break Actions
    
    func startBreak() {
        startBreak(withStanding: false)
    }

    private func startBreak(withStanding: Bool) {
        cancelAutoBreak()
        didPauseForReminder = false
        combinedStandOverlay = withStanding || (combinedStandOverlay && TimerManager.shared.standReminderPending)
        if !combinedStandOverlay || !SettingsManager.shared.settings.standVoiceEnabled {
            SoundManager.shared.playBreakStartSound()
        }
        TimerManager.shared.startBreak()
        BreakWindowController.shared.showOverlay()
    }
    
    func skipBreak() {
        cancelAutoBreak()
        didPauseForReminder = false
        breakTriggered = false
        combinedStandOverlay = false
        TimerManager.shared.skipBreak()
        BreakWindowController.shared.hideOverlay()
        recordBreakSkipped()
    }
    
    func delayBreak(minutes: Int) {
        cancelAutoBreak()
        didPauseForReminder = false
        breakTriggered = false
        combinedStandOverlay = false
        TimerManager.shared.delayBreak(minutes: minutes)
        BreakWindowController.shared.hideOverlay()
    }

    /// 在系统挂起时取消等待中的自动休息，避免锁屏期间偷偷进入休息
    func suspendPendingBreak() {
        cancelAutoBreak()
        breakTriggered = false
    }

    private var canStartBreakNow: Bool {
        !DoNotDisturbManager.shared.isInDoNotDisturbPeriod
            && !AppDetector.shared.shouldPauseReminder
            && !SystemStateMonitor.shared.isSuspended
    }
    
    // MARK: - Standing reminders

    private func handleStandTimeReached() {
        let timer = TimerManager.shared
        guard canStartBreakNow, timer.isStandDue else { return }
        beginStandPresentation(combined: false)
        let content = UNMutableNotificationContent()
        content.title = StandNotification.message
        content.body = "距离上次起身，已累计工作 \(timer.elapsedStandWorkSeconds / 60) 分钟。"
        content.categoryIdentifier = StandNotification.stand
        if let standCycle { content.userInfo = [StandNotification.cycleKey: standCycle] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "stand-reminder", content: content, trigger: nil
        ))
    }

    private func beginStandPresentation(combined: Bool) {
        standCycle = UUID().uuidString
        TimerManager.shared.markStandReminderPresented()
        SoundManager.shared.speakStandReminder(combined ? StandNotification.combinedMessage : StandNotification.message)
    }

    private func clearStandPresentation() {
        let hadStandPresentation = standCycle != nil
        standCycle = nil
        combinedStandOverlay = false
        if hadStandPresentation { SoundManager.shared.stopStandVoice() }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["stand-reminder"])
        center.removeDeliveredNotifications(withIdentifiers: ["stand-reminder"])
    }

    func confirmStanding() {
        guard SettingsManager.shared.settings.standReminderEnabled else { return }
        TimerManager.shared.resetStandCycle()
    }

    func snoozeStanding() {
        guard TimerManager.shared.standReminderPending else { return }
        TimerManager.shared.snoozeStanding()
    }

    func handleStandAction(_ action: String, cycle: String?) {
        guard let cycle, cycle == standCycle, TimerManager.shared.standReminderPending else { return }
        if action == StandNotification.confirm { confirmStanding() }
        if action == StandNotification.snooze { snoozeStanding() }
    }

    // MARK: - Statistics Recording
    
    private func recordBreakCompleted() {
        let breakDuration = SettingsManager.shared.settings.breakDuration
        BreakStatisticsManager.shared.recordBreakCompleted(durationSeconds: breakDuration)
    }
    
    private func recordBreakSkipped() {
        BreakStatisticsManager.shared.recordBreakSkipped()
    }
    
    // MARK: - Notifications
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // 立即发送
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func sendBreakNotification(includingStand: Bool) {
        let content = UNMutableNotificationContent()
        content.title = includingStand ? StandNotification.combinedMessage : "休息时间到"
        content.body = includingStand ? "起身活动两分钟，让眼睛也休息一下。" : "是时候让眼睛休息一下了"
        content.categoryIdentifier = includingStand ? StandNotification.combined : StandNotification.eyes
        if includingStand, let standCycle {
            content.userInfo = [StandNotification.cycleKey: standCycle]
        } else {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: includingStand ? "stand-reminder" : "break-reminder",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
}
