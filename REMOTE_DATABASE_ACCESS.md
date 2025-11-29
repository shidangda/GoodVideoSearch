# 远程数据库访问配置指南

使用 DBeaver 或其他工具连接云服务器上的 MySQL 数据库。

## 问题原因

MySQL 默认配置：
- 只监听 `127.0.0.1`（本地连接）
- 用户权限只允许 `localhost` 连接
- 云服务器防火墙/安全组可能未开放 3306 端口

## 解决方案

### 步骤 1：配置 MySQL 允许远程连接

在服务器上执行：

```bash
# 1. 编辑 MySQL 配置文件
sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf

# 或 Ubuntu 20.04 可能在这里：
sudo nano /etc/mysql/my.cnf
```

找到 `bind-address` 行，修改为：

```ini
# 允许所有 IP 连接（或指定特定 IP）
bind-address = 0.0.0.0

# 或者只允许特定 IP（更安全）
# bind-address = 你的公网IP
```

**保存并退出**（Ctrl+X, Y, Enter）

### 步骤 2：重启 MySQL 服务

```bash
sudo systemctl restart mysql
sudo systemctl status mysql
```

### 步骤 3：创建允许远程连接的用户

```bash
# 登录 MySQL
sudo mysql -u root -p
```

执行以下 SQL：

```sql
-- 创建允许远程连接的用户（使用你的公网IP或 % 表示所有IP）
-- 方案1：允许所有IP连接（不推荐，安全性较低）
CREATE USER 'goodvideo_user'@'%' IDENTIFIED BY '你的密码';
GRANT ALL PRIVILEGES ON goodvideo_archive.* TO 'goodvideo_user'@'%';
FLUSH PRIVILEGES;

-- 方案2：只允许特定IP连接（推荐，更安全）
-- 替换 YOUR_IP 为你的本地公网IP
CREATE USER 'goodvideo_user'@'YOUR_IP' IDENTIFIED BY '你的密码';
GRANT ALL PRIVILEGES ON goodvideo_archive.* TO 'goodvideo_user'@'YOUR_IP';
FLUSH PRIVILEGES;

-- 查看用户权限
SELECT user, host FROM mysql.user WHERE user='goodvideo_user';
```

**注意**：
- `%` 表示允许所有IP连接（安全性较低）
- 指定IP更安全，但需要知道你的本地公网IP
- 如果使用 `%`，建议使用强密码

### 步骤 4：配置防火墙

```bash
# 检查防火墙状态
sudo ufw status

# 开放 3306 端口（MySQL）
sudo ufw allow 3306/tcp

# 如果防火墙未启用，可以启用它
sudo ufw enable
```

### 步骤 5：配置云服务器安全组

**腾讯云**：
1. 登录控制台
2. 云服务器 → 安全组
3. 添加入站规则：
   - 类型：自定义
   - 协议端口：TCP:3306
   - 来源：你的本地IP（或 0.0.0.0/0 允许所有，不推荐）

**阿里云**：
1. 登录控制台
2. ECS → 安全组
3. 配置规则 → 入方向 → 添加安全组规则
4. 端口范围：3306/3306
5. 授权对象：你的本地IP

**AWS**：
1. EC2 → Security Groups
2. Inbound rules → Add rule
3. Type: MySQL/Aurora
4. Port: 3306
5. Source: Your IP

### 步骤 6：在 DBeaver 中配置连接

1. **打开 DBeaver**
   - 新建连接 → MySQL

2. **配置连接信息**
   ```
   主机：你的服务器公网IP（例如：106.52.243.103）
   端口：3306
   数据库：goodvideo_archive
   用户名：goodvideo_user
   密码：你的数据库密码
   ```

3. **高级设置**（可选）
   - 驱动属性 → `useSSL` → `false`（如果未配置SSL）
   - 驱动属性 → `allowPublicKeyRetrieval` → `true`（如果使用 MySQL 8.0+）

4. **测试连接**
   - 点击"测试连接"
   - 如果成功，点击"完成"

## 安全建议

### 1. 使用 SSH 隧道（最安全，推荐）

不直接暴露 3306 端口，通过 SSH 隧道连接：

**DBeaver 配置**：
1. 新建连接 → MySQL
2. 在"SSH"标签页：
   - 启用 SSH 隧道：✓
   - 主机：你的服务器IP
   - 端口：22
   - 用户名：ubuntu
   - 认证方式：密码或密钥
3. 在主连接标签页：
   - 主机：`localhost`（通过SSH隧道）
   - 端口：3306
   - 其他配置同上

**优点**：
- 不需要开放 3306 端口
- 数据通过加密的 SSH 连接传输
- 更安全

### 2. 只允许特定IP连接

创建用户时指定IP，而不是使用 `%`：

```sql
-- 查询你的本地公网IP
-- 访问：https://www.whatismyip.com/

-- 创建只允许该IP连接的用户
CREATE USER 'goodvideo_user'@'你的本地IP' IDENTIFIED BY '强密码';
GRANT ALL PRIVILEGES ON goodvideo_archive.* TO 'goodvideo_user'@'你的本地IP';
FLUSH PRIVILEGES;
```

### 3. 使用强密码

```sql
-- 修改用户密码
ALTER USER 'goodvideo_user'@'%' IDENTIFIED BY '新的强密码';
FLUSH PRIVILEGES;
```

## 验证配置

### 1. 检查 MySQL 监听地址

```bash
# 查看 MySQL 监听的地址
sudo netstat -tlnp | grep 3306

# 应该看到：
# tcp  0  0  0.0.0.0:3306  0.0.0.0:*  LISTEN  ...
```

如果看到 `127.0.0.1:3306`，说明只监听本地，需要修改配置。

### 2. 测试远程连接

```bash
# 在本地（Windows）测试连接
# 需要先安装 MySQL 客户端
mysql -h 106.52.243.103 -P 3306 -u goodvideo_user -p goodvideo_archive
```

### 3. 检查用户权限

```sql
-- 在服务器上执行
SELECT user, host FROM mysql.user WHERE user='goodvideo_user';

-- 应该看到：
-- goodvideo_user | %          (允许所有IP)
-- 或
-- goodvideo_user | 你的IP      (只允许特定IP)
```

## 常见问题

### Q1: 连接超时？

**检查清单**：
1. ✅ MySQL 是否监听 `0.0.0.0:3306`（不是 `127.0.0.1`）
2. ✅ 防火墙是否开放 3306 端口
3. ✅ 云服务器安全组是否开放 3306 端口
4. ✅ 用户是否允许远程连接（host 不是 `localhost`）
5. ✅ 公网IP是否正确

### Q2: Access denied？

**可能原因**：
- 用户只允许 `localhost` 连接
- 密码错误
- IP 不在允许列表中

**解决方案**：
```sql
-- 查看用户权限
SELECT user, host FROM mysql.user WHERE user='goodvideo_user';

-- 如果只有 localhost，创建远程用户
CREATE USER 'goodvideo_user'@'%' IDENTIFIED BY '密码';
GRANT ALL PRIVILEGES ON goodvideo_archive.* TO 'goodvideo_user'@'%';
FLUSH PRIVILEGES;
```

### Q3: 如何查看我的本地公网IP？

访问以下网站：
- https://www.whatismyip.com/
- https://ip.sb/
- https://ifconfig.me/

### Q4: 使用 SSH 隧道还是直接连接？

**SSH 隧道（推荐）**：
- ✅ 更安全
- ✅ 不需要开放 3306 端口
- ✅ 数据加密传输

**直接连接**：
- ✅ 配置简单
- ❌ 需要开放端口
- ❌ 安全性较低

## 快速配置脚本

在服务器上执行以下脚本快速配置：

```bash
#!/bin/bash
# 快速配置 MySQL 远程访问

# 1. 备份配置文件
sudo cp /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf.bak

# 2. 修改 bind-address
sudo sed -i 's/bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf

# 3. 重启 MySQL
sudo systemctl restart mysql

# 4. 创建远程用户（需要手动输入密码）
echo "请在 MySQL 中执行："
echo "CREATE USER 'goodvideo_user'@'%' IDENTIFIED BY '你的密码';"
echo "GRANT ALL PRIVILEGES ON goodvideo_archive.* TO 'goodvideo_user'@'%';"
echo "FLUSH PRIVILEGES;"

# 5. 开放防火墙
sudo ufw allow 3306/tcp

echo "配置完成！请记得："
echo "1. 在 MySQL 中创建远程用户"
echo "2. 在云服务器控制台开放 3306 端口"
```

## 总结

1. **必须配置**：MySQL 监听地址改为 `0.0.0.0`
2. **必须创建**：允许远程连接的用户（host 不是 `localhost`）
3. **必须开放**：防火墙和云服务器安全组的 3306 端口
4. **推荐使用**：SSH 隧道连接（更安全）
5. **安全建议**：只允许特定IP连接，使用强密码





