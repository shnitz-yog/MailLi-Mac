import SwiftUI
import AVFoundation

/// Reads buttons aloud when the mouse rests on them, like the PC app does for
/// children who can't read yet. Uses the Mac's built-in Hebrew voice (Carmit),
/// so it works for every label, name and letter.
@MainActor
final class Speaker: ObservableObject {
    static let shared = Speaker()

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(!enabled, forKey: "speechMuted") }
    }
    private let synth = AVSpeechSynthesizer()
    private var pending: Task<Void, Never>?
    private var hovered: String?
    private lazy var voice: AVSpeechSynthesisVoice? = {
        let he = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("he") }
        return he.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "he-IL")
    }()

    private init() { enabled = !UserDefaults.standard.bool(forKey: "speechMuted") }

    /// Mouse entered / left something that has a spoken name.
    func hover(_ text: String, inside: Bool) {
        if inside {
            hovered = text
            pending?.cancel()
            guard enabled, !text.isEmpty else { return }
            // A short wait, so sweeping the mouse across the screen stays quiet.
            pending = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled, let self, self.hovered == text else { return }
                self.say(text)
            }
        } else if hovered == text {
            hovered = nil
            pending?.cancel()
        }
    }

    func say(_ text: String) {
        guard enabled else { return }
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = 0.43          // a little slower than normal, for children
        u.pitchMultiplier = 1.05
        synth.speak(u)
    }

    func stop() { pending?.cancel(); synth.stopSpeaking(at: .immediate) }

    /// What to say for a key on the on-screen keyboard.
    static func keyName(_ k: String) -> String {
        let names: [String: String] = [
            "א": "אָלֶף", "ב": "בֵּית", "ג": "גִּימֶל", "ד": "דָּלֶת", "ה": "הֵא", "ו": "וָו", "ז": "זַיִן",
            "ח": "חֵית", "ט": "טֵית", "י": "יוּד", "כ": "כַּף", "ל": "לָמֶד", "מ": "מֵם", "נ": "נוּן",
            "ס": "סָמֶך", "ע": "עַיִן", "פ": "פֵּא", "צ": "צָדִי", "ק": "קוּף", "ר": "רֵישׁ", "ש": "שִׁין", "ת": "תָּו",
            "ך": "כַּף סוֹפִית", "ם": "מֵם סוֹפִית", "ן": "נוּן סוֹפִית", "ף": "פֵּא סוֹפִית", "ץ": "צָדִי סוֹפִית",
            "?": "סִימַן שְׁאֵלָה", "!": "סִימַן קְרִיאָה", ",": "פְּסִיק", ".": "נְקוּדָה", "-": "מַקָּף",
            "0": "אֶפֶס", "1": "אַחַת", "2": "שְׁתַּיִם", "3": "שָׁלוֹשׁ", "4": "אַרְבַּע", "5": "חָמֵשׁ",
            "6": "שֵׁשׁ", "7": "שֶׁבַע", "8": "שְׁמוֹנֶה", "9": "תֵּשַׁע",
            "רווח": "רֶוַוח", "😊": "אִימוֹגִ'י",
        ]
        return names[k] ?? k
    }
}

private struct SpeakOnHover: ViewModifier {
    var text: String
    @Environment(\.previewing) private var previewing
    func body(content: Content) -> some View {
        if previewing { content }
        else { content.onHover { Speaker.shared.hover(text, inside: $0) } }
    }
}

extension View {
    /// Say `text` when the mouse rests on this view.
    func speaks(_ text: String) -> some View { modifier(SpeakOnHover(text: text)) }
}

/// Top-bar switch for reading aloud.
struct SpeechToggle: View {
    @ObservedObject var speaker = Speaker.shared
    var body: some View {
        Button {
            speaker.enabled.toggle()
            if speaker.enabled { speaker.say("הַקְרָאָה פְּתוּחָה") } else { speaker.stop() }
        } label: {
            Image(systemName: speaker.enabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(speaker.enabled ? Kid.ink : Kid.ink.opacity(0.4))
                .frame(width: 40, height: 40)
                .background(Circle().fill(.white.opacity(0.7)))
        }
        .buttonStyle(.plain)
        .help(speaker.enabled ? "השתקת ההקראה" : "הפעלת ההקראה")
    }
}
