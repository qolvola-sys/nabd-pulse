import express from "express";
import { config } from "./config.js";
import {
  cleanupOAuthStates, clearTokens, db, deleteAccount, getAccount, getAccountByHandle,
  getMeta, insertAccount, listAccounts, listVideos, saveTokenRow, setMeta, updateAccount,
} from "./db.js";
import { encryptSecret, randomId, randomState } from "./security.js";
import { buildAuthorizeUrl, exchangeCode, fetchUserInfo, TikTokError } from "./tiktok.js";
import { syncAccount, syncAll } from "./sync.js";
import { seedDemoAccountsIfEmpty } from "./demo.js";

const api = express.Router();
const auth = express.Router();

const AVG = (views, posts) => (posts > 0 ? Math.round(views / posts) : 0);

function serializeAccount(row) {
  if (!row) return null;
  return {
    id: row.id,
    platform: "tiktok",
    handle: row.handle,
    url: row.input_url || `https://www.tiktok.com/@${row.handle}`,
    displayName: row.display_name || `@${row.handle}`,
    avatarUrl: row.avatar_url || null,
    isVerified: Boolean(row.is_verified),
    followers: row.follower_count ?? 0,
    following: row.following_count ?? 0,
    likes: row.likes_count ?? 0,
    posts: row.video_count ?? 0,
    views: row.total_views ?? 0,
    videoLikes: row.total_likes ?? 0,
    comments: row.total_comments ?? 0,
    shares: row.total_shares ?? 0,
    fetchedVideos: row.fetched_videos ?? 0,
    avgViews: AVG(row.total_views ?? 0, row.video_count ?? 0),
    coverage: row.video_count > 0 ? Math.min(1, (row.fetched_videos ?? 0) / row.video_count) : 0,
    connected: Boolean(row.connected),
    status: row.status || "pending",
    error: row.error || null,
    lastSyncedAt: row.last_synced_at || null,
    createdAt: row.created_at,
  };
}

export function parseHandle(input) {
  let value = String(input || "").trim();
  if (!value) return null;
  value = value.replace(/^https?:\/\//i, "").replace(/^www\./i, "");
  value = value.replace(/^tiktok\.com\//i, "").replace(/^m\.tiktok\.com\//i, "");
  value = value.split(/[?#]/)[0].replace(/\/+$/, "");
  value = value.replace(/^@/, "");
  const direct = value.match(/^([A-Za-z0-9._]{2,24})$/);
  if (direct && !direct[1].toLowerCase().endsWith(".com")) return direct[1].toLowerCase();
  const withAt = String(input).match(/@([A-Za-z0-9._]{2,24})/);
  return withAt ? withAt[1].toLowerCase() : null;
}

const SHORT_HOSTS = new Set(["vm.tiktok.com", "vt.tiktok.com", "www.tiktok.com", "tiktok.com"]);

/** يحل روابط المشاركة القصيرة (vm.tiktok.com/ZM...) إلى اسم المستخدم */
async function resolveShortLink(input) {
  let url;
  try {
    url = new URL(String(input).trim());
  } catch {
    return null;
  }
  if (!SHORT_HOSTS.has(url.hostname.toLowerCase())) return null;
  try {
    const response = await fetch(url, {
      redirect: "follow",
      headers: { "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15" },
      signal: AbortSignal.timeout(12_000),
    });
    return parseHandle(response.url);
  } catch {
    return null;
  }
}

export function summaryOf(rows) {
  const posts = rows.reduce((s, a) => s + (a.video_count ?? 0), 0);
  const views = rows.reduce((s, a) => s + (a.total_views ?? 0), 0);
  const likes = rows.reduce((s, a) => s + (a.total_likes ?? 0), 0);
  const comments = rows.reduce((s, a) => s + (a.total_comments ?? 0), 0);
  const shares = rows.reduce((s, a) => s + (a.total_shares ?? 0), 0);
  const synced = rows.map((a) => a.last_synced_at).filter(Boolean).sort().at(-1) ?? null;
  return {
    accounts: rows.length,
    connected: rows.filter((a) => a.connected).length,
    posts,
    views,
    likes,
    comments,
    shares,
    avgViews: AVG(views, posts),
    lastSyncedAt: synced,
  };
}

api.get("/summary", (req, res) => {
  const rows = listAccounts();
  res.json({
    summary: summaryOf(rows),
    top: [...rows].sort((a, b) => (b.total_views ?? 0) - (a.total_views ?? 0)).slice(0, 5).map(serializeAccount),
  });
});

api.get("/accounts", (req, res) => {
  const q = String(req.query.q || "").trim().toLowerCase();
  const sort = String(req.query.sort || "views");
  let rows = listAccounts();

  if (q) {
    rows = rows.filter((a) =>
      a.handle.toLowerCase().includes(q) || (a.display_name || "").toLowerCase().includes(q));
  }
  const sorters = {
    views: (a, b) => (b.total_views ?? 0) - (a.total_views ?? 0),
    posts: (a, b) => (b.video_count ?? 0) - (a.video_count ?? 0),
    followers: (a, b) => (b.follower_count ?? 0) - (a.follower_count ?? 0),
    name: (a, b) => String(a.display_name || a.handle).localeCompare(String(b.display_name || b.handle), "ar"),
    recent: (a, b) => String(b.last_synced_at || "").localeCompare(String(a.last_synced_at || "")),
  };
  rows.sort(sorters[sort] || sorters.views);

  res.json({ accounts: rows.map(serializeAccount), summary: summaryOf(rows) });
});

api.post("/accounts", async (req, res, next) => {
  try {
    const raw = req.body?.links ?? req.body?.link ?? req.body?.handles ?? [];
    const inputs = (Array.isArray(raw) ? raw : String(raw).split(/[\n,;]+/))
      .map((s) => String(s).trim())
      .filter(Boolean);

    if (!inputs.length) {
      return res.status(400).json({ error: { code: "empty", message: "أرسل رابطاً واحداً على الأقل" } });
    }
    if (inputs.length > 100) {
      return res.status(400).json({ error: { code: "too_many", message: "الحد الأقصى 100 رابط في الطلب الواحد" } });
    }

    const created = [];
    const skipped = [];
    const invalid = [];

    for (const input of inputs) {
      let handle = parseHandle(input);
      if (!handle && /^https?:\/\//i.test(input)) {
        handle = await resolveShortLink(input);
      }
      if (!handle) {
        invalid.push(input);
        continue;
      }
      const existing = getAccountByHandle(handle);
      if (existing) {
        skipped.push({ handle, id: existing.id, reason: "duplicate" });
        continue;
      }
      const id = randomId();
      insertAccount({ id, handle, inputUrl: input.startsWith("http") ? input : `https://www.tiktok.com/@${handle}` });
      created.push(serializeAccount(getAccount(id)));
    }

    res.status(201).json({ created, skipped, invalid, accounts: listAccounts().map(serializeAccount) });
  } catch (error) {
    next(error);
  }
});

api.get("/accounts/:id", (req, res) => {
  const row = getAccount(req.params.id);
  if (!row) return res.status(404).json({ error: { code: "not_found", message: "الحساب غير موجود" } });
  const limit = Math.min(Number(req.query.limit) || 30, 200);
  const videos = listVideos(req.params.id, limit).map((v) => ({
    id: v.id,
    title: v.title,
    coverUrl: v.cover_url,
    shareUrl: v.share_url,
    duration: v.duration,
    createTime: v.create_time,
    views: v.view_count,
    likes: v.like_count,
    comments: v.comment_count,
    shares: v.share_count,
  }));
  res.json({ account: serializeAccount(row), videos });
});

api.patch("/accounts/:id", (req, res) => {
  const row = getAccount(req.params.id);
  if (!row) return res.status(404).json({ error: { code: "not_found", message: "الحساب غير موجود" } });
  const patch = {};
  if (typeof req.body?.displayName === "string") patch.display_name = req.body.displayName.slice(0, 80);
  updateAccount(req.params.id, patch);
  res.json({ account: serializeAccount(getAccount(req.params.id)) });
});

api.delete("/accounts/:id", (req, res) => {
  const row = getAccount(req.params.id);
  if (!row) return res.status(404).json({ error: { code: "not_found", message: "الحساب غير موجود" } });
  deleteAccount(req.params.id);
  res.json({ deleted: req.params.id });
});

api.post("/accounts/:id/sync", async (req, res, next) => {
  try {
    const result = await syncAccount(req.params.id, { force: true });
    res.json({ account: serializeAccount(result.account), demo: Boolean(result.demo) });
  } catch (error) {
    next(error);
  }
});

api.post("/sync", async (req, res, next) => {
  try {
    const result = await syncAll({ force: Boolean(req.body?.force) });
    res.json({ ...result, summary: summaryOf(listAccounts()) });
  } catch (error) {
    next(error);
  }
});

api.get("/export.csv", (req, res) => {
  const rows = listAccounts();
  const header = ["المنصة", "الحساب", "الاسم", "الرابط", "المنشورات", "المشاهدات", "متوسط المشاهدات", "الإعجابات", "التعليقات", "المشاركات", "المتابعون", "آخر مزامنة"];
  const cell = (value) => `"${String(value ?? "").replace(/"/g, '""')}"`;
  const lines = [header.map(cell).join(",")];
  for (const row of rows) {
    lines.push([
      "TikTok", `@${row.handle}`, row.display_name || "", row.input_url || "",
      row.video_count ?? 0, row.total_views ?? 0, AVG(row.total_views ?? 0, row.video_count ?? 0),
      row.total_likes ?? 0, row.total_comments ?? 0, row.total_shares ?? 0,
      row.follower_count ?? 0, row.last_synced_at ?? "",
    ].map(cell).join(","));
  }
  res.setHeader("Content-Type", "text/csv; charset=utf-8");
  res.setHeader("Content-Disposition", `attachment; filename="nabd-accounts-${new Date().toISOString().slice(0, 10)}.csv"`);
  res.send("\uFEFF" + lines.join("\r\n"));
});

// ── OAuth مع TikTok ──────────────────────────────────────────────────────

auth.get("/tiktok/start", (req, res) => {
  const accountId = String(req.query.account || "");
  const account = accountId ? getAccount(accountId) : null;
  if (!account) {
    return res.status(404).send("الحساب غير موجود. أضف الحساب أولاً ثم اربطه.");
  }
  cleanupOAuthStates();
  const state = randomState();
  db.prepare("INSERT INTO oauth_states (state, account_id, created_at) VALUES (?, ?, ?)")
    .run(state, accountId, new Date().toISOString());

  try {
    const url = buildAuthorizeUrl(state);
    res.redirect(302, url);
  } catch (error) {
    res.status(503).send(`تعذّر بدء الربط: ${error.message}`);
  }
});

auth.get("/tiktok/callback", async (req, res) => {
  const { code, state, error: oauthError } = req.query;
  const deepLink = (status, params = {}) => {
    const query = new URLSearchParams({ status, ...params }).toString();
    const target = `nabd://oauth?${query}`;
    return `<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>نبض — ربط الحساب</title>
<style>
  :root{color-scheme:dark}
  body{margin:0;min-height:100vh;display:grid;place-items:center;background:#0B0D12;color:#F5F7FA;
       font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Tahoma,sans-serif}
  .card{width:min(90vw,380px);padding:32px 24px;text-align:center;border-radius:24px;
        background:linear-gradient(160deg,#161A23,#10131A);border:1px solid #232936;
        box-shadow:0 24px 60px rgba(0,0,0,.45)}
  .ring{width:68px;height:68px;margin:0 auto 18px;border-radius:50%;display:grid;place-items:center;
        background:${status === "ok" ? "linear-gradient(135deg,#25F4EE,#FE2C55)" : "#2A1A1F"};font-size:30px}
  h1{font-size:20px;margin:0 0 8px}
  p{color:#9AA3B2;font-size:14px;line-height:1.7;margin:0 0 20px}
  a{display:inline-block;padding:12px 22px;border-radius:14px;text-decoration:none;color:#0B0D12;
    font-weight:700;background:linear-gradient(135deg,#25F4EE,#7DE2D1)}
</style></head><body>
<div class="card"><div class="ring">${status === "ok" ? "✓" : "!"}</div>
<h1>${status === "ok" ? "تم ربط الحساب" : "لم يكتمل الربط"}</h1>
<p>${status === "ok" ? "سيتم الآن الرجوع إلى تطبيق نبض وتحديث الإحصاءات." : String(params.message || "أعد المحاولة من التطبيق.")}</p>
<a href="${target}">العودة إلى نبض</a></div>
<script>location.replace(${JSON.stringify(target)});</script>
</body></html>`;
  };

  if (oauthError) {
    return res.status(400).send(deepLink("error", { message: String(oauthError) }));
  }
  if (!code || !state) {
    return res.status(400).send(deepLink("error", { message: "طلب غير مكتمل" }));
  }

  const row = db.prepare("SELECT * FROM oauth_states WHERE state = ?").get(String(state));
  if (!row) {
    return res.status(400).send(deepLink("error", { message: "انتهت صلاحية الجلسة، أعد المحاولة" }));
  }
  db.prepare("DELETE FROM oauth_states WHERE state = ?").run(String(state));

  const account = getAccount(row.account_id);
  if (!account) {
    return res.status(404).send(deepLink("error", { message: "الحساب لم يعد موجوداً" }));
  }

  try {
    const token = await exchangeCode(String(code));
    const user = await fetchUserInfo(token.accessToken);

    const duplicate = db.prepare("SELECT id FROM accounts WHERE open_id = ? AND id != ?")
      .get(user.open_id, account.id);
    if (duplicate) {
      return res.status(409).send(deepLink("error", { message: "حساب TikTok هذا مربوط بحساب آخر في نبض" }));
    }

    saveTokenRow(account.id, {
      accessTokenEnc: encryptSecret(token.accessToken),
      refreshTokenEnc: encryptSecret(token.refreshToken),
      expiresAt: token.expiresAt,
      refreshExpiresAt: token.refreshExpiresAt,
      scope: token.scope,
    });
    updateAccount(account.id, {
      open_id: user.open_id,
      display_name: user.display_name || account.display_name,
      avatar_url: user.avatar_url || null,
      is_verified: user.is_verified ? 1 : 0,
      follower_count: user.follower_count ?? 0,
      following_count: user.following_count ?? 0,
      likes_count: user.likes_count ?? 0,
      video_count: user.video_count ?? 0,
      connected: 1,
      status: "ok",
      error: null,
    });
    setMeta(`connected:${account.id}`, new Date().toISOString());

    // اسحب الإحصاءات فوراً في الخلفية
    syncAccount(account.id, { force: true }).catch(() => {});

    return res.send(deepLink("ok", { account: account.id, handle: account.handle }));
  } catch (error) {
    return res.status(502).send(deepLink("error", { message: error.message || "فشل تبادل التوكن" }));
  }
});

api.post("/accounts/:id/disconnect", (req, res) => {
  const row = getAccount(req.params.id);
  if (!row) return res.status(404).json({ error: { code: "not_found", message: "الحساب غير موجود" } });
  clearTokens(row.id);
  updateAccount(row.id, { connected: 0, status: "pending", error: null });
  res.json({ account: serializeAccount(getAccount(row.id)) });
});

api.get("/meta", (req, res) => {
  res.json({
    platform: "tiktok",
    demo: config.demoMode,
    tiktokConfigured: Boolean(config.tiktok.clientKey && config.tiktok.clientSecret),
    maxVideosPerAccount: config.maxVideosPerAccount,
    cacheTtlSeconds: config.cacheTtlSeconds,
    serverTime: new Date().toISOString(),
    seeded: getMeta("demo_seeded") === "1",
  });
});

export { serializeAccount, api, auth };