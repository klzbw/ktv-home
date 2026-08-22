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

// MARK: - WebSocket消息
struct WSMessage: Codable {
    let type: String
    let payload: [String: AnyCodable]?
}

struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let stringVal = try? container.decode(String.self) {
            value = stringVal
        } else if let dictVal = try? container.decode([String: AnyCodable].self) {
            value = dictVal
        } else if let arrayVal = try? container.decode([AnyCodable].self) {
            value = arrayVal
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intVal = value as? Int {
            try container.encode(intVal)
        } else if let doubleVal = value as? Double {
            try container.encode(doubleVal)
        } else if let boolVal = value as? Bool {
            try container.encode(boolVal)
        } else if let stringVal = value as? String {
            try container.encode(stringVal)
        } else {
            try container.encodeNil()
        }
    }
}

// MARK: - WebSocket管理器
class WebSocketManager: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published var isConnected = false
    @Published var vocalMode: String = "accompaniment"
    @Published var volume: Int = 60
    @Published var isMuted: Bool = false
    
    private var webSocket: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var host: String = ""
    private var port: Int = 8980
    var onVocalChanged: ((String) -> Void)?
    var onVolumeChanged: ((Int) -> Void)?
    var onMuteChanged: ((Bool) -> Void)?
    var onPlaybackRestarted: (() -> Void)?
    
    func connect(host: String, port: Int) {
        self.host = host
        self.port = port
        
        let wsScheme = "ws"
        guard let url = URL(string: "\(wsScheme)://\(host):\(port)/ws") else { return }
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
        
        receiveMessage()
        startPing()
    }
    
    func disconnect() {
        stopPing()
        webSocket?.cancel()
        webSocket = nil
        isConnected = false
    }
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
                @unknown default:
                    break
                }
            case .failure:
                self?.isConnected = false
                // 重连
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self?.connect(host: self?.host ?? "", port: self?.port ?? 8980)
                }
                return
            }
            self?.receiveMessage()
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        
        let payload = json["payload"] as? [String: Any]
        
        DispatchQueue.main.async { [weak self] in
            switch type {
            case "pong":
                break
            case "vocal_changed":
                if let mode = payload?["mode"] as? String {
                    self?.vocalMode = mode
                    self?.onVocalChanged?(mode)
                }
            case "volume_changed":
                if let vol = payload?["volume"] as? Int {
                    self?.volume = vol
                    self?.onVolumeChanged?(vol)
                }
            case "mute_changed":
                if let muted = payload?["muted"] as? Bool {
                    self?.isMuted = muted
                    self?.onMuteChanged?(muted)
                }
            case "playback_restarted":
                self?.onPlaybackRestarted?()
            case "progress":
                break
            default:
                print("WebSocket事件: \(type), payload: \(String(describing: payload))")
            }
        }
    }
    
    private func startPing() {
        stopPing()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }
    
    private func stopPing() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
    
    private func sendPing() {
        let message = ["type": "ping"]
        if let data = try? JSONSerialization.data(withJSONObject: message),
           let text = String(data: data, encoding: .utf8) {
            webSocket?.send(.string(text)) { _ in }
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async {
            self.isConnected = true
            print("WebSocket已连接")
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            self.isConnected = false
            print("WebSocket已断开")
        }
    }
}

// MARK: - VLC播放器视图控制器
class VLCPlayerViewController: UIViewController {
    var mediaPlayer: VLCMediaPlayer?
    private var playerView: UIView!
    var currentVocalMode: String = "accompaniment"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        playerView = UIView(frame: view.bounds)
        playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerView.backgroundColor = .black
        view.addSubview(playerView)
        
        setupPlayer()
    }
    
    func setupPlayer() {
        if mediaPlayer == nil {
            mediaPlayer = VLCMediaPlayer()
            mediaPlayer?.drawable = playerView
        }
    }
    
    func play(url: URL) {
        setupPlayer()
        
        let media = VLCMedia(url: url)
        mediaPlayer?.media = media
        mediaPlayer?.play()
        
        // 延迟设置音轨（等待媒体加载）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.applyVocalMode()
        }
        
        print("VLC开始播放: \(url.absoluteString)")
    }
    
    func setVocalMode(_ mode: String) {
        currentVocalMode = mode
        applyVocalMode()
    }
    
    private func applyVocalMode() {
        guard let player = mediaPlayer else { return }
        
        // 获取所有音轨
        if let tracks = player.audioTracks as? [Any] {
            print("可用音轨数: \(tracks.count)")
            
            // KTV mkv通常有2个音轨：0=伴奏，1=原唱
            // 根据vocalMode切换
            if currentVocalMode == "original" {
                // 原唱：选择音轨1（如果有）
                if tracks.count > 1 {
                    player.audioTrackIndex = 1
                    print("切换到原唱（音轨1）")
                }
            } else {
                // 伴奏：选择音轨0
                player.audioTrackIndex = 0
                print("切换到伴奏（音轨0）")
            }
        }
    }
    
    func setVolume(_ volume: Int) {
        mediaPlayer?.audio?.volume = Int32(volume)
        print("设置音量: \(volume)")
    }
    
    func setMuted(_ muted: Bool) {
        mediaPlayer?.audio?.muted = muted
        print("设置静音: \(muted)")
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
    let wsManager = WebSocketManager()
    private var timer: Timer?
    private var host: String = ""
    private var port: Int = 8980
    
    func configure(host: String, port: Int) {
        self.host = host
        self.port = port
        
        // 连接WebSocket
        wsManager.connect(host: host, port: port)
        
        // 设置WebSocket回调
        wsManager.onVocalChanged = { [weak self] mode in
            self?.playerVC?.setVocalMode(mode)
        }
        wsManager.onVolumeChanged = { [weak self] vol in
            self?.playerVC?.setVolume(vol)
        }
        wsManager.onMuteChanged = { [weak self] muted in
            self?.playerVC?.setMuted(muted)
        }
        wsManager.onPlaybackRestarted = { [weak self] in
            if let song = self?.currentSong {
                self?.playSong(song)
            }
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
        wsManager.disconnect()
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
        // 应用当前的vocalMode
        if let mode = queue?.vocalMode {
            playerVC?.setVocalMode(mode)
        }
    }
    
    deinit {
        stopPolling()
        playerVC?.stop()
    }
}

// MARK: - TV播放视图
struct TVPlayerView: UIViewControllerRepresentable {
    @ObservedObject var deviceManager: DeviceManager
    @ObservedObject var playerManager: PlayerManager
    
    func makeUIViewController(context: Context) -> VLCPlayerViewController {
        let vc = VLCPlayerViewController()
        playerManager.playerVC = vc
        return vc
    }
    
    func updateUIViewController(_ uiViewController: VLCPlayerViewController, context: Context) {
        // 更新
    }
    
    static func dismantleUIViewController(_ uiViewController: VLCPlayerViewController, coordinator: ()) {
        uiViewController.stop()
    }
}

// MARK: - 扫码提示页面
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
                
                // WebSocket连接状态
                HStack(spacing: 8) {
                    Circle()
                        .fill(playerManager.wsManager.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(playerManager.wsManager.isConnected ? "遥控已连接" : "遥控未连接")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 10)
                
                Text("等待点歌中...")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .padding(.bottom, 20)
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

// MARK: - 主播放视图
struct PlayerView: View {
    @ObservedObject var deviceManager: DeviceManager
    @StateObject private var playerManager = PlayerManager()
    
    var body: some View {
        ZStack {
            TVPlayerView(deviceManager: deviceManager, playerManager: playerManager)
                .ignoresSafeArea()
            
            if playerManager.showIdleScreen {
                IdleOverlayView(deviceManager: deviceManager, playerManager: playerManager)
                    .transition(.opacity)
            }
            
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
