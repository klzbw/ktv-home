import SwiftUI

struct HomeView: View {
    @StateObject private var deviceManager = DeviceManager()
    @State private var showManualInput = false
    @State private var manualHost = ""
    @State private var manualPort = "8980"

    var body: some View {
        NavigationView {
            if deviceManager.connectedDevice != nil {
                PlayerView(deviceManager: deviceManager)
                    .navigationBarItems(leading: Button("断开") {
                        deviceManager.disconnect()
                    })
            } else {
                deviceListView
                    .navigationTitle("家庭KTV")
            }
        }
        .sheet(isPresented: $showManualInput) {
            ManualInputView(showManualInput: $showManualInput, manualHost: $manualHost, manualPort: $manualPort, deviceManager: deviceManager)
        }
    }

    private var deviceListView: some View {
        VStack(spacing: 12) {
            Button(action: {
                deviceManager.scanForDevices()
            }) {
                HStack {
                    Image(systemName: deviceManager.isScanning ? "arrow.triangle.2.circlepath" : "dot.radiowaves.left.and.right")
                    Text(deviceManager.isScanning ? "正在扫描..." : "扫描局域网设备")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(deviceManager.isScanning)
            .padding(.horizontal)
            .padding(.top)

            Button(action: {
                showManualInput = true
            }) {
                HStack {
                    Image(systemName: "keyboard")
                    Text("手动输入地址")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.2))
                .foregroundColor(.primary)
                .cornerRadius(12)
            }
            .padding(.horizontal)

            List {
                if deviceManager.devices.isEmpty {
                    Text("暂无设备，点击上方按钮扫描或手动输入")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(deviceManager.devices) { device in
                        Button(action: {
                            deviceManager.connectToDevice(device)
                        }) {
                            HStack {
                                Image(systemName: "tv")
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading) {
                                    Text(device.name)
                                    Text("\(device.host):\(device.port)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ManualInputView: View {
    @Binding var showManualInput: Bool
    @Binding var manualHost: String
    @Binding var manualPort: String
    @ObservedObject var deviceManager: DeviceManager

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("服务端地址")) {
                    HStack {
                        Text("地址")
                        TextField("192.168.1.100", text: $manualHost)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    HStack {
                        Text("端口")
                        TextField("8980", text: $manualPort)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                }

                Section {
                    Button("连接") {
                        if !manualHost.isEmpty, let port = Int(manualPort) {
                            let device = KTVDevice(name: manualHost, host: manualHost, port: port)
                            deviceManager.connectToDevice(device)
                            showManualInput = false
                            manualHost = ""
                            manualPort = "8980"
                        }
                    }
                    .disabled(manualHost.isEmpty)
                }
            }
            .navigationTitle("手动输入")
            .navigationBarItems(trailing: Button("取消") {
                showManualInput = false
            })
        }
    }
}
