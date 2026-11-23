// EyeBreather/Features/Timer/MenuBarView.swift
import SwiftUI

/// 菜单栏弹出视图 - 圆环式设计
struct MenuBarView: View {
    @ObservedObject private var timerManager = TimerManager.shared
    @ObservedObject private var appDetector = AppDetector.shared
    @ObservedObject private var mediaMonitor = MediaDeviceMonitor.shared
    @ObservedObject private var statisticsManager = BreakStatisticsManager.shared
    @ObservedObject private var settingsManager = SettingsManager.shared
    
    @State private var showingStandActions = false
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(spacing: 16) {
            // 圆环进度
            circularTimerView
            
            // 状态指示
            VStack(spacing: 6) {
                statusIndicatorView
                if settingsManager.settings.standReminderEnabled {
                    standReminderView
                }
            }
            
            // 操作按钮
            actionButtonsView
            
            Divider()
                .padding(.horizontal)
            
            // 今日统计
            todayStatsView
            
            Divider()
                .padding(.horizontal)
            
            // 底部工具栏
            toolbarView
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .frame(width: 260)
        .background(.regularMaterial)
    }
    
    // MARK: - Circular Timer
    
    private var circularTimerView: some View {
        CircularProgressView(
            progress: timerProgress,
            timeText: timerText,
            subtitle: timerSubtitle,
            color: statusColor,
            size: 120
        )
        .padding(.top, 8)
    }
    
    private var timerProgress: Double {
        switch timerManager.state {
        case .breaking:
            return timerManager.breakProgress
        default:
            return timerManager.workProgress
        }
    }
    
    private var timerText: String {
        if appDetector.shouldPauseReminder {
            return "--:--"
        }
        
        switch timerManager.state {
        case .breaking:
            let remaining = timerManager.remainingBreakTime
            return String(format: "%d:%02d", remaining / 60, remaining % 60)
        default:
            let remaining = timerManager.remainingWorkTime
            return String(format: "%d:%02d", remaining / 60, remaining % 60)
        }
    }
    
    private var timerSubtitle: String {
        switch timerManager.state {
        case .breaking:
            return "休息中"
        case .idle:
            return "未启动"
        default:
            return "下次休息"
        }
    }
    
    // MARK: - Status Indicator
    
    private var statusIndicatorView: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var statusColor: Color {
        if appDetector.shouldPauseReminder {
            return .orange
        }
        switch timerManager.state {
        case .idle: return .gray
        case .working: return .green
        case .preBreak: return .yellow
        case .breaking: return .blue
        case .paused: return .orange
        }
    }
    
    private var statusText: String {
        if case .meeting = appDetector.pauseReason {
            return "会议中"
        }
        if case .focusApp(let name) = appDetector.pauseReason {
            return "专注模式 · \(name)"
        }
        switch timerManager.state {
        case .idle: return "未启动"
        case .working: return "工作中"
        case .preBreak: return "即将休息"
        case .breaking: return "休息中"
        case .paused: return "已暂停"
        }
    }
    
    // MARK: - Action Buttons

    /// 轻量次要入口，护眼圆环仍保持为主要计时信息。
    private var standReminderView: some View {
        Button { showingStandActions.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "figure.stand")
                if timerManager.standReminderPending {
                    Text("该起身活动了")
                } else {
                    Text("距起身还有")
                    Text("\(remainingStandMinutes) 分钟")
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingStandActions) {
            VStack(alignment: .leading, spacing: 8) {
                Button("我刚站过") {
                    showingStandActions = false
                    BreakCoordinator.shared.confirmStanding()
                }
                if timerManager.standReminderPending {
                    Button("10 分钟后提醒") {
                        showingStandActions = false
                        BreakCoordinator.shared.snoozeStanding()
                    }
                }
            }
            .padding(10)
        }
        .fixedSize()
        .accessibilityLabel(timerManager.standReminderPending
            ? "该起身活动了"
            : "距起身还有 \(remainingStandMinutes) 分钟")
        .accessibilityHint("记录已起身，或在提醒后延后 10 分钟")
    }

    private var remainingStandMinutes: Int {
        Int(ceil(Double(max(0, timerManager.remainingStandSeconds)) / 60))
    }
    
    private var actionButtonsView: some View {
        HStack(spacing: 12) {
            // 暂停/继续按钮
            Button(action: togglePause) {
                HStack(spacing: 4) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.caption)
                    Text(isPaused ? "继续" : "暂停")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            
            // 立即休息按钮
            Button(action: startBreakNow) {
                HStack(spacing: 4) {
                    Image(systemName: "eye.slash.fill")
                        .font(.caption)
                    Text("立即休息")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
            .disabled(timerManager.state == .breaking)
        }
        .padding(.horizontal, 4)
    }
    
    private var isPaused: Bool {
        timerManager.state == .paused || timerManager.state == .idle
    }
    
    private func togglePause() {
        switch timerManager.state {
        case .paused:
            timerManager.resume()
        case .idle:
            timerManager.start()
        case .working, .preBreak:
            timerManager.pause()
        default:
            break
        }
    }
    
    private func startBreakNow() {
        BreakCoordinator.shared.startBreak()
    }
    
    // MARK: - Today Stats
    
    private var todayStatsView: some View {
        VStack(spacing: 4) {
            HStack {
                Text("今日已休息")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(statisticsManager.todayStatistics.completedBreaks) 次")
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            
            HStack {
                Text("已跳过")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(statisticsManager.todayStatistics.skippedBreaks) 次")
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            
            if statisticsManager.todayStatistics.totalBreaks > 0 {
                HStack {
                    Text("完成率")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.0f%%", statisticsManager.todayStatistics.completionRate * 100))
                        .font(.caption)
                        .foregroundColor(statisticsManager.todayStatistics.completionRate >= 0.8 ? .green : .orange)
                }
            }
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Toolbar
    
    private var toolbarView: some View {
        HStack(spacing: 0) {
            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            
            Button(action: openStatistics) {
                Image(systemName: "chart.bar")
                    .font(.title3)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            
            Button(action: quitApp) {
                Image(systemName: "xmark.circle")
                    .font(.title3)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private func openSettings() {
        SettingsWindowController.shared.showSettings()
    }
    
    private func openStatistics() {
        StatisticsWindowController.shared.showStatistics()
    }
    
    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

#Preview {
    MenuBarView()
}
