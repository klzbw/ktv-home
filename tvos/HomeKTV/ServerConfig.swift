import Foundation
import SwiftUI

class ServerConfig: ObservableObject {
    static let shared = ServerConfig()

    @Published var serverAddress: String {
        didSet {
            UserDefaults.standard.set(serverAddress, forKey: "serverAddress")
        }
    }

    var serverURL: URL? {
        guard !serverAddress.isEmpty else { return nil }
        var address = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.hasPrefix("http://") && !address.hasPrefix("https://") {
            address = "http://" + address
        }
        if !address.hasSuffix("/m") && !address.hasSuffix("/m/") {
            address = address + "/m"
        }
        return URL(string: address)
    }

    private init() {
        self.serverAddress = UserDefaults.standard.string(forKey: "serverAddress") ?? ""
    }
}
