import Foundation

class ServerConfig: ObservableObject {
    static let shared = ServerConfig()

    @Published var serverAddress: String {
        didSet {
            UserDefaults.standard.set(serverAddress, forKey: "serverAddress")
        }
    }

    init() {
        self.serverAddress = UserDefaults.standard.string(forKey: "serverAddress") ?? ""
    }

    var serverURL: URL? {
        guard !serverAddress.isEmpty else { return nil }
        var address = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.hasPrefix("http://") && !address.hasPrefix("https://") {
            address = "http://" + address
        }
        if address.hasSuffix("/") {
            address = String(address.dropLast())
        }
        return URL(string: address + "/m")
    }
}
