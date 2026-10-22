# بناء IPA وتثبيته على iPhone (iOS 16)

لا تحتاج Mac. البناء يحدث على GitHub Actions (خادم macOS مجاني للمستودعات العامة)، والنتيجة IPA غير موقّع توقّعه على ويندوز بـ Sideloadly.

---

## الطريقة أ — GitHub Actions (موصى بها)

### 1) ارفع المشروع

أنشئ مستودعاً جديداً (يفضّل **Private**) وارفع **محتويات** مجلد `TikTokPulse` إلى جذره، بحيث يكون:

```
project.yml
Nabd/
.github/workflows/build-ipa.yml
server/
```

> المهم أن يكون `project.yml` في الجذر، وليس داخل مجلد فرعي.

### 2) شغّل البناء

1. افتح المستودع → **Actions**.
2. اختر **Build Nabd IPA** → **Run workflow**.
3. انتظر 5–12 دقيقة.
4. افتح آخر تشغيل → **Artifacts** → `Nabd-unsigned-ipa` → نزّل الملف وفك ضغطه لتحصل على `Nabd.ipa`.

### 3) التوقيع والتثبيت على ويندوز

1. نزّل [Sideloadly](https://sideloadly.io/) وثبّته (يحتاج iTunes من موقع Apple، وليس من Microsoft Store).
2. وصّل الآيفون بالكابل واضغط Trust.
3. اسحب `Nabd.ipa` إلى نافذة Sideloadly.
4. أدخل **Apple ID** العادي (بدون كلمة مرور TikTok).
   - إن ظهرت مشكلة 2FA: أنشئ **App-Specific Password** من <https://appleid.apple.com> واستخدمه.
5. اضغط **Start**، وانتظر حتى تظهر `Done`.

### 4) الثقة بالتطبيق على الآيفون

1. الإعدادات → عام → **VPN & Device Management**.
2. اختر بريدك تحت **Developer App** → **Trust**.
3. إن ظهر خيار **Developer Mode** (iOS 16): الإعدادات → الخصوصية والأمان → **Developer Mode** → تشغيل → إعادة تشغيل الجهاز.

### 5) مدة الصلاحية

| نوع الحساب | المدة | التجديد |
|---|---|---|
| Apple ID مجاني | 7 أيام | أعد التثبيت من Sideloadly، أو استخدم AltStore للتجديد التلقائي |
| Apple Developer Program (99$/سنة) | سنة | أعد التوقيع سنوياً؛ ويمكن التوزيع Ad Hoc على 100 جهاز |

> التطبيق لا يحتاج إعادة تثبيت عند انتهاء الشهادة إن كنت تستخدم حساباً مدفوعاً. مع المجاني، أعِد التثبيت كل 7 أيام — بيانات التطبيق تبقى.

---

## الطريقة ب — Xcode على Mac

```bash
brew install xcodegen
cd TikTokPulse
xcodegen generate
open Nabd.xcodeproj
```

1. اختر Target `Nabd` → Signing & Capabilities.
2. فعّل **Automatically manage signing** واختر Team (حساب Apple ID يكفي).
3. غيّر Bundle Identifier إن لزم (`com.nabd.pulse` قد يكون محجوزاً).
4. اختر آيفونك → Run.

Xcode يثبّت التطبيق مباشرة، وصلاحيته 7 أيام مع الحساب المجاني.

---

## الطريقة ج — EAS / Codemagic

المشروع لا يعتمد على أي مدير حزم لـ iOS، لذا يمكنك أيضاً:

- **Codemagic**: أضف خطوة `xcodegen generate` ثم `xcodebuild ... CODE_SIGNING_ALLOWED=NO` وأخرج IPA غير موقّع.
- **EAS**: غير مناسب هنا لأنه موجّه لتطبيقات Expo/React Native.

---

## مشاكل شائعة

| المشكلة | الحل |
|---|---|
| `Unable to install "Nabd"` | أعد التوقيع؛ غالباً الشهادة أو الـ IPA تالف. جرّب كابلاً/منفذاً آخر |
| `Untrusted Developer` | الإعدادات → عام → VPN & Device Management → Trust |
| `This app is not supported on your device` | تأكد أن `MinimumOSVersion` = 16.0 وأن الجهاز iOS 16+ |
| `Provision.cpp:150` أو فشل التوقيع | أنشئ App-Specific Password، أو جرّب حساب Apple ID آخر |
| البناء يفشل: `xcodegen: command not found` | تأكد من خطوة `brew install xcodegen` |
| البناء يفشل: `Nabd.xcodeproj not found` | `project.yml` ليس في جذر المستودع |
| شاشة بيضاء عند الفتح | افتح Console في Xcode، أو أعد التثبيت بعد حذف التطبيق القديم |
| التطبيق يفتح ثم يُغلق | غالباً توقيع/Entitlements؛ أعد التثبيت بحساب مطوّر |

---

## ملاحظات مهمة للتوزيع

- IPA غير الموقّع **لا يعمل** إلا بعد توقيعه (Sideloadly/AltStore/Xcode).
- لا يمكن نشره على App Store بهذه الطريقة؛ ذلك يحتاج حساب مطوّر ومراجعة Apple.
- للتوزيع الداخلي على عدة أجهزة iPhone: حساب مطوّر مدفوع + Ad Hoc (حتى 100 جهاز) أو TestFlight.
- احتفظ بـ `Bundle Identifier` ثابتاً حتى لا تفقد البيانات عند التحديث.
