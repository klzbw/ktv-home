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

// MARK: - 播放管理器
class PlayerManager: NSObject, ObservableObject {
    @Published var currentSong: KTVSong?
    @Published var isPlaying = false
    @Published var queue: KTVQueue?
    @Published var showIdleScreen = true
    @Published var errorMessage: String?
    
    var mediaPlayer: VLCMediaPlayer?
    private var timer: Timer?
    private var host: String = ""
    private var port: Int = 8980
    
    override init() {
        super.init()
        setupPlayer()
    }
    
    func setupPlayer() {
        if mediaPlayer == nil {
            mediaPlayer = VLCMediaPlayer()
            mediaPlayer?.delegate = self
        }
    }
    
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
                        // 有歌曲在播放
                        if self?.currentSong?.id != playing.song.id {
                            // 切换到新歌曲
                            self?.currentSong = playing.song
                            self?.playSong(playing.song)
                        }
                        self?.showIdleScreen = false
                        self?.isPlaying = true
                    } else {
                        // 没有歌曲在播放
                        if self?.currentSong != nil {
                            self?.currentSong = nil
                            self?.mediaPlayer?.stop()
                        }
                        self?.isPlaying = false
                        self?.showIdleScreen = true
                    }
                }
            } catch {
                print("解析队列失败: \(error)")
                DispatchQueue.main.async {
                    self?.errorMessage = "解析失败: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    func playSong(_ song: KTVSong) {
        setupPlayer()
        
        guard let url = URL(string: "http://\(host):\(port)/api/stream/\(song.id)") else {
            errorMessage = "无效的视频地址"
            return
        }
        
        print("开始播放: \(song.title) - \(song.artist)")
        print("视频地址: \(url.absoluteString)")
        
        let media = VLCMedia(url: url)
        mediaPlayer?.media = media
        mediaPlayer?.play()
        
        // 设置音频轨道（原唱/伴奏）
        // VLC会自动处理多音轨
    }
    
    deinit {
        stopPolling()
        mediaPlayer?.stop()
    }
}

// MARK: - VLC播放器代理
extension PlayerManager: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        guard let player = aNotification.object as? VLCMediaPlayer else { return }
        
        DispatchQueue.main.async {
            switch player.state {
            case .playing:
                self.isPlaying = true
                self.errorMessage = nil
                print("VLC: 正在播放")
            case .paused:
                self.isPlaying = false
                print("VLC: 已暂停")
            case .stopped:
                self.isPlaying = false
                print("VLC: 已停止")
            case .ended:
                self.isPlaying = false
                print("VLC: 播放结束")
            case .error:
                self.errorMessage = "播放错误"
                print("VLC: 错误")
            default:
                break
            }
        }
    }
    
    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        // 播放时间变化
    }
}

// MARK: - TV播放视图
struct TVPlayerView: View {
    @ObservedObject var deviceManager: DeviceManager
    @StateObject private var playerManager = PlayerManager()
    
    var body: some View {
        ZStack {
            if playerManager.showIdleScreen {
                // 扫码提示页面
                IdleScreenView(deviceManager: deviceManager, playerManager: playerManager)
            } else {
                // 视频播放页面
                VLCPlayerView(playerManager: playerManager)
                    .ignoresSafeArea()
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

// MARK: - 扫码提示页面
struct IdleScreenView: View {
    @ObservedObject var deviceManager: DeviceManager
    @ObservedObject var playerManager: PlayerManager
    @State private var qrImage: UIImage?
    
    var body: some View {
        ZStack {
            // 背景
            LinearGradient(
                gradient: Gradient(colors: [Color(red: 0.05, green: 0.05, blue: 0.15), Color(red: 0.1, green: 0.05, blue: 0.2)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // 标题
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
                
                // 中间内容
                HStack(spacing: 60) {
                    // 左侧信息
                    VStack(alignment: .leading, spacing: 20) {
                        Text("手机点歌，电视欢唱")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("一家人的客厅KTV")
                            .font(.system(size: 18))
                            .foregroundColor(.gray)
                        
                        // 统计信息
                        HStack(spacing: 30) {
                            StatView(title: "曲库", value: "\(playerManager.queue?.list?.count ?? 0)首")
                            StatView(title: "已点", value: "\(playerManager.queue?.list?.count ?? 0)首")
                            StatView(title: "排队", value: "\(playerManager.queue?.list?.count ?? 0)首")
                        }
                        .padding(.top, 20)
                    }
                    
                    // 右侧二维码
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
                                .overlay(
                                    ProgressView()
                                )
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
                
                // 底部提示
                Text("等待点歌中...")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .padding(.bottom, 30)
            }
        }
        .onAppear {
            generateQRCode()
        }
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

// MARK: - VLC播放器视图
struct VLCPlayerView: UIViewRepresentable {
    @ObservedObject var playerManager: PlayerManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        
        // 确保player已创建
        playerManager.setupPlayer()
        
        if let player = playerManager.mediaPlayer {
            // 将VLC播放器的视图添加到容器
            if let vlcView = player.views?.first as? UIView {
                vlcView.frame = view.bounds
                vlcView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                view.addSubview(vlcView)
            }
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // 更新播放器视图
        if let player = playerManager.mediaPlayer {
            if let vlcView = player.views?.first as? UIView {
                if vlcView.superview !== uiView {
                    vlcView.frame = uiView.bounds
                    vlcView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    uiView.addSubview(vlcView)
                } else {
                    vlcView.frame = uiView.bounds
                }
            }
        }
    }
}

// MARK: - 兼容旧的PlayerView名称
typealias PlayerView = TVPlayerView
