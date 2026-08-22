import SwiftUI
import MobileVLCKit
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

// MARK: - 氛围效果类型
enum KTVEffect: String {
    case applause = "applause"
    case cheer = "cheer"
    case laughter = "laughter"
    case fireworks = "fireworks"
    case whistle = "whistle"
    case scream = "scream"
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .applause: return "鼓掌"
        case .cheer: return "欢呼"
        case .laughter: return "笑声"
        case .fireworks: return "烟花"
        case .whistle: return "口哨"
        case .scream: return "尖叫"
        case .unknown: return "氛围"
        }
    }
}

// MARK: - WebSocket管理器
class WebSocketManager: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published var isConnected = false
    @Published var vocalMode: String = "accompaniment"
    @Published var currentEffect: KTVEffect?
    @Published var showEffect = false
    @Published var lastMessageType: String = ""  // 调试用
    
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pingTimer: Timer?
    private var host: String = ""
    private var port: Int = 8980
    
    var onVocalChanged: ((String) -> Void)?
    var onEffectChanged: ((KTVEffect) -> Void)?
    var onPlaybackRestarted: (() -> Void)?
    
    func connect(host: String, port: Int) {
        self.host = host
        self.port = port
        
        guard let url = URL(string: "ws://\(host):\(port)/ws") else { return }
        
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()
        
        receiveMessage()
        startPing()
    }
    
    func disconnect() {
        stopPing()
        webSocket?.cancel()
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        isConnected = false
    }
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    print("WebSocket收到: \(text)")
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        print("WebSocket收到(data): \(text)")
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
            case .failure(let error):
                print("WebSocket错误: \(error.localizedDescription)")
                self.isConnected = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.connect(host: self?.host ?? "", port: self?.port ?? 8980)
                }
                return
            }
            self.receiveMessage()
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        
        let payload = json["payload"] as? [String: Any]
        lastMessageType = type
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch type {
            case "pong":
                self.isConnected = true
            case "vocal_changed":
                if let mode = payload?["mode"] as? String {
                    print("vocal_changed: \(mode)")
                    self.vocalMode = mode
                    self.onVocalChanged?(mode)
                }
            case "effect":
                // 尝试多种payload格式
                var effectStr: String?
                if let e = payload?["effect"] as? String {
                    effectStr = e
                } else if let e = payload?["type"] as? String {
                    effectStr = e
                } else if let e = payload?["name"] as? String {
                    effectStr = e
                }
                
                if let effectStr = effectStr {
                    print("effect: \(effectStr)")
                    let effect = KTVEffect(rawValue: effectStr) ?? .unknown
                    self.currentEffect = effect
                    self.showEffect = true
                    self.onEffectChanged?(effect)
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                        self?.showEffect = false
                    }
                }
            case "playback_restarted":
                print("playback_restarted")
                self.onPlaybackRestarted?()
            default:
                print("未处理的消息类型: \(type), payload: \(String(describing: payload))")
                break
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
            webSocket?.send(.string(text)) { error in
                if let error = error {
                    print("发送ping失败: \(error.localizedDescription)")
                }
            }
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

// MARK: - VLC播放器视图
struct VLCVideoView: UIViewRepresentable {
    let url: URL?
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .black
        
        let player = VLCMediaPlayer()
        player.drawable = containerView
        
        if let url = url {
            let media = VLCMedia(url: url)
            player.media = media
            player.play()
        }
        
        context.coordinator.player = player
        context.coordinator.lastURL = url
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        guard let player = context.coordinator.player else { return }
        
        // URL变化时重新播放
        if let url = url, context.coordinator.lastURL != url {
            print("切换歌曲: \(url.lastPathComponent)")
            context.coordinator.lastURL = url
            
            // 先停止旧播放
            player.stop()
            
            // 延迟开始新播放，确保VLC准备好
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let media = VLCMedia(url: url)
                player.media = media
                player.play()
                print("开始播放新歌曲")
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var player: VLCMediaPlayer?
        var lastURL: URL?
    }
}

// MARK: - 播放管理器
class PlayerManager: ObservableObject {
    @Published var currentSong: KTVSong?
    @Published var showIdleScreen = true
    @Published var videoURL: URL?
    @Published var vocalMode: String = "accompaniment"
    
    let wsManager = WebSocketManager()
    private var timer: Timer?
    private var host: String = ""
    private var port: Int = 8980
    
    func configure(host: String, port: Int) {
        self.host = host
        self.port = port
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.wsManager.connect(host: host, port: port)
        }
        
        wsManager.onVocalChanged = { [weak self] mode in
            self?.vocalMode = mode
        }
        wsManager.onEffectChanged = { _ in }
        wsManager.onPlaybackRestarted = { [weak self] in
            if let song = self?.currentSong {
                print("播放重启: \(song.title)")
                self?.videoURL = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.videoURL = URL(string: "http://\(self?.host ?? ""):\(self?.port ?? 8980)/api/stream/\(song.id)")
                }
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
                    if let mode = queue.vocalMode, self?.vocalMode == "accompaniment" {
                        self?.vocalMode = mode
                    }
                    
                    if let playing = queue.playing {
                        if self?.currentSong?.id != playing.song.id {
                            print("检测到新歌曲: \(playing.song.title) - \(playing.song.artist) (ID: \(playing.song.id))")
                            self?.currentSong = playing.song
                            self?.videoURL = URL(string: "http://\(self?.host ?? ""):\(self?.port ?? 8980)/api/stream/\(playing.song.id)")
                        }
                        self?.showIdleScreen = false
                    } else {
                        if self?.currentSong != nil {
                            print("播放队列为空，停止播放")
                            self?.currentSong = nil
                            self?.videoURL = nil
                        }
                        self?.showIdleScreen = true
                    }
                }
            } catch {
                print("解析失败: \(error)")
            }
        }.resume()
    }
}

// MARK: - 氛围效果覆盖层
struct EffectOverlayView: View {
    let effect: KTVEffect
    let show: Bool
    
    var body: some View {
        ZStack {
            if show {
                // 半透明背景
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                // 氛围效果内容
                VStack(spacing: 20) {
                    Image(systemName: effectIcon)
                        .font(.system(size: 80))
                        .foregroundColor(.yellow)
                        .shadow(color: .yellow, radius: 10)
                    
                    Text(effect.displayName)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 2)
                }
                .padding(40)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.7))
                )
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: show)
            }
        }
        .allowsHitTesting(false)  // 不拦截点击事件
    }
    
    private var effectIcon: String {
        switch effect {
        case .applause: return "hands.clap"
        case .cheer: return "person.3.fill"
        case .laughter: return "face.smiling"
        case .fireworks: return "sparkles"
        case .whistle: return "wind"
        case .scream: return "exclamationmark.triangle"
        case .unknown: return "star.fill"
        }
    }
}

// MARK: - 扫码提示页面
struct IdleOverlayView: View {
    @ObservedObject var deviceManager: DeviceManager
    @ObservedObject var wsManager: WebSocketManager
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
                
                HStack(spacing: 8) {
                    Circle()
                        .fill(wsManager.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(wsManager.isConnected ? "遥控已连接" : "遥控未连接")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 10)
                
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
            // VLC播放器（最底层）
            VLCVideoView(url: playerManager.videoURL)
                .ignoresSafeArea()
            
            // 氛围效果覆盖层（中间层）
            if let effect = playerManager.wsManager.currentEffect {
                EffectOverlayView(effect: effect, show: playerManager.wsManager.showEffect)
            }
            
            // 扫码提示页面（最上层）
            if playerManager.showIdleScreen {
                IdleOverlayView(deviceManager: deviceManager, wsManager: playerManager.wsManager)
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
