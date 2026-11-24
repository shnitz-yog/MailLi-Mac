import SwiftUI

/// Logical page size of a MailLi letter (stamps are positioned in these units).
/// Matches the 732×444 picture the Windows app sends to parents.
let letterSize = CGSize(width: 732, height: 444)
let letterTopMargin: CGFloat = 10

/// Where the greeting picture sits: top centre at its natural size (as on the PC),
/// shrunk only if it doesn't fit. Returns nil when there is no picture yet.
func greetingRect(_ img: NSImage?) -> CGRect? {
    guard let img, img.size.width > 0, img.size.height > 0 else { return nil }
    var w = img.size.width, h = img.size.height
    let maxW = letterSize.width * 0.9, maxH = letterSize.height * 0.55
    let k = min(1, maxW / w, maxH / h)
    w *= k; h *= k
    return CGRect(x: (letterSize.width - w) / 2, y: letterTopMargin, width: w, height: h)
}

/// Top of the text area in letter units: below the greeting picture, if any.
func textTop(_ img: NSImage?) -> CGFloat {
    (greetingRect(img)?.maxY ?? 8) + 12
}

/// White page with the greeting picture at the top (letter units scaled by k).
struct LetterBackground: View {
    var url: String?
    var image: NSImage? = nil
    var k: CGFloat
    @ObservedObject private var cache = ImageCache.shared
    var body: some View {
        let img = image ?? cache.image(url)
        ZStack(alignment: .topLeading) {
            Color.white
            if let img, let r = greetingRect(img) {
                Image(nsImage: img).resizable()
                    .frame(width: r.width * k, height: r.height * k)
                    .offset(x: r.minX * k, y: r.minY * k)
            }
        }
        .frame(width: letterSize.width * k, height: letterSize.height * k, alignment: .topLeading)
    }
}

/// Draws one stamp so that it fits exactly in its own frame (for placing as a view).
struct PlacedStampView: View {
    var shape: StampShape
    var stamp: PlacedStamp
    var scale: CGFloat

    /// Where this stamp sits on the page, in screen points.
    static func rect(_ shape: StampShape, _ s: PlacedStamp, _ scale: CGFloat) -> CGRect {
        CGRect(origin: .zero, size: shape.size).applying(s.transform)
            .applying(CGAffineTransform(scaleX: scale, y: scale))
    }

    var body: some View {
        let r = Self.rect(shape, stamp, scale)
        Canvas { ctx, _ in
            let t = stamp.transform
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: -r.minX, y: -r.minY))
            let p = shape.path.applying(t)
            let color = Color(hex: stamp.color) ?? shape.fillColor ?? .blue
            if shape.hasFill || !shape.hasStroke { ctx.fill(p, with: .color(color)) }
            if shape.hasStroke { ctx.stroke(p, with: .color(color), lineWidth: shape.strokeWidth * abs(t.a)) }
        }
        .frame(width: max(r.width, 1), height: max(r.height, 1))
    }
}

/// Read-only letter: page, greeting picture, text, stamps. Fits the space it gets.
/// `export` draws it flat for the picture sent to parents.
struct LetterView: View {
    var content: LetterContent
    @ObservedObject var stamps: StampLibrary
    var backgroundImage: NSImage? = nil
    var export = false
    @ObservedObject private var cache = ImageCache.shared

    var body: some View {
        GeometryReader { geo in
            let k = min(geo.size.width / letterSize.width, geo.size.height / letterSize.height)
            page(k)
                .frame(width: letterSize.width * k, height: letterSize.height * k)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(letterSize.width / letterSize.height, contentMode: .fit)
        .environment(\.layoutDirection, .leftToRight)
    }

    @ViewBuilder private func page(_ k: CGFloat) -> some View {
        let bg = backgroundImage ?? cache.image(content.backgroundURL)
        let body = ZStack(alignment: .topLeading) {
            LetterBackground(url: content.backgroundURL, image: bg, k: k)
            // Stamps under the words, so they never hide what was written.
            ForEach(content.stamps) { s in
                if let shape = stamps.shape(s.url) {
                    let r = PlacedStampView.rect(shape, s, k)
                    PlacedStampView(shape: shape, stamp: s, scale: k).offset(x: r.minX, y: r.minY)
                }
            }
            textLayer(k, top: textTop(content.backgroundURL == nil ? nil : bg))
        }
        .frame(width: letterSize.width * k, height: letterSize.height * k, alignment: .topLeading)
        .clipped()
        if export {
            body
        } else {
            body
                .overlay(Rectangle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                .compositingGroup()
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
    }

    private func textLayer(_ k: CGFloat, top: CGFloat) -> some View {
        var a = AttributedString()
        for r in content.runs {
            var piece = AttributedString(r.text)
            piece.foregroundColor = r.color
            piece.font = .system(size: r.size * k, weight: .semibold, design: .rounded)
            a += piece
        }
        return Text(a)
            .multilineTextAlignment(.leading)                       // leading = right in Hebrew
            .frame(width: (letterSize.width - 50) * k, alignment: .topLeading)
            .environment(\.layoutDirection, .rightToLeft)
            .padding(.top, top * k)
            .padding(.leading, 25 * k)
            .allowsHitTesting(false)
    }
}

/// Stamp preview for buttons.
struct StampThumb: View {
    var url: String
    var color: Color
    @ObservedObject var stamps: StampLibrary
    var body: some View {
        Canvas { ctx, size in
            guard let s = stamps.shape(url), s.size.width > 0, s.size.height > 0 else { return }
            let k = min(size.width / s.size.width, size.height / s.size.height) * 0.8
            let t = CGAffineTransform(scaleX: k, y: k)
                .concatenating(CGAffineTransform(translationX: (size.width - s.size.width * k) / 2,
                                                 y: (size.height - s.size.height * k) / 2))
            let p = s.path.applying(t)
            if s.hasFill || !s.hasStroke { ctx.fill(p, with: .color(color)) }
            if s.hasStroke { ctx.stroke(p, with: .color(color), lineWidth: max(s.strokeWidth * k, 1)) }
        }
    }
}

/// The letter as a flat picture (for e-mailing to parents and for printing).
@MainActor
func renderLetter(_ content: LetterContent, stamps: StampLibrary, scale: CGFloat = 1) async -> NSImage? {
    let bg = await ImageCache.shared.preload(content.backgroundURL)
    let view = LetterView(content: content, stamps: stamps, backgroundImage: bg, export: true)
        .frame(width: letterSize.width, height: letterSize.height)
        .environment(\.layoutDirection, .rightToLeft)
    let r = ImageRenderer(content: view)
    r.scale = scale
    return r.nsImage
}

/// "להדפיס": the macOS print window with the letter fitted to a landscape page.
@MainActor
func printLetter(_ img: NSImage) {
    let v = NSImageView(frame: NSRect(x: 0, y: 0, width: letterSize.width, height: letterSize.height))
    v.image = img
    v.imageScaling = .scaleProportionallyUpOrDown
    let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
    info.orientation = .landscape
    info.horizontalPagination = .fit
    info.verticalPagination = .fit
    info.isHorizontallyCentered = true
    info.isVerticallyCentered = true
    let op = NSPrintOperation(view: v, printInfo: info)
    op.jobTitle = "מכתב ממייל לי"
    op.run()
}
