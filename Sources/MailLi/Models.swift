import Foundation
import SwiftUI

struct MailAddress: Hashable {
    var address: String
    var addressType: String   // e.g. SingleMailLiReciepient, PrivateABSMTPAddress, SMTPAlias
    var aliasType: String     // e.g. SingleReciepient, AllFamilyMembers
    var name: String
    var studentID: Int64
    var symbolURL: String

    /// V5 headers use numeric enum values in attributes.
    static let addressTypes = ["SingleMailLiReciepient", "SingleSMTPReciepient", "MailLiAlias", "SMTPAlias",
                               "PrivateABSMTPAddress", "PrivateABMailLiAddress"]

    init(address: String, addressType: String, aliasType: String, name: String, studentID: Int64, symbolURL: String) {
        self.address = address; self.addressType = addressType; self.aliasType = aliasType
        self.name = name; self.studentID = studentID; self.symbolURL = symbolURL
    }

    /// From a <Sender .../> or <Reciepient .../> element (attributes).
    init(attrs e: XMLElement) {
        address = e.attr("Address") ?? ""
        let t = Int(e.attr("AddressType") ?? "") ?? 0
        addressType = t < Self.addressTypes.count ? Self.addressTypes[t] : "SingleMailLiReciepient"
        aliasType = e.attr("AliasType") ?? "0"
        name = (e.attr("Name") ?? "").trimmingCharacters(in: .whitespaces)
        studentID = Int64(e.attr("StudentID") ?? "") ?? 0
        symbolURL = e.attr("SymbolURL") ?? ""
    }

    /// From a <a:From> / <a:To> element (child elements).
    init(elements e: XMLElement) {
        address = e.text("Address") ?? ""
        addressType = e.text("AddressType") ?? "SingleMailLiReciepient"
        aliasType = e.text("AliasType") ?? "SingleReciepient"
        name = (e.text("Name") ?? "").trimmingCharacters(in: .whitespaces)
        studentID = Int64(e.text("StudentID") ?? "") ?? 0
        symbolURL = e.text("SymbolURL") ?? ""
    }

    var soapXML: String {
        "<a:Address>\(xmlEscape(address))</a:Address>" +
        "<a:AddressType>\(addressType)</a:AddressType>" +
        "<a:AliasType>\(aliasType)</a:AliasType>" +
        "<a:Name>\(xmlEscape(name))</a:Name>" +
        "<a:StudentID>\(studentID)</a:StudentID>" +
        "<a:SymbolURL>\(xmlEscape(symbolURL))</a:SymbolURL>"
    }
}

struct MailHeader: Identifiable, Hashable {
    let id: Int64
    var time: Date?
    var read: Bool
    var sender: MailAddress?
    var recipient: MailAddress?
}

enum Mailbox: String, CaseIterable, Identifiable {
    case inbox = "דואר נכנס"
    case sent = "דואר יוצא"
    var id: String { rawValue }
    var icon: String { self == .inbox ? "tray" : "paperplane" }
}

/// One person / group the child can write to.
struct Contact: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var imageURL: String
    var group: String
    var address: MailAddress
}

struct BackgroundChoice: Identifiable, Hashable {
    var id: String { url }
    var name: String
    var url: String
    var group = 0          // 0 = ברכות, 1 = רציתי לספר (server order)
    var title = ""         // Hebrew name (from the app's label list)
    /// Round button picture the PC shows in the greetings picker.
    var icon: String { "https://galeli.com/mailli.web/resources/" + name + ".png" }
}

struct StampChoice: Identifiable, Hashable {
    var id: String { url }
    var url: String
    var xaml: String
}

// MARK: - Letter content

struct TextRun: Hashable {
    var text: String
    var color: Color
    var size: CGFloat
}

struct PlacedStamp: Identifiable, Hashable {
    let id = UUID()
    var url: String
    var color: String          // "#AARRGGBB"
    var transform: CGAffineTransform

    static func == (a: PlacedStamp, b: PlacedStamp) -> Bool { a.id == b.id && a.url == b.url && a.color == b.color && a.transform == b.transform }
    func hash(into h: inout Hasher) { h.combine(id) }

    /// WPF/UWP Matrix "m11,m12,offX,m21,m22,offY,0,0,1" as stored by MailLi.
    init(url: String, color: String, matrix: String) {
        self.url = url; self.color = color
        let v = matrix.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if v.count >= 6 {
            transform = CGAffineTransform(a: v[0], b: v[3], c: v[1], d: v[4], tx: v[2], ty: v[5])
        } else {
            transform = CGAffineTransform(scaleX: 2.5, y: 2.5)
        }
    }
    init(url: String, color: String, transform: CGAffineTransform) {
        self.url = url; self.color = color; self.transform = transform
    }
    var matrixString: String {
        let t = transform
        func f(_ d: CGFloat) -> String { String(Double(d)) }
        return [f(t.a), f(t.c), f(t.tx), f(t.b), f(t.d), f(t.ty), "0", "0", "1"].joined(separator: ",")
    }
}

/// Colours/sizes used by the child's text codes "/cNN" and "/sN".
/// The exact palette of the Windows app is not known; these are close guesses.
enum KidStyle {
    static let colors: [(code: Int, hex: String, name: String)] = [
        // /c01 measured from a real letter e-mailed by the Windows app; the rest are guesses.
        (1, "#FF1C458F", "כחול כהה"), (2, "#FFE53935", "אדום"), (3, "#FF2566AE", "כחול"),
        (4, "#FF43A047", "ירוק"), (5, "#FFFB8C00", "כתום"), (6, "#FF8E24AA", "סגול"),
        (7, "#FFEC407A", "ורוד"), (8, "#FF6D4C41", "חום"), (9, "#FFFDD835", "צהוב"),
        (10, "#FF29B6F6", "תכלת"), (11, "#FF000000", "שחור"),
    ]
    static let sizes: [(code: Int, pt: CGFloat, name: String)] = [
        (1, 20, "קטן"), (2, 28, "רגיל"), (3, 34, "גדול"), (4, 42, "ענק"), (5, 52, "ענק מאוד"),
    ]
    static func color(_ code: Int) -> Color {
        Color(hex: colors.first { $0.code == code }?.hex) ?? .black
    }
    static func size(_ code: Int) -> CGFloat {
        sizes.first { $0.code == code }?.pt ?? CGFloat(14 + code * 6)
    }
}

struct LetterContent: Hashable {
    var runs: [TextRun] = []
    var stamps: [PlacedStamp] = []
    var backgroundURL: String? = nil   // nil = lined paper
    var backgroundColor: String? = nil

    var plainText: String { runs.map(\.text).joined() }

    // MARK: parse

    static func parse(xml: String) -> LetterContent {
        var c = LetterContent()
        guard let doc = try? XMLDocument(xmlString: xml, options: []), let root = doc.rootElement() else {
            c.runs = [TextRun(text: "(לא ניתן להציג את המכתב)", color: .gray, size: 18)]
            return c
        }
        if let re = root.first("RichEdit"), let t = re.attr("Text") {
            c.runs = parseKidCodes(t)
        } else if let rt = root.first("RichTextContent"), let x = rt.attr("XAML") {
            c.runs = parseXAMLText(x)
        }
        for s in root.all("Stamp") {
            guard let url = s.attr("URL") else { continue }
            c.stamps.append(PlacedStamp(url: url, color: s.attr("Color") ?? "#FF2566AE", matrix: s.attr("Matrix") ?? ""))
        }
        if let bg = root.first("Background") {
            let u = bg.attr("URL")
            c.backgroundURL = (u == nil || u == "Default" || u == "") ? nil : u
            c.backgroundColor = bg.attr("Color")
        }
        return c
    }

    /// "/c01/s2hello\n/c03/s4world" → runs
    static func parseKidCodes(_ s: String) -> [TextRun] {
        var runs: [TextRun] = []
        var color = KidStyle.color(1), size = KidStyle.size(2)
        var buf = ""
        func flush() { if !buf.isEmpty { runs.append(TextRun(text: buf, color: color, size: size)); buf = "" } }
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            if chars[i] == "/", i + 3 < chars.count + 1, i + 1 < chars.count {
                if chars[i + 1] == "c", i + 3 < chars.count, chars[i + 2].isNumber, chars[i + 3].isNumber,
                   let n = Int(String(chars[(i + 2)...(i + 3)])) {
                    flush(); color = KidStyle.color(n); i += 4; continue
                }
                if chars[i + 1] == "s", i + 2 < chars.count, chars[i + 2].isNumber, let n = Int(String(chars[i + 2])) {
                    flush(); size = KidStyle.size(n); i += 3; continue
                }
            }
            buf.append(chars[i]); i += 1
        }
        flush()
        return runs
    }

    /// <Section><Paragraph><Run Text=.. Foreground=.. FontSize=../><LineBreak/></Paragraph></Section>
    static func parseXAMLText(_ x: String) -> [TextRun] {
        guard let doc = try? XMLDocument(xmlString: x, options: []), let root = doc.rootElement() else {
            return [TextRun(text: x, color: .black, size: 20)]
        }
        var runs: [TextRun] = []
        func walk(_ e: XMLElement, color: Color, size: CGFloat) {
            let c = Color(hex: e.attr("Foreground")) ?? color
            let s = CGFloat(Double(e.attr("FontSize") ?? "") ?? Double(size))
            switch e.localName {
            case "Run":
                runs.append(TextRun(text: e.attr("Text") ?? e.stringValue ?? "", color: c, size: s))
            case "LineBreak":
                runs.append(TextRun(text: "\n", color: c, size: s))
            default:
                for k in e.elementChildren { walk(k, color: c, size: s) }
                if e.localName == "Paragraph" { runs.append(TextRun(text: "\n", color: c, size: s)) }
            }
        }
        walk(root, color: .black, size: 20)
        while runs.last?.text == "\n" { runs.removeLast() }
        return runs
    }

    // MARK: build (for sending) – same format the Windows app writes

    static func buildXML(text: String, colorCode: Int, sizeCode: Int,
                         stamps: [PlacedStamp], backgroundURL: String?) -> String {
        let code = String(format: "/c%02d/s%d", colorCode, sizeCode)
        let lines = text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
        let encoded = lines.map { code + $0 }.joined(separator: "\n")
        var x = "<Content>\n  <RichEdit Text=\"\(xmlEscape(encoded))\" />\n"
        if stamps.isEmpty {
            x += "  <Stamps />\n"
        } else {
            x += "  <Stamps>\n"
            for s in stamps {
                x += "    <Stamp Matrix=\"\(s.matrixString)\" Color=\"\(xmlEscape(s.color))\" URL=\"\(xmlEscape(s.url))\" />\n"
            }
            x += "  </Stamps>\n"
        }
        if let bg = backgroundURL, bg != linedPaper {
            x += "  <Background URL=\"\(xmlEscape(bg))\" Color=\"#00FFFFFF\" />\n"
        } else {
            x += "  <Background URL=\"Default\" FontSize=\"0\" VerticalLine=\"true\" />\n"
        }
        x += "</Content>"
        return x
    }
}
