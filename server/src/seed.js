import { insertAccount, listAccounts } from "./db.js";
import { randomId } from "./security.js";

/**
 * تُضاف الحسابات يدوياً من التطبيق (تبويب الحسابات → إضافة).
 * القائمة فارغة افتراضياً: لا نضيف أي حساب نيابة عن المستخدم.
 */
export const SEED_HANDLES = [];

export function seedAccountsIfEmpty() {
  if (listAccounts().length > 0) return 0;

  for (const handle of SEED_HANDLES) {
    insertAccount({
      id: randomId(),
      handle,
      inputUrl: `https://www.tiktok.com/@${handle}`,
    });
  }

  console.log(`   أُضيفت ${SEED_HANDLES.length} حساباً افتراضياً`);
  return SEED_HANDLES.length;
}
