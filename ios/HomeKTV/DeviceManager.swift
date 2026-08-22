import Foundation
import Network

class DeviceManager: ObservableObject {
    @Published var devices: [KTVDevice] = []
    @Published var isScanning = false
    @Published var connectedDevice: KTVDevice?

    private var browser: NWBrowser?
    private var connection: NWConnection?

    struct KTVDevice: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let host: String
        let port: Int
        var isHistory: Bool = false
    }

    init() {
        loadHistoryDevices()
    }

    func loadHistoryDevices() {
        if let data = UserDefaults.standard.data(forKey: "historyDevices"),
           let decoded = try? JSONDecoder().decode([KTVDevice].self, from: data) {
            devices = decoded
        }
    }

    func saveHistoryDevices() {
        let historyDevices = devices.filter { $0.isHistory }
        if let encoded = try? JSONEncoder().encode(historyDevices) {
            UserDefaults.standard.set(encoded, forKey: "historyDevices")
        }
    }

    func addHistoryDevice(name: String, host: String, port: Int) {
        let device = KTVDevice(name: name, host: host, port: port, isHistory: true)
        if !devices.contains(where: { $0.host == host && $0.port == port }) {
            devices.insert(device, at: 0)
            if devices.count > 10 {
                devices = Array(devices.prefix(10))
            }
            saveHistoryDevices()
        }
    }

    func removeDevice(_ device: KTVDevice) {
        devices.removeAll { $0.id == device.id }
        saveHistoryDevices()
    }

    func scanForDevices() {
        isScanning = true

        // 使用UDP广播发现KTV设备 (端口18888)
        let broadcastHost = "255.255.255.255"
        let port = 18888

        // 创建UDP连接发送广播
        let connection = NWConnection(host: NWEndpoint.Host(broadcastHost),
                                       port: NWEndpoint.Port(rawValue: UInt16(port))!,
                                       using: .udp)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // 发送发现包
                let discoverMessage = "KTV_DISCOVER".data(using: .utf8)
                connection.send(content: discoverMessage, completion: .contentProcessed { error in
                    if let error = error {
                        print("发送发现包失败: \(error)")
                    }
                })

                // 等待响应
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    connection.cancel()
                    self?.isScanning = false
                }
            case .failed(let error):
                print("UDP连接失败: \(error)")
                DispatchQueue.main.async {
                    self?.isScanning = false
                }
            default:
                break
            }
        }

        // 接收响应
        connection.receiveMessage { [weak self] content, _, isComplete, error in
            if let data = content, let response = String(data: data, encoding: .utf8) {
                print("收到设备响应: \(response)")
                // 解析设备信息
                self?.parseDeviceResponse(response)
            }
            if isComplete || error != nil {
                connection.cancel()
            }
        }

        connection.start(queue: .global())
    }

    private func parseDeviceResponse(_ response: String) {
        // 尝试解析JSON或简单格式的设备信息
        if let data = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let name = json["name"] as? String ?? "未知设备"
            let host = json["host"] as? String ?? json["ip"] as? String ?? ""
            let port = json["port"] as? Int ?? 8980

            if !host.isEmpty {
                DispatchQueue.main.async {
                    let device = KTVDevice(name: name, host: host, port: port)
                    if !self.devices.contains(where: { $0.host == host }) {
                        self.devices.insert(device, at: 0)
                    }
                }
            }
        }
    }

    func connectToDevice(_ device: KTVDevice) {
        connectedDevice = device
        addHistoryDevice(name: device.name, host: device.host, port: device.port)
    }

    func disconnect() {
        connectedDevice = nil
    }
}
