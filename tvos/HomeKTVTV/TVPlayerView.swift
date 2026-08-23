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
                TVIdleView(playerManager: playerManager)
            }
            
            // 播放时迷你二维码（右上角）
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

// MARK: - tvOS等待页面（显示扫码点歌二维码）
struct TVIdleView: View {
    @ObservedObject var playerManager: PlayerManager
    @State private var qrImage: UIImage?
    
    var body: some View {
        VStack(spacing: 30) {
            Text("扫码点歌")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.white)
            
            if let qrImage = qrImage, let url = playerManager.pointSongUrl {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 280, height: 280)
                    .padding(12)
                    .background(Color.white)
                    .cornerRadius(12)
                
                Text(url)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 304, height: 304)
                    .overlay(
                        VStack(spacing: 16) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.6))
                            ProgressView()
                        }
                    )
            }
            
            HStack(spacing: 10) {
                Circle()
                    .fill(playerManager.wsManager.isConnected ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                Text(playerManager.wsManager.isConnected ? "服务已就绪" : "等待连接...")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .onAppear { generateQRCode() }
    }
    
    func generateQRCode() {
        guard let urlString = playerManager.pointSongUrl else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let data = urlString.data(using: .ascii)
            guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return }
            filter.setValue(data, forKey: "inputMessage")
            filter.setValue("M", forKey: "inputCorrectionLevel")
            guard let outputImage = filter.outputImage else { return }
            let scale = 280 / outputImage.extent.width
            let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let context = CIContext()
            if let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) {
                DispatchQueue.main.async {
                    self.qrImage = UIImage(cgImage: cgImage)
                }
            }
        }
    }
}

// MARK: - 播放时迷你二维码（右上角）
struct MiniQrOverlayView: View {
    let urlString: String
    @State private var qrImage: UIImage?
    
    var body: some View {
        VStack(spacing: 0) {
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
                .padding(.top, 100)
            }
            Spacer()
        }
        .allowsHitTesting(false)
        .onAppear { generateQRCode() }
    }
    
    func generateQRCode() {
        DispatchQueue.global(qos: .userInitiated).async {
            let data = urlString.data(using: .ascii)
            guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return }
            filter.setValue(data, forKey: "inputMessage")
            filter.setValue("M", forKey: "inputCorrectionLevel")
            guard let outputImage = filter.outputImage else { return }
            let scale = 100 / outputImage.extent.width
            let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let context = CIContext()
            if let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) {
                DispatchQueue.main.async {
                    self.qrImage = UIImage(cgImage: cgImage)
                }
            }
        }
    }
}
