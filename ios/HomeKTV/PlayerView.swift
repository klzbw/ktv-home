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
    case bell = "bell"
    case drum = "drum"
    case cymbal = "cymbal"
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .applause: return "鼓掌"
        case .cheer: return "欢呼"
        case .laughter: return "笑声"
        case .fireworks: return "烟花"
        case .whistle: return "口哨"
        case .scream: return "尖叫"
        case .bell: return "铃声"
        case .drum: return "鼓声"
        case .cymbal: return "镲声"
        case .unknown: return "氛围"
        }
    }
}

// MARK: - 调试日志条目
struct DebugLogEntry: Identifiable {
    let id = UUID()
    let time: String
    let message: String
    let type: LogType
    
    enum LogType {
        case info, warning, error, websocket
    }
}

// MARK: - WebSocket管理器
class WebSocketManager: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published var isConnected = false
    @Published var vocalMode: String = "accompaniment"
    @Published var currentEffect: KTVEffect?
    @Published var showEffect = false
    @Published var debugLogs: [DebugLogEntry] = []
    @Published var lastMessage: String = ""
    @Published var effectCount = 0
    
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pingTimer: Timer?
    private var host: String = ""
    private var port: Int = 8980
    
    var onVocalChanged: ((String) -> Void)?
    var onEffectChanged: ((KTVEffect) -> Void)?
    var onPlaybackRestarted: (() -> Void)?
    
    private func addLog(_ message: String, type: DebugLogEntry.LogType = .info) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let time = formatter.string(from: Date())
        let entry = DebugLogEntry(time: time, message: message, type: type)
        DispatchQueue.main.async {
            self.debugLogs.insert(entry, at: 0)
            if self.debugLogs.count > 50 {
                self.debugLogs.removeLast()
            }
        }
    }
    
    func connect(host: String, port: Int) {
        self.host = host
        self.port = port
        addLog("连接WebSocket: ws://\(host):\(port)/ws")
        
        guard let url = URL(string: "ws://\(host):\(port)/ws") else {
            addLog("URL无效", type: .error)
            return
        }
        
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()
        
        receiveMessage()
        startPing()
    }
    
    func disconnect() {
        addLog("断开WebSocket")
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
                    self.lastMessage = text
                    self.addLog("收到: \(text)", type: .websocket)
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.lastMessage = text
                        self.addLog("收到(data): \(text)", type: .websocket)
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
            case .failure(let error):
                self.addLog("WebSocket错误: \(error.localizedDescription)", type: .error)
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
              let type = json["type"] as? String else {
            addLog("消息解析失败", type: .error)
            return
        }
        
        let payload = json["payload"] as? [String: Any]
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch type {
            case "pong":
                self.isConnected = true
            case "vocal_changed":
                if let mode = payload?["mode"] as? String {
                    self.addLog("原唱/伴唱切换: \(mode)")
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
                } else if let e = payload?["value"] as? String {
                    effectStr = e
                }
                
                if let effectStr = effectStr {
                    self.effectCount += 1
                    self.addLog("氛围效果 #\(self.effectCount): \(effectStr)")
                    let effect = KTVEffect(rawValue: effectStr) ?? .unknown
                    self.currentEffect = effect
                    self.showEffect = true
                    self.onEffectChanged?(effect)
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                        self?.showEffect = false
                    }
                } else {
                    self.addLog("氛围效果payload解析失败: \(String(describing: payload))", type: .warning)
                }
            case "playback_restarted":
                self.addLog("播放重启")
                self.onPlaybackRestarted?()
            default:
                self.addLog("未处理: \(type)", type: .warning)
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
            self.addLog("WebSocket已连接")
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.addLog("WebSocket已断开")
        }
    }
}

// MARK: - VLC播放器视图
struct VLCVideoView: UIViewRepresentable {
    let url: URL?
    let songId: Int?
    let onLog: ((String, DebugLogEntry.LogType) -> Void)?
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .black
        
        let player = VLCMediaPlayer()
        player.drawable = containerView
        
        if let url = url {
            let media = VLCMedia(url: url)
            player.media = media
            player.play()
            onLog?("开始播放: \(url.lastPathComponent)", .info)
        }
        
        context.coordinator.player = player
        context.coordinator.lastURL = url
        context.coordinator.lastSongId = songId
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        guard let player = context.coordinator.player else { return }
        
        // 歌曲ID变化时重新播放
        if let songId = songId, context.coordinator.lastSongId != songId {
            onLog?("切换歌曲ID: \(songId)", .info)
            context.coordinator.lastSongId = songId
            context.coordinator.lastURL = url
            
            // 先停止旧播放
            player.stop()
            onLog?("停止旧播放", .info)
            
            // 延迟开始新播放
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let url = url {
                    let media = VLCMedia(url: url)
                    player.media = media
                    player.play()
                    self.onLog?("开始新播放: \(url.lastPathComponent)", .info)
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var player: VLCMediaPlayer?
        var lastURL: URL?
        var lastSongId: Int?
    }
}

// MARK: - 播放管理器
class PlayerManager: ObservableObject {
    @Published var currentSong: KTVSong?
    @Published var showIdleScreen = true
    @Published var videoURL: URL?
    @Published var vocalMode: String = "accompaniment"
    @Published var debugLogs: [DebugLogEntry] = []
    
    let wsManager = WebSocketManager()
    private var timer: Timer?
    private var host: String = ""
    private var port: Int = 8980
    
    private func addLog(_ message: String, type: DebugLogEntry.LogType = .info) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let time = formatter.string(from: Date())
        let entry = DebugLogEntry(time: time, message: message, type: type)
        DispatchQueue.main.async {
            self.debugLogs.insert(entry, at: 0)
            if self.debugLogs.count > 30 {
                self.debugLogs.removeLast()
            }
        }
    }
    
    func configure(host: String, port: Int) {
        self.host = host
        self.port = port
        addLog("配置: http://\(host):\(port)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.wsManager.connect(host: host, port: port)
        }
        
        wsManager.onVocalChanged = { [weak self] mode in
            self?.vocalMode = mode
        }
        wsManager.onEffectChanged = { _ in }
        wsManager.onPlaybackRestarted = { [weak self] in
            if let song = self?.currentSong {
                self?.addLog("播放重启: \(song.title)", type: .info)
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
                            self?.addLog("检测到新歌: \(playing.song.title) - \(playing.song.artist) (ID: \(playing.song.id))", type: .info)
                            self?.currentSong = playing.song
                            self?.videoURL = URL(string: "http://\(self?.host ?? ""):\(self?.port ?? 8980)/api/stream/\(playing.song.id)")
                        }
                        self?.showIdleScreen = false
                    } else {
                        if self?.currentSong != nil {
                            self?.addLog("播放队列为空", type: .info)
                            self?.currentSong = nil
                            self?.videoURL = nil
                        }
                        self?.showIdleScreen = true
                    }
                }
            } catch {
                self?.addLog("队列解析失败: \(error.localizedDescription)", type: .error)
            }
        }.resume()
    }
}

// MARK: - 氛围效果覆盖层
struct EffectOverlayView: View {
    let effect: KTVEffect
    let show: Bool
    let count: Int
    
    var body: some View {
        ZStack {
            if show {
                // 半透明背景
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                
                // 氛围效果内容
                VStack(spacing: 20) {
                    Image(systemName: effectIcon)
                        .font(.system(size: 120))
                        .foregroundColor(.yellow)
                        .shadow(color: .yellow, radius: 20)
                    
                    Text(effect.displayName)
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 3)
                    
                    Text("第 \(count) 次")
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                }
                .padding(50)
                .background(
                    RoundedRectangle(cornerRadius: 30)
                        .fill(Color.black.opacity(0.85))
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: show)
    }
    
    private var effectIcon: String {
        switch effect {
        case .applause: return "hands.clap"
        case .cheer: return "person.3.fill"
        case .laughter: return "face.smiling"
        case .fireworks: return "sparkles"
        case .whistle: return "wind"
        case .scream: return "exclamationmark.triangle"
        case .bell: return "bell.fill"
        case .drum: return "hifispeaker.fill"
        case .cymbal: return "circle.fill"
        case .unknown: return "star.fill"
        }
    }
}

// MARK: - 调试信息面板
struct DebugPanelView: View {
    @ObservedObject var wsManager: WebSocketManager
    @ObservedObject var playerManager: PlayerManager
    @Binding var showDebug: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("调试信息")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(action: { showDebug = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(Color.black.opacity(0.9))
            
            // 状态信息
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        Text("WebSocket状态: \(wsManager.isConnected ? "已连接" : "未连接")")
                            .foregroundColor(wsManager.isConnected ? .green : .red)
                        Text("当前歌曲: \(playerManager.currentSong?.title ?? "无")")
                            .foregroundColor(.white)
                        Text("歌曲ID: \(playerManager.currentSong?.id ?? 0)")
                            .foregroundColor(.white)
                        Text("原唱/伴唱: \(wsManager.vocalMode)")
                            .foregroundColor(.white)
                        Text("氛围效果次数: \(wsManager.effectCount)")
                            .foregroundColor(.yellow)
                        Text("最近消息: \(wsManager.lastMessage)")
                            .foregroundColor(.yellow)
                            .lineLimit(3)
                    }
                    .font(.system(size: 12))
                    
                    Divider()
                        .background(Color.gray)
                    
                    Text("日志:")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                    
                    ForEach(wsManager.debugLogs) { log in
                        HStack(alignment: .top) {
                            Text(log.time)
                                .foregroundColor(.gray)
                            Text(log.message)
                                .foregroundColor(logColor(log.type))
                                .lineLimit(3)
                        }
                        .font(.system(size: 10))
                    }
                }
                .padding()
            }
            .frame(maxHeight: 350)
            .background(Color.black.opacity(0.85))
        }
        .cornerRadius(12)
        .shadow(radius: 10)
        .padding()
    }
    
    private func logColor(_ type: DebugLogEntry.LogType) -> Color {
        switch type {
        case .info: return .white
        case .warning: return .yellow
        case .error: return .red
        case .websocket: return .cyan
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
    @State private var showDebug = false
    
    var body: some View {
        ZStack {
            // VLC播放器（最底层）
            VLCVideoView(
                url: playerManager.videoURL,
                songId: playerManager.currentSong?.id,
                onLog: { message, type in
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm:ss"
                    let time = formatter.string(from: Date())
                    let entry = DebugLogEntry(time: time, message: message, type: type)
                    DispatchQueue.main.async {
                        self.playerManager.debugLogs.insert(entry, at: 0)
                        if self.playerManager.debugLogs.count > 30 {
                            self.playerManager.debugLogs.removeLast()
                        }
                    }
                }
            )
            .ignoresSafeArea()
            
            // 氛围效果覆盖层（中间层）
            if let effect = playerManager.wsManager.currentEffect {
                EffectOverlayView(
                    effect: effect,
                    show: playerManager.wsManager.showEffect,
                    count: playerManager.wsManager.effectCount
                )
            }
            
            // 扫码提示页面（最上层）
            if playerManager.showIdleScreen {
                IdleOverlayView(deviceManager: deviceManager, wsManager: playerManager.wsManager)
                    .transition(.opacity)
            }
            
            // 调试按钮（右上角）
            VStack {
                HStack {
                    Spacer()
                    Button(action: { showDebug.toggle() }) {
                        Image(systemName: "ladybug.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding()
                }
                Spacer()
            }
            
            // 调试面板
            if showDebug {
                DebugPanelView(
                    wsManager: playerManager.wsManager,
                    playerManager: playerManager,
                    showDebug: $showDebug
                )
                .transition(.move(edge: .top))
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
