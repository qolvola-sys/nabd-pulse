import { config } from "./config.js";
import {
  clearTokens, getAccount, getTokenRow, listAccounts, replaceVideos, saveTokenRow, updateAccount,
} from "./db.js";
import { decryptSecret, encryptSecret } from "./security.js";
import { fetchAllVideos, fetchUserInfo, refreshAccessToken, TikTokError } from "./tiktok.js";
import { fetchPublicProfile } from "./publicStats.js";
import { syncDemoAccount } from "./demo.js";

const inFlight = new Set();
const DAY_SECONDS = 24 * 60 * 60;

function last24h(videos) {
  const cutoff = Math.floor(Date.now() / 1000) - DAY_SECONDS;
  const recent = videos.filter((video) => (video.createTime ?? 0) >= cutoff);
  return {
    posts: recent.length,
    views: recent.reduce((sum, video) => sum + (video.viewCount ?? 0), 0),
  };
}

/** يعيد توكن صالحاً، ويجدّده تلقائياً إن قارب على الانتهاء */
async function validAccessToken(accountId) {
  const row = getTokenRow(accountId);
  if (!row) {
    throw new TikTokError("الحساب غير مربوط بحساب TikTok", { code: "not_connected", status: 409 });
  }
  const accessToken = decryptSecret(row.access_token_enc);
  const refreshToken = decryptSecret(row.refresh_token_enc);
  const expiresAt = Number(row.expires_at ?? 0);

  if (accessToken && expiresAt - Date.now() > 5 * 60 * 1000) {
    return accessToken;
  }
  if (!refreshToken || Number(row.refresh_expires_at ?? 0) < Date.now()) {
    clearTokens(accountId);
    updateAccount(accountId, { connected: 0, status: "needs_reconnect" });
    throw new TikTokError("انتهت صلاحية الربط، أعد ربط الحساب", { code: "needs_reconnect", status: 409 });
  }

  const refreshed = await refreshAccessToken(refreshToken);
  saveTokenRow(accountId, {
    accessTokenEnc: encryptSecret(refreshed.accessToken),
    refreshTokenEnc: encryptSecret(refreshed.refreshToken),
    expiresAt: refreshed.expiresAt,
    refreshExpiresAt: refreshed.refreshExpiresAt,
    scope: refreshed.scope,
  });
  return refreshed.accessToken;
}

export async function syncPublicAccount(accountId) {
  const account = getAccount(accountId);
  if (!account) throw new TikTokError("الحساب غير موجود", { code: "not_found", status: 404 });

  const info = await fetchPublicProfile(account.handle, {
    force: true,
    knownPosts: account.video_count ?? 0,
  });
  const videos = info.videos ?? [];
  if (videos.length) replaceVideos(accountId, videos);

  const recent = last24h(videos);

  updateAccount(accountId, {
    display_name: info.displayName ?? account.display_name,
    avatar_url: info.avatarUrl ?? account.avatar_url,
    is_verified: info.isVerified ? 1 : 0,
    follower_count: info.followers,
    following_count: info.following,
    likes_count: info.likes,
    video_count: info.posts || account.video_count || videos.length,
    total_views: info.totalViews ?? 0,
    total_likes: 0,
    total_comments: 0,
    total_shares: 0,
    fetched_videos: videos.length,
    posts_24h: recent.posts,
    views_24h: recent.views,
    connected: 0,
    status: "public",
    error: null,
    last_synced_at: new Date().toISOString(),
  });

  return getAccount(accountId);
}

export async function syncAccount(accountId, { force = false } = {}) {
  if (inFlight.has(accountId)) return { skipped: true, account: getAccount(accountId) };
  const account = getAccount(accountId);
  if (!account) throw new TikTokError("الحساب غير موجود", { code: "not_found", status: 404 });

  inFlight.add(accountId);
  try {
    // في الوضع التجريبي: أي حساب بلا توكن حقيقي يُحدَّث ببيانات تمثيلية
    const hasTokens = Boolean(getTokenRow(accountId));
    if (config.demoMode && !hasTokens) {
      return { account: syncDemoAccount(accountId), demo: true };
    }

    // بلا توكن: نقرأ الإحصاءات العامة (منشورات، متابعون، إعجابات) بدون ربط
    if (!hasTokens) {
      return { account: await syncPublicAccount(accountId), public: true };
    }

    const accessToken = await validAccessToken(accountId);
    const user = await fetchUserInfo(accessToken);
    const videos = await fetchAllVideos(accessToken, { maxVideos: config.maxVideosPerAccount });

    replaceVideos(accountId, videos);

    const totals = videos.reduce((acc, v) => {
      acc.views += v.viewCount;
      acc.likes += v.likeCount;
      acc.comments += v.commentCount;
      acc.shares += v.shareCount;
      return acc;
    }, { views: 0, likes: 0, comments: 0, shares: 0 });
    const recent = last24h(videos);

    updateAccount(accountId, {
      open_id: user.open_id ?? null,
      display_name: user.display_name ?? account.display_name,
      avatar_url: user.avatar_url ?? null,
      is_verified: user.is_verified ? 1 : 0,
      follower_count: user.follower_count ?? 0,
      following_count: user.following_count ?? 0,
      likes_count: user.likes_count ?? 0,
      video_count: user.video_count ?? videos.length,
      total_views: totals.views,
      total_likes: totals.likes,
      total_comments: totals.comments,
      total_shares: totals.shares,
      fetched_videos: videos.length,
      posts_24h: recent.posts,
      views_24h: recent.views,
      connected: 1,
      status: "ok",
      error: null,
      last_synced_at: new Date().toISOString(),
    });

    return { account: getAccount(accountId), demo: false };
  } catch (error) {
    updateAccount(accountId, {
      status: error.code === "needs_reconnect" ? "needs_reconnect" : "error",
      error: error.message?.slice(0, 300) ?? "خطأ غير معروف",
      connected: error.code === "needs_reconnect" ? 0 : account.connected,
    });
    throw error;
  } finally {
    inFlight.delete(accountId);
  }
}

export async function syncMany(accountIds, options = {}) {
  const queue = [...accountIds];
  const results = [];
  const ttl = config.cacheTtlSeconds * 1000;

  const worker = async () => {
    while (queue.length) {
      const id = queue.shift();
      const account = getAccount(id);
      if (!account) continue;
      const fresh = account.last_synced_at && Date.now() - Date.parse(account.last_synced_at) < ttl;
      if (fresh && !options.force) {
        results.push({ id, ok: true, cached: true });
        continue;
      }
      try {
        await syncAccount(id, options);
        results.push({ id, ok: true });
      } catch (error) {
        results.push({ id, ok: false, error: error.message, code: error.code });
      }
    }
  };

  await Promise.all(Array.from({ length: Math.min(config.syncConcurrency, queue.length || 1) }, worker));
  return results;
}

export async function syncAll(options = {}) {
  const accounts = listAccounts();
  const results = await syncMany(accounts.map((a) => a.id), options);
  return { syncedAt: new Date().toISOString(), total: accounts.length, results };
}

/** يحدّث الحسابات التي مرّ على آخر مزامنة لها أكثر من 24 ساعة (بلا حجب للطلب) */
const DAY_MS = 24 * 60 * 60 * 1000;
let lastAutoCheck = 0;

export async function refreshStale({ force = false, maxAgeMs = DAY_MS } = {}) {
  const now = Date.now();
  if (!force && now - lastAutoCheck < 60 * 60 * 1000) return { skipped: true };
  lastAutoCheck = now;

  const stale = listAccounts().filter(
    (a) => !a.last_synced_at || now - Date.parse(a.last_synced_at) > maxAgeMs,
  );
  if (!stale.length) return { skipped: true };

  const results = await syncMany(stale.map((a) => a.id), { force: true });
  return { refreshed: stale.length, results };
}
