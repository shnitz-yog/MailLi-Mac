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
    }
}

/// Letters received (or sent) as envelopes.
struct ListView: View {
    @EnvironmentObject var client: MailLiClient
    var box: Mailbox
    var go: (Screen) -> Void
    @Local private var loading = false
    @Local private var error: String? = nil

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
                RoundButton(icon: "arrow.clockwise", size: 46, help: "רענון") { Task { await reload() } }
                    .rotationEffect(.degrees(loading ? 360 : 0))
                    .animation(loading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: loading)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(Kid.strip)

            content.padding(24)
        }
        .task(id: box) { await reload() }
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
                    IndexGrid(count: list.count, columns: max(1, Int((geo.size.width - 8) / 230)), spacing: 18) { i in
                        EnvelopeCard(header: list[i], box: box) { go(.read(list[i], box)) }
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
}

/// One letter: envelope picture (closed = new), who, and the date.
struct EnvelopeCard: View {
    var header: MailHeader
    var box: Mailbox
    var action: () -> Void
    @Local private var hover = false

    var body: some View {
        let who = box == .inbox ? header.sender : header.recipient
        let isNew = box == .inbox && !header.read
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack(alignment: .topLeading) {
                    PCImage(url: box == .sent ? PC.toEnvelope : (isNew ? PC.unreadEnvelope : PC.readEnvelope), fallback: "envelope")
                        .frame(height: 96)
                        .frame(maxWidth: .infinity)
                    if isNew {
                        Text("חדש!").font(Kid.font(16, .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(.red)).rotationEffect(.degrees(-8))
                    }
                }
                HStack(spacing: 8) {
                    Avatar(url: who?.symbolURL, size: 40)
                    Text(who?.name ?? "").font(Kid.font(21, .heavy)).foregroundStyle(Kid.ink).lineLimit(1)
                }
                .padding(.horizontal, 10).frame(height: 50)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Kid.chipLine, lineWidth: 2))
                Text(kidDate(header.time)).font(Kid.font(16, .medium)).foregroundStyle(Kid.ink.opacity(0.7))
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 22).fill(isNew ? Color(hex: "#FFFFF7D6")! : .white))
            .shadow(color: .black.opacity(hover ? 0.15 : 0.05), radius: hover ? 10 : 3, y: hover ? 5 : 1)
            .scaleEffect(hover ? 1.03 : 1)
            .animation(.spring(duration: 0.2), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
