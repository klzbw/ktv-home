import Foundation
import Network

struct KTVDevice: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let host: String
    let port: Int
    var isHistory: Bool

    init(name: String, host: String, port: Int, isHistory: Bool = false) {
        self.id = UUID()
        self.name = name
        self.host = host
        self.port = port
        self.isHistory = isHistory
    }
}

class DeviceManager: ObservableObject {
    @Published var devices: [KTVDevice] = []
    @Published var isScanning = false
    @Published var connectedDevice: KTVDevice?

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
        var device = KTVDevice(name: name, host: host, port: port, isHistory: true)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.isScanning = false
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
