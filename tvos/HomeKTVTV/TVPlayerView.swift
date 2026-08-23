import SwiftUI
import TVVLCKit

// MARK: - tvOS播放视图
struct TVPlayerView: View {
    @ObservedObject var playerManager: PlayerManager
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // VLC播放器
            VLCVideoView(
                url: playerManager.videoURL,
                songId: playerManager.currentSong?.id,
                vocalMode: playerManager.vocalMode,
                onLog: { _, _ in },
                onPlayerReady: { player in
                    playerManager.vlcPlayer = player
                },
                onPlaying: {
                    DispatchQueue.main.async {
                        playerManager.isPlaying = true
                        playerManager.startProgressReporting()
                    }
                },
                onEnded: {
                    DispatchQueue.main.async {
                        playerManager.isPlaying = false
                        playerManager.stopProgressReporting()
                        playerManager.wsManager.sendFinished()
                    }
                },
                onError: {
                    DispatchQueue.main.async {
                        playerManager.isPlaying = false
                        playerManager.stopProgressReporting()
                    }
                }
            )
            .ignoresSafeArea()
            
            // 等待扫码页面
            if playerManager.showIdleScreen {
                TVIdleView(wsManager: playerManager.wsManager)
            }
            
            // 氛围效果
            if let effect = playerManager.wsManager.currentEffect {
                EffectOverlayView(
                    effect: effect,
                    show: playerManager.wsManager.showEffect,
                    count: playerManager.wsManager.effectCount
                )
                .zIndex(100)
            }
        }
    }
}

// MARK: - tvOS等待页面（显示连接地址）
struct TVIdleView: View {
    @ObservedObject var wsManager: WebSocketManager
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "qrcode")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.6))
            
            Text("等待点歌")
                .font(.system(size: 36, weight: .medium))
                .foregroundColor(.white)
            
            Circle()
                .fill(wsManager.isConnected ? Color.green : Color.red)
                .frame(width: 12, height: 12)
            
            Text(wsManager.isConnected ? "遥控已连接" : "等待遥控连接...")
                .font(.title3)
                .foregroundColor(.white.opacity(0.7))
        }
    }
}
