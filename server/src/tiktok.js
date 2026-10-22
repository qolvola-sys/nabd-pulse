import { config } from "./config.js";

const USER_FIELDS = [
  "open_id", "union_id", "avatar_url", "display_name", "profile_deep_link",
  "is_verified", "follower_count", "following_count", "likes_count", "video_count",
].join(",");

const VIDEO_FIELDS = [
  "id", "title", "video_description", "duration", "cover_image_url", "share_url",
  "create_time", "view_count", "like_count", "comment_count", "share_count",
].join(",");

export class TikTokError extends Error {
  constructor(message, { code = "tiktok_error", status = 502, logId = null } = {}) {
    super(message);
    this.name = "TikTokError";
    this.code = code;
    this.status = status;
    this.logId = logId;
  }
}

function ensureCredentials() {
  if (!config.tiktok.clientKey || !config.tiktok.clientSecret) {
    throw new TikTokError("لم تُضبط مفاتيح TikTok على الخادم", { code: "not_configured", status: 503 });
  }
}

async function postForm(url, form) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", "Cache-Control": "no-cache" },
    body: new URLSearchParams(form).toString(),
    signal: AbortSignal.timeout(20_000),
  });
  const text = await response.text();
  let json;
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    throw new TikTokError("رد غير مفهوم من TikTok", { code: "bad_response", status: 502 });
  }
  if (!response.ok || json.error) {
    const code = json?.error || json?.error_code || `http_${response.status}`;
    const description = json?.error_description || json?.message || response.statusText;
    throw new TikTokError(description || "فشل الطلب إلى TikTok", { code, status: 502, logId: json?.log_id });
  }
  return json;
}

async function apiRequest(path, { method = "GET", accessToken, body } = {}) {
  const response = await fetch(`${config.tiktok.apiBase}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(25_000),
  });
  const text = await response.text();
  let json;
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    throw new TikTokError("رد غير مفهوم من TikTok", { code: "bad_response", status: 502 });
  }
  const errorCode = json?.error?.code;
  if (!response.ok || (errorCode && errorCode !== "ok")) {
    throw new TikTokError(json?.error?.message || `فشل الطلب (${response.status})`, {
      code: errorCode || `http_${response.status}`,
      status: response.status === 401 ? 401 : 502,
      logId: json?.error?.log_id,
    });
  }
  return json;
}

export function buildAuthorizeUrl(state) {
  ensureCredentials();
  const url = new URL(config.tiktok.authorizeUrl);
  url.searchParams.set("client_key", config.tiktok.clientKey);
  url.searchParams.set("scope", config.tiktok.scopes);
  url.searchParams.set("redirect_uri", config.tiktok.redirectUri);
  url.searchParams.set("state", state);
  url.searchParams.set("response_type", "code");
  return url.toString();
}

export async function exchangeCode(code) {
  ensureCredentials();
  const json = await postForm(config.tiktok.tokenUrl, {
    client_key: config.tiktok.clientKey,
    client_secret: config.tiktok.clientSecret,
    code,
    grant_type: "authorization_code",
    redirect_uri: config.tiktok.redirectUri,
  });
  return normalizeToken(json);
}

export async function refreshAccessToken(refreshToken) {
  ensureCredentials();
  const json = await postForm(config.tiktok.tokenUrl, {
    client_key: config.tiktok.clientKey,
    client_secret: config.tiktok.clientSecret,
    grant_type: "refresh_token",
    refresh_token: refreshToken,
  });
  return normalizeToken(json);
}

function normalizeToken(json) {
  const now = Date.now();
  return {
    accessToken: json.access_token,
    refreshToken: json.refresh_token,
    scope: json.scope,
    expiresAt: now + Number(json.expires_in ?? 86_400) * 1000,
    refreshExpiresAt: now + Number(json.refresh_expires_in ?? 31_536_000) * 1000,
  };
}

export async function fetchUserInfo(accessToken) {
  const json = await apiRequest(`/user/info/?fields=${encodeURIComponent(USER_FIELDS)}`, { accessToken });
  const user = json?.data?.user;
  if (!user) throw new TikTokError("لا توجد بيانات لهذا الحساب", { code: "no_user" });
  return user;
}

export async function fetchAllVideos(accessToken, { maxVideos = 200 } = {}) {
  const videos = [];
  let cursor = null;
  let hasMore = true;
  let pages = 0;

  while (hasMore && videos.length < maxVideos && pages < 25) {
    const json = await apiRequest(`/video/list/?fields=${encodeURIComponent(VIDEO_FIELDS)}`, {
      method: "POST",
      accessToken,
      body: { max_count: 20, ...(cursor ? { cursor } : {}) },
    });
    const data = json?.data ?? {};
    for (const video of data.videos ?? []) {
      videos.push({
        id: String(video.id),
        title: video.title || video.video_description || "",
        coverUrl: video.cover_image_url || null,
        shareUrl: video.share_url || null,
        duration: video.duration ?? 0,
        createTime: video.create_time ?? 0,
        viewCount: video.view_count ?? 0,
        likeCount: video.like_count ?? 0,
        commentCount: video.comment_count ?? 0,
        shareCount: video.share_count ?? 0,
      });
    }
    hasMore = Boolean(data.has_more);
    cursor = data.cursor ?? null;
    pages += 1;
    if (!cursor) break;
  }

  return videos.slice(0, maxVideos);
}
