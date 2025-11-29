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
  searchUrl = DEFAULT_SEARCH_URL,
} = {}) {
  const { from, to } = normalizePageRange(startPage, endPage);
  const searchContext = buildSearchContext(searchUrl);

  const listingItems = [];

  for (let page = from; page <= to; page += 1) {
    const searchPageUrl = buildSearchUrl(page, searchContext);
    try {
      const listingHtml = await fetchHtmlWithRetry(searchPageUrl);
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
function buildSearchUrl(page, context) {
  const safePage = Number.isFinite(page) && page > 0 ? page : DEFAULT_START_PAGE;

  if (safePage === 1 || !context.templatePath) {
    return new URL(context.firstPagePath, context.baseUrl).href;
  }

  const path = context.templatePath.replace('{page}', safePage);
  return new URL(path, context.baseUrl).href;
}

function buildSearchContext(rawUrl) {
  let parsed;
  try {
    parsed = new URL(rawUrl || DEFAULT_SEARCH_URL);
  } catch {
    parsed = new URL(DEFAULT_SEARCH_URL);
  }

  const pagePattern = /_(\d+)_id\.html$/;
  const templatePath = parsed.pathname.match(pagePattern)
    ? parsed.pathname.replace(pagePattern, '_{page}_id.html')
    : null;

  return {
    baseUrl: `${parsed.protocol}//${parsed.host}`,
    firstPagePath: parsed.pathname,
    templatePath,
  };
}

function buildDetailRecord($, baseItem = {}) {
  const detailText = cleanText($('.link-detail').text());
  const magnet =
    $('#mag-link').val() ||
    cleanText($('#thread_share_text').text()) ||
    null;

  const detailMeta = extractMeta(detailText);
  const heat = extractNumber(detailText, /热度\s*[:：]?\s*(\d+)/);
  const recordedAt = extractRecordedAt(detailText);

  const titleFromPage =
    cleanText($('.box_line h1').first().text()) ||
    cleanText($('h1').first().text());

  const title =
    baseItem.title ||
    titleFromPage ||
    baseItem.detailUrl ||
    magnet ||
    '未知标题';

  const mergedMeta = {
    ...(baseItem.meta || {}),
    ...detailMeta,
  };

  return {
    ...baseItem,
    title,
    magnet,
    heat,
    recordedAt,
    meta: mergedMeta,
  };
}

function normalizeDetailUrl(value) {
  if (typeof value !== 'string') {
    throw new Error('请提供有效的详情页地址');
  }
  const trimmed = value.trim();
  if (!trimmed) {
    throw new Error('详情页地址不能为空');
  }

  try {
    return new URL(trimmed).href;
  } catch {
    // 如果是相对路径，补全 BASE_URL
    try {
      return new URL(trimmed, BASE_URL).href;
    } catch {
      throw new Error('详情页地址格式不正确');
    }
  }
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
    return buildDetailRecord($, item);
  } catch (error) {
    console.error(`Failed to hydrate ${item.detailUrl}: ${error.message}`);
    return null;
  }
}

export async function getRecordFromDetail(detailUrl) {
  const normalized = normalizeDetailUrl(detailUrl);
  const html = await fetchHtmlWithRetry(normalized);
  const $ = load(html);
  const record = buildDetailRecord($, {
    detailUrl: normalized,
  });
  if (!record || !record.title) {
    throw new Error('未能解析该详情页，请确认地址是否正确');
  }
  return record;
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

