import SwiftUI
import AppKit
import CryptoKit

/// Self-update from this project's GitHub releases.
///
/// 1. Asks GitHub for the latest release (tag "v1.2" → version 1.2).
/// 2. If it is newer than this app, offers it to the parent.
/// 3. Downloads MailLi.dmg and checks its SHA-256 against the digest GitHub
///    publishes for that file, opens the DMG, checks the app inside
///    (same bundle id, valid signature), puts it in place of this app and relaunches.
///
/// Files the app downloads itself get no "downloaded from the internet" flag,
/// so an update never runs into the Gatekeeper block that WhatsApp copies did.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    static let repo = "shnitz-yog/MailLi-Mac"
    static let pageURL = URL(string: "https://github.com/\(repo)/releases/latest")!
    private static let apiURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!

    struct Release: Equatable {
        var version: String
        var title: String
        var notes: String
        var dmg: URL
        var sha256: String?     // hex, from GitHub's asset digest
    }

    enum Phase: Equatable {
        case idle
        case checking
        case available(Release)
        case upToDate
        case installing(String)
        case failed(String)
    }

    @Published var phase: Phase = .idle
    private var manual = false

    /// Version of the running app (MAILLI_FAKE_VERSION overrides it, for testing).
    static var currentVersion: String {
        ProcessInfo.processInfo.environment["MAILLI_FAKE_VERSION"]
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
    }

    /// "1.10" > "1.9" > "1.2.1" > "1.2"
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    // MARK: checking

    /// Quiet check at launch, at most once a day.
    func checkOnLaunch() {
        let key = "lastUpdateCheck"
        let last = UserDefaults.standard.double(forKey: key)
        guard Date().timeIntervalSince1970 - last > 20 * 3600 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
        Task { await check(manual: false) }
    }

    /// From the menu: always answers (also "you're up to date" / errors).
    func checkNow() { Task { await check(manual: true) } }

    func check(manual: Bool) async {
        if case .installing = phase { return }
        self.manual = manual
        if manual { phase = .checking }
        do {
            let r = try await Self.latest()
            if Self.isNewer(r.version, than: Self.currentVersion) {
                if UserDefaults.standard.string(forKey: "skipVersion") == r.version && !manual { phase = .idle; return }
                phase = .available(r)
            } else {
                phase = manual ? .upToDate : .idle
            }
        } catch {
            phase = manual ? .failed("לא הצלחנו לבדוק אם יש עדכון. בודקים שיש אינטרנט ומנסים שוב.") : .idle
        }
    }

    static func latest() async throws -> Release {
        var req = URLRequest(url: apiURL, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("MailLi-Mac-Updater", forHTTPHeaderField: "User-Agent")
        let (d, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try JSONSerialization.jsonObject(with: d) as? [String: Any],
              let tag = j["tag_name"] as? String,
              let assets = j["assets"] as? [[String: Any]],
              let dmg = assets.first(where: { ($0["name"] as? String) == "MailLi.dmg" }),
              let s = dmg["browser_download_url"] as? String, let url = URL(string: s),
              url.scheme == "https", url.host == "github.com"
        else { throw URLError(.badServerResponse) }
        let digest = (dmg["digest"] as? String).flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)) : nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(version: version, title: j["name"] as? String ?? tag,
                       notes: j["body"] as? String ?? "", dmg: url, sha256: digest?.lowercased())
    }

    func skip(_ r: Release) {
        UserDefaults.standard.set(r.version, forKey: "skipVersion")
        phase = .idle
    }

    // MARK: installing

    func install(_ r: Release) {
        phase = .installing("מורידים את הגרסה החדשה…")
        Task {
            do {
                let newApp = try await Self.prepare(r) { msg in Task { @MainActor in self.phase = .installing(msg) } }
                phase = .installing("מתקינים…")
                try Self.replaceRunningApp(with: newApp)
                Self.relaunch()
            } catch let e as UpdateError {
                phase = .failed(e.message)
            } catch {
                phase = .failed("העדכון לא הצליח (\(error.localizedDescription)). אפשר להוריד את הגרסה החדשה מהאתר.")
            }
        }
    }

    struct UpdateError: Error { var message: String }

    /// Download, verify, unpack. Returns the new MailLi.app in a temporary folder.
    nonisolated static func prepare(_ r: Release, progress: @escaping (String) -> Void) async throws -> URL {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("MailLiUpdate-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        var req = URLRequest(url: r.dmg, timeoutInterval: 120)
        req.setValue("MailLi-Mac-Updater", forHTTPHeaderField: "User-Agent")
        let (tmp, resp) = try await URLSession.shared.download(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError(message: "ההורדה נכשלה. מנסים שוב מאוחר יותר.") }
        let dmg = work.appendingPathComponent("MailLi.dmg")
        try FileManager.default.moveItem(at: tmp, to: dmg)

        progress("בודקים שהקובץ תקין…")
        guard let want = r.sha256 else { throw UpdateError(message: "אין לגרסה הזו חתימת בדיקה. מורידים אותה מהאתר.") }
        let got = SHA256.hash(data: try Data(contentsOf: dmg)).map { String(format: "%02x", $0) }.joined()
        guard got == want else { throw UpdateError(message: "הקובץ שירד לא תואם לגרסה שפורסמה, ולכן לא הותקן.") }

        let mount = work.appendingPathComponent("mnt")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        guard run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path]) == 0 else {
            throw UpdateError(message: "לא הצלחנו לפתוח את קובץ העדכון.")
        }
        defer { _ = run("/usr/bin/hdiutil", ["detach", "-force", mount.path]) }

        let inside = mount.appendingPathComponent("MailLi.app")
        guard let b = Bundle(url: inside), b.bundleIdentifier == Bundle.main.bundleIdentifier ?? "local.mailli.mac" else {
            throw UpdateError(message: "בקובץ העדכון אין את האפליקציה הנכונה.")
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", inside.path]) == 0 else {
            throw UpdateError(message: "האפליקציה בקובץ העדכון פגומה, ולכן לא הותקנה.")
        }
        let copy = work.appendingPathComponent("MailLi.app")
        guard run("/usr/bin/ditto", [inside.path, copy.path]) == 0 else { throw UpdateError(message: "העתקת העדכון נכשלה.") }
        return copy
    }

    /// Swap the new app into this app's place (e.g. /Applications/MailLi.app).
    static func replaceRunningApp(with newApp: URL) throws {
        let here = Bundle.main.bundleURL
        let path = here.path
        if path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/") {
            throw UpdateError(message: "כדי לעדכן, קודם גוררים את MailLi לתיקיית Applications ופותחים אותה משם.")
        }
        let dir = here.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: dir.path) else {
            throw UpdateError(message: "אין הרשאה לעדכן את האפליקציה בתיקייה \(dir.lastPathComponent). מורידים את הגרסה החדשה מהאתר.")
        }
        // Stage next to the old app (same disk), then swap in one step.
        let staged = dir.appendingPathComponent(".MailLi-update-\(UUID().uuidString).app")
        try FileManager.default.copyItem(at: newApp, to: staged)
        do {
            _ = try FileManager.default.replaceItemAt(here, withItemAt: staged)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw error
        }
    }

    /// Start the new copy once this one has quit.
    static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let pid = ProcessInfo.processInfo.processIdentifier
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.3; done; /usr/bin/open \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }

    @discardableResult
    nonisolated static func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    /// `MailLi --update-test`: check + download + verify + install without asking (for testing).
    static func commandLineTest() -> Int32 {
        var code: Int32 = 1
        var done = false
        Task { @MainActor in
            do {
                let r = try await latest()
                print("running \(currentVersion), latest \(r.version), sha256 \(r.sha256 ?? "none")")
                guard isNewer(r.version, than: currentVersion) else { print("up to date"); code = 0; done = true; return }
                let app = try await prepare(r) { print($0) }
                try replaceRunningApp(with: app)
                print("installed over \(Bundle.main.bundleURL.path)")
                code = 0
            } catch let e as UpdateError { print("FAILED: " + e.message) }
            catch { print("FAILED: \(error)") }
            done = true
        }
        while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        return code
    }
}

/// The update window over the app.
struct UpdateOverlay: View {
    @ObservedObject var updater = Updater.shared

    var body: some View {
        switch updater.phase {
        case .idle, .checking:
            EmptyView()
        default:
            ZStack {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 18) {
                    content
                }
                .padding(36)
                .frame(maxWidth: 560)
                .background(RoundedRectangle(cornerRadius: 28).fill(.white))
                .shadow(radius: 20)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder private var content: some View {
        switch updater.phase {
        case .available(let r):
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 54)).foregroundStyle(Kid.send)
            Text("יש גרסה חדשה של מייל לי!").font(Kid.font(30, .heavy)).foregroundStyle(Kid.ink)
            Text("גרסה \(r.version) (עכשיו מותקנת \(Updater.currentVersion))")
                .font(Kid.font(18, .semibold)).foregroundStyle(Kid.ink.opacity(0.7))
            Text("העדכון לוקח פחות מדקה, והאפליקציה תיפתח מחדש לבד.")
                .font(Kid.font(18)).foregroundStyle(Kid.ink).multilineTextAlignment(.center)
            HStack(spacing: 14) {
                GreenPill(title: "לעדכן עכשיו", icon: PC.send) { updater.install(r) }
                    .keyboardShortcut(.defaultAction)
                Pill(title: "אחר כך", height: 50) { updater.phase = .idle }
                    .keyboardShortcut(.cancelAction)
            }
            Button("לא להזכיר על הגרסה הזו") { updater.skip(r) }
                .buttonStyle(.plain).font(Kid.font(15)).foregroundStyle(Kid.ink.opacity(0.6))
        case .installing(let msg):
            ProgressView().controlSize(.large)
            Text(msg).font(Kid.font(24, .bold)).foregroundStyle(Kid.ink)
        case .upToDate:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(Kid.send)
            Text("יש לך את הגרסה האחרונה").font(Kid.font(28, .heavy)).foregroundStyle(Kid.ink)
            Text("גרסה \(Updater.currentVersion)").font(Kid.font(18)).foregroundStyle(Kid.ink.opacity(0.7))
            Pill(title: "אישור", height: 50) { updater.phase = .idle }.keyboardShortcut(.defaultAction)
        case .failed(let msg):
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 50)).foregroundStyle(.orange)
            Text(msg).font(Kid.font(20, .semibold)).foregroundStyle(Kid.ink).multilineTextAlignment(.center)
            HStack(spacing: 14) {
                Pill(title: "לאתר ההורדה", height: 50) { NSWorkspace.shared.open(Updater.pageURL); updater.phase = .idle }
                Pill(title: "סגירה", height: 50) { updater.phase = .idle }.keyboardShortcut(.cancelAction)
            }
        default:
            EmptyView()
        }
    }
}
