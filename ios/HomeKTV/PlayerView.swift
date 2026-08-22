import SwiftUI
import MobileVLCKit
import AVFoundation
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

// MARK: - 氛围效果类型（四种：鼓掌、欢呼、倒彩、干杯）
enum KTVEffect: String {
    case applause = "applause"
    case clap = "clap"
    case cheer = "cheer"
    case boo = "boo"
    case hiss = "hiss"
    case cheers = "cheers"
    case toast = "toast"
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .applause, .clap: return "鼓掌"
        case .cheer: return "欢呼"
        case .boo, .hiss: return "倒彩"
        case .cheers, .toast: return "干杯"
        case .unknown: return "氛围"
        }
    }
    
    var iconName: String {
        switch self {
        case .applause, .clap: return "hands.clap"
        case .cheer: return "person.3.fill"
        case .boo, .hiss: return "hand.thumbsdown"
        case .cheers, .toast: return "wineglass.fill"
        case .unknown: return "star.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .applause, .clap: return .yellow
        case .cheer: return .green
        case .boo, .hiss: return .red
        case .cheers, .toast: return .orange
        case .unknown: return .white
        }
    }
    
    // 系统音效ID
    var systemSoundID: SystemSoundID {
        switch self {
        case .applause, .clap: return 1104  // 短信收到
        case .cheer: return 1306  // 收到邮件
        case .boo, .hiss: return 1102  // 短信发送
        case .cheers, .toast: return 1304  // 发送邮件
        case .unknown: return 1100
        }
    }
}

// MARK: - 音效播放器
class EffectSoundPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = EffectSoundPlayer()
    private var audioPlayers: [AVAudioPlayer] = []
    private var audioEngine: AVAudioEngine?
    private var noisePlayers: [AVAudioPlayerNode] = []
    
    func playEffect(_ effect: KTVEffect) {
        // 先播放系统音效作为基础
        AudioServicesPlaySystemSound(effect.systemSoundID)
        
        // 根据效果类型生成更真实的音效
        switch effect {
        case .applause, .clap:
            playApplauseSound()
        case .cheer:
            playCheerSound()
        case .boo, .hiss:
            playBooSound()
        case .cheers, .toast:
            playCheersSound()
        case .unknown:
            break
        }
    }
    
    // 鼓掌声 - 使用白噪音模拟
    private func playApplauseSound() {
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        
        // 生成白噪音缓冲
        let frameCount = AVAudioFrameCount(44100 * 2) // 2秒
        let buffer = AVAudioPCMBuffer(pcmFormat: format!, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        
        // 填充随机噪音（模拟掌声）
        if let channelData = buffer.floatChannelData {
            for frame in 0..<Int(frameCount) {
                // 使用衰减的随机噪音模拟掌声
                let decay = Float(1.0 - Double(frame) / Double(frameCount))
                let noise = Float.random(in: -0.5...0.5) * decay
                channelData[0][frame] = noise
                channelData[1][frame] = noise
            }
        }
        
        do {
            try engine.start()
            playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
            playerNode.play()
            
            // 2秒后停止引擎
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                engine.stop()
            }
        } catch {
            print("启动音频引擎失败: \(error)")
        }
    }
    
    // 欢呼声 - 使用更高频率的噪音
    private func playCheerSound() {
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        
        let frameCount = AVAudioFrameCount(44100 * 2)
        let buffer = AVAudioPCMBuffer(pcmFormat: format!, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        
        if let channelData = buffer.floatChannelData {
            for frame in 0..<Int(frameCount) {
                // 欢呼声 - 使用带节奏的噪音
                let decay = Float(1.0 - Double(frame) / Double(frameCount))
                let rhythm = sin(Double(frame) * 0.01) * 0.3
                let noise = Float.random(in: -0.3...0.3) * decay + Float(rhythm) * decay
                channelData[0][frame] = noise
                channelData[1][frame] = noise
            }
        }
        
        do {
            try engine.start()
            playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
            playerNode.play()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                engine.stop()
            }
        } catch {
            print("启动音频引擎失败: \(error)")
        }
    }
    
    // 倒彩声 - 使用低频噪音
    private func playBooSound() {
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        
        let frameCount = AVAudioFrameCount(44100 * 2)
        let buffer = AVAudioPCMBuffer(pcmFormat: format!, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        
        if let channelData = buffer.floatChannelData {
            for frame in 0..<Int(frameCount) {
                // 倒彩声 - 使用低频嗡嗡声
                let decay = Float(1.0 - Double(frame) / Double(frameCount))
                let lowFreq = sin(Double(frame) * 0.005) * 0.4
                let noise = Float.random(in: -0.1...0.1) * decay + Float(lowFreq) * decay
                channelData[0][frame] = noise
                channelData[1][frame] = noise
            }
        }
        
        do {
            try engine.start()
            playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
            playerNode.play()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                engine.stop()
            }
        } catch {
            print("启动音频引擎失败: \(error)")
        }
    }
    
    // 干杯声 - 使用清脆的碰杯声（高频短促）
    private func playCheersSound() {
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        
        let frameCount = AVAudioFrameCount(44100 * 1)
        let buffer = AVAudioPCMBuffer(pcmFormat: format!, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        
        if let channelData = buffer.floatChannelData {
            for frame in 0..<Int(frameCount) {
                // 干杯声 - 使用高频衰减的清脆声音
                let decay = Float(exp(-Double(frame) * 0.005))
                let highFreq = sin(Double(frame) * 0.1) * 0.5
                let noise = Float(highFreq) * decay + Float.random(in: -0.05...0.05) * decay
                channelData[0][frame] = noise
                channelData[1][frame] = noise
            }
        }
        
        do {
            try engine.start()
            playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
            playerNode.play()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                engine.stop()
            }
        } catch {
            print("启动音频引擎失败: \(error)")
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
                    DispatchQueue.main.async {
                        self.lastMessage = text
                        self.addLog("收到: \(text)", type: .websocket)
                        self.handleMessage(text)
                    }
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            self.lastMessage = text
                            self.addLog("收到(data): \(text)", type: .websocket)
                            self.handleMessage(text)
                        }
                    }
                @unknown default:
                    break
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.addLog("WebSocket错误: \(error.localizedDescription)", type: .error)
                    self.isConnected = false
                }
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
        
        switch type {
        case "pong":
            isConnected = true
        case "vocal_changed":
            if let mode = payload?["mode"] as? String {
                addLog("原唱/伴唱切换: \(mode)")
                vocalMode = mode
                onVocalChanged?(mode)
            }
        case "effect", "effect_play", "play_effect", "atmosphere", "ambiance":
            var effectStr: String?
            if let e = payload?["effect"] as? String {
                effectStr = e
            } else if let e = payload?["type"] as? String {
                effectStr = e
            } else if let e = payload?["name"] as? String {
                effectStr = e
            } else if let e = payload?["value"] as? String {
                effectStr = e
            } else if let e = payload?["effect_id"] as? String {
                effectStr = e
            } else if let e = payload?["id"] as? String {
                effectStr = e
            }
            
            addLog("氛围事件类型: \(type), payload: \(String(describing: payload))", type: .websocket)
            
            if let effectStr = effectStr {
                effectCount += 1
                addLog("氛围效果 #\(effectCount): \(effectStr)")
                let effect = KTVEffect(rawValue: effectStr) ?? .unknown
                currentEffect = effect
                showEffect = true
                onEffectChanged?(effect)
                
                // 播放音效
                EffectSoundPlayer.shared.playEffect(effect)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    self?.showEffect = false
                }
            } else {
                addLog("氛围效果payload解析失败", type: .warning)
                effectCount += 1
                currentEffect = .unknown
                showEffect = true
                EffectSoundPlayer.shared.playEffect(.unknown)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    self?.showEffect = false
                }
            }
        case "playback_restarted":
            addLog("播放重启")
            onPlaybackRestarted?()
        default:
            addLog("未处理: \(type)", type: .warning)
            break
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
        containerView.contentMode = .scaleAspectFit
        // 确保视图自动调整大小以填充父视图
        containerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        containerView.clipsToBounds = true
        
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
        
        // 确保drawable视图在屏幕旋转时正确调整大小
        if player.drawable !== uiView {
            player.drawable = uiView
        }
        
        if let songId = songId, context.coordinator.lastSongId != songId {
            onLog?("切换歌曲ID: \(songId), URL: \(url?.lastPathComponent ?? "nil")", .info)
            context.coordinator.lastSongId = songId
            context.coordinator.lastURL = url
            
            // 立即停止旧播放并开始新播放，减少延迟
            player.stop()
            onLog?("停止旧播放", .info)
            
            // 短暂延迟确保VLC准备好，然后立即开始新播放
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let url = url {
                    let media = VLCMedia(url: url)
                    player.media = media
                    player.play()
                    self.onLog?("开始新播放: \(url.lastPathComponent)", .info)
                }
            }
        } else if let url = url, context.coordinator.lastURL != url {
            // URL变化但歌曲ID没变，也需要更新
            onLog?("URL变化: \(url.lastPathComponent)", .info)
            context.coordinator.lastURL = url
            player.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let media = VLCMedia(url: url)
                player.media = media
                player.play()
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

// MARK: - 氛围效果覆盖层（带动画）
struct EffectOverlayView: View {
    let effect: KTVEffect
    let show: Bool
    let count: Int
    
    @State private var animate = false
    @State private var pulse = false
    @State private var float = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if show {
                    // 渐变背景
                    RadialGradient(
                        gradient: Gradient(colors: [effect.color.opacity(0.3), Color.black.opacity(0.8)]),
                        center: .center,
                        startRadius: 0,
                        endRadius: max(geometry.size.width, geometry.size.height)
                    )
                    .ignoresSafeArea()
                    
                    // 粒子效果背景
                    ParticleBackgroundView(effect: effect)
                    
                    // 光环效果
                    Circle()
                        .stroke(effect.color.opacity(0.5), lineWidth: 3)
                        .frame(width: 200, height: 200)
                        .scaleEffect(animate ? 1.5 : 0.5)
                        .opacity(animate ? 0 : 1)
                        .animation(
                            Animation.easeOut(duration: 1.0)
                                .repeatForever(autoreverses: false),
                            value: animate
                        )
                    
                    // 氛围效果内容 - 居中显示
                    VStack(spacing: 20) {
                        Spacer()
                        
                        // 图标 - 带浮动+脉冲+旋转动画
                        Image(systemName: effect.iconName)
                            .font(.system(size: 120))
                            .foregroundColor(effect.color)
                            .shadow(color: effect.color, radius: 20)
                            .scaleEffect(pulse ? 1.3 : 0.9)
                            .rotationEffect(.degrees(animate ? 15 : -15))
                            .offset(y: float ? -20 : 20)
                            .animation(
                                Animation.easeInOut(duration: 0.6)
                                    .repeatForever(autoreverses: true),
                                value: animate
                            )
                            .animation(
                                Animation.spring(response: 0.4, dampingFraction: 0.4)
                                    .repeatForever(autoreverses: true),
                                value: pulse
                            )
                            .animation(
                                Animation.easeInOut(duration: 1.0)
                                    .repeatForever(autoreverses: true),
                                value: float
                            )
                        
                        // 文字 - 带发光效果
                        Text(effect.displayName)
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: effect.color, radius: 10)
                            .shadow(color: .black, radius: 3)
                            .scaleEffect(pulse ? 1.15 : 1.0)
                            .animation(
                                Animation.spring(response: 0.3, dampingFraction: 0.5)
                                    .repeatForever(autoreverses: true),
                                value: pulse
                            )
                        
                        // 次数
                        Text("第 \(count) 次")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(effect.color.opacity(0.3))
                            )
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onAppear {
                animate = true
                pulse = true
                float = true
            }
            .onDisappear {
                animate = false
                pulse = false
                float = false
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.3), value: show)
    }
}

// MARK: - 粒子背景效果
struct ParticleBackgroundView: View {
    let effect: KTVEffect
    @State private var particles: [Particle] = []
    
    struct Particle: Identifiable {
        let id = UUID()
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let opacity: Double
        let speed: Double
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(effect.color)
                        .frame(width: particle.size, height: particle.size)
                        .position(x: particle.x, y: particle.y)
                        .opacity(particle.opacity)
                        .animation(
                            Animation.linear(duration: particle.speed)
                                .repeatForever(autoreverses: false),
                            value: particle.id
                        )
                }
            }
            .onAppear {
                createParticles(in: geometry.size)
            }
        }
    }
    
    private func createParticles(in size: CGSize) {
        particles = (0..<30).map { _ in
            Particle(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: 0...size.height),
                size: CGFloat.random(in: 5...20),
                opacity: Double.random(in: 0.2...0.6),
                speed: Double.random(in: 1...3)
            )
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

// MARK: - 扫码提示页面（适配横屏）
struct IdleOverlayView: View {
    @ObservedObject var deviceManager: DeviceManager
    @ObservedObject var wsManager: WebSocketManager
    @State private var qrImage: UIImage?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color(red: 0.05, green: 0.05, blue: 0.15), Color(red: 0.1, green: 0.05, blue: 0.2)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // 根据屏幕方向调整布局
                if geometry.size.width > geometry.size.height {
                    // 横屏布局
                    HStack(spacing: 40) {
                        VStack(spacing: 20) {
                            Text("家庭KTV")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(wsManager.isConnected ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                                Text(wsManager.isConnected ? "遥控已连接" : "遥控未连接")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                            
                            Text("等待点歌中...")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity)
                        
                        VStack(spacing: 12) {
                            if let qrImage = qrImage {
                                Image(uiImage: qrImage)
                                    .interpolation(.none)
                                    .resizable()
                                    .frame(width: 150, height: 150)
                                    .background(Color.white)
                                    .cornerRadius(12)
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                                    .frame(width: 150, height: 150)
                                    .overlay(ProgressView())
                            }
                            
                            Text("扫码点歌")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            
                            if let device = deviceManager.connectedDevice {
                                Text("http://\(device.host):\(device.port)/m")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding()
                } else {
                    // 竖屏布局
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
            }
            .onAppear { generateQRCode() }
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
            
            // 扫码提示页面（中间层）
            if playerManager.showIdleScreen {
                IdleOverlayView(deviceManager: deviceManager, wsManager: playerManager.wsManager)
                    .transition(.opacity)
            }
            
            // 氛围效果覆盖层（最上层）
            if let effect = playerManager.wsManager.currentEffect {
                EffectOverlayView(
                    effect: effect,
                    show: playerManager.wsManager.showEffect,
                    count: playerManager.wsManager.effectCount
                )
                .zIndex(100)
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
                .zIndex(200)
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
