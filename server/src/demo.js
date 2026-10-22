import { db, getAccount, insertAccount, listAccounts, replaceVideos, setMeta, getMeta, updateAccount } from "./db.js";
import { randomId } from "./security.js";

/** مولد أرقام شبه عشوائي ثابت (نفس البيانات التجريبية في كل تشغيل) */
function mulberry32(seed) {
  let a = seed >>> 0;
  return function next() {
    a += 0x6D2B79F5;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const BRANDS = [
  ["مطبخ سارة", "matbakh_sara"], ["لمسة ديكور", "lamsat_decor"], ["قهوة الصباح", "qahwa_sabah"],
  ["رياضة كل يوم", "riyada_daily"], ["عالم التقنية", "tech_world_ar"], ["أزياء ليان", "fashion_layan"],
  ["سفرة الشام", "sufrat_sham"], ["نباتات البيت", "beet_plants"], ["مكياج نورة", "makeup_noura"],
  ["وصفات سريعة", "fast_recipes"], ["سيارات 360", "cars_360"], ["سفر بلا حدود", "travel_no_limits"],
  ["كورة اليوم", "koora_today"], ["أب وابنه", "dad_and_son"], ["حرف يدوية", "hand_made_art"],
  ["صحة ورشاقة", "fit_health_ar"], ["بيبي وليد", "baby_walid"], ["ديكور مودرن", "modern_decor"],
  ["معلومة في دقيقة", "info_minute"], ["خط عربي", "arabic_calligraphy"], ["طبيعة ساحرة", "magic_nature"],
  ["فك وتركيب", "fix_and_build"], ["أفكار تصوير", "photo_ideas"], ["حلويات أم راشد", "sweets_om_rashid"],
  ["عطور فاخرة", "luxury_scents"], ["قصص نجاح", "success_stories"], ["حيوانات لطيفة", "cute_pets_ar"],
  ["مغامرات صحراء", "desert_rides"], ["تعلم إنجليزي", "learn_english_ar"], ["تزيين كيك", "cake_decor"],
  ["موسيقى هادئة", "calm_music"], ["شعر وخواطر", "poetry_lines"], ["ألعاب جيمنج", "gaming_zone_ar"],
  ["مشاريع صغيرة", "small_business_ar"], ["عناية بالبشرة", "skin_care_ar"], ["حديقة المنزل", "home_garden"],
  ["أخبار التقنية", "tech_news_ar"], ["طبخ بحري", "sea_food_kitchen"], ["تصوير جوال", "mobile_shots"],
  ["نجارة إبداعية", "creative_wood"], ["قهوة مختصة", "specialty_coffee"], ["أمومة وعمل", "mom_and_work"],
  ["رياضة منزلية", "home_workout"], ["ديكور رمضان", "ramadan_decor"], ["سياحة عربية", "arab_tourism"],
  ["كتب ومكتبات", "books_library"], ["حيل ذكية", "smart_hacks_ar"], ["عالم الدرون", "drone_world"],
  ["مطبخ إيطالي", "italian_kitchen"], ["ستايل رجالي", "men_style_ar"],
];

const TITLES = [
  "جربتها وأولادي أحبوها", "طريقة أسرع من اللي تعرفها", "النتيجة صدمتني",
  "خطوة واحدة تفرق كثير", "أفضل ٣ أفكار لهذا الأسبوع", "لا تسويها قبل ما تشوف الفيديو",
  "سر صغير يغيّر كل شيء", "خلّها في بالك", "مقارنة سريعة", "من الكاميرا مباشرة",
  "تسجيل كامل بدون تعديل", "اللي طلبتوه بالكومنتات", "الجزء الثاني", "سؤال وجواب",
];

function sumViews(accountId) {
  return db.prepare("SELECT COALESCE(SUM(view_count),0) v, COALESCE(SUM(like_count),0) l, COALESCE(SUM(comment_count),0) c, COALESCE(SUM(share_count),0) s, COUNT(*) n FROM videos WHERE account_id = ?")
    .get(accountId);
}

export function seedDemoAccountsIfEmpty() {
  const existing = db.prepare("SELECT COUNT(*) AS n FROM accounts").get().n;
  if (existing > 0) return;
  if (getMeta("demo_seeded") === "1") return;

  const rand = mulberry32(20260214);
  const createdAt = new Date().toISOString();

  BRANDS.forEach(([name, handle], index) => {
    const id = randomId();
    insertAccount({ id, handle, inputUrl: `https://www.tiktok.com/@${handle}`, createdAt });

    const posts = 18 + Math.floor(rand() * 260);
    const followers = 3_000 + Math.floor(rand() ** 2 * 1_900_000);
    const avgViews = 4_000 + Math.floor(rand() ** 2.4 * 420_000);

    const videos = [];
    const videoTotal = Math.min(posts, 40);
    for (let v = 0; v < videoTotal; v += 1) {
      const factor = 0.25 + rand() * 2.6;
      const views = Math.max(120, Math.floor(avgViews * factor));
      videos.push({
        id: `demo_${index}_${v}`,
        title: TITLES[Math.floor(rand() * TITLES.length)],
        coverUrl: null,
        shareUrl: `https://www.tiktok.com/@${handle}/video/${7100000000000000000 + index * 1000 + v}`,
        duration: 12 + Math.floor(rand() * 90),
        createTime: Math.floor(Date.now() / 1000) - v * 86_400 - Math.floor(rand() * 3600),
        viewCount: views,
        likeCount: Math.floor(views * (0.03 + rand() * 0.09)),
        commentCount: Math.floor(views * (0.001 + rand() * 0.006)),
        shareCount: Math.floor(views * (0.002 + rand() * 0.01)),
      });
    }
    replaceVideos(id, videos);

    const totals = sumViews(id);
    const scale = posts / Math.max(1, videoTotal);
    updateAccount(id, {
      display_name: name,
      is_verified: rand() > 0.82 ? 1 : 0,
      follower_count: followers,
      following_count: Math.floor(rand() * 900),
      likes_count: Math.floor(totals.l * scale),
      video_count: posts,
      total_views: Math.floor(totals.v * scale),
      total_likes: Math.floor(totals.l * scale),
      total_comments: Math.floor(totals.c * scale),
      total_shares: Math.floor(totals.s * scale),
      fetched_videos: videoTotal,
      connected: 1,
      status: "ok",
      last_synced_at: new Date(Date.now() - Math.floor(rand() * 5) * 60_000).toISOString(),
    });
  });

  setMeta("demo_seeded", "1");
}

/** مزامنة تجريبية: نمو بسيط في المشاهدات */
export function syncDemoAccount(accountId) {
  const account = getAccount(accountId);
  if (!account) return null;
  const rand = mulberry32(Number(account.handle.length) * 977 + Date.now() % 100000);
  const drift = 1 + rand() * 0.02;
  const videos = db.prepare("SELECT id, view_count, like_count, comment_count, share_count FROM videos WHERE account_id = ?").all(accountId);
  const bump = db.prepare("UPDATE videos SET view_count = ?, like_count = ? WHERE id = ?");
  for (const v of videos) {
    if (rand() > 0.55) {
      const views = Math.floor(v.view_count * drift) + Math.floor(rand() * 400);
      bump.run(views, Math.floor(v.like_count * drift), v.id);
    }
  }
  const totals = sumViews(accountId);
  updateAccount(accountId, {
    total_views: totals.v,
    total_likes: totals.l,
    total_comments: totals.c,
    total_shares: totals.s,
    status: "ok",
    error: null,
    connected: 1,
    last_synced_at: new Date().toISOString(),
  });
  return getAccount(accountId);
}

export function demoSummary() {
  const accounts = listAccounts();
  return {
    accounts: accounts.length,
    connected: accounts.filter((a) => a.connected).length,
    posts: accounts.reduce((sum, a) => sum + (a.video_count ?? 0), 0),
    views: accounts.reduce((sum, a) => sum + (a.total_views ?? 0), 0),
  };
}

