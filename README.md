# نبض — تحليلات TikTok لعدة حسابات

تطبيق iPhone (iOS 16+) + خادم خاص، يعطيك لكل حساب TikTok:

- عدد المنشورات
- إجمالي المشاهدات
- متوسط المشاهدات لكل منشور
- الإعجابات والتعليقات والمشاركات
- عدد المتابعين
- أحدث المنشورات وتفاصيلها

بواجهة عربية داكنة وسلسة، ومزامنة لكل الحسابات بضغطة واحدة، وتصدير CSV.

> **مهم:** الأرقام تأتي من **TikTok Display API الرسمي**. لا يمكن قراءة إحصاءات حساب بمجرد رابط؛ كل حساب يجب أن يُربط مرة واحدة بتسجيل الدخول وموافقته. هذا هو الأسلوب الوحيد المستقر والمسموح. التفاصيل في [docs/tiktok-setup.md](docs/tiktok-setup.md).

## النسختان

| التطبيق | معرّف الحزمة | التقييم الأسبوعي |
|---|---|---|
| «نبض» | `com.nabd.pulse` | من المنشورات المتاحة (أحدث ١٠ في وضع القراءة المباشرة) |
| «المتابعة» | `com.nabd.mutabaa` | من **كل** منشورات آخر ٧ أيام لكل حساب |

«المتابعة» تطبيق منفصل ولا يستبدل «نبض». عندما لا تكفي المنشورات المختصرة،
يفتح صفحة الحساب العامة داخل `WKWebView` ويعترض استجابات قائمة المنشورات التي
يوقّعها TikTok بنفسه، ثم يجمع مشاهدات كل منشورات آخر ٧ أيام ويحسب التقييم منها —
بدون خادم وبدون تسجيل دخول وبدون VPN.

---

## ما الذي يعمل الآن؟

| الجزء | الحالة |
|---|---|
| تطبيق iOS (SwiftUI، عربي RTL، iOS 16) | ✅ كامل |
| وضع تجريبي داخلي بـ 50 حساباً | ✅ يعمل بدون خادم |
| خادم OAuth + TikTok Display API (Node.js) | ✅ كامل ومُختبَر |
| حفظ مشفّر للتوكنات + مزامنة تلقائية | ✅ |
| تصدير CSV / مشاركة | ✅ |
| بناء IPA عبر GitHub Actions | ✅ جاهز |
| حساب TikTok Developer ومفاتيحه | ⏳ يحتاج تسجيلك وموافقة TikTok |

---

## البدء السريع

### 1) الخادم محلياً

```bash
cd server
cp .env.example .env
npm install
npm start
```

يعمل على `http://localhost:8787`، ويبدأ بوضع تجريبي وبـ 50 حساباً جاهزاً.

فحص سريع:

```bash
npm run smoke
```

### 2) التطبيق

افتح المجلد في Xcode على Mac:

```bash
brew install xcodegen
xcodegen generate
open Nabd.xcodeproj
```

شغّله على آيفونك (iOS 16+). أو ابنِ IPA بدون Mac عبر GitHub Actions — [docs/build-ipa.md](docs/build-ipa.md).

عند أول تشغيل تجد 50 حساباً تمثيلياً حتى تربط خادمك. أوقف «الوضع التجريبي» من الإعدادات بعد إدخال عنوان الخادم ومفتاح `API_TOKEN`.

### 3) ربط TikTok

1. سجّل تطبيقاً في [TikTok for Developers](https://developers.tiktok.com/).
2. أضف المنتجين: **Login Kit** و **Display API**.
3. اطلب الصلاحيات: `user.info.basic`, `user.info.stats`, `video.list`.
4. ضع Redirect URI: `https://YOUR-SERVER/auth/tiktok/callback`.
5. انسخ `Client Key` و `Client Secret` إلى `server/.env`.
6. أعد تشغيل الخادم، ثم من التطبيق: الإعدادات → حفظ واتصال → الحسابات → إضافة → ربط.

الدليل المفصّل خطوة بخطوة: [docs/tiktok-setup.md](docs/tiktok-setup.md).

---

## كيف تُحسب الأرقام؟

| الرقم | المصدر |
|---|---|
| عدد المنشورات | `video_count` من `user/info` (إجمالي منشورات الحساب) |
| المشاهدات | مجموع `view_count` للمنشورات التي أرجعها `video/list` |
| متوسط المشاهدات | المشاهدات ÷ عدد المنشورات |
| الإعجابات/التعليقات/المشاركات | مجموع الحقول المقابلة في كل منشور |

TikTok لا يعطي «إجمالي مشاهدات الحساب» كما يظهر في التطبيق؛ لذلك نجمع مشاهدات المنشورات. السحب الافتراضي حتى **200 منشور** لكل حساب (`MAX_VIDEOS_PER_ACCOUNT`)، ولهذا يعرض التطبيق شارة **«تحليل جزئي»** وخط «تغطية التحليل» عندما تكون المنشورات أكثر من المسحوب. ارفع الحد إذا احتجت دقة أعلى (كل 20 منشوراً = طلب API واحد).

عند إضافة حساب جديد يظهر «غير مربوط» حتى تسجّل الدخول له مرة واحدة. التوكنات صالحة 24 ساعة وتُجدَّد تلقائياً عبر refresh token (سنة).

---

## بناء IPA وتثبيته على iOS 16

1. ارفع مجلد `TikTokPulse` إلى مستودع GitHub.
2. Actions → **Build Nabd IPA** → Run workflow.
3. نزّل `Nabd-unsigned-ipa` من Artifacts.
4. على ويندوز: افتح [Sideloadly](https://sideloadly.io/)، اسحب `Nabd.ipa`، أدخل Apple ID، ثم Start.
5. على الآيفون: الإعدادات → عام → VPN وإدارة الجهاز → ثق بالمطوّر.

بدون حساب Apple Developer مدفوع: التوقيع المجاني يعمل **7 أيام** ثم تعيد التثبيت. مع حساب مدفوع: سنة كاملة.

التفاصيل والمشاكل الشائعة: [docs/build-ipa.md](docs/build-ipa.md).

---

## نشر الخادم

الخادم Docker جاهز:

```bash
cd server
docker build -t nabd-server .
docker run -d -p 8787:8787 --env-file .env -v nabd-data:/data nabd-server
```

أو على Railway / Render / Fly.io / VPS. المطلوب:

- HTTPS إلزامي (TikTok يرفض redirect غير HTTPS، ما عدا localhost).
- `PUBLIC_BASE_URL` = عنوان الخادم العام.
- `TIKTOK_REDIRECT_URI` = `https://عنوانك/auth/tiktok/callback` **بنفس الحروف تماماً**.
- `API_TOKEN` قوي، و`TOKEN_ENC_KEY` عشوائي 32 بايت.

```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

### متغيرات البيئة

| المتغير | الوصف |
|---|---|
| `PORT` | منفذ الخادم (افتراضي 8787) |
| `PUBLIC_BASE_URL` | العنوان العام للخادم |
| `API_TOKEN` | المفتاح الذي يدخله التطبيق |
| `TOKEN_ENC_KEY` | مفتاح تشفير توكنات TikTok |
| `TIKTOK_CLIENT_KEY` / `TIKTOK_CLIENT_SECRET` | مفاتيح تطبيق TikTok |
| `TIKTOK_REDIRECT_URI` | رابط العودة المسجّل |
| `DEMO_MODE` | `1` بيانات تجريبية، `0` إنتاج |
| `MAX_VIDEOS_PER_ACCOUNT` | حد السحب لكل حساب (200) |
| `SYNC_CONCURRENCY` | عدد الحسابات المتزامنة (2) |
| `CACHE_TTL_SECONDS` | تجاهل المزامنة المتكررة (900) |

---

## الأمان والخصوصية

- كلمة مرور TikTok لا تمر عبر التطبيق ولا الخادم؛ تسجيل الدخول يحدث على نطاق TikTok.
- التوكنات مشفّرة AES-256-GCM في SQLite، والمفتاح من `TOKEN_ENC_KEY`.
- التطبيق يحمل `API_TOKEN` في Keychain، والخادم يرفض أي طلب بدونه.
- `state` أحادي الاستخدام لكل عملية ربط، ويُستهلك مرة واحدة.
- لا يُخزَّن أي شيء على خدمات طرف ثالث.
- التطبيق غير تابع لـ TikTok ولا تدعمه ByteDance.

---

## بنية المشروع

```
TikTokPulse/
├─ Nabd/                      تطبيق SwiftUI
│  ├─ Models/                 نماذج البيانات وفك ترميز مرن
│  ├─ Services/               APIClient، AppStore، OAuth، Keychain، DemoData
│  ├─ Views/                  Dashboard، Accounts، Detail، Add، Settings
│  └─ Resources/Assets.xcassets
├─ server/                    خادم Node.js + SQLite
│  ├─ src/                    config، db، tiktok، sync، routes، server
│  └─ scripts/                smoke test
├─ docs/                      أدلة TikTok وبناء IPA وواجهة API
├─ scripts/make-icon.js       توليد الأيقونة
├─ project.yml                مشروع XcodeGen
└─ .github/workflows/         بناء IPA غير موقّع
```

---

## استكشاف الأخطاء

| المشكلة | الحل |
|---|---|
| «تعذّر الاتصال بالخادم» | تأكد أن الخادم يعمل، وأن العنوان بلا `/` في النهاية، وأن الآيفون على نفس الشبكة عند التجربة المحلية |
| `unauthorized` | `API_TOKEN` في التطبيق يختلف عن الخادم |
| `not_configured` | مفاتيح TikTok غير مضبوطة في `.env` |
| `needs_reconnect` | انتهت صلاحية التوكن — اضغط «ربط الحساب» |
| `scope_not_authorized` | لم تُوافق TikTok على `video.list` لتطبيقك بعد |
| «تحليل جزئي» | الحساب لديه منشورات أكثر من حد السحب؛ ارفع `MAX_VIDEOS_PER_ACCOUNT` |
| البناء يفشل على Actions | تأكد أن `project.yml` و`Nabd/` في جذر المستودع |

---

## أفكار للتطوير التالي

- رسوم بيانية لتطور المشاهدات يومياً (تخزين لقطات تاريخية في جدول `snapshots`).
- تنبيهات عند تجاوز منشور حداً معيناً (Push).
- مقارنة أسبوعية بين الحسابات.
- دعم حسابات متعددة لمالك واحد عبر مجموعات (Groups) وصلاحيات.
- تصدير PDF بعلامتك التجارية.
