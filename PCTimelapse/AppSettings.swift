import Foundation
import ServiceManagement

class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLoginItem()
        }
    }
    
    @Published var silentMode: Bool {
        didSet {
            UserDefaults.standard.set(silentMode, forKey: "silentMode")
        }
    }
    
    @Published var language: String {
        didSet {
            UserDefaults.standard.set(language, forKey: "AppLanguage")
        }
    }
    
    @Published var timerInterval: TimeInterval {
        didSet {
            UserDefaults.standard.set(timerInterval, forKey: "TimerInterval")
        }
    }
    
    private init() {
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        self.silentMode = UserDefaults.standard.bool(forKey: "silentMode")
        
        // 从 UserDefaults 读取语言设置，默认为系统语言
        self.language = UserDefaults.standard.string(forKey: "AppLanguage") ?? Locale.current.language.languageCode?.identifier ?? "en"
        
        // 从 UserDefaults 读取定时器间隔，默认为 1 秒
        self.timerInterval = UserDefaults.standard.double(forKey: "TimerInterval") != 0 ? 
            UserDefaults.standard.double(forKey: "TimerInterval") : 1.0
    }
    
    private func updateLoginItem() {
        if #available(macOS 13.0, *) {
            // 使用新的 ServiceManagement API
            do {
                try SMAppService.mainApp.register()
            } catch {
                print("Failed to register login item: \(error)")
            }
        } else {
            // 使用旧的 API
            if let bundleIdentifier = Bundle.main.bundleIdentifier {
                if launchAtLogin {
                    let config = [
                        "Label": bundleIdentifier,
                        "Program": Bundle.main.bundlePath,
                        "RunAtLoad": true,
                    ] as [String : Any]
                    
                    let path = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Library/LaunchAgents")
                        .appendingPathComponent("\(bundleIdentifier).plist")
                    
                    do {
                        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(),
                                                             withIntermediateDirectories: true)
                        try (config as NSDictionary).write(to: path)
                    } catch {
                        print("Failed to create launch agent: \(error)")
                    }
                } else {
                    let path = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Library/LaunchAgents")
                        .appendingPathComponent("\(bundleIdentifier).plist")
                    
                    try? FileManager.default.removeItem(at: path)
                }
            }
        }
    }
    
    func shouldShowWindow() -> Bool {
        // 检查是否是通过登录项启动
        let isLoginLaunch = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"]?.contains("com.apple.loginwindow") ?? false
        
        // 只有在开机启动且设置为静默模式时才不显示窗口
        // 手动启动时始终显示窗口
        return !isLoginLaunch || !silentMode
    }
    
    func setTimerInterval(_ interval: TimeInterval) {
        timerInterval = max(0.1, min(interval, 60.0)) // 限制在 0.1-60 秒之间
    }
}
