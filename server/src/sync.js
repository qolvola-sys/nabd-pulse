import { config } from "./config.js";
import {
  clearTokens, getAccount, getTokenRow, listAccounts, replaceVideos, saveTokenRow, updateAccount,
} from "./db.js";
import { decryptSecret, encryptSecret } from "./security.js";
import { fetchAllVideos, fetchUserInfo, refreshAccessToken, TikTokError } from "./tiktok.js";
import { syncDemoAccount } from "./demo.js";

const inFlight = new Set();

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
  const accounts = listAccounts().filter((a) => a.connected);
  const results = await syncMany(accounts.map((a) => a.id), options);
  return { syncedAt: new Date().toISOString(), total: accounts.length, results };
}
