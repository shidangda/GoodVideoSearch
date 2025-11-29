# 修复数据库用户访问问题

## 问题说明

应用报错：`Access denied for user 'goodvideo_user'@'localhost'`

**根本原因**：
- MySQL 中 `localhost` 和 `127.0.0.1` 被视为不同的主机
- 安装脚本只创建了 `'goodvideo_user'@'localhost'`
- 但应用使用 `127.0.0.1` 连接，MySQL 查找 `'goodvideo_user'@'127.0.0.1'` 用户，但该用户不存在

## 立即修复方案

在服务器上执行以下 SQL 命令（使用 root 用户登录）：

```bash
sudo mysql -u root -p
```

然后执行：

```sql
-- 创建 127.0.0.1 版本的用户（如果应用使用 127.0.0.1 连接）
CREATE USER IF NOT EXISTS 'goodvideo_user'@'127.0.0.1' IDENTIFIED BY '你的密码';

-- 授予权限
GRANT ALL PRIVILEGES ON goodvideo_archive.* TO 'goodvideo_user'@'127.0.0.1';

-- 刷新权限
FLUSH PRIVILEGES;

-- 验证用户创建成功
SELECT user, host FROM mysql.user WHERE user='goodvideo_user';
```

应该看到两行：
- `goodvideo_user | localhost`
- `goodvideo_user | 127.0.0.1`

## 或者：修改应用使用 localhost

如果不想创建新用户，可以修改 `.env` 文件：

```bash
cd ~/GoodVideoSearch
nano .env
```

将 `DB_HOST` 改为 `localhost`：

```env
DB_HOST=localhost
```

然后重启应用：

```bash
pm2 restart goodvideosearch
```

## 推荐方案

**同时创建两个用户**（已更新安装脚本）：
- `'goodvideo_user'@'localhost'` - 用于 Unix socket 连接
- `'goodvideo_user'@'127.0.0.1'` - 用于 TCP/IP 连接

这样无论应用使用哪种方式连接都能正常工作。

## 验证修复

修复后，测试连接：

```bash
# 测试 localhost 连接
mysql -u goodvideo_user -p -h localhost goodvideo_archive

# 测试 127.0.0.1 连接
mysql -u goodvideo_user -p -h 127.0.0.1 goodvideo_archive
```

两个都应该能成功连接。

然后重启应用：

```bash
pm2 restart goodvideosearch
pm2 logs goodvideosearch
```

如果不再出现 `Access denied` 错误，说明修复成功。





