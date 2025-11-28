import axios from 'axios';
import { load } from 'cheerio';
import dayjs from 'dayjs';
import customParseFormat from 'dayjs/plugin/customParseFormat.js';
import pLimit from 'p-limit';

dayjs.extend(customParseFormat);

const BASE_URL = 'https://www.cilifan.mom';
const DEFAULT_SEARCH_PATH = '/search/666332_1_id.html';
const USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36';

// 统一默认配置，方便在其他模块中复用
export const DEFAULT_HEAT_THRESHOLD = 50;
export const DEFAULT_START_PAGE = 1;
export const DEFAULT_END_PAGE = 1; // 默认只访问第1页，减少请求频率

// 适当提高并发，提升整体抓取速度（详情页并发数）
// 降低并发数，避免触发 429 限流
const CONCURRENCY = 4;
// 列表页请求间隔（毫秒），避免请求过快被限流
// 增加延迟，降低被限流的风险
const LISTING_PAGE_DELAY_MS = 2000;
// 请求重试配置
const MAX_RETRIES = 3;
const RETRY_DELAY_MS = 2000; // 首次重试延迟 2 秒
// 429 限流错误的重试延迟（更长，因为需要等待限流解除）
const RATE_LIMIT_RETRY_DELAY_MS = 10000; // 10 秒

const limit = pLimit(CONCURRENCY);

const HEADERS = {
  'User-Agent': USER_AGENT,
  Referer: BASE_URL,
  Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
};

const DATE_FORMATS = [
  'YYYY-MM-DD HH:mm',
  'YYYY-MM-DD HH:mm:ss',
  'YYYY/MM/DD HH:mm',
  'YYYY/MM/DD HH:mm:ss',
  'YYYY-MM-DD',
  'YYYY/MM/DD',
];

export const DEFAULT_SEARCH_URL = new URL(DEFAULT_SEARCH_PATH, BASE_URL).href;

/**
 * 按条件抓取多页记录并做热度 / 时间排序
 */
export async function getRecords({
  heatThreshold = DEFAULT_HEAT_THRESHOLD,
  startPage = DEFAULT_START_PAGE,
  endPage = DEFAULT_END_PAGE,
} = {}) {
  const { from, to } = normalizePageRange(startPage, endPage);

  const listingItems = [];

  for (let page = from; page <= to; page += 1) {
    const searchUrl = buildSearchUrl(page);
    try {
      const listingHtml = await fetchHtmlWithRetry(searchUrl);
      const $ = load(listingHtml);

      $('.item').each((_, element) => {
        const parsed = parseListingItem($, element);
        if (parsed) {
          listingItems.push({ ...parsed, page });
        }
      });

      // 列表页之间添加延迟，避免请求过快被限流
      // 即使最后一页也添加延迟，避免后续详情页请求过快
      if (page < to) {
        await sleep(LISTING_PAGE_DELAY_MS);
      } else {
        // 最后一页也稍作延迟，给服务器喘息时间
        await sleep(LISTING_PAGE_DELAY_MS / 2);
      }
    } catch (error) {
      console.error(`Failed to fetch listing page ${page} after retries: ${error.message}`);
    }
  }

  // 详情页请求之间也添加小延迟，避免并发过高触发限流
  // 改用串行处理，每个请求后添加延迟，降低被限流的风险
  const hydrated = [];
  for (const item of listingItems) {
    const result = await limit(() => enrichWithDetail(item));
    if (result) {
      hydrated.push(result);
    }
    // 每个详情页请求后稍作延迟（500ms），避免请求过快
    await sleep(500);
  }

  return hydrated
    .filter((item) => typeof item.heat === 'number' && item.heat > heatThreshold)
    .sort((a, b) => {
      if (!a.recordedAt && !b.recordedAt) return 0;
      if (!a.recordedAt) return 1;
      if (!b.recordedAt) return -1;
      return b.recordedAt.valueOf() - a.recordedAt.valueOf();
    });
}

/**
 * 带重试机制的 HTTP 请求
 * @param {string} url 目标 URL
 * @param {number} retries 剩余重试次数
 * @returns {Promise<string>} HTML 内容
 */
async function fetchHtmlWithRetry(url, retries = MAX_RETRIES) {
  try {
    const response = await axios.get(url, {
      headers: HEADERS,
      timeout: 45000,
      // 增加连接超时配置，避免长时间等待
      validateStatus: (status) => status >= 200 && status < 400,
    });
    return response.data;
  } catch (error) {
    // 判断是否为可重试的错误
    const statusCode = error.response?.status;
    const isRateLimit = statusCode === 429; // 429 Too Many Requests
    const isRetryable =
      error.code === 'ECONNABORTED' ||
      error.code === 'ETIMEDOUT' ||
      error.code === 'ECONNRESET' ||
      error.code === 'ENOTFOUND' ||
      (error.response && error.response.status >= 500) ||
      isRateLimit; // 429 错误也可以重试

    if (isRetryable && retries > 0) {
      // 对于 429 限流错误，使用更长的延迟
      const baseDelay = isRateLimit
        ? RATE_LIMIT_RETRY_DELAY_MS
        : RETRY_DELAY_MS;
      // 指数退避：每次重试延迟时间递增
      const delay = baseDelay * (MAX_RETRIES - retries + 1);
      console.warn(
        `Request failed for ${url}${isRateLimit ? ' (Rate Limited)' : ''}, retrying in ${delay}ms... (${retries} retries left)`,
      );
      await sleep(delay);
      return fetchHtmlWithRetry(url, retries - 1);
    }

    throw error;
  }
}

/**
 * 简单的延迟函数
 * @param {number} ms 延迟毫秒数
 */
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * 构造指定页码的搜索 URL
 */
function buildSearchUrl(page) {
  const safePage = Number.isFinite(page) && page > 0 ? page : DEFAULT_START_PAGE;

  if (safePage === 1) {
    return DEFAULT_SEARCH_URL;
  }

  // 站点分页规则：/search/666332_1_id.html、/search/666332_2_id.html、...
  // 为避免 DEFAULT_SEARCH_PATH 被误改，这里用正则替换页码部分
  const path = DEFAULT_SEARCH_PATH.replace(
    /_(\d+)_id\.html$/,
    `_${safePage}_id.html`,
  );
  return new URL(path, BASE_URL).href;
}

/**
 * 规范化页码区间，保证 1 <= from <= to
 */
function normalizePageRange(startPage, endPage) {
  const fromRaw = Number.isFinite(startPage) ? startPage : DEFAULT_START_PAGE;
  const toRaw = Number.isFinite(endPage) ? endPage : DEFAULT_END_PAGE;

  const from = Math.max(1, fromRaw);
  const to = Math.max(from, toRaw);

  return { from, to };
}

function parseListingItem($, element) {
  const titleAnchor = $(element).find('.threadlist_subject a').first();
  if (!titleAnchor.length) {
    return null;
  }

  const relativeHref = titleAnchor.attr('href');
  const detailUrl = new URL(relativeHref, BASE_URL).href;
  const title = cleanText(titleAnchor.text());
  const noteText = cleanText($(element).find('.threadlist_note').text());

  return {
    title,
    detailUrl,
    meta: extractMeta(noteText),
  };
}

async function enrichWithDetail(item) {
  try {
    const html = await fetchHtmlWithRetry(item.detailUrl);
    const $ = load(html);
    const magnet =
      $('#mag-link').val() ||
      cleanText($('#thread_share_text').text()) ||
      null;
    const detailText = cleanText($('.link-detail').text());

    const heat = extractNumber(detailText, /热度\s*[:：]?\s*(\d+)/);
    const recordedAt = extractRecordedAt(detailText);

    return {
      ...item,
      magnet,
      heat,
      recordedAt,
    };
  } catch (error) {
    console.error(`Failed to hydrate ${item.detailUrl}: ${error.message}`);
    return null;
  }
}

function extractMeta(text) {
  const meta = {};
  meta.type = captureText(text, /类型[:：]\s*([^\s]+)/);
  meta.size = captureText(text, /大小[:：]\s*([^\s]+)/);
  meta.listedTimeText = captureText(text, /收录[:：]\s*([^\s]+)/);
  return meta;
}

function extractNumber(text, pattern) {
  const match = text.match(pattern);
  if (!match) {
    return null;
  }
  const value = Number(match[1]);
  return Number.isNaN(value) ? null : value;
}

function extractRecordedAt(text) {
  const raw = captureText(text, /收录[:：]\s*([^\s]+(?:\s+[^\s]+)?)/);
  if (!raw) {
    return null;
  }

  const normalized = raw.replace(/[年月]/g, '-').replace(/[日]/g, '');

  const relativeMatch = normalized.match(/(\d+)\s*(分钟|小时|天)前/);
  if (relativeMatch) {
    const [, amountStr, unit] = relativeMatch;
    const amount = Number(amountStr);
    if (!Number.isNaN(amount)) {
      switch (unit) {
        case '分钟':
          return dayjs().subtract(amount, 'minute');
        case '小时':
          return dayjs().subtract(amount, 'hour');
        case '天':
          return dayjs().subtract(amount, 'day');
        default:
          break;
      }
    }
  }

  if (normalized.includes('刚')) {
    return dayjs();
  }

  for (const format of DATE_FORMATS) {
    const parsed = dayjs(normalized, format, true);
    if (parsed.isValid()) {
      return parsed;
    }
  }

  const fallback = dayjs(normalized);
  return fallback.isValid() ? fallback : null;
}

function captureText(text, pattern) {
  const match = text.match(pattern);
  return match ? match[1].trim() : null;
}

function cleanText(value) {
  return value ? value.replace(/\s+/g, ' ').trim() : '';
}

