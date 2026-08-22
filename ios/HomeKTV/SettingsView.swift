import SwiftUI

struct SettingsView: View {
    @StateObject private var config = ServerConfig.shared
    @Binding var showSettings: Bool
    @State private var address: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("服务端配置")) {
                    TextField("例如: 192.168.1.100:8080", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onAppear {
                            address = config.serverAddress
                        }
                }

                Section {
                    Button("保存并连接") {
                        config.serverAddress = address
                        showSettings = false
                    }
                    .disabled(address.isEmpty)

                    Button("清除配置", role: .destructive) {
                        config.serverAddress = ""
                        address = ""
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        showSettings = false
                    }
                }
            }
        }
    }
}
