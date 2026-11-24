import Foundation
import CryptoKit
import IOKit
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

/// The "remember me" password.
///
/// Not in the Keychain: macOS ties a keychain entry to the exact build that
/// saved it (its "cdhash"), and this app isn't signed with an Apple developer
/// certificate, so after every update macOS would ask for the Mac's password
/// ("wants to use your confidential information stored in MailLiMac").
///
/// Instead: a file in ~/Library/Application Support/MailLiMac that only this
/// Mac user can open (0600), encrypted (AES-GCM) with a key made from this
/// Mac's hardware ID, so a copied file is useless on another computer.
/// Programs running as the same Mac user could still read it. That's fine for
/// a kindergarten mail password, but it's why the README says so.
enum SavedLogin {
    private static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MailLiMac", isDirectory: true)
    }
    private static var file: URL { dir.appendingPathComponent("login.dat") }

    private static var key: SymmetricKey {
        let hw = hardwareUUID() ?? "mailli-no-hwid"
        let k = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(hw.utf8)),
                                       salt: Data("MailLiMac.SavedLogin.v1".utf8),
                                       info: Data(NSUserName().utf8), outputByteCount: 32)
        return k
    }

    private static func hardwareUUID() -> String? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        return IORegistryEntryCreateCFProperty(svc, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    private static func readAll() -> [String: String] {
        guard let d = try? Data(contentsOf: file),
              let box = try? AES.GCM.SealedBox(combined: d),
              let plain = try? AES.GCM.open(box, using: key),
              let m = try? JSONDecoder().decode([String: String].self, from: plain) else { return [:] }
        return m
    }

    private static func writeAll(_ m: [String: String]) {
        let fm = FileManager.default
        if m.isEmpty { try? fm.removeItem(at: file); return }
        guard let plain = try? JSONEncoder().encode(m),
              let sealed = try? AES.GCM.seal(plain, using: key).combined else { return }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let tmp = dir.appendingPathComponent("login.tmp")
        guard fm.createFile(atPath: tmp.path, contents: sealed, attributes: [.posixPermissions: 0o600]) else { return }
        _ = try? fm.replaceItemAt(file, withItemAt: tmp)
    }

    static func save(user: String, password: String) {
        var m = readAll(); m[user] = password; writeAll(m)
        forgetOldKeychainEntry(user)
    }
    static func load(user: String) -> String? { readAll()[user] }
    static func delete(user: String) {
        var m = readAll(); m[user] = nil; writeAll(m)
        forgetOldKeychainEntry(user)
    }

    /// Version 1.0 kept the password in the Keychain. Never read it (that's what
    /// made macOS ask); just try to remove it, with macOS's dialogs switched off.
    private static func forgetOldKeychainEntry(_ user: String) {
        var was: DarwinBoolean = true
        SecKeychainGetUserInteractionAllowed(&was)
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(was.boolValue) }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: "MailLiMac",
                                kSecAttrAccount as String: user]
        SecItemDelete(q as CFDictionary)
    }

    /// `MailLi --login-store-test save|load|delete` with a test entry only.
    static func commandLineTest(_ what: String) -> Int32 {
        let u = "__mailli_store_test__"
        switch what {
        case "save": save(user: u, password: "test-value"); print("saved")
        case "load": print(load(user: u) == "test-value" ? "loaded" : "NOT READABLE")
        default: delete(user: u); print("deleted")
        }
        return 0
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
