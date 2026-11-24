import SwiftUI

/// "מייל לי" start screen, like the PC: big white tiles in the middle.
struct HomeView: View {
    @EnvironmentObject var client: MailLiClient
    var go: (Screen) -> Void

    private var unread: Int { (client.boxes[.inbox] ?? []).filter { !$0.read }.count }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            HStack(spacing: 50) {
                Tile(title: "לשלוח מכתב", image: PC.writeLetter, symbol: "pencil.and.scribble") { go(.write(nil)) }
                    .keyboardShortcut("n")
                Tile(title: "לקבל מכתב", image: PC.receiveLetter, symbol: "envelope.open", badge: unread) { go(.list(.inbox)) }
            }
            Tile(title: "מכתבים ששלחתי", image: PC.sentLetters, symbol: "paperplane", small: true) { go(.list(.sent)) }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .task { try? await client.refresh(.inbox) }
    }
}

/// Big white rounded tile with a picture and a word (PC home buttons).
struct Tile: View {
    var title: String
    var image: String
    var symbol: String
    var badge = 0
    var small = false
    var action: () -> Void
    @Local private var hover = false

    var body: some View {
        let side: CGFloat = small ? 200 : 250
        Button(action: action) {
            VStack(spacing: small ? 6 : 12) {
                ZStack {
                    PCImage(url: image, fallback: symbol).frame(width: side * 0.62, height: side * 0.52)
                    if badge > 0 {
                        // The PC shows the number of new letters on the paper.
                        Text("\(badge)").font(Kid.font(side * 0.16, .heavy)).italic().foregroundStyle(.black)
                            .offset(y: -side * 0.08)
                    }
                }
                Text(title).font(Kid.font(small ? 20 : 30, .bold)).foregroundStyle(Kid.ink)
            }
            .frame(width: side, height: side * (small ? 0.7 : 1))
            .background(RoundedRectangle(cornerRadius: side * 0.1).fill(.white))
            .shadow(color: .black.opacity(hover ? 0.15 : 0.05), radius: hover ? 12 : 4, y: hover ? 6 : 2)
            .scaleEffect(hover ? 1.04 : 1)
            .animation(.spring(duration: 0.25), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .speaks(title)
    }
}

/// Letters received (or sent), laid out like the PC: three columns of cards
/// (envelope + date, "מאת:" + name, the sender's picture). Each card has a
/// circle for marking; "סימון הכל" / "ביטול בחירה" at the top, "למחוק" below.
struct ListView: View {
    @EnvironmentObject var client: MailLiClient
    var box: Mailbox
    var go: (Screen) -> Void
    @Local private var loading = false
    @Local private var error: String? = nil
    @Local private var marked: Set<Int64> = []
    @Local private var confirmDelete = false

    private var letters: [MailHeader] { client.boxes[box] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Pill(title: "חזרה", icon: PC.back, symbol: "arrow.right") { go(.home) }
                    .keyboardShortcut(.cancelAction)
                Divider().frame(height: 40).padding(.horizontal, 6)
                Pill(title: box == .inbox ? "מכתבים שקיבלתי" : "מכתבים ששלחתי",
                     icon: box == .inbox ? PC.unreadEnvelope : PC.toEnvelope, symbol: "envelope", selected: true) {}
                Pill(title: box == .inbox ? "מכתבים ששלחתי" : "מכתבים שקיבלתי",
                     icon: box == .inbox ? PC.toEnvelope : PC.unreadEnvelope, symbol: "envelope") {
                    go(.list(box == .inbox ? .sent : .inbox))
                }
                Spacer()
                if !letters.isEmpty {
                    Pill(title: "סימון הכל", height: 44) { marked = Set(letters.map(\.id)) }
                    Pill(title: "ביטול בחירה", icon: PC.selectAll, symbol: "checkmark.circle", height: 44) { marked = [] }
                        .disabled(marked.isEmpty).opacity(marked.isEmpty ? 0.45 : 1)
                }
                RoundButton(icon: "arrow.clockwise", size: 46, help: "רענון") { Task { await reload() } }
                    .rotationEffect(.degrees(loading ? 360 : 0))
                    .animation(loading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: loading)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(Kid.strip)

            content.padding(.horizontal, 24).padding(.top, 20)

            if !marked.isEmpty {
                HStack {
                    Pill(title: marked.count == 1 ? "למחוק מכתב אחד" : "למחוק \(marked.count) מכתבים",
                         icon: PC.trash, symbol: "trash") { confirmDelete = true }
                        .keyboardShortcut(.delete, modifiers: [])
                }
                .padding(.vertical, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.25), value: marked.isEmpty)
        .task(id: box) { marked = []; await reload() }
        .confirmationDialog(marked.count == 1 ? "למחוק את המכתב?" : "למחוק \(marked.count) מכתבים?",
                            isPresented: $confirmDelete) {
            Button("מחיקה", role: .destructive) { Task { await deleteMarked() } }
            Button("ביטול", role: .cancel) {}
        }
    }

    @ViewBuilder private var content: some View {
        if letters.isEmpty {
            VStack(spacing: 14) {
                Spacer()
                if loading { ProgressView().controlSize(.large) }
                else if let e = error { Text(e).font(Kid.font(22)).foregroundStyle(.red) }
                else {
                    PCImage(url: box == .inbox ? PC.receiveLetter : PC.sentLetters, fallback: "tray").frame(width: 120, height: 100).opacity(0.6)
                    Text(box == .inbox ? "עוד אין מכתבים" : "עוד לא שלחת מכתבים").font(Kid.font(28)).foregroundStyle(Kid.ink.opacity(0.7))
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            GeometryReader { geo in
                KidScroll {
                    let list = letters
                    IndexGrid(count: list.count, columns: max(1, min(4, Int((geo.size.width - 8) / 330))), spacing: 16) { i in
                        let h = list[i]
                        EnvelopeCard(header: h, box: box, marked: marked.contains(h.id),
                                     mark: { if marked.contains(h.id) { marked.remove(h.id) } else { marked.insert(h.id) } },
                                     action: { go(.read(h, box)) })
                    }
                    .padding(4)
                }
            }
        }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        do { try await client.refresh(box); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func deleteMarked() async {
        let ids = letters.map(\.id).filter { marked.contains($0) }
        do {
            try await client.delete(ids, in: box)
            client.boxes[box]?.removeAll { marked.contains($0.id) }
            marked = []
        } catch { self.error = error.localizedDescription }
    }
}

/// One letter card, as on the PC: envelope (closed = new) with the date under it,
/// "מאת:" and the name, the person's picture in a square, a marking circle in the corner.
struct EnvelopeCard: View {
    var header: MailHeader
    var box: Mailbox
    var marked = false
    var mark: () -> Void = {}
    var action: () -> Void
    @Local private var hover = false

    var body: some View {
        let who = box == .inbox ? header.sender : header.recipient
        let isNew = box == .inbox && !header.read
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 4) {
                    PCImage(url: box == .sent ? PC.toEnvelope : (isNew ? PC.unreadEnvelope : PC.readEnvelope), fallback: "envelope")
                        .frame(width: 70, height: 62)
                    Text(kidDate(header.time)).font(Kid.font(14, .semibold)).foregroundStyle(Kid.ink.opacity(0.8))
                        .lineLimit(1).fixedSize()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(box == .inbox ? "מאת:" : "לכבוד:").font(Kid.font(17, .heavy)).foregroundStyle(Kid.outline)
                    Text(who?.name ?? "").font(Kid.font(20, .heavy)).foregroundStyle(Kid.ink)
                        .lineLimit(2).minimumScaleFactor(0.8)
                    if isNew {
                        Text("חדש!").font(Kid.font(14, .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(.red))
                    }
                }
                Spacer(minLength: 4)
                PCImage(url: who?.symbolURL, fallback: "face.smiling")
                    .padding(6)
                    .frame(width: 74, height: 74)
                    .overlay(Rectangle().stroke(Kid.outline, lineWidth: 1))
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 6).fill(isNew ? Color(hex: "#FFFFF7D6")! : .white))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(marked ? Kid.outline : .clear, lineWidth: 3))
            .overlay(alignment: .topLeading) {
                Button(action: mark) {
                    Image(systemName: marked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(marked ? Color.white : Kid.outline, Kid.outline)
                        .background(Circle().fill(.white).padding(2))
                        .frame(width: 34, height: 34).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(marked ? "ביטול סימון" : "סימון")
            }
            .shadow(color: .black.opacity(hover ? 0.15 : 0.04), radius: hover ? 8 : 2, y: hover ? 4 : 1)
            .scaleEffect(hover ? 1.02 : 1)
            .animation(.spring(duration: 0.2), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .speaks((box == .inbox ? "מכתב מ" : "מכתב ל") + ((box == .inbox ? header.sender : header.recipient)?.name ?? "")
                + (box == .inbox && !header.read ? ". מכתב חדש" : ""))
    }
}
