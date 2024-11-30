import Foundation

class LanguageManager {
    static let shared = LanguageManager()
    
    private let supportedLanguages = ["en", "zh-Hans"]
    private var currentLanguage: String
    
    private init() {
        // 获取系统语言
        let preferredLanguage = Locale.preferredLanguages.first ?? "en"
        
        // 检查是否支持该语言，如果不支持则使用英语
        if supportedLanguages.contains(where: { preferredLanguage.starts(with: $0) }) {
            currentLanguage = preferredLanguage
        } else {
            currentLanguage = "en"
        }
    }
    
    func localizedString(_ key: String) -> String {
        let translations: [String: [String: String]] = [
            "en": [
                "Today": "Today",
                "Yesterday": "Yesterday",
                "Take Screenshot": "Take Screenshot",
                "Delete": "Delete",
                "Open Folder": "Open Folder",
                "Camera not available": "Camera not available",
                "Timer": "Timer",
                "Settings": "Settings",
                "Launch at Login": "Launch at Login",
                "Silent Mode": "Silent Mode",
                "Start in background when launched at login": "Start in background when launched at login",
                "Interval": "Interval",
                "seconds": "seconds",
                "Export Video": "Export Video",
                "Video Export Completed": "Video Export Completed",
                "The timelapse video has been saved successfully.": "The timelapse video has been saved successfully.",
                "Video Export Failed": "Video Export Failed",
                "Export Timelapse": "Export Timelapse",
                "Export Timelapse Video": "Export Timelapse Video",
                "Would you like to show timestamps in the video?": "Would you like to show timestamps in the video?",
                "Yes": "Yes",
                "No": "No"
            ],
            "zh-Hans": [
                "Today": "今天",
                "Yesterday": "昨天",
                "Take Screenshot": "拍摄截图",
                "Delete": "删除",
                "Open Folder": "打开文件夹",
                "Camera not available": "相机不可用",
                "Timer": "定时器",
                "Settings": "设置",
                "Launch at Login": "开机启动",
                "Silent Mode": "静默模式",
                "Start in background when launched at login": "开机启动时在后台运行",
                "Interval": "间隔",
                "seconds": "秒",
                "Export Video": "导出视频",
                "Video Export Completed": "视频导出完成",
                "The timelapse video has been saved successfully.": "延时摄影视频已成功保存。",
                "Video Export Failed": "视频导出失败",
                "Export Timelapse": "导出延时摄影",
                "Export Timelapse Video": "导出延时摄影视频",
                "Would you like to show timestamps in the video?": "是否在视频中显示时间戳？",
                "Yes": "是",
                "No": "否"
            ]
        ]
        
        // 获取当前语言的翻译
        let languageCode = currentLanguage.starts(with: "zh") ? "zh-Hans" : "en"
        return translations[languageCode]?[key] ?? key
    }
    
    func localizedDate(_ date: Date, format: String = "MMM d, yyyy") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: currentLanguage)
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

// 便捷访问方法
func LocalizedString(_ key: String) -> String {
    return LanguageManager.shared.localizedString(key)
}

func LocalizedDate(_ date: Date, format: String = "MMM d, yyyy") -> String {
    return LanguageManager.shared.localizedDate(date, format: format)
}
