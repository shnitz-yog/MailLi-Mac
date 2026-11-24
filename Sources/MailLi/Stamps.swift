import Foundation
import SwiftUI

/// A stamp is a single XAML <Path> (vector drawing). We parse its path data
/// ("F1 M14,14 L4,14 C... z") into a SwiftUI Path.
struct StampShape {
    var path: Path            // already scaled to Width x Height
    var size: CGSize
    var hasFill: Bool
    var hasStroke: Bool
    var strokeWidth: CGFloat
    var fillColor: Color?

    static func parse(xaml: String) -> StampShape? {
        guard let doc = try? XMLDocument(xmlString: xaml, options: []), let root = doc.rootElement() else { return nil }
        let pathEl = root.localName == "Path" ? root : root.first("Path")
        guard let p = pathEl, let data = p.attr("Data") else { return nil }
        var path = PathData.parse(data)
        let b = path.boundingRect
        let w = CGFloat(Double(p.attr("Width") ?? "") ?? Double(b.width))
        let h = CGFloat(Double(p.attr("Height") ?? "") ?? Double(b.height))
        if (p.attr("Stretch") ?? "None") != "None", b.width > 0, b.height > 0 {
            path = path.applying(CGAffineTransform(translationX: -b.minX, y: -b.minY)
                .concatenating(CGAffineTransform(scaleX: w / b.width, y: h / b.height)))
        }
        return StampShape(path: path, size: CGSize(width: w, height: h),
                          hasFill: p.attr("Fill") != nil, hasStroke: p.attr("Stroke") != nil,
                          strokeWidth: CGFloat(Double(p.attr("StrokeThickness") ?? "1") ?? 1),
                          fillColor: Color(hex: p.attr("Fill")))
    }
}

/// Minimal XAML/SVG path-mini-language parser (M L H V C S Q T Z, abs + rel, F0/F1).
enum PathData {
    static func parse(_ d: String) -> Path {
        var p = Path()
        var tokens: [String] = []
        let re = try! NSRegularExpression(pattern: #"[A-DF-Za-df-z]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"#)
        for m in re.matches(in: d, range: NSRange(d.startIndex..., in: d)) {
            if let r = Range(m.range, in: d) { tokens.append(String(d[r])) }
        }
        var i = 0
        var cmd: Character = "M"
        var cur = CGPoint.zero, start = CGPoint.zero, lastCtrl: CGPoint? = nil
        func isCmd(_ t: String) -> Bool { t.count == 1 && t.first!.isLetter }
        func num() -> CGFloat? {
            guard i < tokens.count, !isCmd(tokens[i]), let v = Double(tokens[i]) else { return nil }
            i += 1; return CGFloat(v)
        }
        func pt(_ rel: Bool) -> CGPoint? {
            guard let x = num(), let y = num() else { return nil }
            return rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
        }
        while i < tokens.count {
            if isCmd(tokens[i]) { cmd = tokens[i].first!; i += 1 }
            let rel = cmd.isLowercase
            switch cmd.uppercased().first! {
            case "F":
                _ = num()  // fill rule; ignore
                continue
            case "M":
                guard let q = pt(rel) else { i += 1; continue }
                p.move(to: q); cur = q; start = q; lastCtrl = nil
                cmd = rel ? "l" : "L"
            case "L":
                guard let q = pt(rel) else { i += 1; continue }
                p.addLine(to: q); cur = q; lastCtrl = nil
            case "H":
                guard let x = num() else { i += 1; continue }
                cur = CGPoint(x: rel ? cur.x + x : x, y: cur.y); p.addLine(to: cur); lastCtrl = nil
            case "V":
                guard let y = num() else { i += 1; continue }
                cur = CGPoint(x: cur.x, y: rel ? cur.y + y : y); p.addLine(to: cur); lastCtrl = nil
            case "C":
                guard let c1 = pt(rel), let c2 = pt(rel), let e = pt(rel) else { i += 1; continue }
                p.addCurve(to: e, control1: c1, control2: c2); cur = e; lastCtrl = c2
            case "S":
                let c1 = lastCtrl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                guard let c2 = pt(rel), let e = pt(rel) else { i += 1; continue }
                p.addCurve(to: e, control1: c1, control2: c2); cur = e; lastCtrl = c2
            case "Q":
                guard let c = pt(rel), let e = pt(rel) else { i += 1; continue }
                p.addQuadCurve(to: e, control: c); cur = e; lastCtrl = c
            case "T":
                let c = lastCtrl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                guard let e = pt(rel) else { i += 1; continue }
                p.addQuadCurve(to: e, control: c); cur = e; lastCtrl = c
            case "Z":
                p.closeSubpath(); cur = start; lastCtrl = nil
                if i < tokens.count, !isCmd(tokens[i]) { cmd = "M" }
            default:
                i += 1  // unsupported (e.g. arcs): skip a token
            }
        }
        return p
    }
}

/// Parsed stamps by URL. Fed from the address-book call; fetches unknown ones on demand.
@MainActor
final class StampLibrary: ObservableObject {
    @Published private(set) var shapes: [String: StampShape] = [:]
    private var loading: Set<String> = []

    func key(_ url: String) -> String { url.lowercased().replacingOccurrences(of: "https://", with: "http://") }

    func add(url: String, xaml: String) {
        if let s = StampShape.parse(xaml: xaml) { shapes[key(url)] = s }
    }

    func shape(_ url: String) -> StampShape? {
        if let s = shapes[key(url)] { return s }
        let k = key(url)
        if !loading.contains(k), let u = secureURL(url) {
            loading.insert(k)
            Task {
                if let (d, _) = try? await URLSession.shared.data(from: u), let x = String(data: d, encoding: .utf8) {
                    self.add(url: url, xaml: x)
                }
            }
        }
        return nil
    }
}
