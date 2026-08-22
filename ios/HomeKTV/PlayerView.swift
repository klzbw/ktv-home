import SwiftUI
import AVKit
import Combine

// MARK: - 数据模型
struct KTVSong: Codable {
    let id: Int
    let title: String
    let artist: String
}

struct KTVQueueItem: Codable {
    let queueId: Int
    let song: KTVSong
}

struct KTVQueue: Codable {
    let playing: KTVQueueItem?
    let list: [KTVQueueItem]?
    let vocalMode: String?
}

// MARK: - 播放管理器
class PlayerManager: ObservableObject {
    @Published var currentSong: KTVSong?
    @Published var showIdleScreen = true
    @Published var queue: KTVQueue?
    
    var player: AVPlayer?
    private var timer: Timer?
    private var host: String = ""
    private var port: Int = 8980
    
    func configure(host: String, port: Int) {
        self.host = host
        self.port = port
        if player == nil {
            player = AVPlayer()
        }
        startPolling()
    }
    
    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.fetchQueue()
        }
        fetchQueue()
    }
    
    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
    
    func fetchQueue() {
        guard let url = URL(string: "http://\(host):\(port)/api/queue") else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data, error == nil else { return }
            
            do {
                let queue = try JSONDecoder().decode(KTVQueue.self, from: data)
                DispatchQueue.main.async {
                    self?.queue = queue
                    
                    if let playing = queue.playing {
                        if self?.currentSong?.id != playing.song.id {
                            self?.currentSong = playing.song
                            self?.playSong(playing.song)
                        }
                        self?.showIdleScreen = false
                    } else {
                        if self?.currentSong != nil {
                            self?.currentSong = nil
                            self?.player?.pause()
                        }
                        self?.showIdleScreen = true
                    }
                }
            } catch {
                print("解析失败: \(error)")
            }
        }.resume()
    }
    
    func playSong(_ song: KTVSong) {
        guard let url = URL(string: "http://\(host):\(port)/api/stream/\(song.id)") else { return }
        
        if player == nil {
            player = AVPlayer()
        }
        
        let playerItem = AVPlayerItem(url: url)
        player?.replaceCurrentItem(with: playerItem)
        player?.play()
    }
    
    deinit {
        stopPolling()
        player?.pause()
    }
}

// MARK: - 视频播放视图
struct VideoPlayerView: UIViewControllerRepresentable {
    @ObservedObject var playerManager: PlayerManager
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = playerManager.player
        vc.showsPlaybackControls = false
        vc.videoGravity = .resizeAspect
        return vc
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== playerManager.player {
            uiViewController.player = playerManager.player
        }
    }
}

// MARK: - 扫码提示页面
struct IdleOverlayView: View {
    @ObservedObject var deviceManager: DeviceManager
    @State private var qrImage: UIImage?
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color(red: 0.05, green: 0.05, blue: 0.15), Color(red: 0.1, green: 0.05, blue: 0.2)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Text("家庭KTV")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 40)
                
                Spacer()
                
                VStack(spacing: 16) {
                    if let qrImage = qrImage {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 200, height: 200)
                            .background(Color.white)
                            .cornerRadius(12)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                            .frame(width: 200, height: 200)
                            .overlay(ProgressView())
                    }
                    
                    Text("扫码点歌")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    
                    if let device = deviceManager.connectedDevice {
                        Text("http://\(device.host):\(device.port)/m")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                Text("等待点歌中...")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .padding(.bottom, 30)
            }
        }
        .onAppear { generateQRCode() }
    }
    
    func generateQRCode() {
        guard let device = deviceManager.connectedDevice else { return }
        let urlString = "http://\(device.host):\(device.port)/m"
        
        DispatchQueue.global(qos: .userInitiated).async {
            let data = urlString.data(using: .ascii)
            guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return }
            filter.setValue(data, forKey: "inputMessage")
            filter.setValue("H", forKey: "inputCorrectionLevel")
            
            guard let outputImage = filter.outputImage else { return }
            let scaleX = 200 / outputImage.extent.width
            let scaleY = 200 / outputImage.extent.height
            let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            
            let context = CIContext()
            if let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) {
                DispatchQueue.main.async {
                    self.qrImage = UIImage(cgImage: cgImage)
                }
            }
        }
    }
}

// MARK: - 主播放视图
struct PlayerView: View {
    @ObservedObject var deviceManager: DeviceManager
    @StateObject private var playerManager = PlayerManager()
    
    var body: some View {
        ZStack {
            VideoPlayerView(playerManager: playerManager)
                .ignoresSafeArea()
            
            if playerManager.showIdleScreen {
                IdleOverlayView(deviceManager: deviceManager)
                    .transition(.opacity)
            }
        }
        .onAppear {
            if let device = deviceManager.connectedDevice {
                playerManager.configure(host: device.host, port: device.port)
            }
        }
        .onDisappear {
            playerManager.stopPolling()
        }
    }
}
