# GoodVideoSearch

自动抓取并筛选高热度视频资源，支持评分、标签管理和历史记录功能。采用现代化的响应式界面设计，提供流畅的用户体验。

## ✨ 功能特点

### 核心功能
- **智能抓取**：自动抓取列表页和详情页，解析热度、收录时间、磁力链接等完整信息
- **灵活筛选**：支持自定义热度阈值（默认 > 50）和页码范围
- **单页模式**：支持直接解析单个详情页，快速获取资源信息
- **自动过滤**：已评分或已隐藏的资源自动从列表中过滤，避免重复处理
- **数据来源**：支持自定义数据来源 URL，可抓取任意同类列表页

### 资源管理
- **评分系统**：1-5 星评分，支持特征标签（高颜值、高身长、美腿、温柔可爱、高冷御姐）
- **封面上传**：支持粘贴截图或上传封面图片（支持剪贴板粘贴）
- **历史记录**：查看所有已评分的资源，支持按标签筛选
- **隐藏功能**：一键隐藏不需要的资源，避免重复显示

### 界面设计
- **现代化 UI**：采用玻璃拟态（Glassmorphism）设计风格
- **响应式布局**：完美适配桌面端和移动端
- **清爽简洁**：优化的头部区域布局，信息层次清晰
- **实时更新**：显示最后更新时间，方便追踪数据新鲜度

## 🚀 快速开始

### 环境要求
- Node.js 18+ 
- MySQL 5.7+ 或 8.0+
- npm 或 yarn

### 本地开发

1. **克隆项目**
```bash
git clone https://github.com/shidangda/GoodVideoSearch.git
cd GoodVideoSearch
```

2. **安装依赖**
```bash
npm install
```

3. **配置数据库**（可选）

项目会自动创建数据库和表，默认配置：
- 数据库名：`goodvideo_archive`
- 数据库用户：`goodvideo_user`
- 数据库密码：`ZhangJun123,03`
- 数据库主机：`127.0.0.1`
- 数据库端口：`3306`

可通过环境变量自定义：
```bash
export DB_NAME=your_db_name
export DB_USER=your_db_user
export DB_PASSWORD=your_password
export DB_HOST=your_host
export DB_PORT=your_port
```

4. **启动服务**
```bash
npm start
```

5. **访问应用**

打开浏览器访问 `http://localhost:3000`

### 使用说明

#### 批量抓取模式
1. 在「数据来源」输入框中填写列表页 URL（默认已填充）
2. 设置「热度下限」（默认 50）
3. 设置「起始页」和「结束页」（默认第 1 页）
4. 点击「刷新」按钮开始抓取

#### 单个详情页模式
1. 在「单个详情页（可选）」输入框中填写详情页 URL
2. 点击「刷新」按钮直接解析该资源
3. 此模式下会忽略列表页配置，更快用于评分

#### 资源评分
1. 在资源卡片上点击「评分」按钮
2. 选择星级（1-5 星）
3. 选择特征标签（可多选）
4. 上传或粘贴封面截图
5. 点击「保存到历史」完成评分

#### 查看历史记录
1. 点击页面右上角「历史资源」按钮
2. 查看所有已评分的资源
3. 支持按标签筛选和搜索

## 📦 云服务器部署

### 一键安装（推荐）

适用于 Ubuntu 20.04+ 服务器，自动完成所有安装和配置：

```bash
# 1. 上传 install.sh 到服务器
# 2. 设置执行权限
chmod +x install.sh

# 3. 执行安装（需要 sudo 权限）
sudo ./install.sh
```

安装脚本会自动完成：
- Node.js 18+ 安装
- MySQL 数据库安装和配置
- Nginx Web 服务器配置
- PM2 进程管理器配置
- 项目部署和开机自启

详细说明请查看：
- [INSTALL_CHECKLIST.md](./INSTALL_CHECKLIST.md) - 安装检查清单
- [INSTALL_GUIDE.md](./INSTALL_GUIDE.md) - 详细安装指南

### 手动部署

如需手动部署，请参考：
- [DEPLOY.md](./DEPLOY.md) - 手动部署指南
- [NGINX_CONFIG_GUIDE.md](./NGINX_CONFIG_GUIDE.md) - Nginx 配置指南
- [REMOTE_DATABASE_ACCESS.md](./REMOTE_DATABASE_ACCESS.md) - 远程数据库访问配置

## 📁 项目结构

```
GoodVideoSearch/
├── src/
│   ├── app.js              # Express 服务器主文件
│   ├── db.js               # 数据库操作（MySQL）
│   ├── scraper.js          # 网页抓取和解析逻辑
│   ├── views/              # EJS 模板文件
│   │   ├── index.ejs       # 主页面模板
│   │   └── history.ejs    # 历史记录页面模板
│   └── public/             # 静态资源
│       └── styles.css      # 样式文件
├── data/                   # 数据目录（自动创建）
│   └── covers/             # 封面图片存储目录
├── install.sh             # 一键安装脚本
├── package.json           # 项目依赖配置
└── README.md             # 本文件
```

## 🔧 配置说明

### 环境变量

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `PORT` | 服务器端口 | `3000` |
| `DB_NAME` | 数据库名称 | `goodvideo_archive` |
| `DB_HOST` | 数据库主机 | `127.0.0.1` |
| `DB_PORT` | 数据库端口 | `3306` |
| `DB_USER` | 数据库用户 | `goodvideo_user` |
| `DB_PASSWORD` | 数据库密码 | `ZhangJun123,03` |

### 抓取配置

可在 `src/scraper.js` 中调整：
- `CONCURRENCY`：详情页并发数（默认 4）
- `LISTING_PAGE_DELAY_MS`：列表页请求间隔（默认 2000ms）
- `MAX_RETRIES`：请求重试次数（默认 3）
- `DEFAULT_HEAT_THRESHOLD`：默认热度阈值（默认 50）
- `DEFAULT_START_PAGE`：默认起始页（默认 1）
- `DEFAULT_END_PAGE`：默认结束页（默认 1）

## 📊 数据库结构

### history_records（已评分资源）
存储用户已评分的资源，包含：
- 资源基本信息（标题、磁链、详情页 URL、热度、收录时间等）
- 评分信息（星级、特征标签）
- 封面图片路径

### history_common_records（已隐藏资源）
存储用户选择隐藏的资源，用于过滤重复显示。

## ⚠️ 注意事项

1. **网络请求**：项目依赖目标站点可用性，如遇 Cloudflare 等防护，可能需要调整请求头或增加重试机制
2. **请求频率**：默认已配置合理的请求间隔和并发数，避免触发限流
3. **数据库**：首次运行会自动创建数据库和表，确保 MySQL 服务正常运行
4. **封面存储**：封面图片存储在 `data/covers/` 目录，确保有足够的磁盘空间
5. **端口占用**：确保 3000 端口未被占用，或通过环境变量 `PORT` 指定其他端口

## 🛠️ 技术栈

- **后端框架**：Express 5.x
- **模板引擎**：EJS
- **数据库**：MySQL 2
- **网页解析**：Cheerio
- **HTTP 请求**：Axios
- **文件上传**：Multer
- **日期处理**：Day.js
- **并发控制**：p-limit

## 📝 更新日志

### v1.0.0
- ✅ 基础抓取和筛选功能
- ✅ 评分和标签系统
- ✅ 历史记录管理
- ✅ 响应式界面设计
- ✅ 单个详情页模式
- ✅ 自动过滤已处理资源
- ✅ 一键部署脚本

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

ISC License

## 🔗 相关链接

- [GitHub 仓库](https://github.com/shidangda/GoodVideoSearch)
- [问题反馈](https://github.com/shidangda/GoodVideoSearch/issues)
