import SwiftUI
import AppKit

/// `MailLi --screens <samples dir>`: draw each screen from saved server replies
/// into PNG files (for reviewing the design without logging in). Downloads the
/// PC app's public pictures first so they show up.
@MainActor
enum ScreenShots {
    static func run(_ dir: String) -> Int32 {
        let client = MailLiClient()
        func load(_ f: String) -> XMLElement? {
            guard let d = FileManager.default.contents(atPath: dir + "/" + f), let doc = try? XMLDocument(data: d) else { return nil }
            return doc.rootElement()
        }
        client.studentName = "דנה"
        if let r = load("startup_googale.xml") { client.applyLabels(r) }
        if let r = load("GetMailABAndStamps.xml") { client.applyAddressBook(r) }
        if let r = load("GetLast100EmailsV5.xml") {
            var hs = MailLiClient.parseHeaders(r)
            for i in hs.indices where i < 2 { hs[i].read = false }
            client.boxes[.inbox] = hs
        }
        if let r = load("GetSentdMailHeadersV5.xml") { client.boxes[.sent] = MailLiClient.parseHeaders(r) }
        func letter(_ f: String) -> LetterContent? {
            guard let r = load(f)?.first("Body")?.elementChildren.first,
                  let b64 = r.first("CompressedBody")?.stringValue, let raw = Data(base64Encoded: b64),
                  let x = Zlib.inflate(raw), let s = String(data: x, encoding: .utf8) else { return nil }
            return LetterContent.parse(xml: s)
        }
        let withGreeting = letter("GetmailMessage.xml")
        let plain = letter("GetmailMessage_inbox0.xml")

        // Fetch pictures used on these screens (public PC assets + people + greeting).
        var urls: [String] = [PC.writeLetter, PC.receiveLetter, PC.sentLetters, PC.mailLi, PC.writeCrumb, PC.receiveCrumb,
                              PC.readCrumb, PC.sentCrumb, PC.unreadEnvelope, PC.readEnvelope, PC.toEnvelope, PC.toIcon,
                              PC.back, PC.reply, PC.trash, PC.send, PC.toWhom, PC.writing, PC.greetings, PC.stamps,
                              PC.erase, PC.size, PC.move, PC.emoji, PC.enter, PC.backspace, PC.family, PC.friends, PC.staff,
                              PC.sentOK, PC.print, PC.selectAll, PC.tellIcon] + PC.emojiTabs.map(\.1)
        urls += client.contacts.map(\.imageURL)
        urls += (client.boxes[.inbox] ?? []).compactMap { $0.sender?.symbolURL }
        urls += client.backgrounds.prefix(8).map(\.url)
        urls += client.backgrounds.map(\.icon)
        if let b = withGreeting?.backgroundURL { urls.append(b) }
        var done = false
        Task {
            await withTaskGroup(of: Void.self) { g in
                for u in Set(urls) { g.addTask { _ = await ImageCache.shared.preload(u) } }
            }
            done = true
        }
        let deadline = Date().addingTimeInterval(60)
        while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }

        let out = NSTemporaryDirectory()
        func shot<V: View>(_ name: String, _ crumbs: [Crumb], _ v: V, _ sz: CGSize = CGSize(width: 1240, height: 800)) {
            let view = ZStack { Kid.page; VStack(spacing: 0) { TopBar(crumbs: crumbs, onExit: {}); v } }
                .frame(width: sz.width, height: sz.height)
                .environmentObject(client)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.colorScheme, .light)
                .environment(\.previewing, true)
            let r = ImageRenderer(content: view)
            r.scale = 1
            if let img = r.nsImage, let t = img.tiffRepresentation, let rep = NSBitmapImageRep(data: t),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: out + "screen_" + name + ".png"))
                print(out + "screen_" + name + ".png")
            }
        }
        let home = Crumb(title: "מייל לי", icon: PC.mailLi, symbol: "envelope.fill", action: {})
        let recv = Crumb(title: "לקבל מכתב", icon: PC.receiveCrumb, symbol: "envelope.open", action: {})
        shot("home", [home], HomeView(go: { _ in }))
        shot("list", [home, recv], ListView(box: .inbox, go: { _ in }))
        if let h = client.boxes[.inbox]?.first {
            shot("read", [home, recv, Crumb(title: "מכתב שקיבלתי", icon: PC.readCrumb, symbol: "envelope", action: nil)],
                 ReadView(header: h, box: .inbox, go: { _ in }, preloaded: plain ?? withGreeting))
            shot("read_greeting", [home, recv], ReadView(header: h, box: .inbox, go: { _ in }, preloaded: withGreeting))
        }
        let write = Crumb(title: "לשלוח מכתב", icon: PC.writeCrumb, symbol: "pencil", action: nil)
        shot("write", [home, write], WriteView(replyTo: client.boxes[.inbox]?.first?.sender, close: { _ in }))
        shot("write_small", [home, write], WriteView(replyTo: client.boxes[.inbox]?.first?.sender, close: { _ in }),
             CGSize(width: 1000, height: 680))
        shot("stamps", [home, write], StampsPanel(colorCode: 1, add: { _ in }).frame(height: 132).background(Kid.strip),
             CGSize(width: 1240, height: 220))
        shot("write_empty", [home, write], WriteView(replyTo: nil, close: { _ in }))
        shot("picker", [home, write], RecipientPicker(selected: .constant([]), done: {}))
        shot("sent", [home, write], SendingOverlay(sent: true))
        shot("greetings", [home, write], GreetingsPicker(selected: .constant(nil), done: {}))
        let some = Array(client.contacts.filter { $0.group == "חברים בגן" }.prefix(5).map(\.id))
        shot("picker_kids", [home, write], PickerAt(selected: some))
        return 0
    }
}

/// Picker opened on the kindergarten children tab (for screenshots).
private struct PickerAt: View {
    @Local var selected: [UUID]
    init(selected: [UUID]) { _selected = Local(wrappedValue: selected) }
    var body: some View { RecipientPicker(selected: $selected, done: {}, startTab: 2) }
}
