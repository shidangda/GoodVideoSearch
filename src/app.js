import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime.js';
import {
  getRecords,
  DEFAULT_HEAT_THRESHOLD,
  DEFAULT_START_PAGE,
  DEFAULT_END_PAGE,
} from './scraper.js';

dayjs.extend(relativeTime);

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = process.env.PORT || 3000;

app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use('/static', express.static(path.join(__dirname, 'public')));

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

    const normalizedFrom = Math.max(1, pageFrom);
    const normalizedTo = Math.max(normalizedFrom, pageTo);

    const records = await getRecords({
      heatThreshold,
      startPage: normalizedFrom,
      endPage: normalizedTo,
    });

    const enhanced = records.map((record, index) => ({
      ...record,
      displayHeat: `${record.heat}`,
      displayRecordedAt: record.recordedAt
        ? dayjs(record.recordedAt).format('YYYY-MM-DD HH:mm')
        : '未知',
      relativeTime: record.recordedAt
        ? dayjs(record.recordedAt).fromNow()
        : '未知',
      order: index + 1,
    }));

    res.render('index', {
      records: enhanced,
      heatThreshold,
      pageFrom: normalizedFrom,
      pageTo: normalizedTo,
      lastUpdated: dayjs().format('YYYY-MM-DD HH:mm:ss'),
      targetUrl: new URL('/', req.protocol + '://' + req.get('host')).href,
    });
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

  res.status(500).render('index', {
    records: [],
    heatThreshold,
    pageFrom,
    pageTo,
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

app.listen(PORT, () => {
  console.log(`GoodVideoSearch server is running on http://localhost:${PORT}`);
});

    1