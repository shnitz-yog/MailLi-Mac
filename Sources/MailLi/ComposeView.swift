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

            if tool == .greetings {
                GreetingsPicker(selected: $background, done: { tool = .write })
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            if picking {
                RecipientPicker(selected: $selected, done: { picking = false })
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            if sending || sent { SendingOverlay(sent: sent) }
        }
        .animation(.easeInOut(duration: 0.2), value: picking)
        .animation(.easeInOut(duration: 0.2), value: tool)
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
            if chosen.isEmpty {
                // PC: "למי אכתוב?" ‑‑‑‑▶ "לא נבחרו נמענים"
                Button { picking = true } label: {
                    HStack(spacing: 8) {
                        PCImage(url: PC.toWhom, fallback: "person.fill.questionmark").frame(width: 30, height: 30)
                        Text("למי אכתוב?").font(Kid.font(22, .heavy)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16).frame(height: 46)
                    .background(Capsule().fill(Kid.outline))
                }
                .buttonStyle(.plain)
                .speaks("לְמִי אֶכְתֹּב?")
                HStack(spacing: 0) {
                    Text("‑ ‑ ‑ ‑ ‑ ‑").font(Kid.font(20, .heavy)).foregroundStyle(Kid.outline)
                    Image(systemName: "arrowtriangle.left.fill").font(.system(size: 16)).foregroundStyle(Kid.outline)
                }
                Text("לא נבחרו נמענים").font(Kid.font(30, .heavy)).foregroundStyle(Kid.ink)
            } else {
                PCImage(url: PC.toIcon, fallback: "envelope").frame(width: 50, height: 40)
                Text("לכבוד:").font(Kid.font(26, .heavy)).foregroundStyle(Kid.ink)
                RecipientChips(chosen: chosen, remove: { id in selected.removeAll { $0 == id } })
                Button { picking = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold)).foregroundStyle(Kid.outline)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(.white))
                        .overlay(Circle().stroke(Kid.chipLine, style: StrokeStyle(lineWidth: 2, dash: [5])))
                }
                .buttonStyle(.plain).help("להוסיף נמענים")
            }
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
            case .write, .greetings:
                if emoji {
                    EmojiPanel(insert: { text += $0 }, back: { emoji = false })
                } else {
                    HebrewKeyboard(text: $text, emoji: { emoji = true })
                }
            case .stamps:
                StampsPanel(colorCode: colorCode, add: addStamp, emoji: { tool = .write; emoji = true })
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
        guard let img = await renderLetter(letter(), stamps: client.stamps), let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
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
            // Stamps under the words (as on the PC); while a stamp tool is on,
            // the text lets clicks through to them.
            ForEach($stamps) { $s in
                if let shape = lib.shape(s.url) {
                    DraggableStamp(shape: shape, stamp: $s, scale: k, tool: tool) { stampTapped(s.id) }
                }
            }
            editor(k, top: top)
                .allowsHitTesting(tool == .write || tool == .greetings)
            if text.isEmpty {
                Text("כאן כותבים ✏️")
                    .font(.system(size: fontSize * k, weight: .semibold, design: .rounded))
                    .foregroundStyle(color.opacity(0.3))
                    .frame(width: (letterSize.width - 60) * k, alignment: .leading)
                    .environment(\.layoutDirection, .rightToLeft)
                    .offset(x: 25 * k, y: top * k)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: letterSize.width * k, height: letterSize.height * k, alignment: .topLeading)
        .clipped()
        .overlay(Rectangle().stroke(Kid.outline.opacity(0.5), lineWidth: 2))
        .compositingGroup()
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .environment(\.layoutDirection, .leftToRight)
    }

    @Environment(\.previewing) private var previewing

    @ViewBuilder private func editor(_ k: CGFloat, top: CGFloat) -> some View {
        let font = Font.system(size: fontSize * k, weight: .semibold, design: .rounded)
        Group {
            if previewing {   // ImageRenderer can't draw the real text box
                Text(text).font(font).foregroundStyle(color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                TextEditor(text: $text)
                    .font(font)
                    .foregroundStyle(color)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .multilineTextAlignment(.leading)                   // leading = right in Hebrew
                    .focused($focused)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .frame(width: (letterSize.width - 50) * k, height: max(40, (letterSize.height - top - 10)) * k)
        .offset(x: 25 * k, y: top * k)
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
                    Key(image: PC.enter, symbol: "return", spoken: "שׁוּרָה חֲדָשָׁה", width: unit * 1.4, height: h) { text += "\n" }
                    Key(image: PC.backspace, symbol: "delete.right", spoken: "מְחִיקָה", width: unit * 1.4, height: h) { if !text.isEmpty { text.removeLast() } }
                    ForEach(marks, id: \.self) { ch in Key(label: ch, width: unit, height: h) { text += ch } }
                    Key(label: "רווח", width: max(unit, spaceW), height: h) { text += " " }
                    ForEach(digits, id: \.self) { ch in Key(label: ch, width: unit, height: h) { text += ch } }
                    Key(label: "😊", width: unit * 1.4, height: h, action: emoji).help("אימוג'י")
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
    var spoken: String? = nil
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
        .speaks(spoken ?? Speaker.keyName(label ?? ""))
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

/// PC "ברכות ורקעים" window: tabs on top, round pictures with their Hebrew names.
struct GreetingsPicker: View {
    @EnvironmentObject var client: MailLiClient
    @Binding var selected: String?
    var done: () -> Void
    @Local private var tab = 0

    private var tabs: [(String, String, Int)] {
        var t: [(String, String, Int)] = [("ברכות", PC.greetings, 0)]
        if client.backgrounds.contains(where: { $0.group == 1 }) { t.append(("רציתי לספר", PC.tellIcon, 1)) }
        return t
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea().onTapGesture(perform: done)
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: done) {
                        HStack(spacing: 6) {
                            Text("סגירה").font(Kid.font(20, .bold)).foregroundStyle(Kid.ink)
                            Image(systemName: "xmark").font(.system(size: 18, weight: .heavy)).foregroundStyle(Kid.outline)
                        }
                    }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                }
                .padding(.bottom, 8)
                VStack(spacing: 0) {
                    HStack(spacing: 40) {
                        ForEach(0..<tabs.count, id: \.self) { i in
                            Button { tab = i } label: {
                                VStack(spacing: 6) {
                                    PCImage(url: tabs[i].1, fallback: "gift").padding(14)
                                        .frame(width: 76, height: 76)
                                        .background(Circle().fill(.white))
                                        .overlay(Circle().stroke(tab == i ? Kid.ink : .clear, lineWidth: 2))
                                    Text(tabs[i].0).font(Kid.font(22, tab == i ? .heavy : .bold)).foregroundStyle(Kid.ink)
                                }
                            }
                            .buttonStyle(.plain)
                            .speaks(tabs[i].0)
                        }
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Kid.strip)
                    let group = tabs.indices.contains(tab) ? tabs[tab].2 : 0
                    let list = client.backgrounds.filter { $0.group == group }
                    GeometryReader { geo in
                        KidScroll {
                            IndexGrid(count: list.count + 1, columns: max(3, Int((geo.size.width - 20) / 118)), spacing: 12) { i in
                                if i == 0 {
                                    cell(title: "בלי ברכה", icon: nil, on: selected == nil) { selected = nil; done() }
                                } else {
                                    let b = list[i - 1]
                                    cell(title: b.title.isEmpty ? b.name : b.title, icon: b.icon, fallbackURL: b.url,
                                         on: selected == b.url) { selected = b.url; done() }
                                }
                            }
                            .padding(16)
                        }
                    }
                    .background(.white)
                }
                .background(RoundedRectangle(cornerRadius: 18).fill(.white))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Kid.strip, lineWidth: 6))
            }
            .padding(24)
            .frame(maxWidth: 1060, maxHeight: 700)
            .background(RoundedRectangle(cornerRadius: 24).fill(.white))
            .padding(24)
        }
    }

    private func cell(title: String, icon: String?, fallbackURL: String? = nil, on: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Group {
                    if let icon {
                        GreetingIcon(icon: icon, fallback: fallbackURL)
                    } else {
                        Image(systemName: "nosign").font(.system(size: 34)).foregroundStyle(Kid.outline)
                    }
                }
                .frame(width: 80, height: 80)
                Text(title).font(Kid.font(15, .bold)).foregroundStyle(Kid.ink)
                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
                    .frame(height: 36)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Kid.strip.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? Kid.send : .clear, lineWidth: 4))
        }
        .buttonStyle(.plain)
        .speaks(title)
    }
}

/// Round greeting button picture; if the server has none, the greeting itself.
struct GreetingIcon: View {
    var icon: String
    var fallback: String?
    @ObservedObject private var cache = ImageCache.shared
    var body: some View {
        if let i = cache.image(icon) {
            Image(nsImage: i).resizable().scaledToFit()
        } else {
            PCImage(url: fallback, fallback: "gift").padding(6)
                .background(Circle().fill(.white)).clipShape(Circle())
        }
    }
}

struct StampsPanel: View {
    @EnvironmentObject var client: MailLiClient
    var colorCode: Int
    var add: (String) -> Void
    var emoji: () -> Void = {}
    var body: some View {
        GeometryReader { geo in
            let all = client.stampChoices
            let cols = max(1, (all.count + 1) / 2)
            let spacing: CGFloat = 8
            let emojiW: CGFloat = 110
            // Stamps fill the panel's width (two rows), not bunched to one side.
            let cell = max(40, min(64, (geo.size.width - emojiW - 40 - spacing * CGFloat(cols - 1)) / CGFloat(cols),
                                   (geo.size.height - 20 - spacing) / 2))
            HStack(spacing: 14) {
                Button(action: emoji) {
                    VStack(spacing: 4) {
                        Text("😊").font(.system(size: 40))
                        Text("אימוג'י").font(Kid.font(18, .bold)).foregroundStyle(Kid.ink)
                    }
                    .frame(width: emojiW, height: cell * 2 + spacing)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Kid.outline, lineWidth: 2))
                }
                .buttonStyle(.plain).help("להוסיף אימוג'י למכתב")
                .speaks("אִימוֹגִ'י")
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach([0, 1], id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(Array(all.enumerated()).filter { (row == 0) == ($0.offset < cols) }, id: \.offset) { _, s in
                                Button { add(s.url) } label: {
                                    StampThumb(url: s.url, color: KidStyle.color(colorCode), stamps: client.stamps)
                                        .frame(width: cell, height: cell)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(.white))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(10)
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
                    }.buttonStyle(.plain).help(c.name).speaks(c.name)
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

/// "לכבוד:" chips: the first few people, then "+N" (as on the PC).
struct RecipientChips: View {
    var chosen: [Contact]
    var remove: (UUID) -> Void
    var max = 3
    var body: some View {
        ForEach(chosen.prefix(max)) { c in
            PersonChip(name: c.name, image: c.imageURL) { remove(c.id) }
        }
        if chosen.count > max {
            Text("+\(chosen.count - max)").font(Kid.font(20, .bold)).foregroundStyle(Kid.ink)
                .frame(width: 50, height: 50)
                .background(Circle().fill(.white))
                .overlay(Circle().stroke(Kid.chipLine, lineWidth: 2))
        }
    }
}

/// PC recipient screen: "לכבוד:" strip with the chosen people and a green "המשך";
/// folder tabs per group; "סימון כל …" to take a whole group; cards with a circle.
struct RecipientPicker: View {
    @EnvironmentObject var client: MailLiClient
    @Binding var selected: [UUID]
    var done: () -> Void
    var startTab = 0
    @Local private var tab = -1

    private static let allTabs: [(String, String, String, [String])] = [
        ("המשפחה שלי", PC.family, "house.fill", ["משפחה"]),
        ("הגננת והצוות", PC.staff, "person.2.fill", ["הגננת", "צוות הגן"]),
        ("ילדי הגן", PC.friends, "face.smiling.fill", ["חברים בגן"]),
        ("ידידי הגן", PC.friends, "person.3.fill", ["חברים"]),
    ]
    private var tabs: [(String, String, String, [String])] {
        Self.allTabs.filter { t in client.contacts.contains { t.3.contains($0.group) } }
    }
    private var chosen: [Contact] { selected.compactMap { id in client.contacts.first { $0.id == id } } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                PCImage(url: PC.toIcon, fallback: "envelope").frame(width: 50, height: 40)
                Text("לכבוד:").font(Kid.font(26, .heavy)).foregroundStyle(Kid.ink)
                if chosen.isEmpty {
                    Text("בוחרים למטה למי לכתוב").font(Kid.font(22, .semibold)).foregroundStyle(Kid.ink.opacity(0.6))
                } else {
                    RecipientChips(chosen: chosen, remove: { id in selected.removeAll { $0 == id } }, max: 4)
                }
                Spacer()
                GreenPill(title: chosen.isEmpty ? "סגירה" : "המשך", icon: PC.send, action: done)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22).padding(.vertical, 10)
            .frame(minHeight: 74)
            .background(Kid.strip)

            let t = tabs
            let want = tab < 0 ? startTab : tab
            let cur = t.indices.contains(want) ? want : 0
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(0..<t.count, id: \.self) { i in
                        Button { tab = i } label: {
                            HStack(spacing: 12) {
                                PCImage(url: t[i].1, fallback: t[i].2).frame(width: 64, height: 54)
                                Text(t[i].0).font(Kid.font(24, i == cur ? .heavy : .bold)).foregroundStyle(Kid.ink)
                            }
                            .padding(.horizontal, 20).frame(height: i == cur ? 82 : 74)
                            .frame(maxWidth: 300)
                            .background(UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10).fill(.white))
                            .overlay(UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10)
                                        .stroke(Kid.outline, lineWidth: i == cur ? 3 : 1.5))
                            .overlay(alignment: .topTrailing) {
                                Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: 26, y: 0)); p.addLine(to: CGPoint(x: 0, y: 26)) }
                                    .fill(Kid.outline).frame(width: 26, height: 26)
                                    .environment(\.layoutDirection, .leftToRight)
                            }
                        }
                        .buttonStyle(.plain)
                        .speaks(t[i].0)
                        .zIndex(i == cur ? 1 : 0)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 30)

                let people = t.isEmpty ? [] : client.contacts.filter { t[cur].3.contains($0.group) }
                // "Select all" takes the real people, not the family shortcuts (they'd send twice).
                let real = people.filter { $0.address.addressType != "SMTPAlias" }
                let allOn = !real.isEmpty && real.allSatisfy { selected.contains($0.id) }
                VStack(alignment: .leading, spacing: 14) {
                    if real.count > 1 {
                        Button {
                            if allOn { selected.removeAll { id in real.contains { $0.id == id } } }
                            else { for c in real where !selected.contains(c.id) { selected.append(c.id) } }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: allOn ? "checkmark.circle.fill" : "person.3.fill")
                                    .font(.system(size: 24)).foregroundStyle(Kid.outline)
                                Text(allOn ? "ביטול הסימון" : "סימון כל " + t[cur].0.replacingOccurrences(of: " שלי", with: ""))
                                    .font(Kid.font(22, .heavy)).foregroundStyle(Kid.ink)
                            }
                            .padding(.horizontal, 26).frame(height: 54)
                            .background(Capsule().fill(.white))
                            .overlay(Capsule().stroke(Kid.chipLine, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .speaks(allOn ? "ביטול הסימון" : "סימון כל " + t[cur].0.replacingOccurrences(of: " שלי", with: ""))
                    }
                    GeometryReader { geo in
                        KidScroll {
                            IndexGrid(count: people.count, columns: max(2, min(5, Int(geo.size.width / 230))), spacing: 12) { i in
                                PersonCard(contact: people[i], on: selected.contains(people[i].id)) {
                                    let id = people[i].id
                                    if selected.contains(id) { selected.removeAll { $0 == id } } else { selected.append(id) }
                                }
                            }
                            .padding(4)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Rectangle().fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Kid.outline, lineWidth: 3))
                .padding(.horizontal, 26).padding(.bottom, 22)
                .offset(y: -1.5)
            }
            .padding(.top, 18)
            .background(Color.white)
        }
        .background(Color.white)
    }
}

/// One person in the picker: name, picture, circle (filled when chosen).
struct PersonCard: View {
    var contact: Contact
    var on: Bool
    var action: () -> Void
    @Local private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(contact.name).font(Kid.font(22, .heavy)).foregroundStyle(Kid.ink)
                    .lineLimit(2).minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                PCImage(url: contact.imageURL, fallback: "face.smiling").frame(width: 62, height: 62)
            }
            .padding(.leading, 14).padding(.trailing, 30).frame(height: 84)
            .background(RoundedRectangle(cornerRadius: 4).fill(on ? Kid.strip : .white))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Kid.chipLine, lineWidth: on ? 2.5 : 1.5))
            .overlay(alignment: .topTrailing) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(on ? Color.white : Kid.outline, Kid.outline)
                    .padding(6)
            }
            .scaleEffect(hover ? 1.02 : 1).animation(.spring(duration: 0.2), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .speaks(contact.name)
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
