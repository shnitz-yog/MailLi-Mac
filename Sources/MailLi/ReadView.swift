import SwiftUI

/// Reading a letter, laid out like the PC:
/// strip with "מאת:" (sender + date) and "חזרה"; the letter; "לענות" / "למחוק" beside it;
/// "למכתב הקודם" / "למכתב הבא" under it.
struct ReadView: View {
    @EnvironmentObject var client: MailLiClient
    var header: MailHeader
    var box: Mailbox
    var go: (Screen) -> Void
    var preloaded: LetterContent? = nil   // for offline screenshots
    @Local private var content: LetterContent? = nil
    @Local private var error: String? = nil
    @Local private var confirmDelete = false

    private var siblings: [MailHeader] { client.boxes[box] ?? [] }
    private var index: Int? { siblings.firstIndex { $0.id == header.id } }

    var body: some View {
        let who = box == .inbox ? header.sender : header.recipient
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Pill(title: "חזרה", icon: PC.back, symbol: "arrow.right") { go(.list(box)) }
                    .keyboardShortcut(.cancelAction)
                Divider().frame(height: 40).padding(.horizontal, 6)
                VStack(spacing: 2) {
                    PCImage(url: box == .inbox ? PC.unreadEnvelope : PC.toEnvelope, fallback: "envelope").frame(width: 50, height: 38)
                    Text(kidDate(header.time)).font(Kid.font(14, .semibold)).foregroundStyle(Kid.ink)
                }
                Text(box == .inbox ? "מאת:" : "לכבוד:").font(Kid.font(26, .heavy)).foregroundStyle(Kid.ink)
                PersonChip(name: who?.name ?? "", image: who?.symbolURL)
                Spacer()
            }
            .padding(.horizontal, 24).padding(.vertical, 10)
            .background(Kid.strip)

            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 14) {
                    Group {
                        if let c = content ?? preloaded {
                            LetterView(content: c, stamps: client.stamps)
                        } else if let e = error {
                            Text(e).font(Kid.font(22)).foregroundStyle(.red).frame(maxHeight: .infinity)
                        } else {
                            ProgressView().controlSize(.large).frame(maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    HStack(spacing: 20) {
                        Pill(title: "למכתב הקודם", symbol: "chevron.right", height: 44,
                             custom: AnyView(Text("→").font(Kid.font(24, .heavy)).foregroundStyle(Kid.outline))) { step(-1) }
                            .disabled((index ?? 0) <= 0).opacity((index ?? 0) <= 0 ? 0.4 : 1)
                        Pill(title: "למכתב הבא", symbol: "chevron.left", height: 44,
                             custom: AnyView(Text("←").font(Kid.font(24, .heavy)).foregroundStyle(Kid.outline)),
                             trailingIcon: true) { step(1) }
                            .disabled(index == nil || index! >= siblings.count - 1)
                            .opacity(index == nil || index! >= siblings.count - 1 ? 0.4 : 1)
                    }
                }
                VStack(spacing: 14) {
                    if box == .inbox, let s = header.sender {
                        GreenPill(title: "לענות", icon: PC.reply) { go(.write(s)) }
                    }
                    Spacer()
                    Pill(title: "למחוק", icon: PC.trash, symbol: "trash", fill: true) { confirmDelete = true }
                    Pill(title: "להדפיס", icon: PC.print, symbol: "printer", fill: true) {
                        guard let c = content ?? preloaded else { return }
                        Task { if let img = await renderLetter(c, stamps: client.stamps, scale: 3) { printLetter(img) } }
                    }
                    .keyboardShortcut("p", modifiers: .command)
                    .disabled(content == nil && preloaded == nil)
                }
                .frame(width: 170)
                .padding(.vertical, 6)
            }
            .padding(22)
        }
        .task {
            do {
                content = try await client.message(header.id, in: box)
                if box == .inbox { client.markRead(header.id) }
            } catch { self.error = error.localizedDescription }
        }
        .confirmationDialog("למחוק את המכתב?", isPresented: $confirmDelete) {
            Button("מחיקה", role: .destructive) {
                Task {
                    do {
                        try await client.delete(header.id, in: box)
                        client.boxes[box]?.removeAll { $0.id == header.id }
                        go(.list(box))
                    } catch { self.error = error.localizedDescription }
                }
            }
            Button("ביטול", role: .cancel) {}
        }
    }

    private func step(_ d: Int) {
        guard let i = index, siblings.indices.contains(i + d) else { return }
        go(.read(siblings[i + d], box))
    }
}

/// White rectangle with a person's picture and name (PC "מאת:" / "לכבוד:" chip).
struct PersonChip: View {
    var name: String
    var image: String?
    var onRemove: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: 10) {
            Avatar(url: image, size: 40)
            Text(name).font(Kid.font(22, .heavy)).foregroundStyle(Kid.ink).lineLimit(1)
        }
        .padding(.horizontal, 14).frame(height: 54)
        .speaks(name)
        .background(RoundedRectangle(cornerRadius: 4).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Kid.chipLine, lineWidth: 2))
        .overlay(alignment: .topLeading) {
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(.white, Kid.outline)
                }
                .buttonStyle(.plain).offset(x: -8, y: -8)
            }
        }
    }
}
