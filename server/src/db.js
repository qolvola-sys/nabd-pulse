import fs from "node:fs";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { config } from "./config.js";

fs.mkdirSync(config.dataDir, { recursive: true });

export const db = new DatabaseSync(path.join(config.dataDir, "nabd.db"));

db.exec(`
  PRAGMA journal_mode = WAL;
  PRAGMA foreign_keys = ON;

  CREATE TABLE IF NOT EXISTS accounts (
    id               TEXT PRIMARY KEY,
    handle           TEXT NOT NULL UNIQUE,
    input_url        TEXT,
    open_id          TEXT,
    display_name     TEXT,
    avatar_url       TEXT,
    is_verified      INTEGER DEFAULT 0,
    follower_count   INTEGER DEFAULT 0,
    following_count  INTEGER DEFAULT 0,
    likes_count      INTEGER DEFAULT 0,
    video_count      INTEGER DEFAULT 0,
    total_views      INTEGER DEFAULT 0,
    total_likes      INTEGER DEFAULT 0,
    total_comments   INTEGER DEFAULT 0,
    total_shares     INTEGER DEFAULT 0,
    fetched_videos   INTEGER DEFAULT 0,
    connected        INTEGER DEFAULT 0,
    status           TEXT DEFAULT 'pending',
    error            TEXT,
    last_synced_at   TEXT,
    created_at       TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS tokens (
    account_id        TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    access_token_enc  TEXT NOT NULL,
    refresh_token_enc TEXT,
    expires_at        INTEGER,
    refresh_expires_at INTEGER,
    scope             TEXT,
    updated_at        TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS videos (
    id            TEXT PRIMARY KEY,
    account_id    TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    title         TEXT,
    cover_url     TEXT,
    share_url     TEXT,
    duration      INTEGER DEFAULT 0,
    create_time   INTEGER DEFAULT 0,
    view_count    INTEGER DEFAULT 0,
    like_count    INTEGER DEFAULT 0,
    comment_count INTEGER DEFAULT 0,
    share_count   INTEGER DEFAULT 0,
    fetched_at    TEXT NOT NULL
  );

  CREATE INDEX IF NOT EXISTS idx_videos_account ON videos(account_id, create_time DESC);

  CREATE TABLE IF NOT EXISTS oauth_states (
    state       TEXT PRIMARY KEY,
    account_id  TEXT,
    created_at  TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT
  );
`);

export const nowIso = () => new Date().toISOString();

export const accountColumns = [
  "id", "handle", "input_url", "open_id", "display_name", "avatar_url", "is_verified",
  "follower_count", "following_count", "likes_count", "video_count",
  "total_views", "total_likes", "total_comments", "total_shares",
  "fetched_videos", "connected", "status", "error", "last_synced_at", "created_at",
];

export function getMeta(key) {
  return db.prepare("SELECT value FROM meta WHERE key = ?").get(key)?.value ?? null;
}

export function setMeta(key, value) {
  db.prepare("INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value")
    .run(key, String(value));
}

export function getAccountByHandle(handle) {
  return db.prepare("SELECT * FROM accounts WHERE handle = ?").get(handle);
}

export function getAccount(id) {
  return db.prepare("SELECT * FROM accounts WHERE id = ?").get(id);
}

export function listAccounts() {
  return db.prepare("SELECT * FROM accounts ORDER BY total_views DESC, handle ASC").all();
}

export function getTokenRow(accountId) {
  return db.prepare("SELECT * FROM tokens WHERE account_id = ?").get(accountId);
}

export function saveTokenRow(accountId, values) {
  db.prepare(`
    INSERT INTO tokens (account_id, access_token_enc, refresh_token_enc, expires_at, refresh_expires_at, scope, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(account_id) DO UPDATE SET
      access_token_enc = excluded.access_token_enc,
      refresh_token_enc = COALESCE(excluded.refresh_token_enc, tokens.refresh_token_enc),
      expires_at = excluded.expires_at,
      refresh_expires_at = COALESCE(excluded.refresh_expires_at, tokens.refresh_expires_at),
      scope = COALESCE(excluded.scope, tokens.scope),
      updated_at = excluded.updated_at
  `).run(
    accountId,
    values.accessTokenEnc,
    values.refreshTokenEnc ?? null,
    values.expiresAt ?? null,
    values.refreshExpiresAt ?? null,
    values.scope ?? null,
    nowIso(),
  );
}

export function clearTokens(accountId) {
  db.prepare("DELETE FROM tokens WHERE account_id = ?").run(accountId);
}

export function updateAccount(id, patch) {
  const keys = Object.keys(patch).filter((k) => accountColumns.includes(k));
  if (!keys.length) return;
  const sql = `UPDATE accounts SET ${keys.map((k) => `${k} = ?`).join(", ")} WHERE id = ?`;
  db.prepare(sql).run(...keys.map((k) => patch[k]), id);
}

export function insertAccount({ id, handle, inputUrl, createdAt }) {
  db.prepare(`
    INSERT INTO accounts (id, handle, input_url, created_at, status)
    VALUES (?, ?, ?, ?, 'pending')
  `).run(id, handle, inputUrl ?? null, createdAt ?? nowIso());
}

export function deleteAccount(id) {
  db.prepare("DELETE FROM accounts WHERE id = ?").run(id);
}

export function replaceVideos(accountId, rows) {
  const insert = db.prepare(`
    INSERT INTO videos (id, account_id, title, cover_url, share_url, duration, create_time,
                        view_count, like_count, comment_count, share_count, fetched_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      title = excluded.title,
      cover_url = excluded.cover_url,
      share_url = excluded.share_url,
      duration = excluded.duration,
      create_time = excluded.create_time,
      view_count = excluded.view_count,
      like_count = excluded.like_count,
      comment_count = excluded.comment_count,
      share_count = excluded.share_count,
      fetched_at = excluded.fetched_at
  `);
  const stamp = nowIso();
  db.exec("BEGIN");
  try {
    for (const v of rows) {
      insert.run(
        v.id, accountId, v.title ?? "", v.coverUrl ?? null, v.shareUrl ?? null,
        v.duration ?? 0, v.createTime ?? 0,
        v.viewCount ?? 0, v.likeCount ?? 0, v.commentCount ?? 0, v.shareCount ?? 0, stamp,
      );
    }
    db.exec("COMMIT");
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}

export function listVideos(accountId, limit = 60) {
  return db.prepare(`
    SELECT * FROM videos WHERE account_id = ? ORDER BY create_time DESC LIMIT ?
  `).all(accountId, limit);
}

export function cleanupOAuthStates() {
  const cutoff = new Date(Date.now() - 15 * 60 * 1000).toISOString();
  db.prepare("DELETE FROM oauth_states WHERE created_at < ?").run(cutoff);
}
