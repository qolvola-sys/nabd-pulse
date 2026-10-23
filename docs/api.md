# واجهة الخادم (REST API)

العنوان الافتراضي: `http://localhost:8787`

كل مسارات `/api` تتطلب:

```
Authorization: Bearer <API_TOKEN>
```

الاستجابات JSON بترميز UTF-8. أخطاء الشكل:

```json
{ "error": { "code": "unauthorized", "message": "مفتاح الوصول غير صحيح" } }
```

---

## الصحة

### `GET /health`
بدون مصادقة.

```json
{ "ok": true, "service": "nabd-pulse", "version": "1.0.0", "demo": true, "tiktokConfigured": false }
```

---

## الحسابات

### `GET /api/accounts?q=&sort=`
`sort`: `views` | `posts` | `followers` | `name` | `recent`

```json
{
  "accounts": [
    {
      "id": "b1f...", "platform": "tiktok", "handle": "matbakh_sara",
      "url": "https://www.tiktok.com/@matbakh_sara",
      "displayName": "مطبخ سارة", "avatarUrl": null, "isVerified": false,
      "followers": 1231455, "following": 164, "likes": 9225201,
      "posts": 226, "views": 115338348, "videoLikes": 9225201,
      "comments": 396991, "shares": 769015,
      "fetchedVideos": 40, "avgViews": 510347, "coverage": 0.177,
      "connected": true, "status": "ok", "error": null,
      "lastSyncedAt": "2026-10-22T01:32:26.892Z", "createdAt": "..."
    }
  ],
  "summary": { "accounts": 50, "connected": 50, "posts": 6953, "views": 936173282, "likes": 72994232, "comments": 3807432, "shares": 6705797, "avgViews": 134643, "lastSyncedAt": "..." }
}
```

### `POST /api/accounts`
يقبل رابطاً كاملاً، رابط مشاركة قصيراً (`vm.tiktok.com`)، أو `@handle` أو handle مجرد.

```json
{ "links": ["https://www.tiktok.com/@user1", "@user2", "user3"] }
```

```json
{
  "created": [ { "id": "...", "handle": "user1", "status": "pending", ... } ],
  "skipped": [ { "handle": "user2", "id": "...", "reason": "duplicate" } ],
  "invalid": ["!!!"],
  "accounts": [ ... ]
}
```

الحالة `201`. الحد الأقصى 500 رابط في الطلب.

### `GET /api/accounts/:id?limit=40`
يعيد الحساب + فيديوهاته (الأحدث أولاً).

```json
{
  "account": { ... },
  "videos": [
    { "id": "710...", "title": "...", "coverUrl": null, "shareUrl": "...",
      "duration": 42, "createTime": 1729500000, "views": 514000,
      "likes": 32000, "comments": 410, "shares": 900 }
  ]
}
```

### `PATCH /api/accounts/:id`
```json
{ "displayName": "اسم مخصّص" }
```

### `DELETE /api/accounts/:id`
```json
{ "deleted": "b1f..." }
```

### `POST /api/accounts/:id/sync`
يجبر مزامنة حساب واحد (يتجاوز الكاش).

### `POST /api/accounts/:id/disconnect`
يحذف التوكنات ويجعل الحساب «غير مربوط».

---

## المزامنة

### `POST /api/sync`
```json
{ "force": true }
```

```json
{
  "syncedAt": "2026-10-22T01:40:00.000Z",
  "total": 50,
  "results": [ { "id": "...", "ok": true }, { "id": "...", "ok": false, "error": "..." } ],
  "summary": { ... }
}
```

المزامنة تحترم `CACHE_TTL_SECONDS` إلا مع `force`. العدد المتوازي = `SYNC_CONCURRENCY`.

---

## الملخص

### `GET /api/summary`
```json
{ "summary": { ... }, "top": [ ... أعلى 5 حسابات ... ] }
```

### `GET /api/meta`
```json
{
  "platform": "tiktok",
  "demo": false,
  "tiktokConfigured": true,
  "maxVideosPerAccount": 200,
  "cacheTtlSeconds": 900,
  "serverTime": "...",
  "seeded": false
}
```

### `GET /api/export.csv`
CSV بترميز UTF-8 مع BOM (يفتح مباشرة في Excel). الأعمدة:

`المنصة, الحساب, الاسم, الرابط, المنشورات, المشاهدات, متوسط المشاهدات, الإعجابات, التعليقات, المشاركات, المتابعون, آخر مزامنة`

يمكن تمرير `?token=` بدل الترويسة عند التنزيل من المتصفح.

---

## OAuth (بدون Bearer)

### `GET /auth/tiktok/start?account=ID`
ينشئ `state` أحادي الاستخدام ويحوّل (302) إلى صفحة TikTok.

### `GET /auth/tiktok/callback?code=&state=`
- يتحقق من `state` ويستهلكه.
- يتبادل `code` بتوكن.
- يقرأ معلومات الحساب ويحفظ التوكن مشفّراً.
- يبدأ مزامنة في الخلفية.
- يعيد صفحة HTML عربية تُحوّل إلى `nabd://oauth?status=ok&account=...`، فيلتقطها التطبيق ويغلق المتصفح.

أخطاء `state`: صفحة تطلب إعادة المحاولة من التطبيق.

---

## رموز الأخطاء الشائعة

| code | HTTP | المعنى |
|---|---|---|
| `unauthorized` | 401 | توكن التطبيق خطأ |
| `not_found` | 404 | حساب/مسار غير موجود |
| `not_connected` | 409 | لا توجد توكنات لهذا الحساب |
| `needs_reconnect` | 409 | انتهت صلاحية refresh token |
| `not_configured` | 503 | مفاتيح TikTok ناقصة |
| `scope_not_authorized` | 502 | صلاحية غير موافَق عليها |
| `rate_limit_exceeded` | 502 | تجاوز حد TikTok |
| `bad_response` | 502 | رد غير متوقع من TikTok |

---

## أمثلة

```bash
# قائمة مرتبة بالمشاهدات
curl -H "Authorization: Bearer $TOKEN" "http://localhost:8787/api/accounts?sort=views"

# إضافة 3 حسابات
curl -X POST http://localhost:8787/api/accounts \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"links":["https://www.tiktok.com/@a","@b","c"]}'

# مزامنة الكل
curl -X POST http://localhost:8787/api/sync \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"force":true}'

# تصدير
curl -H "Authorization: Bearer $TOKEN" -o accounts.csv http://localhost:8787/api/export.csv
```
