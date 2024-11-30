
import Foundation
import SwiftUI
import AppKit
import AVFoundation
import CoreImage
import UniformTypeIdentifiers

@MainActor
class CameraManager: NSObject, ObservableObject {
    static let shared = CameraManager()
    
    @Published var screenshotGroups: [ScreenshotGroup] = []
    @Published var isTimerRunning = false
    @Published var previewImage: NSImage?
    
    private var timer: Timer? = nil
    private let fileManager = FileManager.default
    private let screenshotDirectory: URL
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let videoQueue = DispatchQueue(label: "videoQueue")
    
    override init() {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "com.example.PCTimelapse"
        let appDirectory = appSupportURL.appendingPathComponent(bundleID)
        screenshotDirectory = appDirectory.appendingPathComponent("PCTimelapse-Screenshots")
        
        super.init()
        
        // 创建必要的目录
        try? fileManager.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        
        Task {
            await setupCamera()
            loadExistingScreenshots()
        }
    }
    
    private func setupCamera() async {
        print("Setting up camera...")
        
        // 列出所有可用的视频设备
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        
        print("Available video devices:")
        for device in discoverySession.devices {
            print("- \(device.localizedName) (\(device.position.rawValue))")
        }
        
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .vga640x480  // 使用较低的分辨率以提高性能
        
        // 配置视频输出质量
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput?.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 640,
            kCVPixelBufferHeightKey as String: 480
        ] as [String : Any]
        
        // 设置是否丢弃延迟的帧
        videoOutput?.alwaysDiscardsLateVideoFrames = true
        
        do {
            // 请求相机权限
            let authorized = await requestCameraAccess()
            print("Camera access authorized: \(authorized)")
            guard authorized else {
                print("Camera access denied")
                return
            }
            
            // 获取摄像头设备
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .external],
                mediaType: .video,
                position: .unspecified
            )
            
            guard let device = discoverySession.devices.first else {
                print("No camera device found")
                return
            }
            
            print("Using camera device: \(device.localizedName) (\(device.position.rawValue))")
            try await configureCameraInput(device)
        } catch {
            print("Failed to setup camera: \(error)")
        }
    }
    
    private func configureCameraInput(_ device: AVCaptureDevice) async throws {
        print("Setting up camera device...")
        
        // 配置设备以获得更好的性能
        try device.lockForConfiguration()
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30) // 30 FPS
        device.unlockForConfiguration()
        
        // 创建输入
        print("Creating camera input for device: \(device.localizedName)")
        let input = try AVCaptureDeviceInput(device: device)
        
        guard let session = captureSession else {
            print("Capture session is nil")
            return
        }
        
        guard session.canAddInput(input) else {
            print("Cannot add camera input")
            return
        }
        
        print("Configuring capture session...")
        session.beginConfiguration()
        
        // 移除现有输入
        session.inputs.forEach { session.removeInput($0) }
        session.addInput(input)
        
        // 配置输出
        if session.canAddOutput(videoOutput ?? AVCaptureVideoDataOutput()) {
            videoOutput?.setSampleBufferDelegate(self, queue: videoQueue)
            session.addOutput(videoOutput ?? AVCaptureVideoDataOutput())
            if let connection = videoOutput?.connection(with: .video) {
                // 设置视频镜像
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
                
                // 设置视频旋转
                if connection.isVideoRotationAngleSupported(0) {
                    connection.videoRotationAngle = 0
                }
            }
            print("Video output configured successfully")
        } else {
            print("Cannot add video output")
            return
        }
        
        session.commitConfiguration()
        print("Configuration committed")
        
        // 在主线程启动会话
        await MainActor.run {
            print("Starting capture session...")
            session.startRunning()
            print("Capture session started")
        }
    }
    
    private func requestCameraAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    func startScreenshotTimer(interval: TimeInterval = 5) {
        stopScreenshotTimer()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.takeScreenshot()
            }
        }
        isTimerRunning = true
    }
    
    func stopScreenshotTimer() {
        timer?.invalidate()
        timer = nil
        isTimerRunning = false
    }
    
    func takeScreenshot() async {
        guard let image = previewImage else {
            print("No preview image available")
            return
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let filename = "Screenshot_\(timestamp).png"
        let fileURL = screenshotDirectory.appendingPathComponent(filename)
        
        if let savedURL = saveScreenshot(image, to: fileURL) {
            print("Screenshot saved to: \(savedURL.path)")
        } else {
            print("Failed to save screenshot")
        }
    }
    
    private func saveScreenshot(_ image: NSImage, to fileURL: URL) -> URL? {
        let fileManager = FileManager.default
        let screenshotDirectory = fileURL.deletingLastPathComponent()
        
        // 确保目录存在
        try? fileManager.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        
        // 使用 CGImage 方式保存
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let pixelBuffer = createPixelBuffer(from: cgImage, date: Date(), showTimestamp: false) {
            
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                do {
                    try data.write(to: fileURL)
                    loadExistingScreenshots()
                    return fileURL
                } catch {
                    print("Error writing PNG data: \(error)")
                }
            } else {
                print("Failed to create PNG data")
            }
        } else {
            print("Failed to get CGImage")
        }
        
        return nil
    }
    
    private func loadExistingScreenshots() {
        let screenshots = getScreenshots()
        let groupedDict = Dictionary(grouping: screenshots) { screenshot in
            Calendar.current.startOfDay(for: screenshot.date)
        }
        
        screenshotGroups = groupedDict.map { date, screenshots in
            ScreenshotGroup(date: date, screenshots: screenshots.sorted { $0.date > $1.date })
        }.sorted { $0.date > $1.date }
    }
    
    private func getScreenshots() -> [Screenshot] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: screenshotDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        return urls
            .filter { $0.pathExtension.lowercased() == "png" }
            .map(Screenshot.init)
    }
    
    private var shouldTakeScreenshot = false
    
    func deleteScreenshot(_ screenshot: Screenshot) {
        try? fileManager.removeItem(at: screenshot.url)
        loadExistingScreenshots()
    }
    
    func openScreenshotFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: screenshotDirectory.path)
    }
    
    // 保存预览图像
    private func savePreviewImage(_ previewImage: NSImage) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let filename = "Preview_\(timestamp).png"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        if let tiffData = previewImage.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            do {
                try pngData.write(to: tempURL)
                return tempURL
            } catch {
                print("Error saving preview image: \(error)")
            }
        } else {
            print("Failed to convert preview image to PNG")
        }
        return nil
    }
    
    func exportTimelapseVideo(for group: ScreenshotGroup) {
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = LocalizedString("Export Timelapse Video")
            alert.informativeText = LocalizedString("Would you like to show timestamps in the video?")
            alert.alertStyle = .informational
            alert.addButton(withTitle: LocalizedString("Yes"))
            alert.addButton(withTitle: LocalizedString("No"))
            
            let response = alert.runModal()
            let showTimestamp = response == .alertFirstButtonReturn
            
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [UTType.mpeg4Movie]
            savePanel.nameFieldStringValue = "Timelapse-\(group.title).mp4"
            
            let panelResponse = await savePanel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow())
            
            guard panelResponse == .OK, let url = savePanel.url else { return }
            await self.createTimelapseVideo(from: group.screenshots, to: url, showTimestamp: showTimestamp)
        }
    }
    
    private func createTimelapseVideo(from screenshots: [Screenshot], to outputURL: URL, showTimestamp: Bool) async {
        // 视频设置
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: NSNumber(value: 1920),
            AVVideoHeightKey: NSNumber(value: 1080),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: NSNumber(value: 10_000_000),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: NSNumber(value: 1) // 每帧都是关键帧，减少闪烁
            ]
        ]
        
        do {
            // 删除可能存在的旧文件
            try? FileManager.default.removeItem(at: outputURL)
            
            // 创建 AVAssetWriter
            let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
            
            // 创建视频输入
            let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            writerInput.expectsMediaDataInRealTime = false
            writerInput.transform = CGAffineTransform(rotationAngle: 0)
            
            // 创建像素缓冲适配器
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: NSNumber(value: 1920),
                kCVPixelBufferHeightKey as String: NSNumber(value: 1080),
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: writerInput,
                sourcePixelBufferAttributes: attributes
            )
            
            assetWriter.add(writerInput)
            
            // 开始写入
            guard assetWriter.startWriting() else {
                throw NSError(domain: "com.PCTimelapse", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to start writing video"
                ])
            }
            
            assetWriter.startSession(atSourceTime: .zero)
            
            // 对截图进行排序
            let sortedScreenshots = screenshots.sorted { $0.date < $1.date }
            
            // 每帧持续时间（0.2秒）
            let frameDuration = CMTimeMake(value: 2, timescale: 10)
            var currentTime = CMTime.zero
            
            // 创建一个信号量来控制内存使用
            let semaphore = DispatchSemaphore(value: 1)
            
            for (index, screenshot) in sortedScreenshots.enumerated() {
                // 等待前一帧处理完成
                _ = semaphore.wait(timeout: .distantFuture)
                
                autoreleasepool {
                    if let cgImage = screenshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                       let pixelBuffer = createPixelBuffer(from: cgImage, date: screenshot.date, showTimestamp: showTimestamp) {
                        
                        while !writerInput.isReadyForMoreMediaData {
                            Thread.sleep(forTimeInterval: 0.1)
                        }
                        
                        if !adaptor.append(pixelBuffer, withPresentationTime: currentTime) {
                            print("Failed to append pixel buffer")
                        }
                        currentTime = CMTimeAdd(currentTime, frameDuration)
                        
                        // 更新进度
                        let progress = Double(index + 1) / Double(sortedScreenshots.count)
                        print("Export progress: \(Int(progress * 100))%")
                    }
                }
                
                semaphore.signal()
            }
            
            // 完成写入
            writerInput.markAsFinished()
            await assetWriter.finishWriting()
            
            if assetWriter.status == .completed {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = LocalizedString("Video Export Completed")
                    alert.informativeText = LocalizedString("The timelapse video has been saved successfully.")
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: LocalizedString("OK"))
                    alert.runModal()
                }
            } else if let error = assetWriter.error {
                throw error
            }
        } catch {
            print("Failed to create asset writer: \(error)")
            
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = LocalizedString("Video Export Failed")
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.addButton(withTitle: LocalizedString("OK"))
                alert.runModal()
            }
        }
    }
    
    private func createPixelBuffer(from image: CGImage, date: Date, showTimestamp: Bool) -> CVPixelBuffer? {
        let sourceWidth = image.width
        let sourceHeight = image.height
        let targetWidth = 1920
        let targetHeight = 1080
        
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            targetWidth,
            targetHeight,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let pixelBuffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: pixelData,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }
        
        // 设置黑色背景
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        
        // 计算缩放比例以适应目标尺寸
        let sourceRatio = CGFloat(sourceWidth) / CGFloat(sourceHeight)
        let targetRatio = CGFloat(targetWidth) / CGFloat(targetHeight)
        
        var drawRect = CGRect.zero
        
        if sourceRatio > targetRatio {
            // 源图像更宽，以高度为基准进行缩放
            let scaledWidth = CGFloat(targetHeight) * sourceRatio
            drawRect = CGRect(
                x: (CGFloat(targetWidth) - scaledWidth) / 2,
                y: 0,
                width: scaledWidth,
                height: CGFloat(targetHeight)
            )
        } else {
            // 源图像更高，以宽度为基准进行缩放
            let scaledHeight = CGFloat(targetWidth) / sourceRatio
            drawRect = CGRect(
                x: 0,
                y: (CGFloat(targetHeight) - scaledHeight) / 2,
                width: CGFloat(targetWidth),
                height: scaledHeight
            )
        }
        
        // 设置高质量插值
        context.interpolationQuality = .high
        
        // 绘制图像
        context.draw(image, in: drawRect)
        
        // 如果需要显示时间戳
        if showTimestamp {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let timestamp = dateFormatter.string(from: date)
            
            // 设置字体
            let fontSize: CGFloat = 32
            let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
            
            // 创建文本属性
            let attributes = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
            ] as CFDictionary
            
            // 创建属性字符串
            let attrString = CFAttributedStringCreate(
                kCFAllocatorDefault,
                timestamp as CFString,
                attributes
            )
            
            // 创建文本行
            let line = CTLineCreateWithAttributedString(attrString!)
            
            // 获取文本尺寸
            let textBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
            
            // 计算文本位置（右上角）
            let margin: CGFloat = 20
            let x = CGFloat(targetWidth) - textBounds.width - margin
            let y = CGFloat(targetHeight) - textBounds.height - margin
            
            // 绘制半透明背景
            context.setFillColor(red: 0, green: 0, blue: 0, alpha: 0.5)
            let backgroundRect = CGRect(
                x: x - 10,
                y: y - 5,
                width: textBounds.width + 20,
                height: textBounds.height + 10
            )
            context.fillPath()
            
            // 绘制文本
            context.saveGState()
            context.translateBy(x: x, y: y)
            CTLineDraw(line, context)
            context.restoreGState()
        }
        
        return pixelBuffer
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to get image buffer")
            return
        }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        // 创建一个新的 context，而不是使用类属性
        let localContext = CIContext(options: [.useSoftwareRenderer: false])
        
        guard let cgImage = localContext.createCGImage(ciImage, from: ciImage.extent) else {
            print("Failed to create CGImage")
            return
        }
        
        let size = NSSize(width: CGFloat(CVPixelBufferGetWidth(imageBuffer)),
                         height: CGFloat(CVPixelBufferGetHeight(imageBuffer)))
        let image = NSImage(cgImage: cgImage, size: size)
        
        Task { @MainActor in
            self.previewImage = image
        }
    }
    
    nonisolated func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("Dropped frame")
    }
}

struct Screenshot: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let date: Date
    var image: NSImage
    
    init(url: URL) {
        self.id = UUID()
        self.url = url
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let creationDate = attributes[FileAttributeKey.creationDate] as? Date {
            self.date = creationDate
        } else {
            self.date = Date()
        }
        
        if let image = NSImage(contentsOf: url) {
            self.image = image
        } else {
            self.image = NSImage()
        }
    }
    
    static func == (lhs: Screenshot, rhs: Screenshot) -> Bool {
        return lhs.id == rhs.id
    }
}

struct ScreenshotGroup: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    var screenshots: [Screenshot]
    
    static func == (lhs: ScreenshotGroup, rhs: ScreenshotGroup) -> Bool {
        lhs.id == rhs.id && lhs.date == rhs.date && lhs.screenshots == rhs.screenshots
    }
    
    var title: String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDate(date, equalTo: now, toGranularity: .day) {
            return LocalizedString("Today")
        } else if calendar.isDateInYesterday(date) {
            return LocalizedString("Yesterday")
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            // 根据当前语言设置日期格式
            let isChineseLocale = Locale.current.identifier.starts(with: "zh")
            if isChineseLocale {
                return LocalizedDate(date, format: "M月d日")
            } else {
                return LocalizedDate(date, format: "MMMM d")
            }
        } else {
            // 根据当前语言设置日期格式
            let isChineseLocale = Locale.current.identifier.starts(with: "zh")
            if isChineseLocale {
                return LocalizedDate(date, format: "yyyy年M月d日")
            } else {
                return LocalizedDate(date, format: "MMMM d, yyyy")
            }
        }
    }
}

extension NSImage {
    func savePNG(to url: URL) -> Bool {
        if let tiffData = self.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            do {
                try pngData.write(to: url)
                return true
            } catch {
                print("Error saving PNG: \(error)")
            }
        } else {
            print("Failed to convert image to PNG")
        }
        return false
    }
}

extension NSView {
    func snapshot() -> NSImage? {
        guard let bitmapRep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: bitmapRep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmapRep)
        return image
    }
}

class ScreenshotManager: ObservableObject {
    @Published var screenshots: [URL] = []
    @Published var isRecording = false
    private var timer: Timer?
    private var view: NSView
    private let screenshotDirectory: URL
    private var displaySleepNotification: NSObjectProtocol?
    private var systemSleepNotification: NSObjectProtocol?
    private var systemWakeNotification: NSObjectProtocol?
    private var displayWakeNotification: NSObjectProtocol?
    
    init(view: NSView) {
        self.view = view
        
        // 获取应用支持目录
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.example.PCTimelapse"
            self.screenshotDirectory = appSupport.appendingPathComponent(bundleIdentifier).appendingPathComponent("PCTimelapse-Screenshots")
        } else {
            // 如果无法获取应用支持目录，则使用临时目录
            self.screenshotDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("PCTimelapse-Screenshots")
        }
        
        // 注册系统休眠通知
        let notificationCenter = NSWorkspace.shared.notificationCenter
        systemSleepNotification = notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemSleep()
        }
        
        // 注册系统唤醒通知
        systemWakeNotification = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemWake()
        }
        
        // 注册显示器休眠通知
        displaySleepNotification = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDisplaySleep()
        }
        
        // 注册显示器唤醒通知
        displayWakeNotification = notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDisplayWake()
        }
        
        loadExistingScreenshots()
    }
    
    deinit {
        // 移除通知观察者
        if let systemSleepNotification = systemSleepNotification {
            NSWorkspace.shared.notificationCenter.removeObserver(systemSleepNotification)
        }
        if let systemWakeNotification = systemWakeNotification {
            NSWorkspace.shared.notificationCenter.removeObserver(systemWakeNotification)
        }
        if let displaySleepNotification = displaySleepNotification {
            NSWorkspace.shared.notificationCenter.removeObserver(displaySleepNotification)
        }
        if let displayWakeNotification = displayWakeNotification {
            NSWorkspace.shared.notificationCenter.removeObserver(displayWakeNotification)
        }
    }
    
    private func handleSystemSleep() {
        if isRecording {
            stopRecording()
        }
    }
    
    private func handleSystemWake() {
        // 系统唤醒时，可以选择自动恢复录制
        // 这里我们选择不自动恢复，让用户手动控制
        print("System woke from sleep")
    }
    
    private func handleDisplaySleep() {
        if isRecording {
            stopRecording()
        }
    }
    
    private func handleDisplayWake() {
        // 显示器唤醒时，可以选择自动恢复录制
        // 这里我们选择不自动恢复，让用户手动控制
        print("Display woke from sleep")
    }
    
    func toggleRecording() {
        isRecording.toggle()
        
        if isRecording {
            startRecording()
        } else {
            stopRecording()
        }
    }
    
    private func startRecording() {
        // 使用 AppSettings 中的定时器间隔
        let interval = AppSettings.shared.timerInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.captureScreenshot()
        }
    }
    
    private func stopRecording() {
        timer?.invalidate()
        timer = nil
    }
    
    // 更新定时器间隔
    func updateTimerInterval(_ interval: TimeInterval) {
        AppSettings.shared.setTimerInterval(interval)
        if isRecording {
            stopRecording()
            startRecording()
        }
    }
    
    // 获取当前定时器间隔
    var currentTimerInterval: TimeInterval {
        return AppSettings.shared.timerInterval
    }
    
    private func loadExistingScreenshots() {
        do {
            try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
            let files = try FileManager.default.contentsOfDirectory(
                at: screenshotDirectory,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension.lowercased() == "png" }
            screenshots = files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        } catch {
            print("Error loading screenshots: \(error)")
        }
    }
    
    private func captureScreenshot() {
        guard let image = view.snapshot() else {
            print("Failed to capture screenshot")
            return
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let filename = "Screenshot_\(timestamp).png"
        let fileURL = screenshotDirectory.appendingPathComponent(filename)
        
        if let savedURL = saveScreenshot(image, to: fileURL) {
            print("Screenshot saved to: \(savedURL.path)")
        } else {
            print("Failed to save screenshot")
        }
    }
    
    private func saveScreenshot(_ image: NSImage, to fileURL: URL) -> URL? {
        let fileManager = FileManager.default
        let screenshotDirectory = fileURL.deletingLastPathComponent()
        
        // 确保目录存在
        try? fileManager.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        
        // 使用 CGImage 方式保存
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                do {
                    try data.write(to: fileURL)
                    loadExistingScreenshots()
                    return fileURL
                } catch {
                    print("Error writing PNG data: \(error)")
                }
            } else {
                print("Failed to create PNG data")
            }
        } else {
            print("Failed to get CGImage")
        }
        
        return nil
    }
}
