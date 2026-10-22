import express from "express";
import { assertProductionSafety, config, hasTikTokCredentials } from "./config.js";
import { api, auth } from "./routes.js";
import { seedDemoAccountsIfEmpty } from "./demo.js";
import { safeEqual } from "./security.js";

export function createServer() {
  const app = express();
  app.disable("x-powered-by");
  app.set("trust proxy", true);
  app.use(express.json({ limit: "512kb" }));
  app.use(express.urlencoded({ extended: false }));

  app.use((req, res, next) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Headers", "Authorization, Content-Type");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS");
    if (req.method === "OPTIONS") return res.sendStatus(204);
    const started = Date.now();
    res.on("finish", () => {
      if (process.env.QUIET === "1") return;
      console.log(`${req.method} ${req.originalUrl.split("?")[0]} → ${res.statusCode} (${Date.now() - started}ms)`);
    });
    next();
  });

  app.get("/health", (req, res) => {
    res.json({
      ok: true,
      service: "nabd-pulse",
      version: "1.0.0",
      demo: config.demoMode,
      tiktokConfigured: hasTikTokCredentials,
      time: new Date().toISOString(),
    });
  });

  app.get("/", (req, res) => {
    res.type("html").send(`<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>نبض — خادم التحليلات</title>
<style>body{background:#0B0D12;color:#F5F7FA;font-family:-apple-system,Tahoma,sans-serif;display:grid;place-items:center;min-height:100vh;margin:0}
.card{padding:28px 32px;border:1px solid #232936;border-radius:20px;background:#12151D;max-width:420px}
h1{margin:0 0 8px;font-size:20px}p{color:#9AA3B2;line-height:1.8;font-size:14px}
code{background:#1B202B;padding:2px 6px;border-radius:6px}</style>
<div class="card"><h1>نبض يعمل ✓</h1>
<p>خادم تحليلات TikTok جاهز. الحالة: <code>${config.demoMode ? "وضع تجريبي" : "إنتاج"}</code><br>
مفاتيح TikTok: <code>${hasTikTokCredentials ? "مضبوطة" : "غير مضبوطة"}</code></p>
<p>افحص <a style="color:#25F4EE" href="/health">/health</a></p></div></html>`);
  });

  // ربط TikTok يصل من متصفح الجهاز بدون توكن، والحماية عبر state أحادي الاستخدام
  app.use("/auth", auth);

  // المصادقة: كل مسارات /api تتطلب توكن التطبيق
  app.use((req, res, next) => {
    if (!config.apiToken) return next();
    const header = req.get("authorization") || "";
    const bearer = header.startsWith("Bearer ") ? header.slice(7) : "";
    const provided = bearer || String(req.query.token || "");
    if (safeEqual(provided, config.apiToken)) return next();
    res.status(401).json({ error: { code: "unauthorized", message: "مفتاح الوصول غير صحيح" } });
  });

  app.use("/api", api);

  app.use((req, res) => {
    res.status(404).json({ error: { code: "not_found", message: "المسار غير موجود" } });
  });

  app.use((error, req, res, next) => { // eslint-disable-line no-unused-vars
    const status = error.status && error.status >= 400 && error.status < 600 ? error.status : 500;
    if (status >= 500) console.error("✖", error);
    res.status(status).json({
      error: {
        code: error.code || "server_error",
        message: error.message || "خطأ في الخادم",
        ...(error.logId ? { logId: error.logId } : {}),
      },
    });
  });

  return app;
}

export function start() {
  if (config.demoMode) seedDemoAccountsIfEmpty();
  const warnings = assertProductionSafety();
  for (const warning of warnings) console.warn("⚠ ", warning);

  const app = createServer();
  app.listen(config.port, "0.0.0.0", () => {
    console.log(`\nنبض — الخادم يعمل على المنفذ ${config.port}`);
    console.log(`   العنوان العام: ${config.publicBaseUrl}`);
    console.log(`   الوضع: ${config.demoMode ? "تجريبي (بيانات جاهزة)" : "إنتاج"}`);
    console.log(`   TikTok: ${hasTikTokCredentials ? "مفاتيح مضبوطة" : "بدون مفاتيح"}\n`);
  });
}
