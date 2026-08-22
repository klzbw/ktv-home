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
    let volume: Int?
    let muted: Bool?
}

// MARK: - WebSocket管理器
class WebSocketManager: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var vocalMode: String = "accompaniment"
    @Published var volume: Int = 100
    @Published var isMuted: Bool = false
    
    private var webSocket: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var host: String = ""
    private var port: Int = 8980
    
    var onVocalChanged: ((String) -> Void)?
    var onVolumeChanged: ((Int) -> Void)?
    var onMuteChanged: ((Bool) -> Void)?
    var onEffectChanged: ((String) -> Void)?
    var onPlaybackRestarted: (() -> Void)?
    
    func connect(host: String, port: Int) {
        self.host = host
        self.port = port
        
        guard let url = URL(string: "ws://\(host):\(port)/ws") else { return }
        
        let session = URLSession(configuration: .default)
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
                self?.isConnected = true
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
            case "effect":
                if let effect = payload?["effect"] as? String {
                    self?.onEffectChanged?(effect)
                }
            case "playback_restarted":
                self?.onPlaybackRestarted?()
            default:
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
            webSocket?.send(.string(text)) { _ in }
        }
    }
}

// MARK: - VLC播放器视图
struct VLCVideoView: UIViewRepresentable {
    let url: URL?
    let vocalMode: String
    let volume: Int
    let isMuted: Bool
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .black
        
        let player = VLCMediaPlayer()
        player.drawable = containerView
        player.audio?.volume = Int32(volume)
        player.audio?.muted = isMuted
        
        if let url = url {
            let media = VLCMedia(url: url)
            player.media = media
            player.play()
            
            // 延迟设置音轨
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.applyVocalMode(player: player, mode: vocalMode)
            }
        }
        
        context.coordinator.player = player
        context.coordinator.lastURL = url
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        guard let player = context.coordinator.player else { return }
        
        // URL变化时重新播放
        if let url = url, context.coordinator.lastURL != url {
            context.coordinator.lastURL = url
            let media = VLCMedia(url: url)
            player.media = media
            player.play()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.applyVocalMode(player: player, mode: vocalMode)
            }
        }
        
        // 音量变化
        if context.coordinator.lastVolume != volume {
            context.coordinator.lastVolume = volume
            player.audio?.volume = Int32(volume)
        }
        
        // 静音变化
        if context.coordinator.lastMuted != isMuted {
            context.coordinator.lastMuted = isMuted
            player.audio?.muted = isMuted
        }
        
        // 原唱/伴唱变化
        if context.coordinator.lastVocalMode != vocalMode {
            context.coordinator.lastVocalMode = vocalMode
            applyVocalMode(player: player, mode: vocalMode)
        }
    }
    
    private func applyVocalMode(player: VLCMediaPlayer, mode: String) {
        // KTV mkv通常有2个音轨：0=伴奏，1=原唱
        if mode == "original" {
            player.audioTrackIndex = 1
        } else {
            player.audioTrackIndex = 0
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var player: VLCMediaPlayer?
        var lastURL: URL?
        var lastVocalMode: String = "accompaniment"
        var lastVolume: Int = 100
        var lastMuted: Bool = false
    }
}

// MARK: - 播放管理器
class PlayerManager: ObservableObject {
    @Published var currentSong: KTVSong?
    @Published var showIdleScreen = true
    @Published var videoURL: URL?
    @Published var vocalMode: String = "accompaniment"
    @Published var volume: Int = 100
    @Published var isMuted: Bool = false
    
    let wsManager = WebSocketManager()
    private var timer: Timer?
    private var host: String = ""
    private var port: Int = 8980
    
    func configure(host: String, port: Int) {
        self.host = host
        self.port = port
        
        // 连接WebSocket
        wsManager.connect(host: host, port: port)
        
        // WebSocket回调
        wsManager.onVocalChanged = { [weak self] mode in
            self?.vocalMode = mode
        }
        wsManager.onVolumeChanged = { [weak self] vol in
            self?.volume = vol
        }
        wsManager.onMuteChanged = { [weak self] muted in
            self?.isMuted = muted
        }
        wsManager.onPlaybackRestarted = { [weak self] in
            if let song = self?.currentSong {
                self?.videoURL = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
                    // 初始化状态
                    if let mode = queue.vocalMode, self?.vocalMode == "accompaniment" {
                        self?.vocalMode = mode
                    }
                    if let vol = queue.volume, self?.volume == 100 {
                        self?.volume = vol
                    }
                    if let muted = queue.muted, self?.isMuted == false {
                        self?.isMuted = muted
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
                
                // WebSocket连接状态
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
            VLCVideoView(
                url: playerManager.videoURL,
                vocalMode: playerManager.vocalMode,
                volume: playerManager.volume,
                isMuted: playerManager.isMuted
            )
            .ignoresSafeArea()
            
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
