import Foundation
import SwiftUI
import AppKit

/// `MailLi --selftest <samples dir>`: decode saved server replies offline and
/// print a summary (no names/texts are printed), then round-trip a built letter.
@MainActor
enum SelfTest {
    static func run(_ dir: String) -> Int32 {
        var ok = true
        func check(_ c: Bool, _ msg: String) { print((c ? "PASS " : "FAIL ") + msg); if !c { ok = false } }
        let lib = StampLibrary()
        var contents: [(String, LetterContent)] = []
        defer {
            // Render the sample letters (without background pictures, which load async).
            for (f, c) in contents {
                var c2 = c; c2.backgroundURL = nil
                let r = ImageRenderer(content: LetterView(content: c2, stamps: lib).frame(width: 752))
                r.scale = 1
                if let img = r.nsImage, let tiff = img.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                    let out = NSTemporaryDirectory() + "render_" + f.replacingOccurrences(of: ".xml", with: ".png")
                    try? png.write(to: URL(fileURLWithPath: out)); print("rendered " + out)
                }
            }
        }

        for f in ["GetmailMessage_inbox0.xml", "GetmailMessage.xml", "GetSentMailMessage.xml"] {
            guard let d = FileManager.default.contents(atPath: dir + "/" + f),
                  let doc = try? XMLDocument(data: d), let r = doc.rootElement()?.first("Body")?.elementChildren.first
            else { check(false, "\(f): read"); continue }
            guard let b64 = r.first("CompressedBody")?.stringValue, let raw = Data(base64Encoded: b64),
                  let xml = Zlib.inflate(raw), let s = String(data: xml, encoding: .utf8)
            else { check(false, "\(f): inflate"); continue }
            let c = LetterContent.parse(xml: s)
            check(!c.runs.isEmpty, "\(f): \(c.runs.count) text runs, \(c.plainText.count) chars, \(c.stamps.count) stamps, bg=\(c.backgroundURL != nil)")
            contents.append((f, c))
        }

        if let d = FileManager.default.contents(atPath: dir + "/GetMailABAndStamps.xml"),
           let doc = try? XMLDocument(data: d), let r = doc.rootElement() {
            var parsed = 0
            let all = r.all("StampDescription")
            for s in all {
                if let u = s.text("URL"), let x = s.text("XAML") { lib.add(url: u, xaml: x); if lib.shapes[lib.key(u)] != nil { parsed += 1 } }
            }
            check(parsed == all.count && parsed > 0, "stamps parsed \(parsed)/\(all.count)")
            check(!r.all("BK").isEmpty, "backgrounds: \(r.all("BK").count)")
            let empty = lib.shapes.values.filter { $0.path.boundingRect.isEmpty }.count
            check(empty == 0, "stamps with empty geometry: \(empty)")
        }

        for f in ["GetLast100EmailsV5.xml", "GetSentdMailHeadersV5.xml"] {
            if let d = FileManager.default.contents(atPath: dir + "/" + f), let doc = try? XMLDocument(data: d),
               let r = doc.rootElement() {
                let hs = r.all("MailHeaderV5")
                let withTime = hs.filter { Dates.parse(($0.kid("Header")?.first("Header") ?? $0.kid("Header"))?.attr("Time")) != nil }.count
                let withSender = hs.filter { $0.kid("Header")?.first("Sender") != nil }.count
                check(!hs.isEmpty && withTime == hs.count, "\(f): \(hs.count) headers, \(withTime) dated, \(withSender) with sender")
            }
        }

        // Round trip: build → compress → inflate → parse
        let stamp = PlacedStamp(url: "http://galeli.com/MailLi.Web/Resources/Stamps/S05.xaml", color: "#ff3dabde",
                                matrix: "2.5,0,107.4075,0,2.5,258.6975,0,0,1")
        let x = LetterContent.buildXML(text: "שלום אמא\nשורה 2 & <בדיקה>", colorCode: 3, sizeCode: 4, stamps: [stamp],
                                       backgroundURL: "http://galeli.com/MailLi.Web/Resources/Backgrounds/MailLi-Congrats.png")
        let back = Zlib.inflate(Zlib.deflate(Data(x.utf8))).flatMap { String(data: $0, encoding: .utf8) }
        check(back == x, "zlib round trip")
        let c = LetterContent.parse(xml: back ?? "")
        check(c.plainText == "שלום אמא\nשורה 2 & <בדיקה>", "text round trip")
        check(c.stamps.first?.matrixString == "2.5,0,107.407,0,2.5,258.698,0,0,1" || c.stamps.first?.transform.tx ?? 0 > 107,
              "stamp matrix round trip: \(c.stamps.first?.matrixString ?? "-")")
        check(c.backgroundURL?.hasSuffix("MailLi-Congrats.png") == true, "background round trip")
        // Python's zlib must accept our stream too (checked by caller); write it out.
        try? Zlib.deflate(Data(x.utf8)).write(to: URL(fileURLWithPath: NSTemporaryDirectory() + "mailli_selftest.z"))
        print("zlib file: " + NSTemporaryDirectory() + "mailli_selftest.z")
        return ok ? 0 : 1
    }
}
