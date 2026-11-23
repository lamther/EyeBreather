import Foundation

/// 应用设置
struct AppSettings: Codable, Equatable {
    // MARK: - 休息规则
    
    /// 工作时长（分钟），默认 20
    var workDuration: Int = 20
    
    /// 休息时长（秒），默认 20
    var breakDuration: Int = 20
    
    /// 提醒模式
    var reminderMode: ReminderMode = .gentle
    
    /// 休息预警时间（秒），默认 60
    var preBreakWarning: Int = 60
    
    /// 延迟选项（分钟）
    var delayOptions: [Int] = [5, 15, 30]
    
    /// 渐进模式：连续跳过多少次后强制休息
    var progressiveForceThreshold: Int = 3

    // MARK: - 起身提醒

    /// 独立的起身提醒，默认关闭
    var standReminderEnabled: Bool = false

    /// 累计工作多少分钟后提醒起身
    var standIntervalMinutes: Int = 50

    /// 起身提醒使用中文语音，与护眼提示音独立
    var standVoiceEnabled: Bool = true
    
    // MARK: - 智能检测
    
    /// 启用活动检测
    var enableActivityDetection: Bool = true
    
    /// 空闲重置阈值（分钟），默认 5
    var idleResetThreshold: Int = 5
    
    // MARK: - 智能暂停
    
    /// 启用会议检测（摄像头/麦克风）
    var enableMeetingDetection: Bool = true
    
    /// 专注模式应用列表
    var focusApps: [FocusApp] = FocusApp.presets
    
    /// 启用智能推荐
    var enableSmartRecommend: Bool = true
    
    // MARK: - 休息界面
    
    /// 休息界面样式
    var breakStyle: BreakStyle = .blur
    
    /// 自定义背景图片路径
    var customBackgroundPath: String? = nil
    
    /// 自定义护眼提示文字
    var customTipsText: String = "让眼睛休息一下\n看看远处，放松眼部肌肉"
    
    // MARK: - 声音提醒
    
    /// 启用声音提醒
    var enableSound: Bool = true
    
    /// 休息开始提示音
    var breakStartSound: String = "default"
    
    /// 休息结束提示音
    var breakEndSound: String = "default"
    
    // MARK: - 勿扰时段
    
    /// 启用勿扰时段
    var enableDoNotDisturb: Bool = false
    
    /// 勿扰开始时间（小时，0-23）
    var doNotDisturbStart: Int = 22
    
    /// 勿扰结束时间（小时，0-23）
    var doNotDisturbEnd: Int = 8
    
    // MARK: - 通用
    
    /// 开机自启
    var launchAtLogin: Bool = false
    
    /// 显示 Dock 图标
    var showInDock: Bool = false
    
    /// 外观模式
    var appearance: AppearanceMode = .system
    
    // MARK: - 默认值
    
    static let `default` = AppSettings()
}

// MARK: - 兼容已有设置

extension AppSettings {
    private enum CodingKeys: String, CodingKey {
        case workDuration, breakDuration, reminderMode, preBreakWarning, delayOptions
        case progressiveForceThreshold
        case standReminderEnabled, standIntervalMinutes, standVoiceEnabled
        case enableActivityDetection, idleResetThreshold, enableMeetingDetection
        case focusApps, enableSmartRecommend, breakStyle, customBackgroundPath, customTipsText
        case enableSound, breakStartSound, breakEndSound
        case enableDoNotDisturb, doNotDisturbStart, doNotDisturbEnd
        case launchAtLogin, showInDock, appearance
    }

    /// 新增字段只补默认值，保留用户已有的护眼、外观和暂停设置。
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        workDuration = try values.decodeIfPresent(Int.self, forKey: .workDuration) ?? workDuration
        breakDuration = try values.decodeIfPresent(Int.self, forKey: .breakDuration) ?? breakDuration
        reminderMode = try values.decodeIfPresent(ReminderMode.self, forKey: .reminderMode) ?? reminderMode
        preBreakWarning = try values.decodeIfPresent(Int.self, forKey: .preBreakWarning) ?? preBreakWarning
        delayOptions = try values.decodeIfPresent([Int].self, forKey: .delayOptions) ?? delayOptions
        progressiveForceThreshold = try values.decodeIfPresent(Int.self, forKey: .progressiveForceThreshold) ?? progressiveForceThreshold
        standReminderEnabled = try values.decodeIfPresent(Bool.self, forKey: .standReminderEnabled) ?? standReminderEnabled
        standIntervalMinutes = try values.decodeIfPresent(Int.self, forKey: .standIntervalMinutes) ?? standIntervalMinutes
        standVoiceEnabled = try values.decodeIfPresent(Bool.self, forKey: .standVoiceEnabled) ?? standVoiceEnabled
        enableActivityDetection = try values.decodeIfPresent(Bool.self, forKey: .enableActivityDetection) ?? enableActivityDetection
        idleResetThreshold = try values.decodeIfPresent(Int.self, forKey: .idleResetThreshold) ?? idleResetThreshold
        enableMeetingDetection = try values.decodeIfPresent(Bool.self, forKey: .enableMeetingDetection) ?? enableMeetingDetection
        focusApps = try values.decodeIfPresent([FocusApp].self, forKey: .focusApps) ?? focusApps
        enableSmartRecommend = try values.decodeIfPresent(Bool.self, forKey: .enableSmartRecommend) ?? enableSmartRecommend
        breakStyle = try values.decodeIfPresent(BreakStyle.self, forKey: .breakStyle) ?? breakStyle
        customBackgroundPath = try values.decodeIfPresent(String.self, forKey: .customBackgroundPath)
        customTipsText = try values.decodeIfPresent(String.self, forKey: .customTipsText) ?? customTipsText
        enableSound = try values.decodeIfPresent(Bool.self, forKey: .enableSound) ?? enableSound
        breakStartSound = try values.decodeIfPresent(String.self, forKey: .breakStartSound) ?? breakStartSound
        breakEndSound = try values.decodeIfPresent(String.self, forKey: .breakEndSound) ?? breakEndSound
        enableDoNotDisturb = try values.decodeIfPresent(Bool.self, forKey: .enableDoNotDisturb) ?? enableDoNotDisturb
        doNotDisturbStart = try values.decodeIfPresent(Int.self, forKey: .doNotDisturbStart) ?? doNotDisturbStart
        doNotDisturbEnd = try values.decodeIfPresent(Int.self, forKey: .doNotDisturbEnd) ?? doNotDisturbEnd
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? launchAtLogin
        showInDock = try values.decodeIfPresent(Bool.self, forKey: .showInDock) ?? showInDock
        appearance = try values.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? appearance
    }
}

// MARK: - UserDefaults 存储

extension AppSettings {
    private static let storageKey = "com.eyebreather.settings"
    
    /// 从 UserDefaults 加载设置
    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return settings
    }
    
    /// 保存到 UserDefaults
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
