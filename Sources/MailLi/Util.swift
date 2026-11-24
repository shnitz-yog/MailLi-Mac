import Foundation
import Compression
import SwiftUI

// MARK: - XML helpers (namespace-agnostic: match on local name)

extension XMLElement {
    var elementChildren: [XMLElement] { (children ?? []).compactMap { $0 as? XMLElement } }
    func kids(_ name: String) -> [XMLElement] { elementChildren.filter { $0.localName == name } }
    func kid(_ name: String) -> XMLElement? { elementChildren.first { $0.localName == name } }
    func text(_ name: String) -> String? { kid(name)?.stringValue }
    func attr(_ name: String) -> String? { attribute(forName: name)?.stringValue }
    func first(_ name: String) -> XMLElement? {
        for c in elementChildren {
            if c.localName == name { return c }
            if let f = c.first(name) { return f }
        }
        return nil
    }
    func all(_ name: String) -> [XMLElement] {
        var r: [XMLElement] = []
        for c in elementChildren {
            if c.localName == name { r.append(c) }
            r += c.all(name)
        }
        return r
    }
}

func xmlEscape(_ s: String) -> String {
    var r = ""
    for ch in s {
        switch ch {
        case "&": r += "&amp;"
        case "<": r += "&lt;"
        case ">": r += "&gt;"
        case "\"": r += "&quot;"
        case "'": r += "&apos;"
        case "\n": r += "&#xA;"
        case "\r": break
        default: r.append(ch)
        }
    }
    return r
}

// MARK: - zlib (the server stores message bodies as zlib-compressed XML)

enum Zlib {
    static func inflate(_ data: Data) -> Data? {
        // zlib header (0x78 ..) + raw deflate + 4-byte adler32
        var body = data
        if data.count > 6, data[data.startIndex] & 0x0F == 8 {
            body = data.subdata(in: (data.startIndex + 2)..<(data.endIndex - 4))
        }
        var cap = max(body.count * 8, 64 * 1024)
        while cap <= 64 << 20 {
            var out = Data(count: cap)
            let n = out.withUnsafeMutableBytes { o in
                body.withUnsafeBytes { i in
                    compression_decode_buffer(o.bindMemory(to: UInt8.self).baseAddress!, cap,
                                              i.bindMemory(to: UInt8.self).baseAddress!, body.count,
                                              nil, COMPRESSION_ZLIB)
                }
            }
            if n == 0 { return nil }
            if n < cap { return out.prefix(n) }
            cap *= 4
        }
        return nil
    }

    static func deflate(_ data: Data) -> Data {
        let cap = data.count + 4096
        var out = Data(count: cap)
        let n = out.withUnsafeMutableBytes { o in
            data.withUnsafeBytes { i in
                compression_encode_buffer(o.bindMemory(to: UInt8.self).baseAddress!, cap,
                                          i.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        var r = Data([0x78, 0x9C])
        r.append(out.prefix(n))
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
        let ad = (b << 16) | a
        r.append(contentsOf: [UInt8(ad >> 24), UInt8((ad >> 16) & 0xFF), UInt8((ad >> 8) & 0xFF), UInt8(ad & 0xFF)])
        return r
    }
}

// MARK: - URLs, colors, dates

/// Server returns http:// links; macOS apps need https (the server supports it).
func secureURL(_ s: String?, base: String = "https://galeli.com/MailLi.Web/Resources/") -> URL? {
    guard var s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty, s != "Default" else { return nil }
    if !s.lowercased().hasPrefix("http") { s = base + s }
    if s.lowercased().hasPrefix("http://") { s = "https://" + s.dropFirst(7) }
    return URL(string: s)
}

extension Color {
    /// "#AARRGGBB" or "#RRGGBB"
    init?(hex: String?) {
        guard var h = hex?.trimmingCharacters(in: .whitespaces), h.hasPrefix("#") else { return nil }
        h.removeFirst()
        guard let v = UInt64(h, radix: 16) else { return nil }
        let a, r, g, b: Double
        if h.count == 8 {
            a = Double((v >> 24) & 0xFF) / 255; r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255; b = Double(v & 0xFF) / 255
        } else if h.count == 6 {
            a = 1; r = Double((v >> 16) & 0xFF) / 255; g = Double((v >> 8) & 0xFF) / 255; b = Double(v & 0xFF) / 255
        } else { return nil }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

enum Dates {
    static func parse(_ s: String?) -> Date? {
        guard var s = s else { return nil }
        // Trim 7-digit .NET fractions, which ISO8601DateFormatter can't read.
        if let r = s.range(of: #"\.\d+"#, options: .regularExpression) { s.removeSubrange(r) }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
    static func now() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = .current
        return f.string(from: Date())
    }
    static let display: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "he_IL")
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}

func firstMatch(_ pattern: String, in s: String) -> String? {
    guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
          let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
          m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s) else { return nil }
    return String(s[r])
}

// MARK: - Keychain (remember password on this Mac only)

enum Keychain {
    static let service = "MailLiMac"
    static func save(user: String, password: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: user]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
    static func load(user: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: user,
                                kSecReturnData as String: true]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func delete(user: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: user]
        SecItemDelete(q as CFDictionary)
    }
}

// MARK: - @Local: same as SwiftUI @State, without needing the SwiftUI macro
// plugin (it ships only with full Xcode, not the Command Line Tools).

@propertyWrapper
struct Local<Value>: DynamicProperty {
    private var storage: SwiftUI.State<Value>
    init(wrappedValue: Value) { storage = SwiftUI.State(initialValue: wrappedValue) }
    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }
    var projectedValue: Binding<Value> { storage.projectedValue }
}
