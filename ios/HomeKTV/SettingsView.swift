import SwiftUI

struct SettingsView: View {
    @StateObject private var config = ServerConfig.shared
    @Binding var showSettings: Bool
    @State private var address: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // 顶部栏：标题 + 关闭按钮
            HStack {
                Text("设置")
                    .font(.headline)
                    .bold()
                Spacer()
                Button(action: {
                    showSettings = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))

            // 内容区域
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 服务端地址输入
                    VStack(alignment: .leading, spacing: 8) {
                        Text("服务端地址")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        TextField("例如: 192.168.1.100:8080", text: $address)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .onAppear {
                                address = config.serverAddress
                            }

                        Text("输入KTV服务端的IP地址和端口，应用会自动加载 /m 点歌页面")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)

                    // 按钮区域
                    VStack(spacing: 12) {
                        Button(action: {
                            config.serverAddress = address
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

                        Button(role: .destructive, action: {
                            config.serverAddress = ""
                            address = ""
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
                    .padding(.horizontal)

                    Spacer()
                }
            }
        }
        .background(Color(UIColor.systemBackground))
        .onTapGesture {
            // 点击空白处收起键盘
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}
