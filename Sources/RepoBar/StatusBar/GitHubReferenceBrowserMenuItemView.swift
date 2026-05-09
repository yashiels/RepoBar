import AppKit
import RepoBarCore
import WebKit

@MainActor
final class GitHubReferenceBrowserMenuItemView: NSView {
    private enum Metrics {
        static let width: CGFloat = 740
        static let minimumHeight: CGFloat = 680
        static let maximumHeight: CGFloat = 980
        static let visibleScreenHeightMultiplier: CGFloat = 0.62
    }

    private let url: URL
    private let webView: WKWebView?
    private let preferredSize: NSSize
    private var hasLoaded = false

    override var intrinsicContentSize: NSSize {
        self.preferredSize
    }

    init(match: GitHubReferenceMatch) {
        self.url = match.url
        self.preferredSize = Self.preferredSize()
        if Self.shouldCreateWebView {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .default()
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            self.webView = WKWebView(frame: .zero, configuration: configuration)
        } else {
            self.webView = nil
        }
        super.init(frame: NSRect(origin: .zero, size: self.preferredSize))
        self.configureView()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard self.window != nil else { return }

        self.loadIfNeeded()
    }

    func preload() {
        self.loadIfNeeded()
    }

    private func configureView() {
        guard let webView = self.webView else { return }

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.allowsBackForwardNavigationGestures = false
        self.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            webView.topAnchor.constraint(equalTo: self.topAnchor),
            webView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])
    }

    private func loadIfNeeded() {
        guard !self.hasLoaded, let webView = self.webView else { return }

        self.hasLoaded = true
        webView.load(URLRequest(url: self.url))
    }

    private static var shouldCreateWebView: Bool {
        ProcessInfo.processInfo.environment["CI"] != "true" &&
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    private static func preferredSize(screen: NSScreen? = NSScreen.main) -> NSSize {
        let visibleHeight = screen?.visibleFrame.height ?? Metrics.minimumHeight
        let desiredHeight = visibleHeight * Metrics.visibleScreenHeightMultiplier
        let height = min(max(desiredHeight, Metrics.minimumHeight), Metrics.maximumHeight)
        return NSSize(width: Metrics.width, height: height.rounded(.down))
    }
}
