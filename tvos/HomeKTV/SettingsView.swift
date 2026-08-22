import SwiftUI

struct SettingsView: View {
    @StateObject private var config = ServerConfig.shared
    @Environment(\.dismiss) private var dismiss
    @State private var address: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("服务端配置") {
                    TextField("例如: 192.168.1.100:8080", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onAppear {
                            address = config.serverAddress
                        }

                    Button("保存并连接") {
                        config.serverAddress = address
                        dismiss()
                    }
                    .disabled(address.isEmpty)
                }

                Section("关于") {
                    LabeledContent("应用名称", value: "家庭KTV")
                    LabeledContent("版本", value: "1.0.0")
                    LabeledContent("平台", value: "tvOS")
                }

                Section {
                    Button(role: .destructive) {
                        config.serverAddress = ""
                        dismiss()
                    } label: {
                        Label("清除配置", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}
