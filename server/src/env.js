import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

/** قارئ .env بسيط بدون مكتبات خارجية. لا يستبدل متغيرات البيئة الموجودة. */
export function loadEnv() {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const root = path.resolve(here, "..");
  const file = path.join(root, ".env");
  if (!fs.existsSync(file)) return;

  const content = fs.readFileSync(file, "utf8");
  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const eq = line.indexOf("=");
    if (eq === -1) continue;
    const key = line.slice(0, eq).trim();
    let value = line.slice(eq + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    if (process.env[key] === undefined) process.env[key] = value;
  }
}
