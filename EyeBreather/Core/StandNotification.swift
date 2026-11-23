import UserNotifications

/// Notification Center replaces all registered categories in a single operation.
/// Register the eye, stand and combined actions together on launch.
enum StandNotification {
    static let stand = "STAND_REMINDER"
    static let combined = "BREAK_AND_STAND_REMINDER"
    static let eyes = "BREAK_REMINDER"
    static let confirm = "CONFIRM_STANDING"
    static let snooze = "SNOOZE_STANDING"
    static let message = "起来走两分钟吧"
    static let combinedMessage = "起来走走，顺便看看远处"
    static let cycleKey = "standCycle"

    static func categories() -> Set<UNNotificationCategory> {
        let standActions = [
            UNNotificationAction(identifier: confirm, title: "已起身"),
            UNNotificationAction(identifier: snooze, title: "10 分钟后提醒")
        ]
        let eyeActions = [
            UNNotificationAction(identifier: "START_BREAK", title: "开始休息", options: .foreground),
            UNNotificationAction(identifier: "SKIP_BREAK", title: "跳过"),
            UNNotificationAction(identifier: "DELAY_5MIN", title: "5分钟后提醒")
        ]
        func category(_ id: String, _ actions: [UNNotificationAction]) -> UNNotificationCategory {
            UNNotificationCategory(identifier: id, actions: actions, intentIdentifiers: [])
        }
        return [category(stand, standActions), category(eyes, eyeActions),
                category(combined, standActions + Array(eyeActions.suffix(2)))]
    }
}
