# 修复 Node.js 版本问题

## 问题说明

应用报错 `ReferenceError: File is not defined`，原因是：
- `undici` 7.16.0（axios 的依赖）需要 Node.js >= 20.18.1
- 当前安装的是 Node.js 18，不支持 `File` API

## 解决方案

### 方案 1：升级 Node.js 到 20（推荐）

在服务器上执行以下命令：

```bash
# 1. 停止应用
pm2 stop goodvideosearch

# 2. 安装 Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# 3. 验证版本
node --version  # 应该显示 v20.x.x

# 4. 重新安装项目依赖（使用新的 Node.js 版本）
cd ~/GoodVideoSearch
rm -rf node_modules package-lock.json
npm install --production

# 5. 重启应用
pm2 restart goodvideosearch

# 6. 检查应用状态
pm2 logs goodvideosearch
```

### 方案 2：使用 nvm 管理 Node.js 版本（更灵活）

```bash
# 1. 安装 nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc

# 2. 安装 Node.js 20
nvm install 20
nvm use 20
nvm alias default 20

# 3. 验证版本
node --version  # 应该显示 v20.x.x

# 4. 重新安装项目依赖
cd ~/GoodVideoSearch
rm -rf node_modules package-lock.json
npm install --production

# 5. 重启应用
pm2 restart goodvideosearch
```

### 方案 3：降级 axios（不推荐，但可以作为临时方案）

如果暂时无法升级 Node.js，可以降级 axios：

```bash
# 1. 停止应用
pm2 stop goodvideosearch

# 2. 降级 axios
cd ~/GoodVideoSearch
npm install axios@1.6.0 --save

# 3. 重启应用
pm2 restart goodvideosearch
```

**注意**：降级 axios 可能导致功能缺失，建议使用方案 1 或 2。

## 验证修复

修复后，检查应用日志：

```bash
pm2 logs goodvideosearch --lines 50
```

如果不再出现 `ReferenceError: File is not defined` 错误，说明修复成功。

## 预防措施

安装脚本已更新，现在会自动安装 Node.js 20。如果重新部署，使用更新后的脚本即可。

