# 数据库迁移指南

将本地数据库迁移到云服务器的完整指南。

**注意**：如果本地数据库在 Windows 系统上，请参考 `DATABASE_MIGRATION_WINDOWS.md`。

## 方案 1：使用 mysqldump（推荐）

这是最常用和可靠的方法，可以完整备份和恢复数据库。

### 步骤 1：在本地导出数据库

```bash
# 在本地执行
mysqldump -u goodvideo_user -p goodvideo_archive > backup.sql
```

或者包含更多选项（推荐）：

```bash
# 完整导出（包含表结构、数据、索引等）
mysqldump -u goodvideo_user -p \
  --single-transaction \
  --routines \
  --triggers \
  --add-drop-table \
  goodvideo_archive > backup_$(date +%Y%m%d_%H%M%S).sql
```

**参数说明**：
- `--single-transaction`：保证数据一致性（InnoDB表）
- `--routines`：导出存储过程和函数
- `--triggers`：导出触发器
- `--add-drop-table`：在CREATE TABLE前添加DROP TABLE

### 步骤 2：上传备份文件到服务器

**方法1：使用 SCP**

```bash
# 在本地执行
scp backup.sql username@your-server-ip:~/
```

**方法2：使用 SFTP 工具**

使用 FileZilla、WinSCP 等工具上传 `backup.sql` 到服务器。

### 步骤 3：在服务器上导入数据库

```bash
# SSH 连接到服务器
ssh username@your-server-ip

# 导入数据库
mysql -u goodvideo_user -p goodvideo_archive < backup.sql
```

或者使用 root 用户导入：

```bash
sudo mysql -u root -p goodvideo_archive < backup.sql
```

## 方案 2：只迁移数据（表结构已存在）

如果云服务器上已经创建了表结构，只需要迁移数据：

### 步骤 1：导出数据（不包含表结构）

```bash
# 在本地执行
mysqldump -u goodvideo_user -p \
  --no-create-info \
  --skip-triggers \
  goodvideo_archive > data_only.sql
```

### 步骤 2：上传并导入

```bash
# 上传到服务器（同上）
scp data_only.sql username@your-server-ip:~/

# 在服务器上导入
mysql -u goodvideo_user -p goodvideo_archive < data_only.sql
```

## 方案 3：只迁移特定表

如果只需要迁移部分表（如历史记录）：

### 步骤 1：导出特定表

```bash
# 导出 history_records 表
mysqldump -u goodvideo_user -p \
  goodvideo_archive history_records > history_records.sql

# 导出多个表
mysqldump -u goodvideo_user -p \
  goodvideo_archive history_records history_common_records > history_tables.sql
```

### 步骤 2：上传并导入

```bash
# 上传
scp history_tables.sql username@your-server-ip:~/

# 导入
mysql -u goodvideo_user -p goodvideo_archive < history_tables.sql
```

## 方案 4：使用压缩传输（大数据量推荐）

如果数据量很大，使用压缩可以加快传输速度：

### 步骤 1：导出并压缩

```bash
# 在本地执行
mysqldump -u goodvideo_user -p goodvideo_archive | gzip > backup.sql.gz
```

### 步骤 2：上传压缩文件

```bash
# 上传压缩文件
scp backup.sql.gz username@your-server-ip:~/
```

### 步骤 3：解压并导入

```bash
# 在服务器上执行
gunzip < backup.sql.gz | mysql -u goodvideo_user -p goodvideo_archive
```

## 方案 5：直接通过管道传输（无需中间文件）

如果网络稳定，可以直接通过管道传输：

```bash
# 在本地执行（需要配置SSH密钥认证）
mysqldump -u goodvideo_user -p goodvideo_archive | \
  ssh username@your-server-ip \
  "mysql -u goodvideo_user -p goodvideo_archive"
```

## 迁移脚本

我创建了一个自动化迁移脚本，可以简化流程。

### 使用迁移脚本

**在本地执行**：

```bash
# 1. 编辑脚本，配置服务器信息
nano migrate_to_server.sh

# 2. 执行脚本
chmod +x migrate_to_server.sh
./migrate_to_server.sh
```

## 迁移前检查清单

### 1. 确认本地数据库信息

```bash
# 查看数据库大小
mysql -u goodvideo_user -p -e "SELECT table_schema AS 'Database', 
  ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)' 
  FROM information_schema.tables 
  WHERE table_schema = 'goodvideo_archive';"

# 查看表列表
mysql -u goodvideo_user -p -e "SHOW TABLES FROM goodvideo_archive;"

# 查看记录数
mysql -u goodvideo_user -p -e "SELECT 
  (SELECT COUNT(*) FROM goodvideo_archive.history_records) AS history_records,
  (SELECT COUNT(*) FROM goodvideo_archive.history_common_records) AS history_common_records;"
```

### 2. 确认服务器数据库信息

```bash
# 在服务器上执行
mysql -u goodvideo_user -p -e "SHOW DATABASES LIKE 'goodvideo_archive';"
mysql -u goodvideo_user -p -e "SHOW TABLES FROM goodvideo_archive;"
```

### 3. 备份服务器现有数据（如果重要）

```bash
# 在服务器上执行
mysqldump -u goodvideo_user -p goodvideo_archive > server_backup_$(date +%Y%m%d_%H%M%S).sql
```

## 常见问题

### Q1: 导入时出现外键约束错误？

**解决方案**：临时禁用外键检查

```bash
mysql -u goodvideo_user -p goodvideo_archive << EOF
SET FOREIGN_KEY_CHECKS=0;
SOURCE backup.sql;
SET FOREIGN_KEY_CHECKS=1;
EOF
```

### Q2: 导入时出现字符集错误？

**解决方案**：指定字符集

```bash
mysql -u goodvideo_user -p \
  --default-character-set=utf8mb4 \
  goodvideo_archive < backup.sql
```

### Q3: 数据量很大，导入很慢？

**解决方案**：
1. 使用压缩传输（方案4）
2. 分批导入
3. 临时禁用索引，导入后再重建

```bash
# 导出时禁用索引
mysqldump -u goodvideo_user -p \
  --disable-keys \
  goodvideo_archive > backup.sql
```

### Q4: 如何验证迁移是否成功？

```bash
# 在服务器上执行
# 1. 检查表数量
mysql -u goodvideo_user -p -e "SELECT COUNT(*) AS table_count FROM information_schema.tables WHERE table_schema = 'goodvideo_archive';"

# 2. 检查记录数
mysql -u goodvideo_user -p -e "SELECT 
  (SELECT COUNT(*) FROM goodvideo_archive.history_records) AS history_records,
  (SELECT COUNT(*) FROM goodvideo_archive.history_common_records) AS history_common_records;"

# 3. 检查数据示例
mysql -u goodvideo_user -p -e "SELECT * FROM goodvideo_archive.history_records LIMIT 5;"
```

## 迁移后操作

### 1. 验证应用功能

```bash
# 重启应用
pm2 restart goodvideosearch

# 查看日志
pm2 logs goodvideosearch

# 访问应用，测试功能
```

### 2. 同步文件（如果需要）

如果 `data/covers` 目录中有封面图片，也需要迁移：

```bash
# 在本地打包
tar -czf covers.tar.gz data/covers/

# 上传到服务器
scp covers.tar.gz username@your-server-ip:~/

# 在服务器上解压
cd ~/GoodVideoSearch
tar -xzf ~/covers.tar.gz
```

## 快速迁移命令（一键执行）

**在本地执行**（需要配置SSH密钥）：

```bash
#!/bin/bash
# 快速迁移脚本

LOCAL_DB_USER="goodvideo_user"
LOCAL_DB_NAME="goodvideo_archive"
REMOTE_USER="ubuntu"
REMOTE_HOST="your-server-ip"
REMOTE_DB_USER="goodvideo_user"
REMOTE_DB_NAME="goodvideo_archive"

echo "开始导出数据库..."
mysqldump -u $LOCAL_DB_USER -p \
  --single-transaction \
  --routines \
  --triggers \
  $LOCAL_DB_NAME > /tmp/backup.sql

echo "上传到服务器..."
scp /tmp/backup.sql $REMOTE_USER@$REMOTE_HOST:~/

echo "导入到服务器数据库..."
ssh $REMOTE_USER@$REMOTE_HOST \
  "mysql -u $REMOTE_DB_USER -p $REMOTE_DB_NAME < ~/backup.sql"

echo "清理临时文件..."
rm /tmp/backup.sql
ssh $REMOTE_USER@$REMOTE_HOST "rm ~/backup.sql"

echo "迁移完成！"
```

## 总结

1. **推荐方案**：使用 `mysqldump` 完整导出导入（方案1）
2. **大数据量**：使用压缩传输（方案4）
3. **部分迁移**：只导出需要的表（方案3）
4. **迁移前**：备份服务器现有数据
5. **迁移后**：验证数据完整性和应用功能

