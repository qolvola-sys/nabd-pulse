/**
 * إحصاءات الحساب العامة — بدون OAuth وبدون خادم خارجي.
 *
 * المصدران:
 *  1) صفحة البروفايل العامة: الاسم، الصورة، المتابعون، الإجمالي، عدد المنشورات.
 *  2) صفحة embed العامة: آخر ١٠ منشورات مع عدد مشاهداتها.
 *
 * يتم استخراج وقت نشر كل منشور من معرّفه (TikTok snowflake id >> 32 = ثواني Unix)،
 * ثم يُحسب عدد منشورات آخر ٢٤ ساعة ومجموع مشاهداتها.
 *
 * ملاحظة: TikTok يعرض أعداد المشاهدات العامة مقرّبة (مثل 2.7M)، لذلك قد تختلف
 * قليلاً عن الرقم الدقيق في TikTok Analytics. هذه هي البيانات الحقيقية المتاحة
 * دون ربط الحساب.
 */
const UA =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 " +
  "(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1";

const DAY_SECONDS = 24 * 60 * 60;
const cache = new Map(); // handle -> { at, data }
const TTL_MS = 3 * 60 * 1000; // آخر ٢٤ ساعة تتغير بسرعة: كاش قصير
const COOKIE_TTL_MS = 45 * 60 * 1000;

let cookieJar = { value: "", at: 0 };
let lastRequestAt = 0;
let queue = Promise.resolve();

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** يمنع إرسال طلبات متتابعة بسرعة تُشعل حماية TikTok */
function paced(task) {
  const run = queue.then(async () => {
    const wait = 1200 - (Date.now() - lastRequestAt);
    if (wait > 0) await sleep(wait);
    try {
      return await task();
    } finally {
      lastRequestAt = Date.now();
    }
  });
  queue = run.catch(() => {});
  return run;
}

function pacedFetch(url, options) {
  return paced(() => fetch(url, options));
}

async function cookies({ force = false } = {}) {
  if (!force && cookieJar.value && Date.now() - cookieJar.at < COOKIE_TTL_MS) return cookieJar.value;

  const response = await fetch("https://www.tiktok.com/", {
    headers: { "user-agent": UA, "accept-language": "en-US,en;q=0.9" },
    signal: AbortSignal.timeout(20_000),
  });
  const list = response.headers.getSetCookie?.() ?? [];
  cookieJar = {
    value: list.map((cookie) => cookie.split(";")[0]).join("; "),
    at: Date.now(),
  };
  return cookieJar.value;
}

function number(value) {
  const n = Number(value);
  return Number.isFinite(n) && n >= 0 ? n : null;
}

function notFoundError(message = "الحساب غير موجود على TikTok") {
  const error = new Error(message);
  error.code = "not_found";
  return error;
}

async function loadProfile(handle, { freshCookies = false } = {}) {
  const jar = await cookies({ force: freshCookies });
  const url = `https://www.tiktok.com/@${encodeURIComponent(handle)}?lang=en`;

  const response = await pacedFetch(url, {
    headers: {
      "user-agent": UA,
      accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "accept-language": "en-US,en;q=0.9",
      cookie: jar,
      referer: "https://www.tiktok.com/",
    },
    signal: AbortSignal.timeout(25_000),
    redirect: "follow",
  });

  if (response.status === 404) throw notFoundError();
  if (!response.ok) {
    const error = new Error(`تعذّر قراءة الصفحة العامة (${response.status})`);
    error.code = "public_fetch_failed";
    throw error;
  }

  const html = await response.text();
  const match = html.match(
    /<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application\/json">([\s\S]*?)<\/script>/,
  );
  if (!match) return null;

  try {
    const scope = JSON.parse(match[1])?.__DEFAULT_SCOPE__?.["webapp.user-detail"] ?? {};
    if (scope.statusCode && scope.statusCode !== 0) {
      throw notFoundError(scope.statusMsg === "user banned" ? "الحساب محظور أو غير موجود" : "الحساب غير موجود أو خاص");
    }
    return scope.userInfo ?? null;
  } catch (error) {
    if (error.code === "not_found") throw error;
    return null;
  }
}

function createTimeFromId(id) {
  try {
    return Number(BigInt(String(id)) >> 32n);
  } catch {
    return 0;
  }
}

function extractFrontityState(html) {
  const scripts = [...html.matchAll(
    /<script[^>]*type="application\/json"[^>]*>([\s\S]*?)<\/script>/g,
  )];
  for (const script of scripts) {
    const text = script[1];
    if (!text.includes('"frontity"')) continue;
    try {
      return JSON.parse(text);
    } catch {
      // جرّب السكربت التالي
    }
  }
  return null;
}

async function loadEmbed(handle, { freshCookies = false } = {}) {
  const jar = await cookies({ force: freshCookies }).catch(() => "");
  const url = `https://www.tiktok.com/embed/@${encodeURIComponent(handle)}`;

  const response = await pacedFetch(url, {
    headers: {
      "user-agent": UA,
      accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "accept-language": "en-US,en;q=0.9",
      cookie: jar,
      referer: "https://www.tiktok.com/",
    },
    signal: AbortSignal.timeout(25_000),
    redirect: "follow",
  });

  if (response.status === 400 || response.status === 404) throw notFoundError("الحساب غير موجود أو خاص");
  if (!response.ok) {
    const error = new Error(`تعذّر قراءة المنشورات العامة (${response.status})`);
    error.code = "public_fetch_failed";
    throw error;
  }

  const state = extractFrontityState(await response.text());
  const data = Object.values(state?.source?.data ?? {}).find((value) => value?.userInfo);
  if (!data) return null;
  return data;
}

function mapVideo(video, handle) {
  const id = String(video.id ?? "");
  if (!id) return null;
  return {
    id,
    title: typeof video.desc === "string" ? video.desc : "",
    coverUrl: video.coverUrl || video.originCoverUrl || video.dynamicCoverUrl || null,
    shareUrl: `https://www.tiktok.com/@${handle}/video/${id}`,
    duration: 0,
    createTime: createTimeFromId(id),
    viewCount: number(video.playCount) ?? 0,
    likeCount: 0,
    commentCount: 0,
    shareCount: 0,
  };
}

export async function fetchPublicProfile(handle, { force = false, knownPosts = 0 } = {}) {
  const key = String(handle).toLowerCase();
  const hit = cache.get(key);
  if (!force && hit && Date.now() - hit.at < TTL_MS) return hit.data;

  const payload = await (async () => {
    let profile = null;
    let embed = null;

    try {
      profile = await loadProfile(key);
    } catch (error) {
      if (error.code === "not_found") throw error;
      // قد تكون صفحة البروفايل محجوبة مؤقتاً؛ نكمل بصفحة embed
    }

    try {
      embed = await loadEmbed(key);
    } catch (error) {
      if (error.code === "not_found" && !profile) throw error;
    }

    // صفحة حماية TikTok: نجدّد الكوكيز ونحاول مرة أخرى بعد مهلة قصيرة
    if (!profile && !embed) {
      await sleep(2500);
      profile = await loadProfile(key, { freshCookies: true }).catch(() => null);
      embed = await loadEmbed(key, { freshCookies: true }).catch(() => null);
    }

    if (!profile && !embed) {
      const error = new Error("تعذّر جلب البيانات العامة الآن (حماية TikTok). أعد المحاولة بعد قليل");
      error.code = "public_blocked";
      throw error;
    }

    return { profile, embed };
  })();

  const profileUser = payload.profile?.user ?? {};
  const profileStats = payload.profile?.stats ?? {};
  const embedUser = payload.embed?.userInfo ?? {};

  const followers = number(profileStats.followerCount) ?? number(embedUser.followerCount) ?? 0;
  const posts = number(profileStats.videoCount) ?? (knownPosts > 0 ? knownPosts : 0);
  const rawLikes = number(profileStats.heartCount) ?? number(embedUser.heartCount) ?? 0;
  const likes = Math.abs(rawLikes);

  if (followers === null && posts === null && !payload.embed) {
    const error = new Error("لا توجد إحصاءات متاحة لهذا الحساب");
    error.code = "public_empty";
    throw error;
  }

  const seen = new Set();
  const videos = (payload.embed?.videoList ?? [])
    .map((video) => mapVideo(video, key))
    .filter((video) => video && !seen.has(video.id) && seen.add(video.id))
    .sort((a, b) => b.createTime - a.createTime);

  const cutoff = Math.floor(Date.now() / 1000) - DAY_SECONDS;
  const recent = videos.filter((video) => video.createTime >= cutoff);
  const views24h = recent.reduce((sum, video) => sum + video.viewCount, 0);
  const totalViews = videos.reduce((sum, video) => sum + video.viewCount, 0);

  const data = {
    handle: key,
    displayName:
      (typeof (profileUser.nickname || embedUser.nickname) === "string" &&
        (profileUser.nickname || embedUser.nickname).trim()) || null,
    avatarUrl:
      profileUser.avatarLarger || profileUser.avatarMedium || profileUser.avatarThumb ||
      embedUser.avatarThumbUrl || null,
    isVerified: Boolean(profileUser.verified ?? embedUser.verified),
    followers: followers ?? 0,
    following: number(profileStats.followingCount) ?? number(embedUser.followingCount) ?? 0,
    likes,
    posts: posts ?? 0,
    videos,
    totalViews,
    posts24h: recent.length,
    views24h,
    fetchedAt: new Date().toISOString(),
  };

  cache.set(key, { at: Date.now(), data });
  return data;
}
