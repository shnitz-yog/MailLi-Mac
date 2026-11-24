<div dir="rtl">

# ✉️ מייל לי למק

אפליקציה למק שמאפשרת לילדים בגן לקרוא ולשלוח מכתבים במערכת **"מייל לי"** של גוגלה,
גם בבית שאין בו מחשב ווינדוס.

האפליקציה בנויה כמו התוכנה שהילדים מכירים ב-PC: פס צהוב למעלה, כפתורים גדולים עם תמונות,
מקלדת עברית על המסך, חותמות, ברכות ורקעים, ואימוג'ים.

> ⚠️ **זו אפליקציה לא רשמית** שנבנתה על ידי הורה, ואין לה קשר לחברת גוגלה.
> היא עובדת מול אותם שרתים של התוכנה הרגילה. אם גוגלה ישנו משהו במערכת, ייתכן שהיא תפסיק לעבוד עד שתצא גרסה מעודכנת.

---

## ⬇️ הורדה

**[להורדת MailLi.dmg](https://github.com/shnitz-yog/MailLi-Mac/releases/latest/download/MailLi.dmg)**

דרישות: macOS 14 (Sonoma) ומעלה. עובד על מקים עם מעבד M ועל מקים עם מעבד Intel.

## 🛠️ התקנה

1. פותחים את הקובץ `MailLi.dmg` שהורדתם.
2. בחלון שנפתח גוררים את **MailLi** לתיקייה **Applications**.
3. פותחים את MailLi מתוך תיקיית Applications.

### בפעם הראשונה: אישור האפליקציה

האפליקציה לא נמכרת ב-App Store ולא חתומה אצל אפל, ולכן בפעם הראשונה המק יציג הודעה שהוא "לא יכול לאמת" אותה.
מאשרים פעם אחת:

**macOS 15 ומעלה**
1. בהודעה לוחצים **"סיום"** (Done).
2. פותחים **הגדרות המערכת ← פרטיות ואבטחה** (Privacy & Security).
3. גוללים למטה, ליד "MailLi נחסם" לוחצים **"לפתוח בכל זאת"** (Open Anyway), ומקלידים את סיסמת המק.

**macOS 14**
- לוחצים על MailLi עם הכפתור הימני (או Control + לחיצה) ← **"פתיחה"** ← **"פתיחה"**.

**אם כתוב רק שאי אפשר לפתוח, ובהגדרות אין "לפתוח בכל זאת"**
(קורה בעיקר כשהקובץ הגיע בוואטסאפ): פותחים את **Terminal**, מדביקים את השורה הזו ולוחצים Enter:

<div dir="ltr">

```bash
xattr -dr com.apple.quarantine /Applications/MailLi.app
```

</div>

הפקודה מסירה רק מהאפליקציה הזו את הסימון "הורד מהאינטרנט". עשו את זה רק אם הורדתם את הקובץ מהעמוד הזה.

## 🔄 עדכונים

האפליקציה בודקת בעצמה פעם ביום אם יצאה גרסה חדשה. אם כן, מופיעה הודעה "יש גרסה חדשה של מייל לי!".
לוחצים **"לעדכן עכשיו"**, והאפליקציה מורידה את הגרסה, בודקת שהיא תקינה, מתקינה אותה ונפתחת מחדש.
לא צריך להוריד שוב ולא צריך לאשר שוב בהגדרות.
אפשר גם לבדוק בעצמכם: בתפריט **מייל לי ← בדיקת עדכונים…**

## 🔑 כניסה

- מקלידים את **שם המשתמש והסיסמה של הילד** שקיבלתם מהגן, אותם פרטים שנכנסים איתם בתוכנה ב-PC.
- הסיסמה מוצגת בכוונה, כדי שאפשר יהיה להקליד אותה **בעברית**. כשהיא מוסתרת, המק מאפשר להקליד רק באנגלית.
- מסמנים **"לזכור אותי"**, ומאז האפליקציה נפתחת ישר למסך של הילד.
- כפתור היציאה הוא הכפתור האפור הקטן בפינת הפס הצהוב.

### לא מצליחים להתחבר?

- **בודקים שהפרטים הם של הילד ולא של ההורה.** לפעמים הגן שולח גם פרטי כניסה להורים.
- **בודקים שהפרטים עובדים באתר:** <span dir="ltr">galeli.com/MailLi.Web/login.aspx</span>. אם גם שם הכניסה לא עובדת, צריך לאפס סיסמה דרך הקישור באתר או לפנות לגן.
- **שמים לב לשפה של הסיסמה** (עברית או אנגלית) ולרווחים מיותרים בסוף.
- האפליקציה מציגה מה בדיוק לא עבד: פרטים שגויים, חשבון של הורה, מנוי שהסתיים, או בעיית אינטרנט.

## 🔒 פרטיות

- האפליקציה מתחברת **רק** לשרתים של המערכת (galeli.com), כמו התוכנה הרגילה.
- הסיסמה נשמרת **רק במחשב שלכם**, בצרור המפתחות (Keychain) של המק, ולא נשלחת לשום מקום אחר.
- אין באפליקציה פרסומות, מעקב או איסוף נתונים.

## ❓ מה יש באפליקציה

| מסך | מה עושים בו |
|---|---|
| **מייל לי** | שני כפתורים גדולים, "לשלוח מכתב" ו"לקבל מכתב", ועליו מספר המכתבים החדשים |
| **לקבל מכתב** | המכתבים ככרטיסים עם מעטפה, תאריך, שם ותמונה של השולח. מעטפה סגורה היא מכתב חדש. מסמנים כמה מכתבים (או "סימון הכל") ומוחקים בבת אחת |
| **מכתב שקיבלתי** | קריאת המכתב, לענות, למחוק, להדפיס, למכתב הקודם / הבא |
| **לשלוח מכתב** | "למי אכתוב?" עם כמה נמענים מכל הקבוצות ו"סימון כל ילדי הגן", כתיבה במקלדת עברית על המסך, ברכות ו"רציתי לספר", חותמות שלא מסתירות את המילים (צבע, מחק, גודל, הזזה), ואימוג'ים |

המכתבים נשמרים באותו פורמט של התוכנה ב-PC, כך שבגן ואצל ההורים הם נראים כרגיל,
וההורים מקבלים אותם במייל כתמונה.

---

## 👩‍💻 למפתחים

</div>

Native SwiftUI app (macOS 14+), no dependencies. Talks to the same WCF/SOAP services on `galeli.com` as the Windows
UWP app: forms login (`.ASPXFORMSAUTH` cookie) → `GoogaleSVC/GetAppStartupForLoggedInUser` (student id) →
`MailliSVC` (inbox / sent / message / send / delete / address book & stamps) and `FIleUploader` (PNG of the letter,
which the server e-mails to parents). Letters are zlib-compressed XML (`<Content><RichEdit Text="/c01/s3…"/>…`),
stamps are XAML paths, greetings are PNGs drawn top-centre at natural size.

```bash
./build.sh          # MailLi.app for this Mac
./build.sh --dist   # universal app + MailLi.dmg with the drag-to-Applications window
```

| Path | |
|---|---|
| `Sources/MailLi/MailLiClient.swift` | login, SOAP calls, sending, upload |
| `Sources/MailLi/Models.swift` | letter format (parse/build), address types, colour/size codes |
| `Sources/MailLi/Stamps.swift` | XAML path parser for stamps |
| `Sources/MailLi/*View.swift`, `Theme.swift` | the PC-style screens |
| `Sources/MailLi/SelfTest.swift`, `ScreenShots.swift` | `--selftest <dir>` / `--screens <dir>` offline checks against saved replies |
| `tools/discover.py`, `tools/probe.py` | protocol discovery (password typed locally, never saved). Output folders are git-ignored because they contain real data. |
| `dist/` | DMG artwork (`make_art.swift`), Finder layout script, Hebrew install notes |

Compiles with the Command Line Tools only (no Xcode): `@Local` in `Util.swift` replaces SwiftUI's `@State`,
whose macro plugin ships only with Xcode.

<div dir="rtl">

**לא רשמי, ללא קשר לגוגלה.** "מייל לי" וגוגלה הם סימנים של בעליהם.
האיורים בתוך האפליקציה נטענים מהשרת של גוגלה בזמן השימוש, בדיוק כמו בתוכנה המקורית, ואינם כלולים במאגר הזה.

</div>
