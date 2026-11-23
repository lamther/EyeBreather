import XCTest
@testable import EyeBreather

final class AppSettingsLegacyCompatibilityTests: XCTestCase {
    func testLegacySettingsKeepAllExistingChoicesAndDefaultOnlyStandingFields() throws {
        // 升级前保存的完整设置，不包含任何起身提醒字段。
        let legacyJSON = #"""
        {
          "workDuration": 35,
          "breakDuration": 45,
          "reminderMode": "progressive",
          "preBreakWarning": 30,
          "delayOptions": [2, 10],
          "progressiveForceThreshold": 5,
          "enableActivityDetection": false,
          "idleResetThreshold": 12,
          "enableMeetingDetection": false,
          "focusApps": [{"bundleId": "com.apple.Safari", "name": "Safari", "isPreset": false}],
          "enableSmartRecommend": false,
          "breakStyle": "custom",
          "customBackgroundPath": "/Users/example/Pictures/rest.jpg",
          "customTipsText": "看看窗外",
          "enableSound": false,
          "breakStartSound": "glass",
          "breakEndSound": "ping",
          "enableDoNotDisturb": true,
          "doNotDisturbStart": 23,
          "doNotDisturbEnd": 7,
          "launchAtLogin": true,
          "showInDock": true,
          "appearance": "dark"
        }
        """#

        var expected = AppSettings()
        expected.workDuration = 35
        expected.breakDuration = 45
        expected.reminderMode = .progressive
        expected.preBreakWarning = 30
        expected.delayOptions = [2, 10]
        expected.progressiveForceThreshold = 5
        expected.enableActivityDetection = false
        expected.idleResetThreshold = 12
        expected.enableMeetingDetection = false
        expected.focusApps = [FocusApp(bundleId: "com.apple.Safari", name: "Safari", isPreset: false)]
        expected.enableSmartRecommend = false
        expected.breakStyle = .custom
        expected.customBackgroundPath = "/Users/example/Pictures/rest.jpg"
        expected.customTipsText = "看看窗外"
        expected.enableSound = false
        expected.breakStartSound = "glass"
        expected.breakEndSound = "ping"
        expected.enableDoNotDisturb = true
        expected.doNotDisturbStart = 23
        expected.doNotDisturbEnd = 7
        expected.launchAtLogin = true
        expected.showInDock = true
        expected.appearance = .dark

        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(decoded, expected)
        XCTAssertFalse(decoded.standReminderEnabled)
        XCTAssertEqual(decoded.standIntervalMinutes, 50)
        XCTAssertTrue(decoded.standVoiceEnabled)
        let reloaded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(reloaded, expected)
    }

    func testStandingSettingsRoundTripIndependentlyOfEyeBreakSound() throws {
        var settings = AppSettings()
        settings.standReminderEnabled = true
        settings.standIntervalMinutes = 65
        settings.standVoiceEnabled = false
        settings.enableSound = true

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        XCTAssertEqual(decoded, settings)
        XCTAssertTrue(decoded.enableSound)
        XCTAssertFalse(decoded.standVoiceEnabled)
    }

    func testEarlierPartialSettingsRetainChoices() throws {
        let data = Data(#"{"workDuration":40,"enableSound":false,"appearance":"light"}"#.utf8)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.workDuration, 40)
        XCTAssertFalse(decoded.enableSound)
        XCTAssertEqual(decoded.appearance, .light)
        XCTAssertEqual(decoded.breakDuration, AppSettings.default.breakDuration)
        XCTAssertFalse(decoded.standReminderEnabled)
        XCTAssertTrue(decoded.standVoiceEnabled)
    }
}
