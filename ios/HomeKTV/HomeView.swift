import SwiftUI

struct HomeView: View {
    @StateObject private var deviceManager = DeviceManager()
    @State private var showManualInput = false
    @State private var manualHost = ""
    @State private var manualPort = "8980"

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if deviceManager.connectedDevice != nil {
                    // 已连接，显示播放页面
                    PlayerView(deviceManager: deviceManager)
                } else {
                    // 未连接，显示设备列表
                    deviceListView
                }
            }
            .navigationTitle(deviceManager.connectedDevice != nil ? "" : "家庭KTV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if deviceManager.connectedDevice != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("断开") {
                            deviceManager.disconnect()
                        }
                    }
                }
            }
            .sheet(isPresented: $showManualInput) {
                manualInputView
            }
        }
        .navigationViewStyle(.stack)
    }

    private var deviceListView: some View {
        VStack(spacing: 0) {
            // 扫描按钮
            Button(action: {
                deviceManager.scanForDevices()
            }) {
                HStack {
                    Image(systemName: deviceManager.isScanning ? "arrow.triangle.2.circlepath" : "dot.radiowaves.left.and.right")
                        .font(.title2)
                    Text(deviceManager.isScanning ? "正在扫描..." : "扫描局域网设备")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.top)
            }
            .disabled(deviceManager.isScanning)

            // 手动输入按钮
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
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // 设备列表
            List {
                if deviceManager.devices.isEmpty {
                    Section(header: Text("暂无设备")) {
                        Text("点击上方按钮扫描局域网中的KTV设备，或手动输入地址")
                            .foregroundColor(.secondary)
                            .padding(.vertical)
                    }
                } else {
                    Section(header: Text("可用设备 (\(deviceManager.devices.count))")) {
                        ForEach(deviceManager.devices) { device in
                            DeviceRow(device: device) {
                                deviceManager.connectToDevice(device)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if device.isHistory {
                                    Button(role: .destructive) {
                                        deviceManager.removeDevice(device)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var manualInputView: some View {
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
                            let device = DeviceManager.KTVDevice(name: manualHost, host: manualHost, port: port)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showManualInput = false
                    }
                }
            }
        }
    }
}

struct DeviceRow: View {
    let device: DeviceManager.KTVDevice
    let onConnect: () -> Void

    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 12) {
                Image(systemName: "tv")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.headline)
                    Text("\(device.host):\(device.port)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if device.isHistory {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.secondary)
                }

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
