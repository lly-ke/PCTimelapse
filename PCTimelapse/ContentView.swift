//
//  ContentView.swift
//  PCTimelapse
//
//  Created by llyke on 2024/11/29.
//

import SwiftUI
import AppKit

// 设置面板组件
struct SettingsPanel: View {
    @ObservedObject var settings: AppSettings
    @Binding var isTimerRunning: Bool
    @Binding var timerInterval: TimeInterval
    let timerIntervals: [TimeInterval]
    let onTimerChange: (Bool) -> Void
    
    var body: some View {
        GroupBox(label: Text(LocalizedString("Settings"))) {
            VStack(spacing: 12) {
                HStack(spacing: 20) {
                    Toggle(LocalizedString("Launch at Login"), isOn: $settings.launchAtLogin)
                    Toggle(LocalizedString("Silent Mode"), isOn: $settings.silentMode)
                        .help(LocalizedString("Start in background when launched at login"))
                }
                
                HStack {
                    Text(LocalizedString("Interval"))
                    Picker("", selection: $timerInterval) {
                        ForEach(timerIntervals, id: \.self) { interval in
                            Text("\(Int(interval))\(LocalizedString("seconds"))").tag(interval)
                        }
                    }
                    .frame(width: 100)
                    
                    Toggle(isOn: $isTimerRunning) {
                        Label(LocalizedString("Timer"), systemImage: "timer")
                    }
                    .onChange(of: isTimerRunning, perform: onTimerChange)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// 控制按钮组件
struct ControlButtons: View {
    let onTakeScreenshot: () -> Void
    let onOpenFolder: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Button(action: onTakeScreenshot) {
                Label(LocalizedString("Take Screenshot"), systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            
            Button(action: onOpenFolder) {
                Label(LocalizedString("Open Folder"), systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// 截图网格项组件
struct ScreenshotGridItem: View {
    let screenshot: Screenshot
    let onDelete: () -> Void
    let onSelect: () -> Void
    
    var body: some View {
        AsyncImageView(url: screenshot.url) { _ in
            onSelect()
        }
        .contextMenu {
            Button(action: onDelete) {
                Text(LocalizedString("Delete"))
                Image(systemName: "trash")
            }
        }
    }
}

// 截图组组件
struct ScreenshotGroupView: View {
    let group: ScreenshotGroup
    let columns: [GridItem]
    let onDeleteScreenshot: (Screenshot) -> Void
    let onSelectScreenshot: (Screenshot) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.title)
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(group.screenshots) { screenshot in
                    ScreenshotGridItem(
                        screenshot: screenshot,
                        onDelete: { onDeleteScreenshot(screenshot) },
                        onSelect: { onSelectScreenshot(screenshot) }
                    )
                }
            }
            .padding(.horizontal)
        }
        .id(group.id)
    }
}

// 主截图网格组件
struct ScreenshotGrid: View {
    let columns: [GridItem]
    let screenshotGroups: [ScreenshotGroup]
    let onDeleteScreenshot: (Screenshot) -> Void
    let onSelectScreenshot: (Screenshot) -> Void
    @StateObject private var cameraManager = CameraManager.shared
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                ForEach(screenshotGroups) { group in
                    Section(header: HStack {
                        Text(group.title)
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button(action: {
                            cameraManager.exportTimelapseVideo(for: group)
                        }) {
                            Image(systemName: "film")
                            Text(LocalizedString("Export Timelapse"))
                        }
                        .buttonStyle(.borderless)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.windowBackgroundColor))
                    ) {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(group.screenshots) { screenshot in
                                ScreenshotGridItem(
                                    screenshot: screenshot,
                                    onDelete: { onDeleteScreenshot(screenshot) },
                                    onSelect: { onSelectScreenshot(screenshot) }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
    }
}

// 主视图
struct ContentView: View {
    @StateObject private var cameraManager = CameraManager.shared
    @StateObject private var settings = AppSettings.shared
    @State private var isTimerRunning = false
    @State private var timerInterval: TimeInterval = 5
    @State private var showingImageViewer = false
    @State private var selectedScreenshot: Screenshot?
    
    private let timerIntervals: [TimeInterval] = [1, 3, 5, 10, 15, 30, 60]
    private let leftWidth: CGFloat = 300
    
    private func openImageViewer(screenshot: Screenshot) {
        let panel = ImageViewerPanel(image: screenshot.image)
        panel.makeKeyAndOrderFront(nil)
    }
    
    var body: some View {
        GeometryReader { geometry in
            let rightWidth = geometry.size.width - leftWidth - 1
            let columns = [
                GridItem(.adaptive(minimum: min(200, (rightWidth - 32) / 3), maximum: 280))
            ]
            
            HStack(spacing: 0) {
                // 左侧控制面板
                VStack {
                    // 摄像头预览
                    ZStack {
                        if let previewImage = cameraManager.previewImage {
                            Image(nsImage: previewImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .cornerRadius(8)
                        } else {
                            Text(LocalizedString("Camera not available"))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: leftWidth)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(8)
                    
                    // 设置和控制按钮
                    VStack(spacing: 12) {
                        SettingsPanel(
                            settings: settings,
                            isTimerRunning: $isTimerRunning,
                            timerInterval: $timerInterval,
                            timerIntervals: timerIntervals,
                            onTimerChange: { newValue in
                                if newValue {
                                    cameraManager.startScreenshotTimer(interval: timerInterval)
                                } else {
                                    cameraManager.stopScreenshotTimer()
                                }
                            }
                        )
                        
                        Divider()
                        
                        ControlButtons(
                            onTakeScreenshot: {
                                Task {
                                    await cameraManager.takeScreenshot()
                                }
                            },
                            onOpenFolder: {
                                cameraManager.openScreenshotFolder()
                            }
                        )
                    }
                    .padding()
                }
                .frame(width: leftWidth)
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // 右侧预览列表
                ScreenshotGrid(
                    columns: columns,
                    screenshotGroups: cameraManager.screenshotGroups,
                    onDeleteScreenshot: { screenshot in
                        cameraManager.deleteScreenshot(screenshot)
                    },
                    onSelectScreenshot: { screenshot in
                        openImageViewer(screenshot: screenshot)
                    }
                )
                .frame(width: rightWidth)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .navigationTitle("PC Timelapse")
        .onDisappear {
            cameraManager.stopScreenshotTimer()
        }
    }
}

// AsyncImageView
struct AsyncImageView: View {
    @StateObject private var loader: ImageLoader
    let action: (NSImage) -> Void
    
    init(url: URL, action: @escaping (NSImage) -> Void) {
        self._loader = StateObject(wrappedValue: ImageLoader(url: url))
        self.action = action
    }
    
    var body: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .cornerRadius(8)
                    .onTapGesture {
                        action(image)
                    }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }
}

// ImageLoader
class ImageLoader: ObservableObject {
    @Published var image: NSImage?
    private var url: URL
    private var task: Task<Void, Never>?
    
    init(url: URL) {
        self.url = url
        loadImage()
    }
    
    private func loadImage() {
        task = Task {
            if let image = NSImage(contentsOf: url) {
                await MainActor.run {
                    self.image = image
                }
            }
        }
    }
    
    deinit {
        task?.cancel()
    }
}

// ImageViewerPanel
class ImageViewerPanel: NSPanel {
    static var activePanel: ImageViewerPanel?
    private var localMonitor: Any?
    
    init(image: NSImage) {
        super.init(contentRect: .zero,
                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                  backing: .buffered,
                  defer: false)
        
        self.title = ""
        self.isMovableByWindowBackground = true
        self.backgroundColor = .clear
        self.hasShadow = true
        self.center()
        
        // 设置内容视图
        let hostingView = NSHostingView(rootView: ImageViewerContent(image: image))
        self.contentView = hostingView
        
        // 设置窗口大小
        let screenSize = NSScreen.main?.visibleFrame ?? .zero
        let maxSize = CGSize(width: screenSize.width * 0.8,
                           height: screenSize.height * 0.8)
        
        let imageSize = image.size
        let scale = min(maxSize.width / imageSize.width,
                       maxSize.height / imageSize.height)
        
        let windowSize = CGSize(width: imageSize.width * scale,
                              height: imageSize.height * scale)
        
        self.setContentSize(windowSize)
        self.center()
        
        // 关闭之前的面板
        ImageViewerPanel.activePanel?.close()
        ImageViewerPanel.activePanel = self
        
        // 添加按键监听
        setupKeyMonitor()
    }
    
    private func setupKeyMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC key
                self?.close()
                return nil
            }
            return event
        }
    }
    
    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// ImageViewerContent
private struct ImageViewerContent: View {
    let image: NSImage
    
    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
    }
}

#Preview {
    ContentView()
}
