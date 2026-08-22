import SwiftUI
import WebKit

struct PlayerView: View {
    @ObservedObject var deviceManager: DeviceManager
    @State private var selectedPath = "/m/lyric"
    @State private var showPathSelection = false

    let paths = [
        (name: "歌词播放 (TV端)", path: "/m/lyric"),
        (name: "遥控器", path: "/m/remote"),
        (name: "播放队列", path: "/m/queue"),
        (name: "点歌端", path: "/m"),
        (name: "首页", path: "/m/home"),
        (name: "搜索", path: "/m/search"),
        (name: "浏览", path: "/m/browse"),
        (name: "最近播放", path: "/m/recent"),
        (name: "我的收藏", path: "/m/favorites"),
        (name: "管理后台", path: "/m/admin"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 路径选择栏
            HStack {
                Menu {
                    ForEach(paths, id: \.path) { item in
                        Button(item.name) {
                            selectedPath = item.path
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "list.bullet")
                        Text(paths.first(where: { $0.path == selectedPath })?.name ?? selectedPath)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }

                Spacer()

                Button(action: {
                    showPathSelection = true
                }) {
                    Image(systemName: "globe")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(UIColor.systemBackground))

            // WebView
            if let device = deviceManager.connectedDevice {
                WebView(url: URL(string: "http://\(device.host):\(device.port)\(selectedPath)")!)
                    .edgesIgnoringSafeArea(.all)
            } else {
                Text("未连接设备")
            }
        }
        .sheet(isPresented: $showPathSelection) {
            PathSelectionView(selectedPath: $selectedPath, paths: paths)
        }
    }
}

struct PathSelectionView: View {
    @Binding var selectedPath: String
    let paths: [(name: String, path: String)]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List(paths, id: \.path) { item in
                Button(action: {
                    selectedPath = item.path
                    dismiss()
                }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.name)
                                .font(.headline)
                            Text(item.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if selectedPath == item.path {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("选择页面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black

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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("WebView loaded: \(webView.url?.absoluteString ?? "unknown")")
        }
    }
}
