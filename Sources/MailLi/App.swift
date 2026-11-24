import SwiftUI
import AppKit
import AVFoundation

@main
struct MailLiApp: App {
    @StateObject private var client = MailLiClient()

    init() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--selftest"), i + 1 < args.count {
            exit(MainActor.assumeIsolated { SelfTest.run(args[i + 1]) })
        }
        if let i = args.firstIndex(of: "--screens"), i + 1 < args.count {
            exit(MainActor.assumeIsolated { ScreenShots.run(args[i + 1]) })
        }
        if let i = args.firstIndex(of: "--login-store-test"), i + 1 < args.count {
            exit(SavedLogin.commandLineTest(args[i + 1]))
        }
        if args.contains("--speech-test") {
            exit(MainActor.assumeIsolated { () -> Int32 in
                let v = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("he") }
                print("hebrew voices:", v.map { "\($0.name) \($0.quality.rawValue)" })
                Speaker.shared.enabled = true
                Speaker.shared.say("שָׁלוֹם, זֶה מֵיְיל לִי")
                RunLoop.main.run(until: Date().addingTimeInterval(3))
                return v.isEmpty ? 1 : 0
            })
        }
        if args.contains("--update-test") {
            exit(MainActor.assumeIsolated { Updater.commandLineTest() })
        }
        // Run as a normal windowed app even when launched from the command line.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("מייל לי") {
            RootView()
                .environmentObject(client)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he_IL"))
                .preferredColorScheme(.light)
                .frame(minWidth: 1000, minHeight: 680)
        }
        .defaultSize(width: 1240, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("בדיקת עדכונים…") { Updater.shared.checkNow() }
            }
        }
    }
}

/// Which full-window screen is showing (like the PC app: one screen at a time,
/// with the path shown as breadcrumbs in the yellow bar).
enum Screen: Equatable {
    case home
    case list(Mailbox)
    case read(MailHeader, Mailbox)
    case write(MailAddress?)
}

struct RootView: View {
    @EnvironmentObject var client: MailLiClient
    @Local private var screen: Screen = .home
    @Local private var confirmExit = false

    var body: some View {
        ZStack {
            Kid.page.ignoresSafeArea()
            if !client.loggedIn {
                LoginView()
            } else {
                VStack(spacing: 0) {
                    TopBar(crumbs: crumbs, onExit: { confirmExit = true })
                    Group {
                        switch screen {
                        case .home:
                            HomeView(go: { screen = $0 })
                        case .list(let b):
                            ListView(box: b, go: { screen = $0 })
                        case .read(let h, let b):
                            ReadView(header: h, box: b, go: { screen = $0 })
                        case .write(let to):
                            WriteView(replyTo: to, close: { sent in screen = sent ? .list(.sent) : .home })
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                }
            }
        }
        .overlay { UpdateOverlay() }
        .onAppear { Updater.shared.checkOnLaunch() }
        .animation(.easeInOut(duration: 0.2), value: screen)
        .animation(.easeInOut(duration: 0.2), value: client.loggedIn)
        .confirmationDialog("לצאת מהחשבון?", isPresented: $confirmExit) {
            Button("יציאה", role: .destructive) {
                SavedLogin.delete(user: UserDefaults.standard.string(forKey: "lastUser") ?? "")
                screen = .home
                client.logout()
            }
            Button("ביטול", role: .cancel) {}
        } message: { Text("בפעם הבאה יהיה צריך להקליד שוב שם משתמש וסיסמה.") }
    }

    private var crumbs: [Crumb] {
        let home = Crumb(title: "מייל לי", icon: PC.mailLi, symbol: "envelope.fill", action: { screen = .home })
        func box(_ b: Mailbox, tappable: Bool) -> Crumb {
            b == .inbox
                ? Crumb(title: "לקבל מכתב", icon: PC.receiveCrumb, symbol: "envelope.open", action: tappable ? { screen = .list(.inbox) } : nil)
                : Crumb(title: "מכתבים ששלחתי", icon: PC.sentCrumb, symbol: "paperplane", action: tappable ? { screen = .list(.sent) } : nil)
        }
        switch screen {
        case .home: return [home]
        case .list(let b): return [home, box(b, tappable: false)]
        case .read(_, let b):
            return [home, box(b, tappable: true),
                    Crumb(title: b == .inbox ? "מכתב שקיבלתי" : "מכתב ששלחתי", icon: PC.readCrumb, symbol: "envelope.open.fill", action: nil)]
        case .write: return [home, Crumb(title: "לשלוח מכתב", icon: PC.writeCrumb, symbol: "pencil", action: nil)]
        }
    }
}

// MARK: - Login (done once by a parent; "remember me" logs in automatically after)

struct LoginView: View {
    @EnvironmentObject var client: MailLiClient
    @AppStorage("lastUser") private var savedUser = ""
    @AppStorage("remember") private var remember = true
    @Local private var user = ""
    @Local private var password = ""
    @Local private var showPassword = true   // hidden fields force an English keyboard on macOS
    @Local private var busy = false
    @Local private var error: String? = nil

    var body: some View {
        VStack(spacing: 22) {
            if let icon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage {
                Image(nsImage: icon).resizable().frame(width: 130, height: 130)
            }
            Text("מייל לי").font(Kid.font(54, .heavy)).foregroundStyle(Kid.ink)
            if busy && password.isEmpty == false && error == nil && savedUser == user && remember {
                ProgressView().controlSize(.large)
            }
            VStack(spacing: 14) {
                field(icon: "person.fill", placeholder: "שם משתמש", text: $user, secure: false)
                HStack(spacing: 8) {
                    field(icon: "key.fill", placeholder: "סיסמה", text: $password, secure: !showPassword)
                    RoundButton(icon: showPassword ? "eye.slash.fill" : "eye.fill", size: 44,
                                help: "הסתרת הסיסמה (כשהיא מוסתרת אפשר להקליד רק באנגלית)") { showPassword.toggle() }
                }
                Toggle("לזכור אותי במחשב הזה", isOn: $remember)
                    .font(Kid.font(16, .medium)).foregroundStyle(Kid.ink)
            }
            .frame(width: 380)
            if let e = error {
                Text(e).font(Kid.font(18, .semibold)).foregroundStyle(.red)
            }
            GreenPill(title: busy ? "רגע…" : "כניסה", icon: PC.send) {
                Task { await doLogin() }
            }
            .disabled(busy || user.isEmpty || password.isEmpty)
            .keyboardShortcut(.defaultAction)
            Text("את שם המשתמש והסיסמה מקבלים מהגן").font(Kid.font(15, .medium)).foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            user = savedUser
            if remember, !savedUser.isEmpty, let p = SavedLogin.load(user: savedUser) {
                password = p
                Task { await doLogin() }
            }
        }
    }

    private func field(icon: String, placeholder: String, text: Binding<String>, secure: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Kid.outline).font(.system(size: 20, weight: .bold))
            Group {
                if secure { SecureField(placeholder, text: text) } else { TextField(placeholder, text: text) }
            }
            .textFieldStyle(.plain)
            .font(Kid.font(22, .semibold))
            .onSubmit { Task { await doLogin() } }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(Capsule().fill(.white))
        .overlay(Capsule().stroke(Kid.outline, lineWidth: 2))
    }

    private func doLogin() async {
        guard !busy, !user.isEmpty, !password.isEmpty else { return }
        busy = true; error = nil
        defer { busy = false }
        let u = user.trimmingCharacters(in: .whitespaces)
        do {
            try await client.login(user: u, password: password)
            savedUser = u
            if remember { SavedLogin.save(user: u, password: password) } else { SavedLogin.delete(user: u) }
            password = ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}
