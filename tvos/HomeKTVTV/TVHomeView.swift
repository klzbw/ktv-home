import SwiftUI

struct TVHomeView: View {
    @StateObject private var playerManager = PlayerManager()
    @State private var hostInput: String = ""
    @State private var isConnected = false
    
    var body: some View {
        ZStack {
            if isConnected {
                TVPlayerView(playerManager: playerManager)
            } else {
                connectionView
            }
        }
        .onAppear {
            // 自动连接默认地址
            if let saved = UserDefaults.standard.string(forKey: "ktv_host") {
                hostInput = saved
            }
        }
    }
    
    private var connectionView: some View {
        VStack(spacing: 40) {
            Image(systemName: "tv")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
            
            Text("家庭KTV")
                .font(.system(size: 48, weight: .bold))
            
            Text("请输入服务器地址")
                .font(.title2)
                .foregroundColor(.secondary)
            
            HStack {
                TextField("192.168.1.100", text: $hostInput)
                    .font(.title)
                    .textFieldStyle(.automatic)
                    .frame(width: 400)
                
                Button("连接") {
                    connect()
                }
                .font(.title2)
            }
        }
        .padding()
    }
    
    private func connect() {
        guard !hostInput.isEmpty else { return }
        UserDefaults.standard.set(hostInput, forKey: "ktv_host")
        playerManager.configure(host: hostInput, port: 8980)
        isConnected = true
    }
}
