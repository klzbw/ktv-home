import SwiftUI
import TVVLCKit

// MARK: - tvOS播放视图
struct TVPlayerView: View {
    @ObservedObject var playerManager: PlayerManager
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // VLC播放器
            VLCVideoView(
                url: playerManager.videoURL,
                songId: playerManager.currentSong?.id,
                vocalMode: playerManager.vocalMode,
                onLog: { _, _ in },
                onPlayerReady: { player in
                    playerManager.vlcPlayer = player
                },
                onPlaying: {
                    DispatchQueue.main.async {
                        playerManager.isPlaying = true
                        playerManager.startProgressReporting()
                    }
                },
                onEnded: {
                    DispatchQueue.main.async {
                        playerManager.isPlaying = false
                        playerManager.stopProgressReporting()
                        playerManager.wsManager.sendFinished()
                    }
                },
                onError: {
                    DispatchQueue.main.async {
                        playerManager.isPlaying = false
                        playerManager.stopProgressReporting()
                    }
                }
            )
            .ignoresSafeArea()
            
            // 等待扫码页面
            if playerManager.showIdleScreen {
                TVIdleView(wsManager: playerManager.wsManager)
            }

            // 播放时迷你二维码（右下角，参考安卓端 imgMiniQr）
            if !playerManager.showIdleScreen, let url = playerManager.pointSongUrl {
                MiniQrOverlayView(urlString: url)
                    .zIndex(40)
                    .transition(.opacity)
            }

            // 氛围效果
            if let effect = playerManager.wsManager.currentEffect {
                EffectOverlayView(
                    effect: effect,
                    show: playerManager.wsManager.showEffect,
                    count: playerManager.wsManager.effectCount
                )
                .zIndex(100)
            }
        }
    }
}

// MARK: - tvOS等待页面（显示连接地址）
struct TVIdleView: View {
    @ObservedObject var wsManager: WebSocketManager
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "qrcode")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.6))
            
            Text("等待点歌")
                .font(.system(size: 36, weight: .medium))
                .foregroundColor(.white)
            
            Circle()
                .fill(wsManager.isConnected ? Color.green : Color.red)
                .frame(width: 12, height: 12)
            
            Text(wsManager.isConnected ? "遥控已连接" : "等待遥控连接...")
                .font(.title3)
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

// MARK: - 播放时迷你二维码（右下角，参考安卓端 imgMiniQr）
/// 视频播放期间在右下角显示的小型扫码点歌二维码，
/// 对应安卓端 activity_main.xml 中的 imgMiniQr（104dp，白底+扫码点歌标签）。
struct MiniQrOverlayView: View {
    let urlString: String
    @State private var qrImage: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 0) {
                Spacer()
                VStack(spacing: 4) {
                    if let qrImage = qrImage {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 100, height: 100)
                            .padding(4)
                            .background(Color.white)
                            .cornerRadius(6)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white)
                            .frame(width: 108, height: 108)
                            .overlay(ProgressView().scaleEffect(0.7))
                    }

                    Text("扫码点歌")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.85), radius: 3, x: 1, y: 1)
                }
                .padding(.trailing, 32)
                // 底部留出空间（tvOS 屏幕较大，适当增加边距）
                .padding(.bottom, 100)
            }
        }
        .allowsHitTesting(false)
        .onAppear { generateQRCode() }
    }

    /// 使用 CoreImage 生成点歌地址二维码。
    func generateQRCode() {
        DispatchQueue.global(qos: .userInitiated).async {
            let data = urlString.data(using: .ascii)
            guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return }
            filter.setValue(data, forKey: "inputMessage")
            // 安卓端服务端使用 ErrorCorrectionLevel.M，此处保持一致
            filter.setValue("M", forKey: "inputCorrectionLevel")

            guard let outputImage = filter.outputImage else { return }
            let scale = 100 / outputImage.extent.width
            let transformedImage = outputImage.transformed(
                by: CGAffineTransform(scaleX: scale, y: scale)
            )

            let context = CIContext()
            if let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) {
                DispatchQueue.main.async {
                    self.qrImage = UIImage(cgImage: cgImage)
                }
            }
        }
    }
}
