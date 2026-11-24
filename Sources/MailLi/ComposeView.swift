import SwiftUI

/// Which tool is active – the PC app's tool column.
enum Tool: Equatable {
    case write, greetings, stamps, color, erase, size, move
}

/// Writing a letter, laid out like the PC app:
/// strip "לכבוד:" + recipients + green "שליחה"; the letter; tools column beside it;
/// the active tool's panel at the bottom (Hebrew keyboard for writing).
struct WriteView: View {
    @EnvironmentObject var client: MailLiClient
    var replyTo: MailAddress? = nil
    var close: (_ sent: Bool) -> Void

    @Local private var selected: [UUID] = []
    @Local private var text = ""
    @Local private var colorCode = 1
    @Local private var sizeCode = 3
    @Local private var background: String? = nil
    @Local private var stamps: [PlacedStamp] = []
    @Local private var tool: Tool = .write
    @Local private var emoji = false
    @Local private var picking = false
    @Local private var sending = false
    @Local private var sent = false
    @Local private var hint: String? = nil
    @Local private var error: String? = nil
    @ObservedObject private var cache = ImageCache.shared

    private var color: Color { KidStyle.color(colorCode) }
    private var chosen: [Contact] { selected.compactMap { id in client.contacts.first { $0.id == id } } }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                strip
                HStack(alignment: .top, spacing: 18) {
                    EditableLetter(text: $text, color: color, fontSize: KidStyle.size(sizeCode),
                                   background: background, stamps: $stamps, lib: client.stamps,
                                   tool: tool, stampTapped: stampTapped)
                    ToolColumn(tool: $tool, emoji: $emoji)
                        .frame(width: 190)
                }
                .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 10)
                .frame(maxHeight: .infinity)
                bottomPanel
                    .frame(height: 132)
                    .padding(.horizontal, 22).padding(.bottom, 14)
            }
            .disabled(sending || sent)

            if picking {
                RecipientPicker(selected: $selected, done: { picking = false })
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            if sending || sent { SendingOverlay(sent: sent) }
        }
        .animation(.easeInOut(duration: 0.2), value: picking)
        .onAppear {
            preselect()
            if selected.isEmpty { picking = true }   // first: who do I write to?
        }
        .alert("המכתב לא נשלח", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("אישור", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    // MARK: strip

    private var strip: some View {
        HStack(spacing: 12) {
            Pill(title: "חזרה", icon: PC.back, symbol: "arrow.right") { close(false) }
                .keyboardShortcut(.cancelAction)
            Divider().frame(height: 40).padding(.horizontal, 4)
            PCImage(url: PC.toIcon, fallback: "envelope").frame(width: 50, height: 40)
            Text("לכבוד:").font(Kid.font(26, .heavy)).foregroundStyle(Kid.ink)
            ForEach(chosen.prefix(4)) { c in
                PersonChip(name: c.name, image: c.imageURL) { selected.removeAll { $0 == c.id } }
            }
            if chosen.count > 4 {
                Text("+\(chosen.count - 4)").font(Kid.font(22, .heavy)).foregroundStyle(Kid.ink)
            }
            Button { picking = true } label: {
                Image(systemName: chosen.isEmpty ? "person.crop.circle.badge.plus" : "plus")
                    .font(.system(size: 24, weight: .bold)).foregroundStyle(Kid.outline)
                    .frame(width: 54, height: 54)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Kid.chipLine, style: StrokeStyle(lineWidth: 2, dash: [5])))
            }
            .buttonStyle(.plain).help("למי לשלוח?")
            Spacer()
            if let h = hint {
                Text(h).font(Kid.font(19, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Color.orange))
                    .transition(.scale.combined(with: .opacity))
            }
            GreenPill(title: "שליחה", icon: PC.send) { Task { await send() } }
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 22).padding(.vertical, 10)
        .background(Kid.strip)
        .animation(.spring(duration: 0.3), value: hint)
    }

    // MARK: bottom panel for the active tool

    @ViewBuilder private var bottomPanel: some View {
        Group {
            switch tool {
            case .write:
                if emoji {
                    EmojiPanel(insert: { text += $0 }, back: { emoji = false })
                } else {
                    HebrewKeyboard(text: $text, emoji: { emoji = true })
                }
            case .greetings:
                GreetingsPanel(selected: $background)
            case .stamps:
                StampsPanel(colorCode: colorCode, add: addStamp)
            case .color:
                ColorPanel(colorCode: $colorCode)
            case .size:
                SizePanel(sizeCode: $sizeCode)
            case .erase:
                HintPanel(icon: PC.erase, text: "לוחצים על חותמת כדי למחוק אותה") {
                    Pill(title: "למחוק את כל החותמות", icon: PC.trash, symbol: "trash", height: 46) { stamps.removeAll() }
                    Pill(title: "למחוק את כל הכתב", icon: PC.erase, symbol: "eraser", height: 46) { text = "" }
                }
            case .move:
                HintPanel(icon: PC.move, text: "גוררים חותמת עם העכבר כדי להזיז אותה") { EmptyView() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(Kid.strip.opacity(0.9)))
    }

    // MARK: actions

    private func stampTapped(_ id: UUID) {
        guard let i = stamps.firstIndex(where: { $0.id == id }) else { return }
        switch tool {
        case .erase: stamps.remove(at: i)
        case .size:
            // 2 → 3 → 4 → 5 → 2 (around the stamp's centre)
            var t = stamps[i].transform
            let old = t.a
            let new: CGFloat = old >= 5 ? 2 : old + 1
            let s = client.stamps.shape(stamps[i].url)?.size ?? CGSize(width: 10, height: 10)
            t.tx -= s.width * (new - old) / 2; t.ty -= s.height * (new - old) / 2
            t.a = new; t.d = new
            stamps[i].transform = t
        case .color: stamps[i].color = KidStyle.colors.first { $0.code == colorCode }?.hex ?? stamps[i].color
        default: break
        }
    }

    private func preselect() {
        guard let r = replyTo, selected.isEmpty else { return }
        if let c = client.contacts.first(where: { $0.address.address == r.address && $0.address.addressType == r.addressType })
            ?? client.contacts.first(where: { $0.name == r.name }) {
            selected = [c.id]
        }
    }

    private func addStamp(_ url: String) {
        let size = client.stamps.shape(url)?.size ?? CGSize(width: 10, height: 10)
        let k: CGFloat = 3
        let top = textTop(background == nil ? nil : cache.image(background))
        let maxX = max(41, letterSize.width - 40 - size.width * k)
        let minY = min(top + 40, letterSize.height - 80)
        let maxY = max(minY + 1, letterSize.height - 20 - size.height * k)
        stamps.append(PlacedStamp(url: url, color: KidStyle.colors.first { $0.code == colorCode }?.hex ?? "#FF2566AE",
                                  transform: CGAffineTransform(a: k, b: 0, c: 0, d: k,
                                                               tx: .random(in: 40...maxX), ty: .random(in: minY...maxY))))
    }

    private func show(_ h: String) {
        hint = h
        Task { try? await Task.sleep(for: .seconds(2.5)); if hint == h { hint = nil } }
    }

    private func letter() -> LetterContent {
        let lines = text.components(separatedBy: "\n")
        let runs = lines.enumerated().map { i, l in
            TextRun(text: l + (i < lines.count - 1 ? "\n" : ""), color: color, size: KidStyle.size(sizeCode))
        }
        return LetterContent(runs: runs, stamps: stamps, backgroundURL: background)
    }

    private func send() async {
        if chosen.isEmpty { picking = true; return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && stamps.isEmpty && background == nil {
            show("המכתב עוד ריק ✏️"); return
        }
        sending = true
        let picture = await renderPNG()
        var failed: [String] = []
        for t in chosen {
            do {
                try await client.send(to: t.address, text: text, colorCode: colorCode, sizeCode: sizeCode,
                                      stamps: stamps, backgroundURL: background, image: picture)
            } catch {
                failed.append("\(t.name): \(error.localizedDescription)")
            }
        }
        sending = false
        if failed.isEmpty {
            sent = true
            try? await Task.sleep(for: .seconds(2.2))
            close(true)
        } else {
            error = failed.joined(separator: "\n")
        }
    }

    /// Picture of the letter (the server e-mails it to parents), like the Windows app.
    private func renderPNG() async -> Data? {
        let bg = await cache.preload(background)
        let view = LetterView(content: letter(), stamps: client.stamps, backgroundImage: bg, export: true)
            .frame(width: letterSize.width, height: letterSize.height)
            .environment(\.layoutDirection, .rightToLeft)
        let r = ImageRenderer(content: view)
        r.scale = 1
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

// MARK: - The letter you type on

struct EditableLetter: View {
    @Binding var text: String
    var color: Color
    var fontSize: CGFloat
    var background: String?
    @Binding var stamps: [PlacedStamp]
    @ObservedObject var lib: StampLibrary
    var tool: Tool
    var stampTapped: (UUID) -> Void
    @FocusState private var focused: Bool
    @ObservedObject private var cache = ImageCache.shared

    var body: some View {
        GeometryReader { geo in
            let k = min(geo.size.width / letterSize.width, geo.size.height / letterSize.height)
            page(k).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { focused = true }
        .onChange(of: tool) { if tool == .write { focused = true } }
    }

    private func page(_ k: CGFloat) -> some View {
        let top = textTop(background == nil ? nil : cache.image(background))
        return ZStack(alignment: .topLeading) {
            LetterBackground(url: background, k: k)
                .onTapGesture { focused = true }
            TextEditor(text: $text)
                .font(.system(size: fontSize * k, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .multilineTextAlignment(.leading)                   // leading = right in Hebrew
                .environment(\.layoutDirection, .rightToLeft)
                .focused($focused)
                .frame(width: (letterSize.width - 50) * k, height: max(40, (letterSize.height - top - 10)) * k)
                .offset(x: 25 * k, y: top * k)
            if text.isEmpty {
                Text("כאן כותבים ✏️")
                    .font(.system(size: fontSize * k, weight: .semibold, design: .rounded))
                    .foregroundStyle(color.opacity(0.3))
                    .frame(width: (letterSize.width - 60) * k, alignment: .leading)
                    .environment(\.layoutDirection, .rightToLeft)
                    .offset(x: 25 * k, y: top * k)
                    .allowsHitTesting(false)
            }
            ForEach($stamps) { $s in
                if let shape = lib.shape(s.url) {
                    DraggableStamp(shape: shape, stamp: $s, scale: k, tool: tool) { stampTapped(s.id) }
                }
            }
        }
        .frame(width: letterSize.width * k, height: letterSize.height * k, alignment: .topLeading)
        .clipped()
        .overlay(Rectangle().stroke(Kid.outline.opacity(0.5), lineWidth: 2))
        .compositingGroup()
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// A stamp on the letter: drag to move; a tap does what the active tool says.
struct DraggableStamp: View {
    var shape: StampShape
    @Binding var stamp: PlacedStamp
    var scale: CGFloat
    var tool: Tool
    var tapped: () -> Void
    @Local private var drag: CGSize = .zero
    @Local private var hover = false

    var body: some View {
        let r = PlacedStampView.rect(shape, stamp, scale)
        let active = [Tool.erase, .size, .color, .move].contains(tool)
        PlacedStampView(shape: shape, stamp: stamp, scale: scale)
            .padding(6)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 8)
                .stroke(Kid.outline.opacity(hover || active ? 0.6 : 0), style: StrokeStyle(lineWidth: 2, dash: [5])))
            .scaleEffect(drag == .zero ? 1 : 1.1)
            .offset(x: r.minX - 6 + drag.width, y: r.minY - 6 + drag.height)
            .onHover { hover = $0 }
            .gesture(DragGesture(minimumDistance: 3)
                .onChanged { drag = $0.translation }
                .onEnded { v in
                    stamp.transform.tx += v.translation.width / scale
                    stamp.transform.ty += v.translation.height / scale
                    drag = .zero
                })
            .onTapGesture(perform: tapped)
    }
}

// MARK: - Tool column (PC: כתיבה · ברכות ורקעים · חותמות[צבע, מחק, גודל, הזזה])

struct ToolColumn: View {
    @Binding var tool: Tool
    @Binding var emoji: Bool
    var body: some View {
        VStack(spacing: 12) {
            Pill(title: "כתיבה", icon: PC.writing, symbol: "character", selected: tool == .write, height: 54, fill: true) { tool = .write; emoji = false }
            Pill(title: "ברכות ורקעים", icon: PC.greetings, symbol: "photo", selected: tool == .greetings, height: 54, fill: true) { tool = .greetings }
            VStack(spacing: 8) {
                Pill(title: "חותמות", icon: PC.stamps, symbol: "seal", selected: tool == .stamps, height: 54, fill: true) { tool = .stamps }
                Pill(title: "צבע", selected: tool == .color, height: 42, fill: true, custom: AnyView(colorDot)) { tool = .color }
                Pill(title: "מחק", icon: PC.erase, symbol: "eraser", selected: tool == .erase, height: 42, fill: true) { tool = .erase }
                Pill(title: "גודל", icon: PC.size, symbol: "plus.magnifyingglass", selected: tool == .size, height: 42, fill: true) { tool = .size }
                Pill(title: "הזזה", icon: PC.move, symbol: "cursorarrow.motionlines", selected: tool == .move, height: 42, fill: true) { tool = .move }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16).fill(Kid.toolBox))
            Spacer(minLength: 0)
        }
    }
    private var colorDot: some View {
        HStack(spacing: -6) {
            ForEach(["#FFE53935", "#FFFDD835", "#FF43A047", "#FF2566AE"], id: \.self) { Circle().fill(Color(hex: $0)!).frame(width: 14, height: 14) }
        }
    }
}

// MARK: - Bottom panels

/// On-screen Hebrew keyboard, same rows as the PC app.
struct HebrewKeyboard: View {
    @Binding var text: String
    var emoji: () -> Void
    private let row1 = ["א","ב","ג","ד","ה","ו","ז","ח","ט","י","כ","ל","מ","נ","ס","ע","פ","צ","ק","ר","ש","ת","ך","ם","ן","ף","ץ"]
    private let marks = ["?", "!", ",", ".", "-"]
    private let digits = ["9","8","7","6","5","4","3","2","1","0"]
    private let gap: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let n = CGFloat(row1.count)
            let unit = (geo.size.width - gap * (n - 1)) / n
            let h = (geo.size.height - 8) / 2
            // Row 2 uses the same key width; the space bar takes what is left.
            let others: CGFloat = 1.4 * 3 + CGFloat(marks.count + digits.count)
            let spaceW = geo.size.width - unit * others - gap * CGFloat(marks.count + digits.count + 3)
            VStack(spacing: 8) {
                HStack(spacing: gap) {
                    ForEach(row1, id: \.self) { ch in Key(label: ch, width: unit, height: h) { text += ch } }
                }
                HStack(spacing: gap) {
                    Key(image: PC.enter, symbol: "return", width: unit * 1.4, height: h) { text += "\n" }
                    Key(image: PC.backspace, symbol: "delete.right", width: unit * 1.4, height: h) { if !text.isEmpty { text.removeLast() } }
                    ForEach(marks, id: \.self) { ch in Key(label: ch, width: unit, height: h) { text += ch } }
                    Key(label: "רווח", width: max(unit, spaceW), height: h) { text += " " }
                    ForEach(digits, id: \.self) { ch in Key(label: ch, width: unit, height: h) { text += ch } }
                    Key(image: PC.emoji, symbol: "face.smiling", width: unit * 1.4, height: h, action: emoji)
                }
            }
        }
        .padding(10)
        .environment(\.layoutDirection, .rightToLeft)
    }
}

struct Key: View {
    var label: String? = nil
    var image: String? = nil
    var symbol: String = "questionmark"
    var width: CGFloat
    var height: CGFloat
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Group {
                if let label { Text(label).font(Kid.font(label.count > 1 ? 18 : min(26, height * 0.5), .semibold)).foregroundStyle(Kid.ink) }
                else { PCImage(url: image, fallback: symbol).frame(width: min(30, width * 0.6), height: min(24, height * 0.5)) }
            }
            .frame(width: width, height: height)
            .background(Rectangle().fill(.white))
            .overlay(Rectangle().stroke(Kid.keyLine, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Emoji in the PC's categories.
struct EmojiPanel: View {
    var insert: (String) -> Void
    var back: () -> Void
    @Local private var tab = 0
    static let sets: [[String]] = [
        ["😀","😃","😄","😁","😆","😊","🙂","😍","🥰","😘","😜","🤪","😎","🤩","🥳","😇","🤗","🤭","😮","😢","😭","😡","🥺","😴","🤒","🤔"],
        ["👍","👏","🙌","👋","✌️","🤞","💪","🙏","👶","👦","👧","👨","👩","👴","👵","🧑‍🚀","👮","👷","🧙","🧚","🦸","🤴","👸","💃","🕺","👨‍👩‍👧"],
        ["🍎","🍌","🍉","🍇","🍓","🍒","🍑","🥕","🌽","🍕","🍔","🍟","🌭","🍿","🧁","🍰","🎂","🍩","🍪","🍫","🍬","🍭","🍦","🥛","🍯","🥞"],
        ["🎈","🎁","🎉","🧸","⚽","🏀","🎨","🖍️","✏️","📚","🎒","🎵","🎸","🥁","🧩","🪁","🎮","📷","⏰","💡","🔑","🧲","🛝","🪀","🎀","🏆"],
        ["🚗","🚌","🚓","🚑","🚒","🚜","🚲","🛴","🚂","✈️","🚁","🚀","⛵","🚢","🏠","🏫","🏥","🏖️","🏕️","🌈","☀️","🌙","⭐","☁️","❄️","🌊"],
        ["❤️","🧡","💛","💚","💙","💜","🤍","💖","💕","✨","⭐","🌟","💫","✔️","❌","❓","❗","➕","💯","🔴","🟢","🔵","🟡","🔶","🔷","🇮🇱"],
    ]
    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(0..<PC.emojiTabs.count, id: \.self) { i in
                        Button { tab = i } label: {
                            PCImage(url: PC.emojiTabs[i].1, fallback: "face.smiling").frame(width: 26, height: 26)
                                .frame(width: 40, height: 36)
                                .background(RoundedRectangle(cornerRadius: 8).fill(tab == i ? Kid.outline.opacity(0.25) : .white))
                        }.buttonStyle(.plain)
                    }
                }
                Pill(title: "חזרה למקלדת", height: 40, action: back)
            }
            KidScroll(axis: .horizontal) {
                let set = Self.sets[tab]
                let half = (set.count + 1) / 2
                VStack(alignment: .leading, spacing: 4) {
                    ForEach([0, 1], id: \.self) { row in
                        HStack(spacing: 4) {
                            ForEach(Array(set.enumerated()).filter { (row == 0) == ($0.offset < half) }, id: \.offset) { _, e in
                                Button { insert(e) } label: {
                                    Text(e).font(.system(size: 34)).frame(width: 52, height: 52)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(.white))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
    }
}

/// Greeting pictures / backgrounds from the server.
struct GreetingsPanel: View {
    @EnvironmentObject var client: MailLiClient
    @Binding var selected: String?
    var body: some View {
        KidScroll(axis: .horizontal) {
            HStack(spacing: 10) {
                Button { selected = nil } label: {
                    Text("בלי ברכה").font(Kid.font(18, .bold)).foregroundStyle(Kid.ink)
                        .frame(width: 150, height: 96)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.white))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected == nil ? Kid.send : .clear, lineWidth: 4))
                }.buttonStyle(.plain)
                ForEach(client.backgrounds) { b in
                    Button { selected = b.url } label: {
                        PCImage(url: b.url, fallback: "photo").padding(6)
                            .frame(width: 180, height: 96)
                            .background(RoundedRectangle(cornerRadius: 10).fill(.white))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected == b.url ? Kid.send : .clear, lineWidth: 4))
                    }.buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }
}

struct StampsPanel: View {
    @EnvironmentObject var client: MailLiClient
    var colorCode: Int
    var add: (String) -> Void
    var body: some View {
        KidScroll(axis: .horizontal) {
            let all = client.stampChoices
            let half = (all.count + 1) / 2
            VStack(alignment: .leading, spacing: 8) {
                ForEach([0, 1], id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(Array(all.enumerated()).filter { (row == 0) == ($0.offset < half) }, id: \.offset) { _, s in
                            Button { add(s.url) } label: {
                                StampThumb(url: s.url, color: KidStyle.color(colorCode), stamps: client.stamps)
                                    .frame(width: 50, height: 50)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(.white))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(10)
        }
    }
}

struct ColorPanel: View {
    @Binding var colorCode: Int
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                ForEach(KidStyle.colors, id: \.code) { c in
                    Button { colorCode = c.code } label: {
                        Circle().fill(Color(hex: c.hex) ?? .black).frame(width: 52, height: 52)
                            .overlay(Circle().stroke(.white, lineWidth: 4))
                            .overlay(Circle().stroke(Kid.ink, lineWidth: colorCode == c.code ? 4 : 0).padding(-5))
                    }.buttonStyle(.plain).help(c.name)
                }
            }
            Text("הצבע של הכתב ושל החותמות החדשות. לוחצים על חותמת כדי לצבוע אותה.")
                .font(Kid.font(16, .semibold)).foregroundStyle(Kid.ink.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SizePanel: View {
    @Binding var sizeCode: Int
    var body: some View {
        HStack(spacing: 24) {
            Text("גודל הכתב:").font(Kid.font(22, .bold)).foregroundStyle(Kid.ink)
            ForEach([(2, 22.0), (3, 32.0), (4, 44.0)], id: \.0) { code, pt in
                Button { sizeCode = code } label: {
                    Text("א").font(Kid.font(pt, .heavy)).foregroundStyle(sizeCode == code ? .white : Kid.ink)
                        .frame(width: 76, height: 76)
                        .background(RoundedRectangle(cornerRadius: 16).fill(sizeCode == code ? Kid.ink : .white))
                }.buttonStyle(.plain)
            }
            Divider().frame(height: 60)
            Text("לוחצים על חותמת כדי להגדיל אותה").font(Kid.font(18, .semibold)).foregroundStyle(Kid.ink.opacity(0.75))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HintPanel<Extra: View>: View {
    var icon: String
    var text: String
    @ViewBuilder var extra: () -> Extra
    var body: some View {
        HStack(spacing: 20) {
            PCImage(url: icon, fallback: "hand.tap").frame(width: 60, height: 60)
            Text(text).font(Kid.font(24, .bold)).foregroundStyle(Kid.ink)
            extra()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Who gets the letter (opens first, like the PC "למי אכתוב?")

struct RecipientPicker: View {
    @EnvironmentObject var client: MailLiClient
    @Binding var selected: [UUID]
    var done: () -> Void
    @Local private var tab = 0

    private let tabs: [(String, String, String, [String])] = [
        ("המשפחה שלי", PC.family, "house.fill", ["משפחה"]),
        ("הגננת והצוות", PC.staff, "person.2.fill", ["הגננת", "צוות הגן"]),
        ("החברים בגן", PC.friends, "face.smiling.fill", ["חברים בגן", "חברים"]),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea().onTapGesture(perform: done)
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    PCImage(url: PC.toWhom, fallback: "person.fill.questionmark").frame(width: 56, height: 56)
                    Text("למי אכתוב?").font(Kid.font(36, .heavy)).foregroundStyle(Kid.ink)
                    Spacer()
                    GreenPill(title: selected.isEmpty ? "סגירה" : "סיום", icon: PC.send, action: done)
                        .keyboardShortcut(.defaultAction)
                }
                HStack(spacing: 14) {
                    ForEach(0..<tabs.count, id: \.self) { i in
                        Pill(title: tabs[i].0, icon: tabs[i].1, symbol: tabs[i].2, selected: tab == i, height: 60) { tab = i }
                    }
                    Spacer()
                }
                let people = client.contacts.filter { tabs[tab].3.contains($0.group) }
                KidScroll {
                    IndexGrid(count: people.count, columns: 6, spacing: 12) { i in
                        let c = people[i]
                        let on = selected.contains(c.id)
                        Button {
                            if on { selected.removeAll { $0 == c.id } } else { selected.append(c.id) }
                        } label: {
                            VStack(spacing: 6) {
                                Avatar(url: c.imageURL, size: 78, ring: on ? Kid.send : nil)
                                    .overlay(alignment: .bottomTrailing) {
                                        if on {
                                            Image(systemName: "checkmark.circle.fill").font(.system(size: 28))
                                                .foregroundStyle(.white, Kid.send).offset(x: 6, y: 6)
                                        }
                                    }
                                Text(c.name).font(Kid.font(18, .bold)).foregroundStyle(Kid.ink)
                                    .lineLimit(2).multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 16).fill(on ? Kid.send.opacity(0.15) : .white))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(4)
                }
            }
            .padding(26)
            .frame(maxWidth: 1000, maxHeight: 640)
            .background(RoundedRectangle(cornerRadius: 28).fill(Kid.strip))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Kid.outline, lineWidth: 3))
            .padding(30)
        }
    }
}

// MARK: - "Sent!" (PC: girl with thumbs up, "המכתב נשלח בהצלחה")

struct SendingOverlay: View {
    var sent: Bool
    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 16) {
                if sent {
                    PCImage(url: PC.sentOK, fallback: "hand.thumbsup.fill").frame(width: 360, height: 260)
                    Text("המכתב נשלח בהצלחה!").font(Kid.font(40, .heavy)).foregroundStyle(Kid.ink)
                } else {
                    PCImage(url: PC.sentLetters, fallback: "envelope.fill").frame(width: 180, height: 150)
                    Text("שולחים…").font(Kid.font(40, .heavy)).foregroundStyle(Kid.ink)
                    ProgressView().controlSize(.large)
                }
            }
            .padding(44)
            .background(RoundedRectangle(cornerRadius: 36).fill(.white))
            .shadow(radius: 20)
        }
    }
}
