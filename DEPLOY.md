# GoodVideoSearch 云服务器部署指南

本指南将帮助您将 GoodVideoSearch 项目部署到云服务器上。

## 前置要求

- 一台云服务器（推荐 Ubuntu 20.04+ 或 CentOS 7+）
- 服务器已配置 SSH 访问
- 域名（可选，用于访问）

## 一、服务器环境准备

### 1.1 更新系统

```bash
# Ubuntu/Debian
sudo apt update && sudo apt upgrade -y

# CentOS/RHEL
sudo yum update -y
```

### 1.2 安装 Node.js

推荐使用 Node.js 18+ 版本：

```bash
# 使用 NodeSource 安装（Ubuntu/Debian）
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# 或使用 nvm（推荐）
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc
nvm install 18
nvm use 18
```

验证安装：
```bash
node --version
npm --version
```

### 1.3 安装 MySQL

```bash
# Ubuntu/Debian
sudo apt install mysql-server -y
sudo mysql_secure_installation

# CentOS/RHEL
sudo yum install mysql-server -y
sudo systemctl start mysqld
sudo systemctl enable mysqld
sudo mysql_secure_installation
```

### 1.4 安装 Nginx（用于反向代理）

```bash
# Ubuntu/Debian
sudo apt install nginx -y

# CentOS/RHEL
sudo yum install nginx -y

# 启动并设置开机自启
sudo systemctl start nginx
sudo systemctl enable nginx
```

### 1.5 安装 PM2（进程管理）

```bash
sudo npm install -g pm2
```

## 二、项目部署

### 2.1 上传项目文件

使用以下方式之一上传项目到服务器：

**方式一：使用 Git（推荐）**

```bash
# 在服务器上克隆项目
cd ~
git clone https://github.com/shidangda/GoodVideoSearch.git
cd GoodVideoSearch
```

**方式二：使用 SCP**

```bash
# 在本地执行
scp -r /path/to/GoodVideoSearch user@your-server-ip:~/
```

**方式三：使用 SFTP 工具**

使用 FileZilla、WinSCP 等工具上传项目文件夹。

### 2.2 安装项目依赖

```bash
cd ~/GoodVideoSearch
npm install --production
```

### 2.3 配置环境变量

创建 `.env` 文件：

```bash
cp .env.example .env
nano .env
```

编辑 `.env` 文件，设置以下变量：

```env
# 数据库配置
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=goodvideo_archive
DB_USER=goodvideo_user
DB_PASSWORD=your_secure_password_here

# 应用端口（可选，默认 3000）
PORT=3000
```

**重要：** 请将 `DB_PASSWORD` 替换为强密码！

### 2.4 配置 MySQL 数据库

登录 MySQL：

```bash
sudo mysql -u root -p
```

创建数据库和用户：

```sql
-- 创建数据库
CREATE DATABASE IF NOT EXISTS goodvideo_archive CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 创建用户（请替换密码）
CREATE USER 'goodvideo_user'@'localhost' IDENTIFIED BY 'your_secure_password_here';

-- 授予权限
GRANT ALL PRIVILEGES ON goodvideo_archive.* TO 'goodvideo_user'@'localhost';

-- 刷新权限
FLUSH PRIVILEGES;

-- 退出
EXIT;
```

### 2.5 创建必要的目录

```bash
# 确保 data/covers 目录存在（项目会自动创建，但提前创建更安全）
mkdir -p ~/GoodVideoSearch/data/covers
chmod 755 ~/GoodVideoSearch/data/covers
```

## 三、使用 PM2 启动应用

### 3.1 使用 PM2 启动

```bash
cd ~/GoodVideoSearch
pm2 start src/app.js --name goodvideosearch
```

### 3.2 配置 PM2 开机自启

```bash
pm2 startup
# 按照提示执行生成的命令
pm2 save
```

### 3.3 PM2 常用命令

```bash
# 查看应用状态
pm2 status

# 查看日志
pm2 logs goodvideosearch

# 重启应用
pm2 restart goodvideosearch

# 停止应用
pm2 stop goodvideosearch

# 删除应用
pm2 delete goodvideosearch
```

## 四、配置 Nginx 反向代理

### 4.1 创建 Nginx 配置文件

```bash
sudo nano /etc/nginx/sites-available/goodvideosearch
```

添加以下配置（请替换 `your-domain.com` 为您的域名或服务器 IP）：

```nginx
server {
    listen 80;
    server_name your-domain.com;  # 替换为您的域名或 IP

    # 如果使用域名，取消下面的注释以启用 HTTPS
    # listen 443 ssl;
    # ssl_certificate /path/to/your/cert.pem;
    # ssl_certificate_key /path/to/your/key.pem;

    client_max_body_size 10M;  # 允许上传最大 10MB 的文件

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
```

### 4.2 启用配置

```bash
# Ubuntu/Debian
sudo ln -s /etc/nginx/sites-available/goodvideosearch /etc/nginx/sites-enabled/

# CentOS/RHEL（配置文件路径可能不同）
# 直接编辑 /etc/nginx/nginx.conf 或 /etc/nginx/conf.d/goodvideosearch.conf
```

### 4.3 测试并重启 Nginx

```bash
# 测试配置
sudo nginx -t

# 重启 Nginx
sudo systemctl restart nginx
```

## 五、配置防火墙

### 5.1 Ubuntu/Debian (UFW)

```bash
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS（如果使用）
sudo ufw enable
```

### 5.2 CentOS/RHEL (firewalld)

```bash
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

## 六、SSL 证书配置（可选但推荐）

### 6.1 使用 Let's Encrypt（免费）

```bash
# 安装 Certbot
sudo apt install certbot python3-certbot-nginx -y

# 获取证书（替换为您的域名）
sudo certbot --nginx -d your-domain.com

# 自动续期测试
sudo certbot renew --dry-run
```

## 七、验证部署

1. 访问 `http://your-server-ip` 或 `http://your-domain.com`
2. 检查应用是否正常运行
3. 测试搜索功能
4. 测试历史记录功能

## 八、常见问题排查

### 8.1 应用无法启动

```bash
# 查看 PM2 日志
pm2 logs goodvideosearch

# 检查端口是否被占用
sudo netstat -tulpn | grep 3000

# 检查环境变量
cat ~/GoodVideoSearch/.env
```

### 8.2 数据库连接失败

```bash
# 测试 MySQL 连接
mysql -u goodvideo_user -p -h 127.0.0.1 goodvideo_archive

# 检查 MySQL 服务状态
sudo systemctl status mysql
```

### 8.3 Nginx 502 错误

- 检查应用是否在运行：`pm2 status`
- 检查应用端口是否正确：`netstat -tulpn | grep 3000`
- 查看 Nginx 错误日志：`sudo tail -f /var/log/nginx/error.log`

### 8.4 文件上传失败

- 检查 `data/covers` 目录权限
- 检查 Nginx 的 `client_max_body_size` 配置

## 九、备份建议

### 9.1 数据库备份

创建备份脚本 `~/backup-db.sh`：

```bash
#!/bin/bash
BACKUP_DIR=~/backups
mkdir -p $BACKUP_DIR
mysqldump -u goodvideo_user -p'your_password' goodvideo_archive > $BACKUP_DIR/db_$(date +%Y%m%d_%H%M%S).sql
```

设置定时任务（每天凌晨 2 点备份）：

```bash
crontab -e
# 添加以下行
0 2 * * * /home/your-user/backup-db.sh
```

### 9.2 文件备份

定期备份 `data/covers` 目录：

```bash
tar -czf ~/backups/covers_$(date +%Y%m%d_%H%M%S).tar.gz ~/GoodVideoSearch/data/covers
```

## 十、更新部署

当需要更新应用时：

```bash
cd ~/GoodVideoSearch
git pull  # 如果使用 Git
npm install --production
pm2 restart goodvideosearch
```

## 完成！

现在您的应用应该已经成功部署到云服务器上了。如果遇到任何问题，请查看日志文件或联系技术支持。

