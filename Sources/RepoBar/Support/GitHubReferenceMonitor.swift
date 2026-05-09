import AppKit
import RepoBarCore

@MainActor
final class GitHubReferenceMonitor {
    private let minimumBareDigits: Int
    private let pasteboard: NSPasteboard
    private let onPasteboardWithoutReference: () async -> Void
    private let onReferences: ([GitHubReferenceQuery], String) async -> Void
    private var pasteboardPoller: PasteboardTextPoller?
    private var isRunning = false

    init(
        minimumBareDigits: Int = AppLimits.GitHubReferenceMonitor.minimumBareDigits,
        pasteboard: NSPasteboard = .general,
        onPasteboardWithoutReference: @escaping () async -> Void = {},
        onReferences: @escaping ([GitHubReferenceQuery], String) async -> Void
    ) {
        self.minimumBareDigits = minimumBareDigits
        self.pasteboard = pasteboard
        self.onPasteboardWithoutReference = onPasteboardWithoutReference
        self.onReferences = onReferences
    }

    func start() {
        guard self.isRunning == false else { return }

        if self.pasteboardPoller == nil {
            self.startPasteboardTimer()
        }
        self.isRunning = true
    }

    func stop() {
        self.pasteboardPoller?.stop()
        self.pasteboardPoller = nil
        self.isRunning = false
    }

    private func startPasteboardTimer() {
        let poller = PasteboardTextPoller(pasteboard: self.pasteboard) { [weak self] text in
            Task { @MainActor in
                self?.handlePasteboardText(text)
            }
        }
        poller.start()
        self.pasteboardPoller = poller
    }

    private func handlePasteboardText(_ text: String) {
        let queries = Self.queries(from: text, minimumBareDigits: self.minimumBareDigits)
        guard queries.isEmpty == false else {
            Task { await self.onPasteboardWithoutReference() }
            return
        }

        Task { await self.onReferences(queries, text) }
    }

    static func query(from rawText: String, minimumBareDigits: Int = AppLimits.GitHubReferenceMonitor.minimumBareDigits) -> GitHubReferenceQuery? {
        GitHubReferenceTranslator.query(from: rawText, minimumBareDigits: minimumBareDigits)
    }

    static func queries(from rawText: String, minimumBareDigits: Int = AppLimits.GitHubReferenceMonitor.minimumBareDigits) -> [GitHubReferenceQuery] {
        GitHubReferenceTranslator.queries(from: rawText, minimumBareDigits: minimumBareDigits)
    }
}

private final class PasteboardTextPoller: @unchecked Sendable {
    private let pasteboard: NSPasteboard
    private let queue = DispatchQueue(label: "com.steipete.repobar.github-reference-pasteboard", qos: .utility)
    private let onText: @Sendable (String) -> Void
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int
    private let pollInterval: DispatchTimeInterval = .seconds(2)
    private let pollLeeway: DispatchTimeInterval = .milliseconds(500)
    private let graceDelay: DispatchTimeInterval = .milliseconds(100)

    init(pasteboard: NSPasteboard, onText: @escaping @Sendable (String) -> Void) {
        self.pasteboard = pasteboard
        self.onText = onText
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        self.queue.async { [weak self] in
            guard let self, self.timer == nil else { return }

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + self.pollInterval, repeating: self.pollInterval, leeway: self.pollLeeway)
            timer.setEventHandler { [weak self] in
                self?.tick()
            }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        self.queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    private func tick() {
        let changeCount = self.pasteboard.changeCount
        guard changeCount != self.lastChangeCount else { return }

        self.lastChangeCount = changeCount
        self.queue.asyncAfter(deadline: .now() + self.graceDelay) { [weak self] in
            guard let self else { return }
            guard changeCount == self.pasteboard.changeCount else { return }
            guard let text = self.readPasteboardText() else { return }

            self.onText(text)
        }
    }

    private func readPasteboardText() -> String? {
        if let direct = self.pasteboard.string(forType: .string) {
            return direct
        }

        let preferredTypes: [NSPasteboard.PasteboardType] = [
            .init("public.utf8-plain-text"),
            .init("public.utf16-external-plain-text"),
            .init("public.text")
        ]
        for item in self.pasteboard.pasteboardItems ?? [] {
            for type in preferredTypes {
                if let value = item.string(forType: type) {
                    return value
                }
            }
        }
        return nil
    }
}
