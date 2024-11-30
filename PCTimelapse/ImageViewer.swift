import SwiftUI

struct ImageViewer: View {
    let image: NSImage
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            GeometryReader { geometry in
                let size = calculateImageSize(for: geometry.size)
                
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(scale)
                    .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dragOffset = value.translation
                            }
                            .onEnded { value in
                                offset.width += dragOffset.width
                                offset.height += dragOffset.height
                                dragOffset = .zero
                                
                                // 如果拖动距离超过一定阈值，关闭查看器
                                let dragThreshold: CGFloat = 100
                                if abs(offset.height) > dragThreshold {
                                    if let window = NSApplication.shared.keyWindow {
                                        window.close()
                                    }
                                }
                            }
                    )
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                scale = min(max(scale * delta, 1), 4)
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                            }
                    )
                    .gesture(
                        TapGesture(count: 2)
                            .onEnded {
                                withAnimation(.spring()) {
                                    if scale > 1 {
                                        scale = 1
                                        offset = .zero
                                    } else {
                                        scale = 2
                                    }
                                }
                            }
                    )
            }
            
            // 关闭按钮
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        if let window = NSApplication.shared.keyWindow {
                            window.close()
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding()
                }
                Spacer()
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
    
    private func calculateImageSize(for screenSize: CGSize) -> CGSize {
        let imageSize = NSSize(width: image.size.width, height: image.size.height)
        let screenAspect = screenSize.width / screenSize.height
        let imageAspect = imageSize.width / imageSize.height
        
        if imageAspect > screenAspect {
            // 图片更宽，适应屏幕宽度
            let width = screenSize.width
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        } else {
            // 图片更高，适应屏幕高度
            let height = screenSize.height
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        }
    }
}

struct ImageThumbnail: View {
    let url: URL
    @Binding var isPresented: Bool
    @State private var image: NSImage?
    
    var body: some View {
        Button(action: {
            if let image = NSImage(contentsOf: url) {
                withAnimation {
                    self.image = image
                    isPresented = true
                }
            }
        }) {
            ZStack {
                if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 160)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 160)
                        .cornerRadius(8)
                        .overlay(
                            ProgressView()
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            if let image = image {
                ImageViewer(image: image)
            }
        }
    }
}
