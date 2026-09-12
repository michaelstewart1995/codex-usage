import AppKit
import SwiftUI

struct UsageWindow: Decodable, Identifiable {
    let id: String
    let bucket: String
    let label: String
    let used: Double
    let remaining: Double
    let resetsAt: Double?
}
struct UsageSnapshot: Decodable {
    let fetchedAt: Double
    let windows: [UsageWindow]
}
struct ReaderError: Decodable { let error: String }

final class UsageStore: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var error: String?
    @Published var refreshing = false
    @Published var interval: Int = UserDefaults.standard.integer(forKey: "refreshMinutes") == 0 ? 5 : UserDefaults.standard.integer(forKey: "refreshMinutes")
    var onChange: (() -> Void)?
    private var timer: Timer?
    private var process: Process?

    func start() {
        schedule()
        refresh()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
    }
    @objc private func woke() { refresh() }
    func setInterval(_ minutes: Int) {
        interval = minutes
        UserDefaults.standard.set(minutes, forKey: "refreshMinutes")
        schedule()
    }
    private func schedule() {
        timer?.invalidate()
        let next = Timer(timeInterval: Double(interval * 60), repeats: true) { [weak self] _ in self?.refresh() }
        next.tolerance = 5
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }
    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        onChange?()
        guard let script = Bundle.main.path(forResource: "fetch_usage", ofType: "py") else {
            complete(nil, "The bundled usage reader is missing. Rebuild the app.")
            return
        }
        let candidates = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3",
                          "/Library/Frameworks/Python.framework/Versions/Current/bin/python3", "/usr/bin/python3"]
        guard let python = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            complete(nil, "Python 3.9 or newer is required. Install Python, then reopen Codex Usage.")
            return
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: python)
        // Isolated mode ignores PYTHONPATH and user-installed startup customizations.
        task.arguments = ["-I", script]
        // Finder launches with a minimal PATH. The reader also checks app bundle locations.
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        task.environment = environment
        task.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let output = Pipe()
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice
        process = task
        do { try task.run() }
        catch { complete(nil, "Unable to start Python: \(error.localizedDescription)"); return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let data = output.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            let decoder = JSONDecoder()
            let result = task.terminationStatus == 0 ? try? decoder.decode(UsageSnapshot.self, from: data) : nil
            let failure = (try? decoder.decode(ReaderError.self, from: data))?.error
            DispatchQueue.main.async {
                self?.complete(result, result == nil ? (failure ?? "Could not read usage. Check Codex sign-in and try again.") : nil)
            }
        }
    }
    private func complete(_ result: UsageSnapshot?, _ failure: String?) {
        if let result = result { snapshot = result }
        error = failure
        refreshing = false
        process = nil
        onChange?()
    }
}

struct WindowCard: View {
    let window: UsageWindow
    var color: Color { window.used >= 90 ? .red : window.used >= 75 ? .orange : .accentColor }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label).font(.headline)
                Spacer()
                Text("\(Int(window.remaining))% left").font(.system(.title3, design: .rounded).weight(.semibold)).foregroundStyle(color)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule().fill(color)
                        .frame(width: geometry.size.width * min(100, max(0, window.used)) / 100)
                }
            }.frame(height: 7)
                .accessibilityLabel("Usage")
                .accessibilityValue("\(Int(window.used)) percent used")
            HStack {
                Text("\(Int(window.used))% used")
                Spacer()
                if window.bucket != "codex" { Text(window.bucket) }
            }.font(.caption).foregroundStyle(.secondary)
            if let reset = window.resetsAt {
                Text("Resets \(Date(timeIntervalSince1970: reset).formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Reset time unavailable").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct UsagePanel: View {
    @ObservedObject var store: UsageStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex Usage").font(.headline)
                    Text("Your account allowances").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if store.refreshing { ProgressView().controlSize(.small) }
            }
            if let snapshot = store.snapshot {
                if snapshot.windows.count <= 2 {
                    VStack(spacing: 10) {
                        ForEach(snapshot.windows) { window in WindowCard(window: window) }
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(snapshot.windows) { window in WindowCard(window: window) }
                        }
                    }.frame(height: 360)
                }
                Text("Updated \(Date(timeIntervalSince1970: snapshot.fetchedAt).formatted(date: .abbreviated, time: .shortened)) · \(TimeZone.current.abbreviation() ?? "local time")")
                    .font(.caption).foregroundStyle(.secondary)
            } else if store.error == nil {
                Text("Fetching your usage…").foregroundStyle(.secondary).padding(.vertical, 20)
            }
            if let error = store.error {
                VStack(alignment: .leading, spacing: 5) {
                    Label(store.snapshot == nil ? "Usage unavailable" : "Update failed · showing previous values", systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                    Text(error).font(.caption).textSelection(.enabled)
                }.foregroundStyle(.orange)
            }
            Divider()
            HStack {
                Text("Refresh every").foregroundStyle(.secondary)
                Spacer()
                Picker("Refresh every", selection: Binding(get: { store.interval }, set: { store.setInterval($0) })) {
                    ForEach([1, 5, 15, 30, 60], id: \.self) { Text("\($0) min").tag($0) }
                }.labelsHidden().frame(width: 100)
            }.font(.caption)
            HStack {
                Button { store.refresh() } label: { Label("Refresh now", systemImage: "arrow.clockwise") }
                    .disabled(store.refreshing)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(width: 350)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(Color(nsColor: .labelColor))
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// Explicit screen coordinates avoid popover edge selection in a flipped menu-bar view.
func panelFrame(anchor: NSRect, visibleFrame: NSRect, size: NSSize) -> NSRect {
    let bounds = visibleFrame.insetBy(dx: 8, dy: 8)
    let width = min(size.width, bounds.width)
    let height = min(size.height, bounds.height)
    return NSRect(x: min(max(anchor.midX - width / 2, bounds.minX), bounds.maxX - width),
                  y: max(bounds.minY, min(anchor.minY - 8, bounds.maxY) - height),
                  width: width, height: height)
}

final class UsageWindowPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore()
    var statusItem: NSStatusItem!
    let panel = UsageWindowPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
    var host: NSHostingView<UsagePanel>!
    var outsideClick: Any?
    var localClick: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(toggle)
        }
        host = NSHostingView(rootView: UsagePanel(store: store))
        panel.contentView = host
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.backgroundColor = .windowBackgroundColor
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.panel.orderOut(nil)
        }
        localClick = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self = self, event.window !== self.panel && event.window !== self.statusItem.button?.window {
                self.panel.orderOut(nil)
            }
            return event
        }
        store.onChange = { [weak self] in
            self?.updateTitle()
            DispatchQueue.main.async { if self?.panel.isVisible == true { self?.positionPanel() } }
        }
        store.start()
    }
    func updateTitle() {
        guard let button = statusItem.button else { return }
        let windows = store.snapshot?.windows ?? []
        let rows = windows.prefix(2).map { "\($0.label)  \(Int($0.remaining))%" }
        let lines = rows.isEmpty ? ["Codex", "Updating…"] : rows
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let strings = lines.map { NSAttributedString(string: $0, attributes: attributes) }
        let textWidth = ceil(strings.map { $0.size().width }.max() ?? 60)
        let warningWidth: CGFloat = store.error == nil ? 0 : 13
        let size = NSSize(width: textWidth + warningWidth, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            for (index, string) in strings.enumerated() {
                let rowCenter: CGFloat = index == 0 ? 16.5 : 5.5
                string.draw(at: NSPoint(x: 0, y: rowCenter - string.size().height / 2))
            }
            if warningWidth > 0 {
                NSAttributedString(string: "!", attributes: attributes)
                    .draw(at: NSPoint(x: rect.width - 9, y: 5))
            }
            return true
        }
        image.isTemplate = true
        button.title = ""
        button.imagePosition = .imageOnly
        button.image = image
        button.setAccessibilityLabel("Codex remaining: " + lines.joined(separator: ", "))
        button.toolTip = "Codex allowance remaining. Click for usage and reset times."
    }
    func positionPanel() {
        guard let button = statusItem.button, let window = button.window,
              let screen = window.screen else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        panel.setFrame(panelFrame(anchor: anchor, visibleFrame: screen.visibleFrame,
                                  size: NSSize(width: 350, height: size.height)), display: true)
    }
    @objc func toggle() {
        if panel.isVisible { panel.orderOut(nil) }
        else {
            positionPanel()
            panel.makeKeyAndOrderFront(nil)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
