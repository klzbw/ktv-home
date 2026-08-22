import SwiftUI

struct SettingsView: View {
    @StateObject private var config = ServerConfig.shared
    @Binding var showSettings: Bool
    @State private var address: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("设置")
                    .font(.largeTitle)
                    .bold()
                    .padding(.top, 40)

                VStack(alignment: .leading, spacing: 8) {
                    Text("服务端地址")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    TextField("例如: 192.168.1.100:8080", text: $address)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($isFocused)
                        .onAppear {
                            address = config.serverAddress
                        }
                        .padding(.bottom, 8)

                    Text("输入KTV服务端的IP地址和端口，应用会自动加载 /m 点歌页面")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)

                VStack(spacing: 12) {
                    Button(action: {
                        config.serverAddress = address
                        isFocused = false
                        showSettings = false
                    }) {
                        HStack {
                            Spacer()
                            Text("保存并连接")
                                .bold()
                            Spacer()
                        }
                        .padding()
                        .background(address.isEmpty ? Color.gray : Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(address.isEmpty)

                    Button(action: {
                        isFocused = false
                        showSettings = false
                    }) {
                        HStack {
                            Spacer()
                            Text("取消")
                            Spacer()
                        }
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                    }

                    Button(role: .destructive, action: {
                        config.serverAddress = ""
                        address = ""
                        isFocused = false
                        showSettings = false
                    }) {
                        HStack {
                            Spacer()
                            Text("清除配置")
                            Spacer()
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .background(Color(UIColor.systemBackground))
        .onTapGesture {
            isFocused = false
        }
    }
}
