import fs from "node:fs";
import path from "node:path";

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.endsWith(".swift")) out.push(full);
  }
  return out;
}

const pairs = { "{": "}", "(": ")", "[": "]" };

/** ماسح بسيط يتجاهل النصوص والتعليقات ويستخرج رموز الأقواس فقط */
function tokens(source) {
  const out = [];
  let i = 0;
  const n = source.length;
  while (i < n) {
    const c = source[i];
    const next = source[i + 1];

    if (c === "/" && next === "/") {
      while (i < n && source[i] !== "\n") i += 1;
      continue;
    }
    if (c === "/" && next === "*") {
      i += 2;
      let depth = 1;
      while (i < n && depth > 0) {
        if (source[i] === "/" && source[i + 1] === "*") { depth += 1; i += 2; continue; }
        if (source[i] === "*" && source[i + 1] === "/") { depth -= 1; i += 2; continue; }
        i += 1;
      }
      continue;
    }
    if (c === '"') {
      const triple = source.startsWith('"""', i);
      i += triple ? 3 : 1;
      while (i < n) {
        if (source[i] === "\\") { i += 2; continue; }
        if (triple ? source.startsWith('"""', i) : source[i] === '"') { i += triple ? 3 : 1; break; }
        i += 1;
      }
      continue;
    }
    if (pairs[c]) out.push({ ch: c, index: i });
    else if (c === "}" || c === ")" || c === "]") out.push({ ch: c, index: i });
    i += 1;
  }
  return out;
}

const files = walk(path.join(process.cwd(), "Nabd"));
let bad = 0;

for (const file of files) {
  const source = fs.readFileSync(file, "utf8");
  const stack = [];
  let error = null;

  for (const token of tokens(source)) {
    if (pairs[token.ch]) stack.push(token);
    else {
      const top = stack.pop();
      if (!top || pairs[top.ch] !== token.ch) {
        const line = source.slice(0, token.index).split("\n").length;
        error = `مشكلة عند السطر ${line}`;
        break;
      }
    }
  }
  if (!error && stack.length) {
    const line = source.slice(0, stack[0].index).split("\n").length;
    error = `قوس غير مغلق بدأ عند السطر ${line}`;
  }
  if (error) {
    console.log("✗", path.relative(process.cwd(), file), error);
    bad += 1;
  }
}

console.log(bad ? `${bad} ملف فيه خلل` : "✓ جميع الملفات متوازنة الأقواس");
