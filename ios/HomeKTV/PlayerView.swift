import SwiftUI
import MobileVLCKit
import Combine

// MARK: - 数据模型
struct KTVSong: Codable {
    let id: Int
    let title: String
    let artist: String
    let language: String?
    let mediaType: String?
    let hasVocalTrack: Bool?
    let durationMs: Int?
    let lyricType: String?
    let coverUrl: String?
    let lyricUrl: String?
    let playCount: Int?
}

struct KTVQueueItem: Codable {
    let queueId: Int
    let song: KTVSong
    let orderedByNick: String?
    let status: String?
}

struct KTVQueue: Codable {
    let playing: KTVQueueItem?
    let list: [KTVQueueItem]?
    let state: String?
    let volume: Int?
    let muted: Bool?
    let vocalMode: String?
    let tvOnline: Bool?
    let connectedPhones: Int?
}

// MARK: - VLC播放器视图控制器
class VLCPlayerViewController: UIViewController {
    var mediaPlayer: VLCMediaPlayer?
    private var playerView: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        // 创建播放器视图容器
        playerView = UIView(frame: view.bounds)
        playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerView.backgroundColor = .black
        view.addSubview(playerView)
        
        // 初始化VLC播放器
        setupPlayer()
    }
    
    func setupPlayer() {
        if mediaPlayer == nil {
            mediaPlayer = VLCMediaPlayer()
            // 设置drawable为playerView
            mediaPlayer?.drawable = playerView
        }
    }
    
    func play(url: URL) {
        setupPlayer()
        
        let media = VLCMedia(url: url)
        mediaPlayer?.media = media
        mediaPlayer?.play()
        
        print("VLC开始播放: \(url.absoluteString)")
    }
    
    func stop() {
        mediaPlayer?.stop()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerView.frame = view.bounds
    }
}

// MARK: - 播放管理器
class PlayerManager: ObservableObject {
    @Published var currentSong: KTVSong?
    @Published var isPlaying = false
    @Published var queue: KTVQueue?
    @Published var showIdleScreen = true
    @Published var errorMessage: String?
    
    weak var playerVC: VLCPlayerViewController?
    private var timer: Timer?
    private var host: String = ""
    private var port: Int = 8980
    
    func configure(host: String, port: Int) {
        self.host = host
        self.port = port
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
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    self?.errorMessage = error?.localizedDescription
                }
                return
            }
            
            do {
                let queue = try JSONDecoder().decode(KTVQueue.self, from: data)
                DispatchQueue.main.async {
                    self?.queue = queue
                    self?.errorMessage = nil
                    
                    if let playing = queue.playing {
                        if self?.currentSong?.id != playing.song.id {
                            self?.currentSong = playing.song
                            self?.playSong(playing.song)
                        }
                        self?.showIdleScreen = false
                        self?.isPlaying = true
                    } else {
                        if self?.currentSong != nil {
                            self?.currentSong = nil
                            self?.playerVC?.stop()
                        }
                        self?.isPlaying = false
                        self?.showIdleScreen = true
                    }
                }
            } catch {
                print("解析队列失败: \(error)")
            }
        }.resume()
    }
    
    func playSong(_ song: KTVSong) {
        guard let url = URL(string: "http://\(host):\(port)/api/stream/\(song.id)") else {
            errorMessage = "无效的视频地址"
            return
        }
        
        playerVC?.play(url: url)
    }
    
    deinit {
        stopPolling()
        playerVC?.stop()
    }
}

// MARK: - TV播放视图
struct TVPlayerView: UIViewControllerRepresentable {
    @ObservedObject var deviceManager: DeviceManager
    @StateObject private var playerManager = PlayerManager()
    
    func makeUIViewController(context: Context) -> VLCPlayerViewController {
        let vc = VLCPlayerViewController()
        playerManager.playerVC = vc
        return vc
    }
    
    func updateUIViewController(_ uiViewController: VLCPlayerViewController, context: Context) {
        if let device = deviceManager.connectedDevice {
            playerManager.configure(host: device.host, port: device.port)
        }
    }
    
    static func dismantleUIViewController(_ uiViewController: VLCPlayerViewController, coordinator: ()) {
        uiViewController.stop()
    }
}

// MARK: - 扫码提示页面（作为覆盖层）
struct IdleOverlayView: View {
    @ObservedObject var deviceManager: DeviceManager
    @ObservedObject var playerManager: PlayerManager
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
                VStack(spacing: 8) {
                    Text("家庭KTV")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("FAMILY KARAOKE")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.gray)
                        .tracking(4)
                }
                .padding(.top, 40)
                
                Spacer()
                
                HStack(spacing: 60) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("手机点歌，电视欢唱")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("一家人的客厅KTV")
                            .font(.system(size: 18))
                            .foregroundColor(.gray)
                        
                        HStack(spacing: 30) {
                            StatView(title: "曲库", value: "\(playerManager.queue?.list?.count ?? 0)首")
                            StatView(title: "已点", value: "\(playerManager.queue?.list?.count ?? 0)首")
                            StatView(title: "排队", value: "\(playerManager.queue?.list?.count ?? 0)首")
                        }
                        .padding(.top, 20)
                    }
                    
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

struct StatView: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
    }
}

// MARK: - 主播放视图（包含扫码覆盖层）
struct PlayerView: View {
    @ObservedObject var deviceManager: DeviceManager
    @StateObject private var playerManager = PlayerManager()
    
    var body: some View {
        ZStack {
            // VLC播放器
            TVPlayerView(deviceManager: deviceManager)
                .ignoresSafeArea()
            
            // 扫码提示覆盖层
            if playerManager.showIdleScreen {
                IdleOverlayView(deviceManager: deviceManager, playerManager: playerManager)
                    .transition(.opacity)
            }
            
            // 错误提示
            if let error = playerManager.errorMessage {
                VStack {
                    Spacer()
                    Text(error)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                        .padding(.bottom, 20)
                }
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
