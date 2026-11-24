import SwiftUI
import AppKit

/// Look of the Windows "מייל לי" app (colours sampled from Googale's screenshots):
/// yellow top bar, light-cyan page, white pills with blue outline, green action buttons.
enum Kid {
    static let bar = Color(hex: "#FFF7D970")!         // yellow top bar
    static let strip = Color(hex: "#FFDCF8FF")!       // pale strip under the bar
    static let page = Color(hex: "#FFBDF1FF")!        // page background
    static let toolBox = Color(hex: "#FFAED8E6")!     // grouped tools box
    static let outline = Color(hex: "#FF3DA7D9")!     // pill outline
    static let chipLine = Color(hex: "#FF5AC3E6")!
    static let send = Color(hex: "#FF74CE2F")!        // green buttons
    static let ink = Color(hex: "#FF1F3A93")!         // dark-blue text
    static let keyLine = Color(hex: "#FF8C9396")!
    static let sun = Color(hex: "#FFF4B71E")!
    static let sky = LinearGradient(colors: [page, page], startPoint: .top, endPoint: .bottom)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// The PC app's own pictures, loaded from the Googale server (like the Windows app does).
enum PC {
    static let v5 = "https://galeli.com/mailli.web/resources/v5/"
    static let writeLetter = v5 + "WriteALetter.png"
    static let receiveLetter = v5 + "ReceiveALetter1.png"
    static let sentLetters = v5 + "LetterSent.png"
    static let mailLi = "https://galeli.com/MailLi.web/Resources/V5/MailLiBC.svg"
    static let writeCrumb = "https://galeli.com/MailLi.web/Resources/V5/WriteALetterBC.svg"
    static let receiveCrumb = "https://galeli.com/MailLi.web/Resources/V5/ReceiveALetterBC.svg"
    static let readCrumb = "https://galeli.com/MailLi.web/Resources/V5/ReadEmailBC.svg"
    static let sentCrumb = "https://galeli.com/MailLi.web/Resources/V5/LetterSentBC.svg"
    static let unreadEnvelope = "https://galeli.com/MailLi.web/resources/v5/ReceiveEmailEnvelope.png"
    static let readEnvelope = "https://galeli.com/MailLi.web/resources/v5/ReadEmail.png"
    static let toEnvelope = "https://galeli.com/MailLi.web/resources/v5/ToEnvelope.png"
    static let toIcon = v5 + "To.png"
    static let back = v5 + "BackButton.png"
    static let reply = v5 + "Reply.png"
    static let print = "https://galeli.com/mailli.web/resources/Common-Print.png"
    static let tellIcon = "https://galeli.com/mailli.web/resources/MailLi-IWantToTellThat.png"
    static let selectAll = v5 + "SelectAll.png"
    static let trash = "https://galeli.com/galeli.web/content/v5/Trash.png"
    static let send = v5 + "send.png"
    static let sentOK = v5 + "LetterWasSentF.png"
    static let toWhom = v5 + "ToWhomIWillWrite.png"
    static let writing = v5 + "WrittingButton.svg"
    static let greetings = v5 + "GreetingsAndBackgroundButton.svg"
    static let stamps = v5 + "StampsButton.svg"
    static let erase = v5 + "Erase.svg"
    static let size = v5 + "MagnifyerBig2.svg"
    static let move = v5 + "Move.svg"
    static let emoji = v5 + "Emoji.svg"
    static let enter = v5 + "Enter.svg"
    static let backspace = v5 + "Backspace.svg"
    static let close = v5 + "Close.svg"
    static let family = "https://galeli.com/MailLi.Web/Resources/familyicon.png"
    static let friends = "https://galeli.com/MailLi.Web/Resources/friends.png"
    static let staff = "https://galeli.com/MailLi.Web/Resources/staff.png"
    static let emojiTabs: [(String, String)] = [
        ("Smilies", v5 + "Smilies.svg"), ("People", v5 + "People.svg"), ("Food", v5 + "Food.svg"),
        ("Objects", v5 + "Objects.svg"), ("Travel", v5 + "Travel.svg"), ("Symbols", "https://galeli.com/mailli.web/resources/v5/Symbols.svg"),
    ]
}

/// Downloads and keeps pictures (PNG or SVG) by URL; views redraw when one arrives.
@MainActor
final class ImageCache: ObservableObject {
    static let shared = ImageCache()
    @Published private(set) var images: [URL: NSImage] = [:]
    private var loading: Set<URL> = []

    func image(_ s: String?) -> NSImage? {
        guard let u = secureURL(s) else { return nil }
        if let i = images[u] { return i }
        if !loading.contains(u) {
            loading.insert(u)
            Task { await self.load(u) }
        }
        return nil
    }

    @discardableResult
    func load(_ u: URL) async -> NSImage? {
        if let i = images[u] { return i }
        guard let (d, r) = try? await URLSession.shared.data(from: u),
              (r as? HTTPURLResponse)?.statusCode ?? 200 == 200, let img = NSImage(data: d) else { return nil }
        images[u] = img
        return img
    }

    func preload(_ s: String?) async -> NSImage? {
        guard let u = secureURL(s) else { return nil }
        return await load(u)
    }
}

/// A server picture with a fallback SF Symbol while it loads (or if it fails).
struct PCImage: View {
    var url: String?
    var fallback: String = "photo"
    @ObservedObject private var cache = ImageCache.shared
    var body: some View {
        if let img = cache.image(url) {
            Image(nsImage: img).resizable().scaledToFit()
        } else {
            Image(systemName: fallback).resizable().scaledToFit().foregroundStyle(Kid.outline.opacity(0.6)).padding(4)
        }
    }
}

/// White pill with blue outline, icon + word – the PC app's standard button.
struct Pill: View {
    var title: String
    var icon: String? = nil          // server picture URL
    var symbol: String = "circle"    // fallback SF Symbol
    var selected = false
    var height: CGFloat = 50
    var fill = false                 // stretch to the column width
    var custom: AnyView? = nil       // own icon instead of a picture
    var trailingIcon = false         // put the icon after the word
    var action: () -> Void
    @Local private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if !trailingIcon { iconView }
                Text(title).font(Kid.font(height * 0.42, .bold)).foregroundStyle(Kid.ink)
                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.7)
                if trailingIcon { iconView }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: height)
            .background(Capsule().fill(selected ? Kid.strip : .white))
            .overlay(Capsule().stroke(Kid.outline, lineWidth: selected ? 4 : 2))
            .scaleEffect(hover ? 1.04 : 1)
            .animation(.spring(duration: 0.2), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .speaks(title)
    }

    @ViewBuilder private var iconView: some View {
        if let custom { custom }
        else if icon != nil {
            PCImage(url: icon, fallback: symbol).frame(width: height * 0.72, height: height * 0.72)
        }
    }
}

/// Green pill (send / answer).
struct GreenPill: View {
    var title: String
    var icon: String
    var height: CGFloat = 54
    var action: () -> Void
    @Local private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title).font(Kid.font(height * 0.45, .heavy)).foregroundStyle(.white)
                PCImage(url: icon, fallback: "paperplane.fill").frame(width: height * 0.6, height: height * 0.6)
                    .colorMultiply(.white)
            }
            .padding(.horizontal, 26)
            .frame(height: height)
            .background(Capsule().fill(Kid.send))
            .shadow(color: Kid.send.opacity(0.4), radius: hover ? 8 : 3, y: 2)
            .scaleEffect(hover ? 1.05 : 1)
            .animation(.spring(duration: 0.2), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .speaks(title)
    }
}

/// One step in the yellow top bar ("מייל לי" › "לשלוח מכתב" …).
struct Crumb: Identifiable {
    let id = UUID()
    var title: String
    var icon: String
    var symbol: String
    var action: (() -> Void)?
}

/// Yellow bar: breadcrumbs on the right, child's name + picture on the left.
struct TopBar: View {
    @EnvironmentObject var client: MailLiClient
    var crumbs: [Crumb]
    var onExit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(crumbs.enumerated()), id: \.element.id) { i, c in
                Button { c.action?() } label: {
                    HStack(spacing: 10) {
                        PCImage(url: c.icon, fallback: c.symbol).frame(width: 34, height: 34)
                        Text(c.title).font(Kid.font(20, .bold)).foregroundStyle(Kid.ink)
                    }
                    .padding(.horizontal, 18).frame(height: 46)
                    .background(Capsule().fill(i == crumbs.count - 1 ? .white : Color.white.opacity(0.55)))
                    .overlay(Capsule().stroke(Kid.bar, lineWidth: 3))
                }
                .buttonStyle(.plain)
                .speaks(c.title)
                .allowsHitTesting(c.action != nil)
                .padding(.leading, i == 0 ? 0 : -14)
                .zIndex(Double(crumbs.count - i))
            }
            Spacer()
            HStack(spacing: 10) {
                Text(client.studentName).font(Kid.font(22, .heavy)).foregroundStyle(Kid.ink)
                Avatar(url: client.studentSymbol, size: 38)
            }
            .padding(.horizontal, 16).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 6).fill(.white))
            .speaks(client.studentName)
            SpeechToggle().padding(.leading, 10)
            Button(action: onExit) {
                Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Kid.ink.opacity(0.45)).frame(width: 34, height: 34)
            }
            .buttonStyle(.plain).help("יציאה מהחשבון (להורים)")
        }
        .padding(.horizontal, 14)
        .frame(height: 62)
        .background(Kid.bar)
    }
}

/// Round icon-only button.
struct RoundButton: View {
    var icon: String
    var color: Color = .white
    var tint: Color = Kid.ink
    var size: CGFloat = 56
    var help: String = ""
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .heavy))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(color))
                .overlay(Circle().stroke(Kid.outline, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(help)
        .speaks(help)
    }
}

/// Person's picture (the MailLi symbol), in a white square like the PC chips.
struct Avatar: View {
    var url: String?
    var size: CGFloat
    var ring: Color? = nil
    var body: some View {
        PCImage(url: url, fallback: "face.smiling")
            .padding(size * 0.06)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.2).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: size * 0.2).stroke(ring ?? .clear, lineWidth: 4))
    }
}

/// "היום 10:30", "אתמול", or "27.09.23" like the PC.
func kidDate(_ d: Date?) -> String {
    guard let d else { return "" }
    let cal = Calendar.current
    let t = DateFormatter(); t.locale = Locale(identifier: "he_IL"); t.dateFormat = "HH:mm"
    if cal.isDateInToday(d) { return "היום " + t.string(from: d) }
    if cal.isDateInYesterday(d) { return "אתמול" }
    let f = DateFormatter(); f.locale = Locale(identifier: "he_IL"); f.dateFormat = "dd.MM.yy"
    return f.string(from: d)
}

/// Simple non-lazy grid: `count` cells in rows of `columns` (fine for small lists).
struct IndexGrid<Cell: View>: View {
    var count: Int
    var columns: Int
    var spacing: CGFloat = 10
    @ViewBuilder var cell: (Int) -> Cell

    var body: some View {
        let cols = max(columns, 1)
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(stride(from: 0, to: count, by: cols)), id: \.self) { start in
                HStack(spacing: spacing) {
                    ForEach(start..<min(start + cols, count), id: \.self) { i in cell(i) }
                    if count - start < cols {
                        ForEach(0..<(cols - (count - start)), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                }
            }
        }
    }
}

private struct PreviewingKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True while drawing offline screenshots (ImageRenderer can't draw scroll views).
    var previewing: Bool {
        get { self[PreviewingKey.self] }
        set { self[PreviewingKey.self] = newValue }
    }
}

/// ScrollView in the app; plain clipped content in offline screenshots.
struct KidScroll<Content: View>: View {
    var axis: Axis.Set = .vertical
    @ViewBuilder var content: () -> Content
    @Environment(\.previewing) private var previewing
    var body: some View {
        if previewing {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) { content().fixedSize(horizontal: axis == .horizontal, vertical: false) }
                .clipped()
        } else {
            ScrollView(axis) { content() }
        }
    }
}
