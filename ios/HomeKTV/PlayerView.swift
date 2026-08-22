import SwiftUI
import MobileVLCKit
import Combine
import AVFoundation

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
    
    var systemSoundID: UInt32? {
        // 使用系统音效
        switch self {
        case .applause: return 1104  // 点击声
        case .cheer: return 1105
        case .laughter: return 1106
        case .fireworks: return 1107
        case .whistle: return 1108
        case .scream: return 1109
        case .unknown: return nil
        }
    }
}

// MARK: - 氛围音效播放器
class EffectSoundPlayer {
    static let shared = EffectSoundPlayer()
    
    func playEffect(_ effect: KTVEffect) {
        print("播放氛围效果: \(effect.displayName) (\(effect.rawValue))")
        
        // 尝试播放系统音效
        if let soundID = effect.systemSoundID {
            AudioServicesPlaySystemSound(soundID)
        }
        
        // 也可以使用震动反馈
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

// MARK: - WebSocket管理器
class WebSocketManager: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published var isConnected = false
    @Published var vocalMode: String = "accompaniment"
    @Published var currentEffect: KTVEffect?
    @Published var showEffect = false
    @Published var lastMessage: String = ""
    
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
                    print("收到WebSocket消息: \(text)")
                    DispatchQueue.main.async {
                        self.lastMessage = text
                    }
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        print("收到WebSocket数据: \(text)")
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
        
        print("处理消息类型: \(type), payload: \(String(describing: payload))")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch type {
            case "pong":
                self.isConnected = true
            case "vocal_changed":
                if let mode = payload?["mode"] as? String {
                    self.vocalMode = mode
                    self.onVocalChanged?(mode)
                }
            case "effect", "trigger_effect", "play_effect", "effect_trigger":
                // 尝试多种字段名
                let effectStr = payload?["effect"] as? String
                    ?? payload?["type"] as? String
                    ?? payload?["name"] as? String
                    ?? payload?["id"] as? String
                    ?? (payload?["effect"] as? [String: Any])?["type"] as? String
                
                if let effectStr = effectStr {
                    let effect = KTVEffect(rawValue: effectStr) ?? .unknown
                    self.currentEffect = effect
                    self.showEffect = true
                    self.onEffectChanged?(effect)
                    EffectSoundPlayer.shared.playEffect(effect)
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                        self?.showEffect = false
                    }
                }
            case "playback_restarted":
                self.onPlaybackRestarted?()
            default:
                print("未处理的消息类型: \(type)")
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
    let vocalMode: String
    
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
        context.coordinator.lastVocalMode = vocalMode
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        guard let player = context.coordinator.player else { return }
        
        if let url = url, context.coordinator.lastURL != url {
            context.coordinator.lastURL = url
            let media = VLCMedia(url: url)
            player.media = media
            player.play()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var player: VLCMediaPlayer?
        var lastURL: URL?
        var lastVocalMode: String = "accompaniment"
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
                self?.videoURL = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
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
                            self?.currentSong = playing.song
                            self?.videoURL = URL(string: "http://\(self?.host ?? ""):\(self?.port ?? 8980)/api/stream/\(playing.song.id)")
                        }
                        self?.showIdleScreen = false
                    } else {
                        if self?.currentSong != nil {
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
        if show {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: effectIcon)
                            .font(.system(size: 80))
                            .foregroundColor(.yellow)
                            .scaleEffect(1.2)
                            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: show)
                        Text(effect.displayName)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(40)
                    .background(
                        RadialGradient(gradient: Gradient(colors: [Color.yellow.opacity(0.3), Color.clear]), center: .center, startRadius: 0, endRadius: 200)
                    )
                    .cornerRadius(30)
                    Spacer()
                }
                Spacer()
            }
            .transition(.opacity)
        }
    }
    
    private var effectIcon: String {
        switch effect {
        case .applause: return "hands.clap.fill"
        case .cheer: return "person.3.fill"
        case .laughter: return "face.smiling.fill"
        case .fireworks: return "sparkles"
        case .whistle: return "wind"
        case .scream: return "exclamationmark.triangle.fill"
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
                
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(wsManager.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(wsManager.isConnected ? "遥控已连接" : "遥控未连接")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    
                    // 调试信息：显示最后收到的消息
                    if !wsManager.lastMessage.isEmpty {
                        Text("最后消息: \(wsManager.lastMessage.prefix(50))")
                            .font(.system(size: 10))
                            .foregroundColor(.gray.opacity(0.6))
                            .lineLimit(1)
                    }
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
            VLCVideoView(
                url: playerManager.videoURL,
                vocalMode: playerManager.vocalMode
            )
            .ignoresSafeArea()
            
            // 氛围效果覆盖层
            if let effect = playerManager.wsManager.currentEffect {
                EffectOverlayView(effect: effect, show: playerManager.wsManager.showEffect)
            }
            
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
