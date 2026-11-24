#!/usr/bin/env python3
"""
MailLi read-only probe.

Logs in (password typed here, never saved/printed), then calls only READ
operations and saves the raw server replies to ./samples/ so the message
format can be studied. Nothing is sent, deleted or changed on the server.

Run:  python3 -I probe.py
"""
import getpass
import http.cookiejar
import os
import re
import urllib.parse
import urllib.request
from xml.sax.saxutils import escape

BASE = "https://galeli.com"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "samples")
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
      "(KHTML, like Gecko) Version/17.0 Safari/605.1.15")

jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))


def login(user, pw):
    url = BASE + "/GaleliAPI/login.aspx?ReturnUrl=%2f"
    with opener.open(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=30) as r:
        html = r.read().decode("utf-8", "replace")
    f = {}
    for n in ("__VIEWSTATE", "__VIEWSTATEGENERATOR", "__EVENTVALIDATION"):
        m = re.search(r'name="%s"[^>]*value="([^"]*)"' % n, html)
        if m:
            f[n] = m.group(1)
    f.update({"__EVENTTARGET": "", "__EVENTARGUMENT": "",
              "Login1$UserName": user, "Login1$Password": pw,
              "Login1$LoginButton.x": "10", "Login1$LoginButton.y": "10"})
    req = urllib.request.Request(url, data=urllib.parse.urlencode(f).encode(), headers={
        "Content-Type": "application/x-www-form-urlencoded", "Referer": url,
        "Origin": BASE, "User-Agent": UA})
    with opener.open(req, timeout=30) as r:
        r.read()
    return any(c.name == ".ASPXFORMSAUTH" for c in jar)


def soap(path, iface, op, params=""):
    body = ('<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
            f'<{op} xmlns="http://tempuri.org/">{params}</{op}></s:Body></s:Envelope>').encode()
    req = urllib.request.Request(BASE + path, data=body, headers={
        "Content-Type": "text/xml; charset=utf-8",
        "SOAPAction": f'"http://tempuri.org/{iface}/{op}"', "User-Agent": UA})
    try:
        with opener.open(req, timeout=60) as r:
            txt = r.read().decode("utf-8", "replace")
            st = r.status
    except urllib.error.HTTPError as e:
        txt, st = e.read().decode("utf-8", "replace"), e.code
    with open(os.path.join(OUT, f"{op}.xml"), "w", encoding="utf-8") as fh:
        fh.write(txt)
    print(f"  {op}: HTTP {st}, {len(txt)} bytes")
    return txt


def tag(xml, name):
    m = re.search(r"<(?:\w+:)?%s>([^<]*)<" % name, xml)
    return m.group(1) if m else None


MAIL = "/Mailli.web/MailliSVC.svc"
MI = "IMailLiSVC"


def main():
    os.makedirs(OUT, exist_ok=True)
    print("Child's MailLi login (paste the password if the keyboard won't switch).")
    user = input("Username: ").strip()
    pw = getpass.getpass("Password: ")
    ok = login(user, pw)
    del pw
    print("Logged in:", ok)
    if not ok:
        return

    print("Identity:")
    G = "/Googale.Web/GoogaleSVC.svc"
    candidates = []
    lu = soap("/LoginService.Web/LoginSVC.svc", "ILoginSVC", "LoggedInUser")
    v = tag(lu, "LoggedInUserResult") or ""
    print(f"  LoggedInUser result: {'numeric' if v.isdigit() else 'text'} ({len(v)} chars)")
    for name, op, params in [
        ("googale", "GetAppStartupForLoggedInUser",
         "<StudentID>0</StudentID><AppType>MailLi</AppType><SignedData></SignedData><signature></signature>"),
        ("googale_ext", "GetAppStartupForLoggedInUserExtended",
         "<StudentID>0</StudentID><AppType>MailLi</AppType><SignedData></SignedData><signature></signature>"
         "<Platform>UWP</Platform><FormFactor>Desktop</FormFactor><VersionString>1.0.18.0</VersionString>"),
    ]:
        st = soap(G, "IGoogaleSVC", op, params)
        os.replace(os.path.join(OUT, f"{op}.xml"), os.path.join(OUT, f"startup_{name}.xml"))
        s = tag(st, "CurrentStudentID")
        print(f"  {name}: StudentID {'set' if s and s != '0' else 'zero/missing'}, "
              f"login type {tag(st, 'CurrentLoginType')}, fault: {'Fault' in st}")
        if s and s != "0":
            candidates.append(s)
    cl = soap("/StudentLogin.web/ChildLogin.svc", "IChildLogin", "GetClassIDFromLoggedInUser")
    cid = tag(cl, "GetClassIDFromLoggedInUserResult")
    soap("/StudentLogin.web/ChildLogin.svc", "IChildLogin", "GetGUIDOfLoggedInUser")
    if cid:
        soap("/StudentLogin.web/ChildLogin.svc", "IChildLogin", "GetChildList", f"<ClassID>{cid}</ClassID>")
    if v.isdigit() and v != "0":
        candidates.append(v)
    sid = candidates[0] if candidates else None
    print("  StudentID found:", bool(sid))
    if not sid:
        print("  (could not find StudentID; samples saved so far)")
        return
    p = f"<StudentID>{sid}</StudentID>"

    print("Mail (read-only):")
    soap(MAIL, MI, "GetNumberOfItemsInInbox", p)
    inbox = soap(MAIL, MI, "GetLast100EmailsV5", p)
    soap(MAIL, MI, "GetStoredMailHeaders", p)
    soap(MAIL, MI, "GetFirstSixMailHeaders", p)
    sent = soap(MAIL, MI, "GetSentdMailHeadersV5", p)
    soap(MAIL, MI, "GetMailABAndStamps", p)

    ids = re.findall(r"<(?:\w+:)?EMailID>(\d+)<", inbox)
    if ids:
        m = soap(MAIL, MI, "GetmailMessage", p + f"<MessageID>{ids[0]}</MessageID>")
        os.replace(os.path.join(OUT, "GetmailMessage.xml"),
                   os.path.join(OUT, "GetmailMessage_inbox0.xml"))
        if len(ids) > 1:
            soap(MAIL, MI, "GetmailMessage", p + f"<MessageID>{ids[1]}</MessageID>")
    sids = re.findall(r"<(?:\w+:)?EMailID>(\d+)<", sent)
    if sids:
        soap(MAIL, MI, "GetSentMailMessage", p + f"<MessageID>{sids[0]}</MessageID>")
    print(f"\nDone. Inbox ids: {len(ids)}, sent ids: {len(sids)}. Saved to {OUT}")


if __name__ == "__main__":
    main()
