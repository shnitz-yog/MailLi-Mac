import Foundation
import SwiftUI

enum MailLiError: LocalizedError {
    case badLogin(String?), notLoggedIn, server(String), noStudent, expired, offline, sendRefused(String)
    var errorDescription: String? {
        switch self {
        case .badLogin(let msg):
            return "השרת לא קיבל את שם המשתמש או הסיסמה" + (msg.map { " (\"\($0)\")" } ?? "") + ".\n" +
                   "כדאי לבדוק: אותיות בעברית/אנגלית, רווחים מיותרים, ושזה החשבון של הילד ולא של ההורה."
        case .notLoggedIn: return "החיבור פג. נא להתחבר שוב."
        case .server(let s): return "שגיאה מהשרת: \(s)"
        case .noStudent: return "הכניסה הצליחה, אבל זה לא חשבון של ילד/ה.\nצריך את שם המשתמש והסיסמה של הילד (לא של ההורה)."
        case .expired: return "המנוי של החשבון הזה הסתיים. כדאי לבדוק מול הגן או גוגלה."
        case .offline: return "אין חיבור לאינטרנט, או שהשרת של המערכת לא עונה כרגע."
        case .sendRefused(let s): return "השרת לא שלח את המכתב (\(s))."
        }
    }
}

/// Talks to the same galeli.com services the Windows "מייל לי" app uses.
@MainActor
final class MailLiClient: ObservableObject {
    static let base = "https://galeli.com"
    static let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    private static let dc = "http://schemas.datacontract.org/2004/07/MailLi.Web"

    @Published var loggedIn = false
    @Published var studentID: Int64 = 0
    @Published var studentName = ""
    @Published var studentSymbol = ""
    @Published var contacts: [Contact] = []
    @Published var backgrounds: [BackgroundChoice] = []
    @Published var stampChoices: [StampChoice] = []
    /// Last loaded letters per mailbox (so screens don't flash empty).
    @Published var boxes: [Mailbox: [MailHeader]] = [:]

    func refresh(_ box: Mailbox) async throws {
        boxes[box] = try await headers(box)
    }

    func markRead(_ id: Int64) {
        guard var list = boxes[.inbox], let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].read = true
        boxes[.inbox] = list
    }
    let stamps = StampLibrary()

    private var session: URLSession = MailLiClient.makeSession()
    private var creds: (String, String)?

    private static func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral   // own in-memory cookie jar
        cfg.httpCookieAcceptPolicy = .always
        cfg.timeoutIntervalForRequest = 45
        return URLSession(configuration: cfg)
    }

    // MARK: login

    func login(user: String, password: String) async throws {
        session = Self.makeSession()
        do {
            try await formLogin(user: user, password: password)
        } catch let e as URLError {
            _ = e
            throw MailLiError.offline
        }
        creds = (user, password)
        try await loadIdentity()
        loggedIn = true
        try? await loadAddressBook()
    }

    func logout() {
        loggedIn = false; creds = nil; studentID = 0
        contacts = []; boxes = [:]; session = Self.makeSession()
    }

    private func formLogin(user: String, password: String) async throws {
        let url = URL(string: Self.base + "/GaleliAPI/login.aspx?ReturnUrl=%2f")!
        var get = URLRequest(url: url)
        get.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
        let (d, _) = try await session.data(for: get)
        let html = String(data: d, encoding: .utf8) ?? ""
        var fields: [(String, String)] = []
        for n in ["__VIEWSTATE", "__VIEWSTATEGENERATOR", "__EVENTVALIDATION"] {
            if let v = firstMatch("name=\"\(n)\"[^>]*value=\"([^\"]*)\"", in: html) { fields.append((n, v)) }
        }
        fields += [("__EVENTTARGET", ""), ("__EVENTARGUMENT", ""),
                   ("Login1$UserName", user), ("Login1$Password", password),
                   ("Login1$LoginButton.x", "10"), ("Login1$LoginButton.y", "10")]
        var post = URLRequest(url: url)
        post.httpMethod = "POST"
        post.httpBody = Self.formEncode(fields)
        post.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        post.setValue(url.absoluteString, forHTTPHeaderField: "Referer")
        post.setValue(Self.base, forHTTPHeaderField: "Origin")
        post.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
        let (pd, _) = try await session.data(for: post)
        let cookies = session.configuration.httpCookieStorage?.cookies(for: URL(string: Self.base + "/")!) ?? []
        guard cookies.contains(where: { $0.name == ".ASPXFORMSAUTH" }) else {
            // The login page shows its own red error text; pass it on.
            let page = String(data: pd, encoding: .utf8) ?? ""
            let msg = firstMatch(#"color:\s*Red[^>]*>(.*?)</td>"#, in: page)?
                .replacingOccurrences(of: #"<[^>]+>|\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            throw MailLiError.badLogin(msg?.isEmpty == false ? msg : nil)
        }
    }

    private static func formEncode(_ pairs: [(String, String)]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._*")
        let s = pairs.map { k, v in
            (k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k) + "=" +
            (v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)
        }.joined(separator: "&")
        return Data(s.utf8)
    }

    private func loadIdentity() async throws {
        let r = try await soap("/Googale.Web/GoogaleSVC.svc", "IGoogaleSVC", "GetAppStartupForLoggedInUser",
                               "<StudentID>0</StudentID><AppType>MailLi</AppType><SignedData></SignedData><signature></signature>")
        let status = r.first("CurrentAccountStatus")?.stringValue ?? ""
        if status == "AccountExpired" || status == "FreeTrialExpired" { throw MailLiError.expired }
        guard let sid = Int64(r.first("CurrentStudentID")?.stringValue ?? ""), sid != 0 else { throw MailLiError.noStudent }
        studentID = sid
        studentName = (r.first("CurrentStudentName")?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
        studentSymbol = r.first("CurrentStudentSymbolURL")?.stringValue ?? ""
    }

    // MARK: SOAP

    /// Returns the response element inside <s:Body>. Re-logs in once if the session expired.
    private func soap(_ path: String, _ iface: String, _ op: String, _ params: String = "",
                      retry: Bool = true) async throws -> XMLElement {
        let body = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body>" +
                   "<\(op) xmlns=\"http://tempuri.org/\">\(params)</\(op)></s:Body></s:Envelope>"
        var req = URLRequest(url: URL(string: Self.base + path)!)
        req.httpMethod = "POST"
        req.httpBody = Data(body.utf8)
        req.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("\"http://tempuri.org/\(iface)/\(op)\"", forHTTPHeaderField: "SOAPAction")
        req.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
        let (d, resp) = try await session.data(for: req)
        let ctype = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        if ctype.contains("html") {
            if retry, let (u, p) = creds {
                try await formLogin(user: u, password: p)
                return try await soap(path, iface, op, params, retry: false)
            }
            throw MailLiError.notLoggedIn
        }
        let doc = try XMLDocument(data: d, options: [])
        guard let bodyEl = doc.rootElement()?.first("Body"), let first = bodyEl.elementChildren.first else {
            throw MailLiError.server("תשובה ריקה")
        }
        if first.localName == "Fault" {
            throw MailLiError.server(first.first("Text")?.stringValue ?? first.first("faultstring")?.stringValue ?? "Fault")
        }
        return first
    }

    private var sidParam: String { "<StudentID>\(studentID)</StudentID>" }
    private let mail = "/Mailli.web/MailliSVC.svc"

    // MARK: mail

    func headers(_ box: Mailbox) async throws -> [MailHeader] {
        let op = box == .inbox ? "GetLast100EmailsV5" : "GetSentdMailHeadersV5"
        let r = try await soap(mail, "IMailLiSVC", op, sidParam)
        return Self.parseHeaders(r)
    }

    static func parseHeaders(_ r: XMLElement) -> [MailHeader] {
        r.all("MailHeaderV5").compactMap { h in
            guard let id = Int64(h.text("EMailID") ?? "") else { return nil }
            let inner = h.kid("Header")?.first("Header") ?? h.kid("Header")
            return MailHeader(id: id,
                              time: Dates.parse(inner?.attr("Time")),
                              read: (inner?.attr("Read") ?? "true") == "true",
                              sender: inner?.kid("Sender").map(MailAddress.init(attrs:)),
                              recipient: inner?.kid("Reciepient").map(MailAddress.init(attrs:)))
        }.sorted { ($0.time ?? .distantPast) > ($1.time ?? .distantPast) }
    }

    func message(_ id: Int64, in box: Mailbox) async throws -> LetterContent {
        let op = box == .inbox ? "GetmailMessage" : "GetSentMailMessage"
        let r = try await soap(mail, "IMailLiSVC", op, sidParam + "<MessageID>\(id)</MessageID>")
        if let b64 = r.first("CompressedBody")?.stringValue, let raw = Data(base64Encoded: b64),
           let xml = Zlib.inflate(raw), let s = String(data: xml, encoding: .utf8) {
            return LetterContent.parse(xml: s)
        }
        if let x = r.first("MailMessageXML"), let inner = x.elementChildren.first {
            return LetterContent.parse(xml: inner.xmlString)
        }
        return LetterContent(runs: [TextRun(text: "(מכתב ריק)", color: .gray, size: 18)])
    }

    func delete(_ id: Int64, in box: Mailbox) async throws {
        let op = box == .inbox ? "DeleteMailMessage" : "DeleteSentMailMessage"
        _ = try await soap(mail, "IMailLiSVC", op, sidParam + "<MessageID>\(id)</MessageID>")
    }

    // MARK: address book, stamps, backgrounds

    func loadAddressBook() async throws {
        let r = try await soap(mail, "IMailLiSVC", "GetMailABAndStamps", sidParam)
        applyAddressBook(r)
    }

    func applyAddressBook(_ r: XMLElement) {
        stampChoices = []
        for s in r.all("StampDescription") {
            guard let url = s.text("URL"), let x = s.text("XAML") else { continue }
            stamps.add(url: url, xaml: x)
            stampChoices.append(StampChoice(url: url, xaml: x))
        }
        backgrounds = r.all("BK").compactMap { b in
            guard let u = b.attr("ImageURL") else { return nil }
            return BackgroundChoice(name: b.attr("ButtonName") ?? "", url: u)
        }
        var list: [Contact] = []
        let groups: [(String, String)] = [("Family", "משפחה"), ("HomeEmail", "משפחה"), ("Teacher", "הגננת"),
                                          ("StaffAddressBook", "צוות הגן"), ("StudentsAddressBook", "חברים בגן"),
                                          ("Friends", "חברים")]
        var seen = Set<String>()
        for (tag, title) in groups {
            guard let sec = r.first(tag) else { continue }
            for abe in sec.all("ABE") {
                guard let a = abe.first("Address"), let c = contact(abe: abe, addr: a, group: title) else { continue }
                let key = c.address.addressType + c.address.aliasType + c.address.address
                if seen.insert(key).inserted { list.append(c) }
            }
        }
        contacts = list
    }

    private func contact(abe: XMLElement, addr: XMLElement, group: String) -> Contact? {
        let name = (abe.attr("Text") ?? "").trimmingCharacters(in: .whitespaces)
        let img = abe.attr("Image") ?? ""
        let fullImg = secureURL(img)?.absoluteString.replacingOccurrences(of: "https://", with: "http://") ?? img
        let a = addr.attr("Address") ?? "0"
        let ma: MailAddress
        switch (addr.attr("Type") ?? "").uppercased() {
        case "MAILLI":
            ma = MailAddress(address: a, addressType: "SingleMailLiReciepient", aliasType: "SingleReciepient",
                             name: name, studentID: Int64(a) ?? 0, symbolURL: fullImg)
        case "PABS":
            ma = MailAddress(address: a, addressType: "PrivateABSMTPAddress", aliasType: "SingleReciepient",
                             name: name, studentID: studentID, symbolURL: fullImg)
        case "TOALLMYFAMILY":
            ma = MailAddress(address: "0", addressType: "SMTPAlias", aliasType: "AllFamilyMembers",
                             name: name, studentID: 0, symbolURL: fullImg)
        case "TOMYFAMILY":
            ma = MailAddress(address: "0", addressType: "SMTPAlias", aliasType: "MyFamily",
                             name: name, studentID: 0, symbolURL: fullImg)
        default:
            return nil
        }
        return Contact(name: name, imageURL: img, group: group, address: ma)
    }

    // MARK: send

    /// Uploads a file to the server's upload folder in small chunks (the service
    /// appends each chunk). Returns the file name to reference.
    func upload(_ data: Data, ext: String) async throws -> String {
        let name = "Message-" + UUID().uuidString.lowercased() + "." + ext
        let chunkSize = 12 * 1024   // server limit is 16384 bytes per chunk
        var offset = 0
        repeat {
            let end = min(offset + chunkSize, data.count)
            let chunk = data.subdata(in: offset..<end).base64EncodedString()
            _ = try await soap("/FileUploader.Web/FIleUploader.svc", "IFIleUploader", "uploadFile",
                               "<fileName>\(xmlEscape(name))</fileName><chunk>\(chunk)</chunk>")
            offset = end
        } while offset < data.count
        return name
    }

    func send(to: MailAddress, text: String, colorCode: Int, sizeCode: Int,
              stamps placed: [PlacedStamp], backgroundURL: String?, image: Data?) async throws {
        var imageName: String?
        if let image { imageName = try await upload(image, ext: "png") }
        let xml = LetterContent.buildXML(text: text, colorCode: colorCode, sizeCode: sizeCode,
                                         stamps: placed, backgroundURL: backgroundURL)
        let body = Zlib.deflate(Data(xml.utf8)).base64EncodedString()
        let from = MailAddress(address: String(studentID), addressType: "SingleMailLiReciepient",
                               aliasType: "SingleReciepient", name: studentName, studentID: studentID,
                               symbolURL: studentSymbol.isEmpty
                                   ? "http://galeli.com/IntegratedApp.Web/Content/EmptyStudentSymbol.png" : studentSymbol)
        let msg = "<Message xmlns:a=\"\(Self.dc)\" xmlns:i=\"http://www.w3.org/2001/XMLSchema-instance\">" +
            "<a:CompressedBody>\(body)</a:CompressedBody>" +
            "<a:Header><a:EMailID>0</a:EMailID><a:From>\(from.soapXML)</a:From>" +
            "<a:TimeRecieved>\(Dates.now())</a:TimeRecieved><a:To>\(to.soapXML)</a:To></a:Header>" +
            "<a:MailMessageXML i:nil=\"true\"/><a:version>version1</a:version></Message>" +
            (imageName.map { "<ImageFileName>\(xmlEscape($0))</ImageFileName>" }
                ?? "<ImageFileName i:nil=\"true\" xmlns:i=\"http://www.w3.org/2001/XMLSchema-instance\"/>")
        let r = try await soap(mail, "IMailLiSVC", "SendMessage", sidParam + msg)
        let status = r.first("SendMessageResult")?.stringValue ?? ""
        guard status == "OK" else { throw MailLiError.sendRefused(status.isEmpty ? "ללא תשובה" : status) }
    }
}
