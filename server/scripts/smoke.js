/**
 * اختبار سريع للخادم: يتحقق من كل المسارات الأساسية.
 * الاستخدام: npm run smoke  (أو BASE_URL=https://... node scripts/smoke.js)
 */
const BASE = process.env.BASE_URL || "http://localhost:8787";
const TOKEN = process.env.API_TOKEN || "";
const headers = { "Content-Type": "application/json", ...(TOKEN ? { Authorization: `Bearer ${TOKEN}` } : {}) };

let passed = 0;
let failed = 0;

function check(name, condition, extra = "") {
  if (condition) {
    passed += 1;
    console.log(`  ✓ ${name}`);
  } else {
    failed += 1;
    console.log(`  ✗ ${name} ${extra}`);
  }
}

async function json(path, options = {}) {
  const response = await fetch(`${BASE}${path}`, { headers, ...options });
  const body = await response.json().catch(() => ({}));
  return { status: response.status, body };
}

console.log(`\nاختبار الخادم: ${BASE}\n`);

const health = await json("/health");
check("health يعمل", health.status === 200 && health.body.ok === true, JSON.stringify(health.body));

const summary = await json("/api/summary");
check("ملخص الإحصاءات", summary.status === 200 && typeof summary.body.summary?.views === "number");
console.log(`    الحسابات: ${summary.body.summary?.accounts} | المنشورات: ${summary.body.summary?.posts} | المشاهدات: ${summary.body.summary?.views}`);

const accounts = await json("/api/accounts");
check("قائمة الحسابات", accounts.status === 200 && Array.isArray(accounts.body.accounts));
const first = accounts.body.accounts?.[0];

const detail = first ? await json(`/api/accounts/${first.id}`) : { status: 0 };
check("تفاصيل حساب + فيديوهات", detail.status === 200 && Array.isArray(detail.body.videos));

const add = await json("/api/accounts", {
  method: "POST",
  body: JSON.stringify({ links: ["https://www.tiktok.com/@smoke_test_one?lang=ar", "@smoke_test_two", "!!!"] }),
});
check(
  "إضافة روابط (رابط كامل + معرف + رابط خاطئ)",
  add.status === 201 && add.body.created?.length === 2 && add.body.invalid?.length === 1,
  JSON.stringify(add.body),
);

for (const account of add.body.created ?? []) {
  const sync = await json(`/api/accounts/${account.id}/sync`, { method: "POST" });
  check(`مزامنة @${account.handle}`, sync.status === 200 && typeof sync.body.account?.views === "number");
  const removed = await fetch(`${BASE}/api/accounts/${account.id}`, { method: "DELETE", headers });
  check(`حذف @${account.handle}`, removed.status === 200);
}

const syncAll = await json("/api/sync", { method: "POST", body: JSON.stringify({}) });
check("مزامنة الكل", syncAll.status === 200 && Array.isArray(syncAll.body.results));

const csv = await fetch(`${BASE}/api/export.csv`, { headers });
const csvText = await csv.text();
check(
  "تصدير CSV (ترويسة عربية + صفوف)",
  csv.status === 200 && csvText.replace(/^\uFEFF/, "").startsWith('"المنصة"') && csvText.split("\r\n").length > 2,
  `status=${csv.status} head=${JSON.stringify(csvText.slice(0, 20))}`,
);

const meta = await json("/api/meta");
check("بيانات الوصف", meta.status === 200 && meta.body.platform === "tiktok");

console.log(`\nالنتيجة: ${passed} ناجح، ${failed} فاشل\n`);
process.exit(failed ? 1 : 0);
