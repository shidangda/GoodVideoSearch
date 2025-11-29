# Nginx 配置指南 - 公网IP访问

## 问题说明

安装脚本默认使用 `hostname -I` 获取的IP地址，这通常是**内网IP**。如果要从公网访问，需要配置**公网IP**或域名。

## 检查当前配置

在服务器上执行：

```bash
# 查看当前Nginx配置
sudo cat /etc/nginx/sites-available/goodvideosearch | grep server_name

# 查看服务器IP地址
hostname -I  # 内网IP
curl ifconfig.me  # 公网IP（如果服务器有公网访问）
```

## 配置方案

### 方案 1：使用公网IP（推荐，如果没有域名）

1. **获取公网IP**

   ```bash
   # 方法1：从云服务器控制台查看
   # 腾讯云/阿里云等控制台会显示公网IP
   
   # 方法2：使用命令查询（如果服务器可以访问外网）
   curl ifconfig.me
   curl ip.sb
   ```

2. **修改Nginx配置**

   ```bash
   sudo nano /etc/nginx/sites-available/goodvideosearch
   ```

   修改 `server_name` 行：

   ```nginx
   server {
       listen 80;
       server_name 你的公网IP;  # 例如：123.45.67.89
       # ... 其他配置
   }
   ```

3. **测试并重载配置**

   ```bash
   # 测试配置
   sudo nginx -t
   
   # 如果测试通过，重载配置
   sudo systemctl reload nginx
   ```

### 方案 2：使用域名（推荐，如果有域名）

1. **修改Nginx配置**

   ```bash
   sudo nano /etc/nginx/sites-available/goodvideosearch
   ```

   修改 `server_name` 行：

   ```nginx
   server {
       listen 80;
       server_name your-domain.com www.your-domain.com;  # 你的域名
       # ... 其他配置
   }
   ```

2. **配置DNS解析**

   在域名DNS管理中添加A记录：
   - 主机记录：`@` 或 `www`
   - 记录值：你的公网IP
   - TTL：600（或默认）

3. **测试并重载配置**

   ```bash
   sudo nginx -t
   sudo systemctl reload nginx
   ```

### 方案 3：同时支持IP和域名

```nginx
server {
    listen 80;
    server_name 你的公网IP your-domain.com www.your-domain.com;
    # ... 其他配置
}
```

### 方案 4：允许所有主机（不推荐，仅用于测试）

```nginx
server {
    listen 80;
    server_name _;  # 下划线表示匹配所有主机名
    # ... 其他配置
}
```

**注意**：这种方式不安全，仅用于测试。

## 重要配置检查

### 1. 确保防火墙开放端口

```bash
# 检查防火墙状态
sudo ufw status

# 如果没有开放80端口，执行：
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp  # 如果使用HTTPS
```

### 2. 检查云服务器安全组

- **腾讯云**：控制台 → 云服务器 → 安全组 → 入站规则
- **阿里云**：控制台 → ECS → 安全组 → 入站规则

确保开放：
- 端口 80（HTTP）
- 端口 443（HTTPS，如果使用）

### 3. 验证配置

```bash
# 1. 测试Nginx配置
sudo nginx -t

# 2. 检查Nginx状态
sudo systemctl status nginx

# 3. 检查应用状态
pm2 status

# 4. 测试访问（在服务器上）
curl http://localhost
curl http://你的公网IP

# 5. 从外部访问
# 在浏览器中访问：http://你的公网IP
```

## 常见问题

### Q1: 配置了公网IP但无法访问？

**检查清单**：
1. ✅ Nginx配置是否正确：`sudo nginx -t`
2. ✅ Nginx服务是否运行：`sudo systemctl status nginx`
3. ✅ 防火墙是否开放端口：`sudo ufw status`
4. ✅ 云服务器安全组是否开放端口
5. ✅ 应用是否正常运行：`pm2 status`
6. ✅ 公网IP是否正确：从云服务器控制台查看

### Q2: 如何查看Nginx访问日志？

```bash
# 实时查看访问日志
sudo tail -f /var/log/nginx/goodvideosearch_access.log

# 查看错误日志
sudo tail -f /var/log/nginx/goodvideosearch_error.log
```

### Q3: 如何配置HTTPS？

使用 Let's Encrypt 免费证书：

```bash
# 安装 Certbot
sudo apt install certbot python3-certbot-nginx -y

# 获取证书（替换为你的域名）
sudo certbot --nginx -d your-domain.com

# 自动续期测试
sudo certbot renew --dry-run
```

## 快速修复脚本

如果安装时使用了内网IP，可以快速修复：

```bash
#!/bin/bash
# 获取公网IP（需要服务器能访问外网）
PUBLIC_IP=$(curl -s ifconfig.me)

if [ -z "$PUBLIC_IP" ]; then
    echo "无法自动获取公网IP，请手动输入："
    read -p "公网IP: " PUBLIC_IP
fi

# 备份原配置
sudo cp /etc/nginx/sites-available/goodvideosearch /etc/nginx/sites-available/goodvideosearch.bak

# 修改配置
sudo sed -i "s/server_name.*;/server_name $PUBLIC_IP;/" /etc/nginx/sites-available/goodvideosearch

# 测试配置
sudo nginx -t && sudo systemctl reload nginx

echo "配置已更新，server_name 设置为: $PUBLIC_IP"
```

## 总结

1. **必须修改**：如果要从公网访问，Nginx的 `server_name` 必须设置为公网IP或域名
2. **推荐使用域名**：更专业，且可以配置HTTPS
3. **检查安全组**：确保云服务器安全组开放了80和443端口
4. **测试访问**：配置后从浏览器访问验证





