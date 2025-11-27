# GoodVideoSearch

自动抓取 `https://www.cilifan.mom/search/666332_1_id.html` 上的资源，逐条解析详情页里的热度与收录时间，筛选出热度大于 50 的记录，并以美观的网页形式展示下载链接。

## 功能特点
- 列表页与详情页双重解析，保证热度、时间、磁力链接数据完整
- 按收录时间倒序排列，动态筛选热度阈值
- 采用玻璃拟态风格的响应式界面，桌面与移动端均友好

## 快速开始
```bash
npm install
npm start
```

启动后访问 `http://localhost:3000`，即可看到最新筛选结果：
- 可通过「热度下限」输入框调整热度过滤阈值（默认 > 50）；
- 可通过「起始页 / 结束页」输入框设置抓取的页码范围（默认第 1–5 页）。

## 结构说明
- `src/scraper.js`：抓取列表页、并发解析详情页（磁力、热度、时间）
- `src/app.js`：Express 服务，注入数据并渲染 EJS 视图
- `src/views/index.ejs`：页面模板
- `src/public/styles.css`：自定义样式

## 注意事项
- 网络请求依赖目标站点可用性，如遇 Cloudflare 等阻断，可适当增加 headers 或重试
- 默认并发 4 条详情请求，可按需要在 `src/scraper.js` 中调整
