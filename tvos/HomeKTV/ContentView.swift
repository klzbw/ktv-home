import SwiftUI
#if canImport(WebKit)
import WebKit
#endif

struct ContentView: View {
    @StateObject private var config = ServerConfig.shared
    @State private var showSettings = false

    var body: some View {
        ZStack {
            if let url = config.serverURL {
                #if canImport(WebKit)
                WebView(url: url)
                    .edgesIgnoringSafeArea(.all)
                #else
                Text("WebKit not available")
                #endif
            } else {
                SetupView(showSettings: $showSettings)
            }
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView()
        }
        .onLongPressGesture(minimumDuration: 1.5) {
            showSettings = true
        }
    }
}

#if canImport(WebKit)
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
#endif

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
                Label("配置服务端", systemImage: "gear")
                    .font(.title2)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(60)
    }
}
