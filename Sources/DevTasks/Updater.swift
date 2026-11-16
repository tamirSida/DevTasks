import SwiftUI
import AppKit

// Self-update from GitHub Releases. Downloads the prebuilt zip (no Xcode or building needed),
// verifies it, swaps the app bundle in place with rollback, and relaunches.

struct ReleaseInfo: Equatable {
    let version: String
    let notes: String
    let assetURL: URL
    let size: Int64
    let pageURL: URL
}

enum UpdateEngine {
    static let repo = "tamirSida/DevTasks"
    static let bundleID = "dev.local.devtasks"

    // MARK: versions

    static func isNewer(_ a: String, than b: String) -> Bool {
        guard b != "dev" else { return false } // never replace a dev build run from source
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: GitHub

    static func fetchLatest() async throws -> ReleaseInfo {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("DevTasks-Updater", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw DTError("no response from GitHub") }
        guard http.statusCode == 200 else {
            throw DTError(http.statusCode == 404 ? "no releases published yet" : "GitHub returned HTTP \(http.statusCode)")
        }
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = o["tag_name"] as? String,
              let page = (o["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = o["assets"] as? [[String: Any]],
              let zip = assets.first(where: { ($0["name"] as? String)?.hasSuffix("-macOS.zip") == true }),
              let dl = (zip["browser_download_url"] as? String).flatMap(URL.init(string:)) else {
            throw DTError("latest release has no macOS zip attached")
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return ReleaseInfo(version: version, notes: o["body"] as? String ?? "", assetURL: dl,
                           size: (zip["size"] as? NSNumber)?.int64Value ?? 0, pageURL: page)
    }

    // MARK: download

    final class Downloader: NSObject, URLSessionDownloadDelegate {
        private var cont: CheckedContinuation<URL, Error>?
        private let progress: (Double) -> Void
        init(progress: @escaping (Double) -> Void) { self.progress = progress }

        func download(_ url: URL) async throws -> URL {
            try await withCheckedThrowingContinuation { c in
                cont = c
                let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
                session.downloadTask(with: url).resume()
            }
        }

        func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                        totalBytesWritten written: Int64, totalBytesExpectedToWrite total: Int64) {
            if total > 0 { progress(Double(written) / Double(total)) }
        }

        func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("DevTasks-update-\(UUID().uuidString).zip")
            do {
                if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                    throw DTError("download failed (HTTP \(http.statusCode))")
                }
                try FileManager.default.moveItem(at: location, to: dest)
                cont?.resume(returning: dest)
            } catch {
                cont?.resume(throwing: error)
            }
            cont = nil
            s.finishTasksAndInvalidate()
        }

        func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error { cont?.resume(throwing: error); cont = nil }
        }
    }

    // MARK: install

    @discardableResult
    static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard p.terminationStatus == 0 else { throw DTError("\(URL(fileURLWithPath: tool).lastPathComponent) failed: \(out.trimmingCharacters(in: .whitespacesAndNewlines))") }
        return out
    }

    /// Unzips and checks the download: right app, right version, valid signature.
    static func prepare(zip: URL, expect version: String) throws -> (app: URL, root: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DevTasks-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path])
        let root = dir.appendingPathComponent("DevTasks")
        let app = root.appendingPathComponent("DevTasks.app")
        guard let info = Bundle(url: app)?.infoDictionary else { throw DTError("the download doesn't contain DevTasks.app") }
        guard info["CFBundleIdentifier"] as? String == bundleID else { throw DTError("the download is not DevTasks") }
        guard info["CFBundleShortVersionString"] as? String == version else { throw DTError("the download's version doesn't match \(version)") }
        try run("/usr/bin/codesign", ["--verify", "--deep", app.path])
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        return (app, root)
    }

    /// The installed app bundle to replace (env override is for testing).
    static func installedApp() throws -> URL {
        if let o = ProcessInfo.processInfo.environment["DEVTASKS_UPDATE_DEST"], !o.isEmpty { return URL(fileURLWithPath: o) }
        var url = Bundle.main.bundleURL
        if url.pathExtension != "app" {
            // CLI through a symlink: .../DevTasks.app/Contents/MacOS/DevTasks
            url = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        }
        guard url.pathExtension == "app" else { throw DTError("updating only works for the installed DevTasks.app") }
        guard FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path) else {
            throw DTError("no permission to replace \(url.path)")
        }
        return url
    }

    /// Writes and starts a detached script that waits for `waitPID` to exit, swaps the bundle
    /// (rolling back on failure), refreshes the Claude skill, and optionally relaunches.
    static func launchSwap(newApp: URL, root: URL, dest: URL, waitPID: Int32?, relaunch: Bool) throws -> Process {
        let script = """
        #!/bin/bash
        PID="$1"; NEW="$2"; DEST="$3"; ROOT="$4"; RELAUNCH="$5"
        if [ -n "$PID" ]; then for i in $(seq 1 150); do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done; fi
        BACKUP="$DEST.previous"
        rm -rf "$BACKUP"
        if mv "$DEST" "$BACKUP" && /usr/bin/ditto "$NEW" "$DEST"; then
          /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
          rm -rf "$BACKUP"
          echo "updated"
        else
          echo "update failed, restoring previous version"
          rm -rf "$DEST"; mv "$BACKUP" "$DEST"
        fi
        if [ -d "$HOME/.claude/skills/devtasks" ] && [ -d "$ROOT/agent/skills/devtasks" ]; then
          rm -rf "$HOME/.claude/skills/devtasks"; cp -R "$ROOT/agent/skills/devtasks" "$HOME/.claude/skills/devtasks"
        fi
        if [ "$RELAUNCH" = "1" ]; then /usr/bin/open "$DEST"; fi
        """
        let url = root.deletingLastPathComponent().appendingPathComponent("swap.sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        let log = root.deletingLastPathComponent().appendingPathComponent("swap.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [url.path, waitPID.map(String.init) ?? "", newApp.path, dest.path, root.path, relaunch ? "1" : "0"]
        if let h = try? FileHandle(forWritingTo: log) { p.standardOutput = h; p.standardError = h }
        try p.run()
        return p
    }
}

// MARK: - App-side state for the wizard

@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    enum Phase: Equatable {
        case idle, checking, upToDate, available, downloading(Double), installing
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var release: ReleaseInfo?
    @Published var showWizard = false

    static let autoKey = "autoCheckUpdates"
    private let lastCheckKey = "lastUpdateCheck"
    private let skipKey = "skippedVersion"

    var current: String { AppVersion.current }
    var updateAvailable: Bool { release.map { UpdateEngine.isNewer($0.version, than: current) } ?? false }

    /// Quiet check on launch: at most every 6 hours, never pops up the wizard by itself.
    func checkInBackground() {
        let d = UserDefaults.standard
        guard d.object(forKey: Updater.autoKey) as? Bool ?? true else { return }
        let last = d.double(forKey: lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 6 * 3600 else { return }
        Task { await check(userInitiated: false) }
    }

    func openWizard() {
        showWizard = true
        if phase != .available { Task { await check(userInitiated: true) } }
    }

    func check(userInitiated: Bool) async {
        if userInitiated { phase = .checking }
        do {
            let r = try await UpdateEngine.fetchLatest()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
            let skipped = UserDefaults.standard.string(forKey: skipKey)
            if UpdateEngine.isNewer(r.version, than: current) && (userInitiated || skipped != r.version) {
                release = r
                phase = .available
            } else {
                release = nil
                phase = .upToDate
            }
        } catch {
            if userInitiated { phase = .failed("\(error)") }
        }
    }

    func skipThisVersion() {
        if let r = release { UserDefaults.standard.set(r.version, forKey: skipKey) }
        release = nil
        phase = .idle
        showWizard = false
    }

    func install() {
        guard let r = release else { return }
        phase = .downloading(0)
        Task {
            do {
                let dest = try UpdateEngine.installedApp()
                let zip = try await UpdateEngine.Downloader { p in
                    Task { @MainActor in self.phase = .downloading(p) }
                }.download(r.assetURL)
                phase = .installing
                let prepared = try await Task.detached { try UpdateEngine.prepare(zip: zip, expect: r.version) }.value
                Store.shared?.saveNow()
                _ = try UpdateEngine.launchSwap(newApp: prepared.app, root: prepared.root, dest: dest,
                                                waitPID: ProcessInfo.processInfo.processIdentifier, relaunch: true)
                try? await Task.sleep(nanoseconds: 400_000_000)
                NSApp.terminate(nil)
            } catch {
                phase = .failed("\(error)")
            }
        }
    }
}

// MARK: - Wizard UI

struct UpdateWizard: View {
    @ObservedObject var updater = Updater.shared
    @Environment(\.theme) private var t

    private var step: Int {
        switch updater.phase {
        case .idle, .checking, .upToDate, .failed: 1
        case .available: 2
        case .downloading: 3
        case .installing: 4
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                FAIcon("rocket", size: 16)
                    .foregroundStyle(t.accentInk)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 8).fill(t.accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text("update devtasks").font(.mono(14, .bold))
                    Text("installed: v\(updater.current)").font(.mono(11)).foregroundStyle(t.muted)
                }
                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(Array(["check", "review", "download", "install"].enumerated()), id: \.offset) { i, name in
                    let n = i + 1
                    HStack(spacing: 5) {
                        Text("\(n)").font(.mono(9.5, .bold))
                            .foregroundStyle(n <= step ? t.accentInk : t.faint)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(n <= step ? t.accent : t.raised))
                        Text(name).font(.mono(10.5)).foregroundStyle(n == step ? t.text : t.faint)
                            .lineLimit(1).fixedSize()
                    }
                    if n < 4 { Rectangle().fill(n < step ? t.accent : t.border).frame(minWidth: 8, maxHeight: 1) }
                }
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 120, alignment: .top)

            buttons
        }
        .padding(22)
        .frame(width: 480)
        .background(t.panel)
        .foregroundStyle(t.text)
    }

    @ViewBuilder private var content: some View {
        switch updater.phase {
        case .idle, .checking:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("checking github releases...").font(.mono(12)).foregroundStyle(t.muted)
            }
        case .upToDate:
            HStack(spacing: 10) {
                FAIcon("circle-check", size: 16).foregroundStyle(t.accent)
                Text("you're on the latest version.").font(.mono(12))
            }
        case .available:
            if let r = updater.release {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("v\(updater.current)").font(.mono(13)).foregroundStyle(t.muted)
                        FAIcon("arrow-right", size: 10).foregroundStyle(t.faint)
                        Text("v\(r.version)").font(.mono(13, .bold)).foregroundStyle(t.accent)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: r.size, countStyle: .file)).font(.mono(10.5)).foregroundStyle(t.faint)
                    }
                    ScrollView {
                        Text(readableNotes(r.notes))
                            .font(.mono(11))
                            .foregroundStyle(t.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 170)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(t.bg))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(t.border))
                    Text("devtasks will restart. your tasks and notes are kept.").font(.mono(10.5)).foregroundStyle(t.faint)
                }
            }
        case .downloading(let p):
            VStack(alignment: .leading, spacing: 8) {
                Text("downloading v\(updater.release?.version ?? "")...").font(.mono(12))
                ProgressView(value: p).tint(t.accent)
                Text("\(Int(p * 100))%").font(.mono(10.5)).foregroundStyle(t.faint)
            }
        case .installing:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("verifying and installing. devtasks will restart...").font(.mono(12))
            }
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    FAIcon("triangle-exclamation", size: 13).foregroundStyle(t.danger)
                    Text("update failed").font(.mono(12, .bold))
                }
                Text(msg).font(.mono(11)).foregroundStyle(t.muted).textSelection(.enabled)
                Text("nothing was changed. you can retry, or download the zip from the release page and run install.sh.")
                    .font(.mono(10.5)).foregroundStyle(t.faint)
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        HStack(spacing: 14) {
            switch updater.phase {
            case .available:
                textButton("skip this version", t.faint) { updater.skipThisVersion() }
                Spacer()
                textButton("later", t.muted) { updater.showWizard = false }
                    .keyboardShortcut(.cancelAction)
                primary("update now") { updater.install() }
            case .failed:
                if let page = updater.release?.pageURL {
                    textButton("open release page", t.muted) { NSWorkspace.shared.open(page) }
                }
                Spacer()
                textButton("close", t.muted) { updater.showWizard = false }
                    .keyboardShortcut(.cancelAction)
                primary("retry") { Task { await updater.check(userInitiated: true) } }
            case .downloading, .installing:
                Spacer()
            default:
                Spacer()
                primary("close") { updater.showWizard = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    /// Release notes are markdown: show headings and code blocks as plain lines, keep **bold** / `code` / links.
    private func readableNotes(_ md: String) -> AttributedString {
        let cleaned = md.replacingOccurrences(of: "\r", with: "")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            .map { line -> String in
                var l = line
                while l.hasPrefix("#") { l.removeFirst() }
                return l.hasPrefix(" ") && line.hasPrefix("#") ? String(l.dropFirst()).uppercased() : l
            }
            .joined(separator: "\n")
        return (try? AttributedString(markdown: cleaned, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(cleaned)
    }

    private func textButton(_ title: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.plain).handCursor().font(.mono(12)).foregroundStyle(color)
    }

    private func primary(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.mono(12, .bold))
                .foregroundStyle(t.accentInk)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7).fill(t.accent))
        }
        .buttonStyle(.plain)
        .handCursor()
        .keyboardShortcut(.defaultAction)
    }
}

/// Sidebar pill shown when a newer release exists.
struct UpdatePill: View {
    @ObservedObject var updater = Updater.shared
    @Environment(\.theme) private var t
    @State private var hover = false

    var body: some View {
        if updater.updateAvailable, let r = updater.release {
            Button { updater.openWizard() } label: {
                HStack(spacing: 8) {
                    FAIcon("circle-arrow-up", size: 12)
                    Text("update v\(r.version)").font(.mono(11.5, .semibold))
                    Spacer()
                    FAIcon("chevron-right", size: 9)
                }
                .foregroundStyle(t.accent)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7).fill(t.accent.opacity(hover ? 0.2 : 0.12)))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(t.accent.opacity(0.4)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .handCursor()
            .onHover { hover = $0 }
        }
    }
}
