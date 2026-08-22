import SwiftUI
import WebKit

struct ContentView: View {
    @StateObject private var config = ServerConfig.shared
    @State private var showSettings = false

    var body: some View {
        Group {
            if let url = config.serverURL {
                WebView(url: url)
                    .edgesIgnoringSafeArea(.all)
            } else {
                SetupView(showSettings: $showSettings)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(showSettings: $showSettings)
        }
        .onLongPressGesture(minimumDuration: 1.5) {
            showSettings = true
        }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.bounces = false

        let request = URLRequest(url: url)
        webView.load(request)

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url {
            uiView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("WebView navigation failed: \(error.localizedDescription)")
        }
    }
}

struct SetupView: View {
    @Binding var showSettings: Bool

    var body: some View {
        VStack(spacing: 40) {
            Image(systemName: "music.note.tv")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)

            Text("家庭KTV")
                .font(.largeTitle)
                .bold()

            Text("请配置服务端地址")
                .font(.title3)
                .foregroundColor(.secondary)

            Button(action: { showSettings = true }) {
                HStack {
                    Image(systemName: "gear")
                    Text("配置服务端")
                }
                .font(.title2)
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(60)
    }
}
