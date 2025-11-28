import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import mysql from 'mysql2/promise';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const DATA_DIR = path.resolve(__dirname, '../data');
const COVER_DIR = path.join(DATA_DIR, 'covers');
fs.mkdirSync(COVER_DIR, { recursive: true });

const DB_NAME = process.env.DB_NAME || 'goodvideo_archive';
const DB_HOST = process.env.DB_HOST || '127.0.0.1';
const DB_PORT = Number(process.env.DB_PORT) || 3306;
const DB_USER = process.env.DB_USER || 'goodvideo_user';
const DB_PASSWORD = process.env.DB_PASSWORD || 'ZhangJun123,03';

const baseConfig = {
  host: DB_HOST,
  port: DB_PORT,
  user: DB_USER,
  password: DB_PASSWORD,
  timezone: 'Z',
  dateStrings: true,
};

let pool;

async function ensureDatabase() {
  const connection = await mysql.createConnection(baseConfig);
  await connection.query(
    `CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`,
  );
  await connection.end();
}

async function ensureTables() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS history_records (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      resource_id VARCHAR(191) NOT NULL UNIQUE,
      title VARCHAR(512) NOT NULL,
      magnet TEXT,
      detail_url TEXT,
      heat INT,
      recorded_at DATETIME NULL,
      size_text VARCHAR(255),
      type_text VARCHAR(255),
      rating TINYINT,
      tags JSON,
      cover_path VARCHAR(255),
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS history_common_records (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      resource_id VARCHAR(191) NOT NULL UNIQUE,
      title VARCHAR(512) NOT NULL,
      magnet TEXT,
      detail_url TEXT,
      heat INT,
      recorded_at DATETIME NULL,
      size_text VARCHAR(255),
      type_text VARCHAR(255),
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  `);
}

async function bootstrap() {
  await ensureDatabase();
  pool = mysql.createPool({
    ...baseConfig,
    database: DB_NAME,
    waitForConnections: true,
    connectionLimit: 10,
  });
  await ensureTables();
}

const ready = bootstrap();

export function getCoverDirectory() {
  return COVER_DIR;
}

export async function upsertHistoryRecord(record) {
  await ready;
  const sql = `
    INSERT INTO history_records (
      resource_id,
      title,
      magnet,
      detail_url,
      heat,
      recorded_at,
      size_text,
      type_text,
      rating,
      tags,
      cover_path
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
      title = VALUES(title),
      magnet = VALUES(magnet),
      detail_url = VALUES(detail_url),
      heat = VALUES(heat),
      recorded_at = VALUES(recorded_at),
      size_text = VALUES(size_text),
      type_text = VALUES(type_text),
      rating = VALUES(rating),
      tags = VALUES(tags),
      cover_path = VALUES(cover_path),
      updated_at = CURRENT_TIMESTAMP
  `;

  const recordedAt =
    record.recordedAt && !Number.isNaN(Date.parse(record.recordedAt))
      ? new Date(record.recordedAt)
      : null;

  await pool.execute(sql, [
    record.resourceId,
    record.title,
    record.magnet || null,
    record.detailUrl || null,
    record.heat ?? null,
    recordedAt,
    record.sizeText || null,
    record.typeText || null,
    record.rating ?? null,
    record.tags || '[]',
    record.coverPath || null,
  ]);
}

export async function listHistoryRecords() {
  await ready;
  const [rows] = await pool.query(
    'SELECT * FROM history_records ORDER BY updated_at DESC',
  );
  return rows;
}

export async function upsertCommonHistoryRecord(record) {
  await ready;
  const sql = `
    INSERT INTO history_common_records (
      resource_id,
      title,
      magnet,
      detail_url,
      heat,
      recorded_at,
      size_text,
      type_text
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
      title = VALUES(title),
      magnet = VALUES(magnet),
      detail_url = VALUES(detail_url),
      heat = VALUES(heat),
      recorded_at = VALUES(recorded_at),
      size_text = VALUES(size_text),
      type_text = VALUES(type_text),
      updated_at = CURRENT_TIMESTAMP
  `;

  const recordedAt =
    record.recordedAt && !Number.isNaN(Date.parse(record.recordedAt))
      ? new Date(record.recordedAt)
      : null;

  await pool.execute(sql, [
    record.resourceId,
    record.title,
    record.magnet || null,
    record.detailUrl || null,
    record.heat ?? null,
    recordedAt,
    record.sizeText || null,
    record.typeText || null,
  ]);
}

export async function isRecordFiltered(title) {
  await ready;
  if (!title || typeof title !== 'string') {
    return false;
  }

  // 检查完整标题是否存在于两张表中
  const [exactMatches] = await pool.query(
    `SELECT 1 FROM history_records WHERE title = ?
     UNION
     SELECT 1 FROM history_common_records WHERE title = ?
     LIMIT 1`,
    [title, title],
  );

  if (exactMatches.length > 0) {
    return true;
  }

  // 提取标题中的连续7位数字
  const sevenDigitMatches = title.match(/\d{7}/g);
  if (!sevenDigitMatches || sevenDigitMatches.length === 0) {
    return false;
  }

  // 检查这些7位数字是否在两张表的title字段中出现
  // 使用 LIKE 模式匹配，更安全
  for (const sevenDigits of sevenDigitMatches) {
    const [digitMatches] = await pool.query(
      `SELECT 1 FROM history_records WHERE title LIKE ?
       UNION
       SELECT 1 FROM history_common_records WHERE title LIKE ?
       LIMIT 1`,
      [`%${sevenDigits}%`, `%${sevenDigits}%`],
    );

    if (digitMatches.length > 0) {
      return true;
    }
  }

  return false;
}

