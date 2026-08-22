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

// MARK: - 音效播放器（使用系统音效，自然不突兀）
class EffectSoundPlayer {
    static let shared = EffectSoundPlayer()
    
    func playEffect(_ effect: KTVEffect) {
        // 使用系统音效，自然不突兀
        AudioServicesPlaySystemSound(effect.systemSoundID)
        
        // 对于某些效果，播放两次增强效果
        switch effect {
        case .applause, .clap:
            // 鼓掌：连续播放两次
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                AudioServicesPlaySystemSound(1104)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                AudioServicesPlaySystemSound(1104)
            }
        case .cheer:
            // 欢呼：连续播放两次
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                AudioServicesPlaySystemSound(1306)
            }
        case .boo, .hiss:
            // 倒彩：使用较低的音效
            AudioServicesPlaySystemSound(1102)
        case .cheers, .toast:
            // 干杯：使用清脆的音效
            AudioServicesPlaySystemSound(1304)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                AudioServicesPlaySystemSound(1304)
            }
        case .unknown:
            break
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
    var onPlaybackControl: ((String) -> Void)?
    var onStateSync: (([String: Any]) -> Void)?
    
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
            // 打印完整payload用于调试
            if let payloadData = try? JSONSerialization.data(withJSONObject: payload ?? [:], options: .prettyPrinted),
               let payloadStr = String(data: payloadData, encoding: .utf8) {
                addLog("vocal_changed完整payload: \(payloadStr)", type: .websocket)
                print("vocal_changed完整payload: \(payloadStr)")
            }
            
            // 从多个位置尝试提取音轨模式
            var mode: String? = nil
            
            // 位置1：payload.mode
            if let m = payload?["mode"] as? String {
                mode = m
                addLog("从payload.mode获取: \(m)", type: .info)
            }
            // 位置2：payload.vocalMode
            else if let m = payload?["vocalMode"] as? String {
                mode = m
                addLog("从payload.vocalMode获取: \(m)", type: .info)
            }
            // 位置3：payload.playing.vocalMode
            else if let playing = payload?["playing"] as? [String: Any],
                    let m = playing["vocalMode"] as? String {
                mode = m
                addLog("从playing.vocalMode获取: \(m)", type: .info)
            }
            // 位置4：payload.playing.song.vocalMode
            else if let playing = payload?["playing"] as? [String: Any],
                    let song = playing["song"] as? [String: Any],
                    let m = song["vocalMode"] as? String {
                mode = m
                addLog("从playing.song.vocalMode获取: \(m)", type: .info)
            }
            
            if let mode = mode {
                addLog("原唱/伴唱切换: \(mode)", type: .info)
                vocalMode = mode
                onVocalChanged?(mode)
            } else {
                addLog("⚠️ vocal_changed消息中未找到mode字段", type: .warning)
                // 尝试从playing对象中提取所有字段名
                if let playing = payload?["playing"] as? [String: Any] {
                    let keys = Array(playing.keys)
                    addLog("playing对象字段: \(keys)", type: .warning)
                }
                if let allKeys = payload?.keys {
                    addLog("payload字段: \(Array(allKeys))", type: .warning)
                }
            }
        case "sync_full", "now_playing", "queue_updated":
            // 完整状态快照或播放状态更新
            addLog("状态同步: \(type)", type: .websocket)
            // 提取播放状态
            if let state = payload?["state"] as? String {
                addLog("播放状态: \(state)")
                onPlaybackControl?(state)
            }
            // 从多个位置提取音轨模式
            var syncMode: String? = nil
            if let m = payload?["vocalMode"] as? String {
                syncMode = m
            } else if let playing = payload?["playing"] as? [String: Any],
                      let m = playing["vocalMode"] as? String {
                syncMode = m
            }
            if let mode = syncMode {
                addLog("音轨模式(同步): \(mode)", type: .info)
                vocalMode = mode
                onVocalChanged?(mode)
            }
            // 从playing对象中提取状态
            if let playing = payload?["playing"] as? [String: Any] {
                if let state = payload?["state"] as? String {
                    onPlaybackControl?(state)
                }
            }
        case "play", "pause", "player_state", "playback_state", "toggle_playback":
            let state = payload?["state"] as? String ?? type
            addLog("播放控制: \(state), type: \(type)", type: .websocket)
            onPlaybackControl?(state)
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

// MARK: - 应用音轨模式（原唱/伴唱）全局函数

// MARK: - VLC播放器视图
struct VLCVideoView: UIViewRepresentable {
    let url: URL?
    let songId: Int?
    let vocalMode: String  // "original" 或 "accompaniment"
    let onLog: ((String, DebugLogEntry.LogType) -> Void)?
    let onPlayerReady: ((VLCMediaPlayer) -> Void)?  // 播放器就绪回调
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .black
        containerView.contentMode = .scaleAspectFill
        containerView.clipsToBounds = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        let player = VLCMediaPlayer()
        player.drawable = containerView
        
        // 通知播放器就绪
        print("VLCVideoView.makeUIView - onPlayerReady闭包是否为nil: \(onPlayerReady == nil)")
        onPlayerReady?(player)
        print("VLCVideoView.makeUIView - 已调用onPlayerReady")
        
        if let url = url {
            let media = VLCMedia(url: url)
            player.media = media
            player.play()
            onLog?("开始播放: \(url.lastPathComponent)", .info)
        }
        
        context.coordinator.player = player
        context.coordinator.lastURL = url
        context.coordinator.lastSongId = songId
        context.coordinator.lastVocalMode = vocalMode
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        guard let player = context.coordinator.player else { return }
        
        // 确保drawable视图在屏幕旋转时正确调整大小
        if let drawable = player.drawable as? UIView, drawable !== uiView {
            player.drawable = uiView
        }
        
        // 确保视图填充整个父视图（横屏修复关键）
        if let superview = uiView.superview {
            NSLayoutConstraint.activate([
                uiView.topAnchor.constraint(equalTo: superview.topAnchor),
                uiView.bottomAnchor.constraint(equalTo: superview.bottomAnchor),
                uiView.leadingAnchor.constraint(equalTo: superview.leadingAnchor),
                uiView.trailingAnchor.constraint(equalTo: superview.trailingAnchor)
            ])
        }
        
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
        
        if let songId = songId, context.coordinator.lastSongId != songId {
            onLog?("切换歌曲ID: \(songId), URL: \(url?.lastPathComponent ?? "nil")", .info)
            context.coordinator.lastSongId = songId
            context.coordinator.lastURL = url
            
            // 立即停止旧播放并开始新播放
            player.stop()
            onLog?("停止旧播放", .info)
            
            // 立即开始新播放，不延迟
            if let url = url {
                let media = VLCMedia(url: url)
                player.media = media
                player.play()
                onLog?("开始新播放: \(url.lastPathComponent)", .info)
            }
        } else if let url = url, context.coordinator.lastURL != url {
            // URL变化但歌曲ID没变，也需要更新
            onLog?("URL变化: \(url.lastPathComponent)", .info)
            context.coordinator.lastURL = url
            player.stop()
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
        var lastSongId: Int?
        var lastVocalMode: String = "accompaniment"
    }
}

// MARK: - 播放管理器
class PlayerManager: ObservableObject {
    @Published var currentSong: KTVSong?
    @Published var showIdleScreen = true
    @Published var videoURL: URL?
    @Published var vocalMode: String = "accompaniment"
    @Published var debugLogs: [DebugLogEntry] = []
    @Published var isPlaying: Bool = false
    
    let wsManager = WebSocketManager()
    private var timer: Timer?
    private var host: String = ""
    private var port: Int = 8980
    var vlcPlayer: VLCMediaPlayer?  // VLC播放器引用，直接控制播放/暂停/音轨（strong，确保不被释放）
    
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
    
    // 直接控制VLC播放器播放
    func play() {
        print("PlayerManager.play() 被调用, vlcPlayer是否为nil: \(vlcPlayer == nil)")
        addLog("执行播放, VLC就绪: \(vlcPlayer != nil)", type: .info)
        guard let player = vlcPlayer else {
            addLog("错误: VLC播放器未就绪", type: .error)
            return
        }
        player.play()
        isPlaying = true
        addLog("✅ 播放已执行", type: .info)
    }
    
    // 直接控制VLC播放器暂停
    func pause() {
        print("PlayerManager.pause() 被调用, vlcPlayer是否为nil: \(vlcPlayer == nil)")
        addLog("执行暂停, VLC就绪: \(vlcPlayer != nil)", type: .info)
        guard let player = vlcPlayer else {
            addLog("错误: VLC播放器未就绪", type: .error)
            return
        }
        player.pause()
        isPlaying = false
        addLog("✅ 暂停已执行", type: .info)
    }
    
    // 切换播放/暂停
    func togglePlayback() {
        if vlcPlayer?.isPlaying == true {
            pause()
        } else {
            play()
        }
    }
    
    // 直接切换音轨（原唱/伴唱）- 尝试多种VLC API
    func switchVocalMode(_ mode: String) {
        vocalMode = mode
        print("========== switchVocalMode被调用（测试1：仅读取操作）==========")
        print("mode: \(mode)")
        addLog("🔊 [测试1] switchVocalMode被调用: \(mode) (仅读取，无写入)", type: .info)
        
        guard let player = vlcPlayer else {
            addLog("❌ VLC播放器未就绪", type: .error)
            return
        }
        
        let targetIndex: Int32 = (mode == "original") ? 1 : 2
        addLog("🎯 目标音轨索引: \(targetIndex)", type: .info)
        
        // 测试读取操作1：audioTrackNames
        do {
            if let trackNames = player.value(forKey: "audioTrackNames") as? [String] {
                addLog("📋 可用音轨: \(trackNames)", type: .info)
                print("可用音轨: \(trackNames)")
            }
        } catch {
            addLog("❌ 读取audioTrackNames失败: \(error.localizedDescription)", type: .error)
        }
        
        // 测试读取操作2：audioTrackIndex
        do {
            if let currentTrack = player.value(forKey: "audioTrackIndex") as? Int32 {
                addLog("📊 当前音轨索引: \(currentTrack)", type: .info)
                print("当前音轨索引: \(currentTrack)")
            }
        } catch {
            addLog("❌ 读取audioTrackIndex失败: \(error.localizedDescription)", type: .error)
        }
        
        // 测试读取操作3：audio对象
        do {
            if let audio = player.value(forKey: "audio") as? NSObject {
                addLog("📊 audio对象获取成功", type: .info)
            }
        } catch {
            addLog("❌ 读取audio对象失败: \(error.localizedDescription)", type: .error)
        }
        
        // 暂时不执行写入操作，防止闪退
        addLog("🔇 [测试1] 写入操作已禁用，仅测试读取", type: .warning)
    }
    
    // 保留原方法的占位，后续逐步恢复
    func switchVocalModeOriginal(_ mode: String) {
        vocalMode = mode
        print("========== switchVocalMode被调用 ==========")
        print("mode: \(mode)")
        addLog("🔊 switchVocalMode被调用: \(mode)", type: .info)
        
        guard let player = vlcPlayer else {
            addLog("❌ VLC播放器未就绪", type: .error)
            return
        }
        
        // 关键修复：可用音轨是 ["Disable", "Track 1", "Track 2"]
        // 索引0=Disable(禁用), 索引1=Track 1, 索引2=Track 2
        // 所以原唱和伴唱应该用索引1和2，而不是0和1！
        let targetIndex: Int32 = (mode == "original") ? 1 : 2
        addLog("🎯 目标音轨索引: \(targetIndex) (0=Disable,1=Track1,2=Track2)", type: .info)
        
        // 打印可用音轨
        if let trackNames = player.value(forKey: "audioTrackNames") as? [String] {
            addLog("📋 可用音轨: \(trackNames)", type: .info)
            print("可用音轨: \(trackNames)")
        }
        
        // 打印当前音轨
        if let currentTrack = player.value(forKey: "audioTrackIndex") as? Int32 {
            addLog("📊 当前音轨索引: \(currentTrack)", type: .info)
            print("当前音轨索引: \(currentTrack)")
        }
        
        // 方法1：通过audio对象设置trackNumber（有安全检查）
        if let audio = player.value(forKey: "audio") as? NSObject {
            if audio.responds(to: Selector(("setTrackNumber:"))) {
                audio.setValue(targetIndex, forKey: "trackNumber")
                addLog("✅ 方法1: audio.trackNumber = \(targetIndex)", type: .info)
            } else {
                addLog("⚠️ 方法1: audio没有setTrackNumber方法", type: .warning)
            }
        } else {
            addLog("⚠️ 方法1: 无法获取audio对象", type: .warning)
        }
        
        // 方法2：设置audioTrackIndex（有安全检查）
        if player.responds(to: Selector(("setAudioTrackIndex:"))) {
            player.setValue(targetIndex, forKey: "audioTrackIndex")
            addLog("✅ 方法2: audioTrackIndex = \(targetIndex)", type: .info)
        } else {
            addLog("⚠️ 方法2: player没有setAudioTrackIndex方法", type: .warning)
        }
        
        // 方法3：设置currentAudioTrackIndex（有安全检查）
        if player.responds(to: Selector(("setCurrentAudioTrackIndex:"))) {
            player.setValue(targetIndex, forKey: "currentAudioTrackIndex")
            addLog("✅ 方法3: currentAudioTrackIndex = \(targetIndex)", type: .info)
        } else {
            addLog("⚠️ 方法3: player没有setCurrentAudioTrackIndex方法", type: .warning)
        }
        
        // 延迟验证，如果失败则自动交换索引
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self, let player = self.vlcPlayer else { return }
            if let currentTrack = player.value(forKey: "audioTrackIndex") as? Int32 {
                print("0.8秒后验证 - 当前音轨索引: \(currentTrack), 目标: \(targetIndex)")
                self.addLog("🔍 验证: 当前\(currentTrack)/目标\(targetIndex)", type: .info)
                
                // 如果验证失败，尝试交换音轨索引（可能Track1=伴奏，Track2=原唱）
                if currentTrack != targetIndex {
                    self.addLog("⚠️ 音轨切换未生效，尝试交换索引", type: .warning)
                    let swappedIndex: Int32 = (mode == "original") ? 2 : 1
                    // 尝试所有方法（都有安全检查）
                    if let audio = player.value(forKey: "audio") as? NSObject {
                        if audio.responds(to: Selector(("setTrackNumber:"))) {
                            audio.setValue(swappedIndex, forKey: "trackNumber")
                        }
                    }
                    if player.responds(to: Selector(("setAudioTrackIndex:"))) {
                        player.setValue(swappedIndex, forKey: "audioTrackIndex")
                    }
                    if player.responds(to: Selector(("setCurrentAudioTrackIndex:"))) {
                        player.setValue(swappedIndex, forKey: "currentAudioTrackIndex")
                    }
                    self.addLog("🔄 交换后尝试: \(swappedIndex)", type: .info)
                }
            }
        }
    }
    
    func configure(host: String, port: Int) {
        self.host = host
        self.port = port
        addLog("📋 configure被调用: http://\(host):\(port)", type: .info)
        addLog("设置onVocalChanged回调", type: .info)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.wsManager.connect(host: host, port: port)
        }
        
        wsManager.onVocalChanged = { [weak self] mode in
            print("onVocalChanged回调被调用: \(mode)")
            self?.addLog("📞 onVocalChanged回调: \(mode)", type: .info)
            DispatchQueue.main.async {
                self?.switchVocalMode(mode)
            }
        }
        wsManager.onEffectChanged = { _ in }
        wsManager.onPlaybackControl = { [weak self] command in
            DispatchQueue.main.async {
                print("收到播放控制命令: \(command)")
                self?.addLog("收到播放控制: \(command)", type: .info)
                // 处理多种状态格式：play/playing, pause/paused, toggle
                if command == "play" || command == "playing" {
                    self?.play()
                } else if command == "pause" || command == "paused" {
                    self?.pause()
                } else if command == "toggle" {
                    self?.togglePlayback()
                } else if command == "idle" {
                    // 空闲状态，停止播放
                    self?.currentSong = nil
                    self?.videoURL = nil
                    self?.showIdleScreen = true
                }
            }
        }
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

// MARK: - 氛围效果覆盖层（鼓掌中间大图标，喝彩满屏动画刷过）
struct EffectOverlayView: View {
    let effect: KTVEffect
    let show: Bool
    let count: Int
    
    @State private var animate = false
    @State private var pulse = false
    @State private var particles: [Particle] = []
    
    struct Particle: Identifiable {
        let id = UUID()
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let opacity: Double
        let delay: Double
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if show {
                    // 根据效果类型显示不同的动画
                    switch effect {
                    case .applause, .clap:
                        // 鼓掌：中间大图标显示
                        VStack(spacing: 20) {
                            Spacer()
                            
                            Image(systemName: effect.iconName)
                                .font(.system(size: 120))
                                .foregroundColor(effect.color)
                                .shadow(color: effect.color, radius: 20)
                                .scaleEffect(pulse ? 1.3 : 0.9)
                                .rotationEffect(.degrees(animate ? 15 : -15))
                                .animation(
                                    Animation.easeInOut(duration: 0.5)
                                        .repeatForever(autoreverses: true),
                                    value: animate
                                )
                                .animation(
                                    Animation.spring(response: 0.4, dampingFraction: 0.4)
                                        .repeatForever(autoreverses: true),
                                    value: pulse
                                )
                            
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
                        .background(Color.black.opacity(0.3))
                        .transition(.opacity)
                        
                    case .cheer:
                        // 喝彩：满屏动画刷过（粒子效果）
                        ZStack {
                            // 半透明背景
                            Color.black.opacity(0.2)
                            
                            // 粒子效果 - 从左到右刷过
                            ForEach(particles) { particle in
                                Image(systemName: "star.fill")
                                    .font(.system(size: particle.size))
                                    .foregroundColor(effect.color)
                                    .opacity(particle.opacity)
                                    .position(x: particle.x, y: particle.y)
                                    .offset(x: animate ? geometry.size.width + 100 : -100)
                                    .animation(
                                        Animation.linear(duration: 1.5)
                                            .delay(particle.delay)
                                            .repeatForever(autoreverses: false),
                                        value: animate
                                    )
                            }
                            
                            // 中间文字
                            VStack(spacing: 15) {
                                Text("🎉")
                                    .font(.system(size: 80))
                                
                                Text(effect.displayName)
                                    .font(.system(size: 48, weight: .bold))
                                    .foregroundColor(.white)
                                    .shadow(color: effect.color, radius: 10)
                                    .shadow(color: .black, radius: 3)
                                
                                Text("第 \(count) 次")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                        .transition(.opacity)
                        
                    case .boo, .hiss:
                        // 倒彩：中间显示，红色调
                        VStack(spacing: 20) {
                            Spacer()
                            
                            Image(systemName: effect.iconName)
                                .font(.system(size: 100))
                                .foregroundColor(.red)
                                .shadow(color: .red, radius: 15)
                                .scaleEffect(pulse ? 1.2 : 0.9)
                                .animation(
                                    Animation.spring(response: 0.4, dampingFraction: 0.4)
                                        .repeatForever(autoreverses: true),
                                    value: pulse
                                )
                            
                            Text(effect.displayName)
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.white)
                                .shadow(color: .red, radius: 8)
                            
                            Text("第 \(count) 次")
                                .font(.system(size: 18))
                                .foregroundColor(.white.opacity(0.8))
                            
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.4))
                        .transition(.opacity)
                        
                    case .cheers, .toast:
                        // 干杯：中间显示，橙色调，碰杯动画
                        VStack(spacing: 20) {
                            Spacer()
                            
                            HStack(spacing: -20) {
                                Image(systemName: "wineglass.fill")
                                    .font(.system(size: 80))
                                    .foregroundColor(.orange)
                                    .rotationEffect(.degrees(animate ? -20 : -10))
                                    .offset(x: animate ? 10 : 0)
                                
                                Image(systemName: "wineglass.fill")
                                    .font(.system(size: 80))
                                    .foregroundColor(.yellow)
                                    .rotationEffect(.degrees(animate ? 20 : 10))
                                    .offset(x: animate ? -10 : 0)
                            }
                            .animation(
                                Animation.easeInOut(duration: 0.5)
                                    .repeatForever(autoreverses: true),
                                value: animate
                            )
                            .shadow(color: .orange, radius: 15)
                            
                            Text(effect.displayName)
                                .font(.system(size: 44, weight: .bold))
                                .foregroundColor(.white)
                                .shadow(color: .orange, radius: 10)
                            
                            Text("第 \(count) 次")
                                .font(.system(size: 18))
                                .foregroundColor(.white.opacity(0.8))
                            
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.35))
                        .transition(.opacity)
                        
                    case .unknown:
                        // 未知：右上角小提示
                        VStack {
                            HStack {
                                Spacer()
                                HStack(spacing: 10) {
                                    Image(systemName: effect.iconName)
                                        .font(.system(size: 28))
                                        .foregroundColor(.white)
                                    Text(effect.displayName)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(15)
                                .padding(.trailing, 20)
                                .padding(.top, 60)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onAppear {
                animate = true
                pulse = true
                createParticles(in: geometry.size)
            }
            .onDisappear {
                animate = false
                pulse = false
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.3), value: show)
    }
    
    private func createParticles(in size: CGSize) {
        particles = (0..<20).map { i in
            Particle(
                x: CGFloat.random(in: -50...size.width),
                y: CGFloat.random(in: 0...size.height),
                size: CGFloat.random(in: 15...40),
                opacity: Double.random(in: 0.4...0.9),
                delay: Double(i) * 0.08
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
                    
                    Text("WebSocket日志:")
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
                    
                    Divider()
                        .background(Color.orange)
                        .padding(.vertical, 8)
                    
                    Text("===== 播放器日志 =====")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.orange)
                    
                    ForEach(playerManager.debugLogs) { log in
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
                vocalMode: playerManager.vocalMode,
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
                },
                onPlayerReady: { player in
                    // 将VLC播放器引用传递给PlayerManager，用于直接控制播放/暂停/音轨
                    print("PlayerView.onPlayerReady - 被调用")
                    self.playerManager.vlcPlayer = player
                    print("PlayerView.onPlayerReady - 已设置playerManager.vlcPlayer")
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
            
            // 原唱/伴唱状态提示（顶部居中，明显显示）
            VStack {
                HStack {
                    Spacer()
                    Text(playerManager.vocalMode == "original" ? "🎤 原唱" : "🎵 伴唱")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(playerManager.vocalMode == "original" ? Color.orange.opacity(0.8) : Color.blue.opacity(0.8))
                        )
                        .padding(.top, 50)
                    Spacer()
                }
                Spacer()
            }
            .allowsHitTesting(false)
            .zIndex(50)
            .animation(.easeInOut(duration: 0.3), value: playerManager.vocalMode)
            
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
