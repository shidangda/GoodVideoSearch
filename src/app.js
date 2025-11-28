import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
import multer from 'multer';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime.js';
import {
  getRecords,
  DEFAULT_HEAT_THRESHOLD,
  DEFAULT_START_PAGE,
  DEFAULT_END_PAGE,
  DEFAULT_SEARCH_URL,
} from './scraper.js';
import {
  getCoverDirectory,
  upsertHistoryRecord,
  listHistoryRecords,
  upsertCommonHistoryRecord,
  isRecordFiltered,
} from './db.js';

dayjs.extend(relativeTime);

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = process.env.PORT || 3000;
const COVER_DIR = getCoverDirectory();

const coverUpload = multer({
  storage: multer.diskStorage({
    destination: (_, __, cb) => cb(null, COVER_DIR),
    filename: (_, file, cb) => {
      const ext = path.extname(file.originalname || '').toLowerCase() || '.png';
      const unique = `cover-${Date.now()}-${Math.random().toString(16).slice(2)}${ext}`;
      cb(null, unique);
    },
  }),
  fileFilter: (_req, file, cb) => {
    if (file.mimetype.startsWith('image/')) {
      cb(null, true);
    } else {
      cb(new Error('仅支持图片格式'));
    }
  },
  limits: {
    fileSize: 6 * 1024 * 1024,
  },
});

app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use('/static', express.static(path.join(__dirname, 'public')));
app.use('/covers', express.static(COVER_DIR));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.get('/', async (req, res, next) => {
  try {
    const heatThreshold = parsePositiveNumber(
      req.query.heat,
      DEFAULT_HEAT_THRESHOLD,
    );
    const pageFrom = parsePositiveInteger(
      req.query.pageFrom,
      DEFAULT_START_PAGE,
    );
    const pageTo = parsePositiveInteger(
      req.query.pageTo,
      DEFAULT_END_PAGE,
    );
    const normalizedSearchUrl = normalizeSearchUrl(req.query.searchUrl);

    const normalizedFrom = Math.max(1, pageFrom);
    const normalizedTo = Math.max(normalizedFrom, pageTo);

    const records = await getRecords({
      heatThreshold,
      startPage: normalizedFrom,
      endPage: normalizedTo,
      searchUrl: normalizedSearchUrl,
    });

    // 过滤掉已存在于历史表中的记录
    const filteredRecords = [];
    for (const record of records) {
      const shouldFilter = await isRecordFiltered(record.title);
      if (!shouldFilter) {
        filteredRecords.push(record);
      }
    }

    const enhanced = filteredRecords.map((record, index) => ({
      ...record,
      displayHeat: `${record.heat}`,
      displayRecordedAt: record.recordedAt
        ? dayjs(record.recordedAt).format('YYYY-MM-DD HH:mm')
        : '未知',
      relativeTime: record.recordedAt
        ? dayjs(record.recordedAt).fromNow()
        : '未知',
      order: index + 1,
      displaySize: formatSizeToGb(record.meta?.size),
      rawSize: record.meta?.size || '',
      rawType: record.meta?.type || '',
      isoRecordedAt: record.recordedAt ? dayjs(record.recordedAt).toISOString() : '',
    }));

    res.render('index', {
      records: enhanced,
      heatThreshold,
      pageFrom: normalizedFrom,
      pageTo: normalizedTo,
      searchUrl: normalizedSearchUrl,
      lastUpdated: dayjs().format('YYYY-MM-DD HH:mm:ss'),
      targetUrl: new URL('/', req.protocol + '://' + req.get('host')).href,
    });
  } catch (error) {
    next(error);
  }
});

app.get('/history', async (req, res, next) => {
  try {
    const rowsData = await listHistoryRecords();
    const rows = rowsData.map((row) => ({
      ...row,
      displaySize: formatSizeToGb(row.size_text) || row.size_text || '未知',
      displayRecordedAt: row.recorded_at
        ? dayjs(row.recorded_at).format('YYYY-MM-DD HH:mm')
        : '未知',
      relativeTime: row.updated_at ? dayjs(row.updated_at).fromNow() : '',
      tags: safeParseTags(row.tags),
      coverUrl: row.cover_path ? `/covers/${row.cover_path}` : null,
    }));

    res.render('history', {
      records: rows,
      lastUpdated: dayjs().format('YYYY-MM-DD HH:mm:ss'),
    });
  } catch (error) {
    next(error);
  }
});

app.post(
  '/history',
  coverUpload.single('cover'),
  async (req, res, next) => {
    try {
      const {
        resourceId,
        title,
        magnet,
        detailUrl,
        heat,
        recordedAt,
        sizeText,
        typeText,
        rating,
        tags,
      } = req.body;

      if (!resourceId || !title) {
        return res.status(400).json({ message: '缺少资源标识或标题' });
      }

      const normalizedRating = Math.min(
        5,
        Math.max(1, Number.parseInt(rating, 10) || 0),
      );
      if (!normalizedRating) {
        return res.status(400).json({ message: '请至少选择一颗星' });
      }

      if (!req.file) {
        return res.status(400).json({ message: '请上传封面截图' });
      }

      let parsedTags = [];
      try {
        const candidate = JSON.parse(tags || '[]');
        parsedTags = Array.isArray(candidate) ? candidate : [];
      } catch {
        parsedTags = [];
      }

      await upsertHistoryRecord({
        resourceId,
        title,
        magnet,
        detailUrl,
        heat: Number.isFinite(Number(heat)) ? Number(heat) : null,
        recordedAt,
        sizeText,
        typeText,
        rating: normalizedRating,
        tags: JSON.stringify(parsedTags),
        coverPath: req.file.filename,
      });

      res.json({ message: '保存成功' });
    } catch (error) {
      next(error);
    }
  },
);

app.post('/hide-resource', async (req, res, next) => {
  try {
    const {
      resourceId,
      title,
      magnet,
      detailUrl,
      heat,
      recordedAt,
      sizeText,
      typeText,
    } = req.body;

    if (!resourceId || !title) {
      return res.status(400).json({ message: '缺少资源标识或标题' });
    }

    await upsertCommonHistoryRecord({
      resourceId,
      title,
      magnet: magnet || null,
      detailUrl: detailUrl || null,
      heat: Number.isFinite(Number(heat)) ? Number(heat) : null,
      recordedAt: recordedAt || null,
      sizeText: sizeText || null,
      typeText: typeText || null,
    });

    res.json({ message: '已隐藏' });
  } catch (error) {
    next(error);
  }
});

app.use((err, req, res, _next) => {
  console.error(err);

  const heatThreshold = parsePositiveNumber(
    req.query.heat,
    DEFAULT_HEAT_THRESHOLD,
  );

  const from = parsePositiveInteger(
    req.query.pageFrom,
    DEFAULT_START_PAGE,
  );
  const to = parsePositiveInteger(
    req.query.pageTo,
    DEFAULT_END_PAGE,
  );
  const pageFrom = Math.max(1, from);
  const pageTo = Math.max(pageFrom, to);
  const normalizedSearchUrl = normalizeSearchUrl(req.query.searchUrl);

  res.status(500).render('index', {
    records: [],
    heatThreshold,
    pageFrom,
    pageTo,
    searchUrl: normalizedSearchUrl,
    lastUpdated: dayjs().format('YYYY-MM-DD HH:mm:ss'),
    targetUrl: req.originalUrl,
    errorMessage:
      err.message || '服务出现异常，请稍后再试。',
  });
});

function parsePositiveInteger(value, fallback) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  const int = Math.trunc(parsed);
  return int > 0 ? int : fallback;
}

function parsePositiveNumber(value, fallback) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }
  return parsed;
}

function normalizeSearchUrl(value) {
  if (typeof value !== 'string') {
    return DEFAULT_SEARCH_URL;
  }
  const trimmed = value.trim();
  if (!trimmed) {
    return DEFAULT_SEARCH_URL;
  }
  try {
    const parsed = new URL(trimmed);
    return parsed.href;
  } catch (error) {
    return DEFAULT_SEARCH_URL;
  }
}

function formatSizeToGb(rawValue) {
  if (typeof rawValue !== 'string' || !rawValue.trim()) {
    return null;
  }
  const normalized = rawValue.trim().toLowerCase();
  const match = normalized.match(/(\d+(?:\.\d+)?)/);
  if (!match) {
    return null;
  }
  const value = Number(match[1]);
  if (!Number.isFinite(value)) {
    return null;
  }

  let unitMultiplier = 1;
  if (normalized.includes('tb') || normalized.endsWith('t')) {
    unitMultiplier = 1024;
  } else if (normalized.includes('mb') || normalized.endsWith('m')) {
    unitMultiplier = 1 / 1024;
  } else if (normalized.includes('kb') || normalized.endsWith('k')) {
    unitMultiplier = 1 / (1024 * 1024);
  } else if (normalized.includes('gb') || normalized.endsWith('g')) {
    unitMultiplier = 1;
  }

  const gbValue = value * unitMultiplier;
  const display =
    gbValue >= 10 ? gbValue.toFixed(1) : gbValue.toFixed(2);
  return `${Number(display)} GB`;
}

function safeParseTags(value) {
  try {
    const parsed = JSON.parse(value || '[]');
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

app.listen(PORT, () => {
  console.log(`GoodVideoSearch server is running on http://localhost:${PORT}`);
});

    1