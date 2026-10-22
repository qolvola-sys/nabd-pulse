import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");

const num = (value, fallback) => {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
};

const trimSlash = (value) => String(value || "").replace(/\/+$/, "");

export const config = {
  port: num(process.env.PORT, 8787),
  publicBaseUrl: trimSlash(process.env.PUBLIC_BASE_URL || `http://localhost:${num(process.env.PORT, 8787)}`),
  apiToken: process.env.API_TOKEN || "",
  tokenEncKey: process.env.TOKEN_ENC_KEY || "nabd-dev-key-change-me",
  dataDir: path.resolve(root, process.env.DATA_DIR || "./data"),

  tiktok: {
    clientKey: process.env.TIKTOK_CLIENT_KEY || "",
    clientSecret: process.env.TIKTOK_CLIENT_SECRET || "",
    redirectUri: process.env.TIKTOK_REDIRECT_URI || "",
    scopes: process.env.TIKTOK_SCOPES || "user.info.basic,user.info.stats,video.list",
    authorizeUrl: "https://www.tiktok.com/v2/auth/authorize/",
    tokenUrl: "https://open.tiktokapis.com/v2/oauth/token/",
    apiBase: "https://open.tiktokapis.com/v2",
  },

  demoMode: String(process.env.DEMO_MODE ?? "1") !== "0",
  maxVideosPerAccount: num(process.env.MAX_VIDEOS_PER_ACCOUNT, 200),
  syncConcurrency: Math.max(1, num(process.env.SYNC_CONCURRENCY, 2)),
  cacheTtlSeconds: num(process.env.CACHE_TTL_SECONDS, 900),
};

export const hasTikTokCredentials = Boolean(config.tiktok.clientKey && config.tiktok.clientSecret);

if (!config.tiktok.redirectUri) {
  config.tiktok.redirectUri = `${config.publicBaseUrl}/auth/tiktok/callback`;
}

export function assertProductionSafety() {
  const warnings = [];
  if (!config.apiToken || config.apiToken === "please-change-me") {
    warnings.push("API_TOKEN غير مضبوط — الخادم مفتوح لأي طلب. اضبطه قبل النشر.");
  }
  if (config.tokenEncKey === "nabd-dev-key-change-me") {
    warnings.push("TOKEN_ENC_KEY افتراضي — توكنات TikTok مشفّرة بمفتاح معروف.");
  }
  if (!hasTikTokCredentials) {
    warnings.push("مفاتيح TikTok غير مضبوطة — وضع البيانات التجريبية فقط.");
  }
  return warnings;
}
