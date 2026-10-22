/**
 * يولّد أيقونة التطبيق 1024×1024 بدون أي مكتبات خارجية.
 * التشغيل: node scripts/make-icon.js
 */
const fs = require("node:fs");
const path = require("node:path");
const zlib = require("node:zlib");

const SIZE = 1024;
const SS = 2;
const W = SIZE * SS;

const out = path.join(__dirname, "..", "Nabd", "Resources", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png");

// مسار النبض (إحداثيات نسبية)
const points = [
  [0.08, 0.52], [0.27, 0.52], [0.35, 0.52], [0.41, 0.31],
  [0.49, 0.76], [0.57, 0.52], [0.71, 0.52], [0.77, 0.52],
  [0.84, 0.42], [0.9, 0.52], [0.94, 0.52],
];

const cyan = [0x25, 0xf4, 0xee];
const violet = [0x7c, 0x5c, 0xff];
const pink = [0xfe, 0x2c, 0x55];

function mix(a, b, t) {
  return a.map((v, i) => v + (b[i] - v) * t);
}

function strokeColor(t) {
  return t < 0.5 ? mix(cyan, violet, t / 0.5) : mix(violet, pink, (t - 0.5) / 0.5);
}

function distToSegment(px, py, ax, ay, bx, by) {
  const dx = bx - ax;
  const dy = by - ay;
  const len2 = dx * dx + dy * dy || 1;
  let t = ((px - ax) * dx + (py - ay) * dy) / len2;
  t = Math.max(0, Math.min(1, t));
  const x = ax + t * dx;
  const y = ay + t * dy;
  return Math.hypot(px - x, py - y);
}

const pts = points.map(([x, y]) => [x * W, y * W]);

function sample(x, y) {
  // خلفية متدرجة
  const nx = x / W;
  const ny = y / W;
  const radial = Math.max(0, 1 - Math.hypot(nx - 0.5, ny - 0.42) / 0.85);
  let r = 6 + radial * 12;
  let g = 9 + radial * 16;
  let b = 14 + radial * 26;

  // هالة زرقاء/بنفسجية في الزوايا
  const glowA = Math.exp(-((Math.hypot(nx - 0.18, ny - 0.82) / 0.34) ** 2)) * 0.24;
  const glowB = Math.exp(-((Math.hypot(nx - 0.88, ny - 0.16) / 0.32) ** 2)) * 0.22;
  r += glowB * 90;
  g += glowA * 60 + glowB * 20;
  b += glowA * 110 + glowB * 110;

  // مسافة لأقرب قطعة من مسار النبض
  let dist = Infinity;
  for (let i = 0; i < pts.length - 1; i += 1) {
    const d = distToSegment(x, y, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1]);
    if (d < dist) dist = d;
  }

  const coreWidth = 11 * SS;
  const color = strokeColor(Math.min(1, Math.max(0, nx)));
  const core = Math.max(0, Math.min(1, coreWidth - dist));
  if (core > 0) {
    const k = core;
    r = r * (1 - k) + color[0] * k;
    g = g * (1 - k) + color[1] * k;
    b = b * (1 - k) + color[2] * k;
  }

  const glow = Math.exp(-Math.max(0, dist - coreWidth) / (16 * SS)) * 0.55;
  if (glow > 0.004) {
    r = r * (1 - glow) + color[0] * glow;
    g = g * (1 - glow) + color[1] * glow;
    b = b * (1 - glow) + color[2] * glow;
  }

  // نقطة نهاية مضيئة
  const [ex, ey] = pts[pts.length - 1];
  const endDist = Math.hypot(x - ex, y - ey);
  const dot = Math.max(0, Math.min(1, 19 * SS - endDist));
  if (dot > 0) {
    r = r * (1 - dot) + 255 * dot;
    g = g * (1 - dot) + 255 * dot;
    b = b * (1 - dot) + 255 * dot;
  }

  return [Math.min(255, r), Math.min(255, g), Math.min(255, b)];
}

const raw = Buffer.alloc((SIZE * 4 + 1) * SIZE);
for (let y = 0; y < SIZE; y += 1) {
  raw[y * (SIZE * 4 + 1)] = 0;
  for (let x = 0; x < SIZE; x += 1) {
    let r = 0;
    let g = 0;
    let b = 0;
    for (let sy = 0; sy < SS; sy += 1) {
      for (let sx = 0; sx < SS; sx += 1) {
        const px = sample(x * SS + sx + 0.5, y * SS + sy + 0.5);
        r += px[0];
        g += px[1];
        b += px[2];
      }
    }
    const n = SS * SS;
    const index = y * (SIZE * 4 + 1) + 1 + x * 4;
    raw[index] = Math.round(r / n);
    raw[index + 1] = Math.round(g / n);
    raw[index + 2] = Math.round(b / n);
    raw[index + 3] = 255;
  }
}

const table = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buffer) {
  let c = 0xffffffff;
  for (const byte of buffer) c = table[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const typeBuffer = Buffer.from(type, "ascii");
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([typeBuffer, data])));
  return Buffer.concat([length, typeBuffer, data, crc]);
}

const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(SIZE, 0);
ihdr.writeUInt32BE(SIZE, 4);
ihdr[8] = 8;
ihdr[9] = 6;
ihdr[10] = 0;
ihdr[11] = 0;
ihdr[12] = 0;

const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk("IHDR", ihdr),
  chunk("IDAT", zlib.deflateSync(raw, { level: 9 })),
  chunk("IEND", Buffer.alloc(0)),
]);

fs.writeFileSync(out, png);
console.log(`✓ ${out} (${(png.length / 1024).toFixed(1)} KB)`);
