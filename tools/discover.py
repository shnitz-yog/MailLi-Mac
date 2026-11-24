#!/usr/bin/env python3
"""
MailLi API discovery.

Logs in to galeli.com with the child's username/password (typed here, never
saved or printed), then downloads the API descriptions (WSDL/XSD) of the
services that are hidden behind the login. Only the schemas are saved, not
any messages or personal data.

Run:  python3 -I discover.py
Output: ./api/  (next to this script)
"""
import getpass
import http.cookiejar
import os
import re
import sys
import urllib.parse
import urllib.request
from xml.sax.saxutils import escape

BASE = "https://galeli.com"
SERVICES = [
    "LoginService.web/LoginSVC.svc",
    "StudentLogin.web/ChildLogin.svc",
    "Mailli.web/MailliSVC.svc",
    "MailLiForMyParents.Web/MailLiForMyParentsSVC.svc",
    "ParentsLocation.web/AddressBook.svc",
    "FileUploader.Web/FIleUploader.svc",
    "googale.web/googalesvc.svc",
    "LoginAssistant.Web/LoginAssistant.svc",
]
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "api")

jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
opener.addheaders = [("User-Agent", "MailLiMac/0.1")]


def soap_login(user, pw, path="/Googale.Web/GoogaleSVC.svc", iface="IGoogaleSVC"):
    body = (
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
        '<Login xmlns="http://tempuri.org/">'
        f"<UserName>{escape(user)}</UserName><Password>{escape(pw)}</Password>"
        "</Login></s:Body></s:Envelope>"
    ).encode("utf-8")
    req = urllib.request.Request(
        BASE + path,
        data=body,
        headers={
            "Content-Type": "text/xml; charset=utf-8",
            "SOAPAction": f'"http://tempuri.org/{iface}/Login"',
        },
    )
    with opener.open(req, timeout=30) as r:
        global LAST_HEADERS
        LAST_HEADERS = r.headers
        return r.status, r.read().decode("utf-8", "replace")


LAST_HEADERS = None


def failure_text(html):
    """The red error message an ASP.NET Login control shows, if any."""
    m = re.search(r'color:\s*Red[^>]*>(.*?)</td>', html, re.S | re.I)
    if not m:
        return None
    return re.sub(r"<[^>]+>|\s+", " ", m.group(1)).strip()[:150] or None


def form_login(user, pw, url=BASE + "/GaleliAPI/login.aspx?ReturnUrl=%2f", image_button=True):
    """Sign in through an ASP.NET login web form."""
    with opener.open(url, timeout=30) as r:
        html = r.read().decode("utf-8", "replace")
    fields = {}
    for name in ("__VIEWSTATE", "__VIEWSTATEGENERATOR", "__EVENTVALIDATION"):
        m = re.search(r'name="%s"[^>]*value="([^"]*)"' % name, html)
        if m:
            fields[name] = m.group(1)
    fields.update({
        "Login1$UserName": user,
        "Login1$Password": pw,
        "__EVENTTARGET": "",
        "__EVENTARGUMENT": "",
    })
    if image_button:
        fields.update({"Login1$LoginButton.x": "10", "Login1$LoginButton.y": "10"})
    else:
        fields["Login1$LoginButton"] = "Log In"
    data = urllib.parse.urlencode(fields).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={
        "Content-Type": "application/x-www-form-urlencoded",
        "Referer": url,
        "Origin": BASE,
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
    })
    with opener.open(req, timeout=30) as r:
        body = r.read().decode("utf-8", "replace")
        return r.status, r.geturl(), body


def masked_set_cookies(headers):
    """Set-Cookie headers with the secret values replaced by their length."""
    out = []
    for h in headers.get_all("Set-Cookie") or []:
        parts = [p.strip() for p in h.split(";")]
        name, _, val = parts[0].partition("=")
        out.append("; ".join([f"{name}=<{len(val)} chars>"] + parts[1:]))
    return out


def describe_result(text):
    m = re.search(r"<LoginResult>(.*?)</LoginResult>", text, re.S)
    if not m:
        return "no LoginResult in response (first 200 chars): " + text[:200]
    v = m.group(1)
    if len(v) <= 40 and not re.fullmatch(r"[0-9a-fA-F-]{20,}", v):
        return f"LoginResult = {v!r}"
    return f"LoginResult is a {len(v)}-char value (hidden; looks like a token/id)"


def fetch(url):
    try:
        with opener.open(url, timeout=30) as r:
            return r.status, r.geturl(), r.headers.get("Content-Type", ""), r.read()
    except urllib.error.HTTPError as e:
        return e.code, url, "", b""


def save_tree(svc):
    """Download ?wsdl and every ?wsdl=/ ?xsd= it links to."""
    root = f"{BASE}/{svc}?wsdl"
    todo, seen, saved = [root], set(), []
    while todo:
        url = todo.pop()
        if url.lower() in seen:
            continue
        seen.add(url.lower())
        status, final, ctype, data = fetch(url)
        if status != 200 or "xml" not in ctype:
            return f"BLOCKED ({status}, {ctype or 'no type'}, ended at {final.split('?')[0]})"
        q = urllib.parse.urlparse(url).query.replace("=", "_") or "wsdl"
        name = svc.split("/")[-1].replace(".svc", "") + "__" + q + ".xml"
        with open(os.path.join(OUT, name), "wb") as f:
            f.write(data)
        saved.append(name)
        for ref in re.findall(rb'(?:schemaLocation|location)="([^"]+\?(?:wsdl|xsd)=[^"]+)"', data):
            todo.append(ref.decode())
    return f"OK, {len(saved)} files"


def main():
    os.makedirs(OUT, exist_ok=True)
    print("Child's MailLi login (password is not shown or saved).")
    user = input("Username: ").strip()
    pw = getpass.getpass("Password (switch keyboard to the language you usually type it in!): ")
    # Diagnostics only: counts and character classes, never the characters.
    def kinds(s):
        k = set()
        for ch in s:
            if "֐" <= ch <= "׿": k.add("hebrew")
            elif ch.isascii() and ch.isalpha(): k.add("latin")
            elif ch.isdigit(): k.add("digits")
            elif ch.isspace(): k.add("SPACE")
            elif not ch.isprintable(): k.add("INVISIBLE")
            else: k.add("symbols")
        return sorted(k)
    print(f"Username: {len(user)} chars, {kinds(user)}; password: {len(pw)} chars, {kinds(pw)}")
    # Does GoogaleSVC/Login really check the password? Try a surely-wrong one.
    _, wrong = soap_login(user, "definitely-wrong-" + os.urandom(4).hex())
    print("GoogaleSVC with a WRONG password says:", describe_result(wrong))
    status, text = soap_login(user, pw)
    if "<LoginResult>true</LoginResult>" not in text:
        print(f"GoogaleSVC login: HTTP {status}: {describe_result(text)}; trying LoginSVC...")
        status, text = soap_login(user, pw, "/LoginService.Web/LoginSVC.svc", "ILoginSVC")
    for form_url, img in [
        (BASE + "/MailLi.Web/login.aspx", True),
        (BASE + "/StudentLogin.Web/login.aspx", True),
        (BASE + "/GaleliAPI/login.aspx?ReturnUrl=%2f", True),
        (BASE + "/ParentsLocation.Web/login.aspx", False),
    ]:
        try:
            fst, furl, fbody = form_login(user, pw, form_url, img)
        except Exception as e:  # keep going with the other forms
            print(f"Web-form {form_url}: error {type(e).__name__}")
            continue
        still_form = "Login1$Password" in fbody
        print(f"Web-form {form_url.split('?')[0]}: HTTP {fst}, ended at {furl.split('?')[0]}, "
              f"{'form shown again' if still_form else 'LEFT the login form'}; "
              f"message: {failure_text(fbody)!r}; cookies now: {sorted({c.name for c in jar})}")
    del pw
    print(f"Login HTTP {status}: {describe_result(text)}")
    print("Cookies received (names only):", sorted({c.name for c in jar}) or "none")
    sc = masked_set_cookies(LAST_HEADERS)
    print("Set-Cookie headers (values hidden):", sc or "none")
    safe_hdrs = [k for k in LAST_HEADERS.keys() if k.lower() != "set-cookie"]
    print("Other response headers (names only):", safe_hdrs)
    # Check whether the login session is accepted by another service:
    st, final, ctype, _ = fetch(BASE + "/Mailli.web/MailliSVC.svc?wsdl")
    print(f"Mail service after login: HTTP {st}, {ctype}, ended at {final.split('?')[0]}")

    report = []
    for svc in SERVICES:
        res = save_tree(svc)
        report.append(f"{svc}: {res}")
        print(f"  {svc}: {res}")
    with open(os.path.join(OUT, "_report.txt"), "w") as f:
        f.write(f"login http {status}; {describe_result(text)}\n")
        f.write("cookies: " + ", ".join(sorted({c.name for c in jar})) + "\n")
        f.write("\n".join(report) + "\n")
    print(f"\nDone. Saved to {OUT}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(1)
