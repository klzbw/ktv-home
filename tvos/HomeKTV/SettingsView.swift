import SwiftUI

struct SettingsView: View {
    @StateObject private var config = ServerConfig.shared
    @Binding var showSettings: Bool
    @State private var address: String = ""

    var body: some View {
        VStack(spacing: 30) {
            Text("设置")
                .font(.largeTitle)
                .bold()
                .padding(.top, 40)

            Form {
                Section(header: Text("服务端配置")) {
                    TextField("例如: 192.168.1.100:8080", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onAppear {
                            address = config.serverAddress
                        }
                }

                Section {
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
                    }
                    .disabled(address.isEmpty)

                    Button(action: {
                        showSettings = false
                    }) {
                        HStack {
                            Spacer()
                            Text("取消")
                            Spacer()
                        }
                    }

                    Button(role: .destructive, action: {
                        config.serverAddress = ""
                        showSettings = false
                    }) {
                        HStack {
                            Spacer()
                            Text("清除配置")
                            Spacer()
                        }
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .background(Color(UIColor.systemBackground))
    }
}
