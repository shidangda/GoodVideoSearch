# 迁移脚本故障排除指南

## 问题：Cover directory not found in archive

### 原因分析

**根本原因：** PowerShell 的 `Compress-Archive` 在使用管道输入文件列表时，**不会保留目录结构**。

**问题代码（已修复）：**
```powershell
# ❌ 错误方式：丢失目录结构
Get-ChildItem -Path $workDir -File -Recurse | Compress-Archive -DestinationPath $archivePath
```

**修复后：**
```powershell
# ✅ 正确方式：保留目录结构
Push-Location $workDir
Compress-Archive -Path * -DestinationPath $archivePath -Force
Pop-Location
```

### 验证修复

#### 1. 重新备份（Windows）

```powershell
# 删除旧的备份文件
Remove-Item backups\gvs-backup-*.zip

# 重新备份
.\scripts\export-data.ps1
```

#### 2. 检查 ZIP 文件内容（Windows）

```powershell
# 查看 ZIP 文件内容
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead("backups\gvs-backup-最新.zip")
$zip.Entries | Select-Object FullName | Format-Table
$zip.Dispose()
```

**应该看到的结构：**
```
db.sql
manifest.json
data/
  covers/
    cover-xxx.png
    cover-yyy.png
    ...
```

#### 3. 在服务器上测试解压

```bash
# 创建测试目录
mkdir -p /tmp/test-restore
cd /tmp/test-restore

# 解压 ZIP 文件
unzip -q /path/to/gvs-backup-*.zip

# 检查目录结构
find . -type d
find . -type f | head -20

# 应该看到：
# ./db.sql
# ./manifest.json
# ./data/covers/cover-xxx.png
```

### 数据库恢复失败排查

#### 1. 检查 SQL 文件是否存在

```bash
# 解压后检查
unzip -l gvs-backup-*.zip | grep db.sql
```

#### 2. 检查数据库配置

```bash
# 验证 .env 文件
cat .env | grep DB_

# 测试数据库连接
mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASSWORD -e "SELECT 1"
```

#### 3. 检查数据库是否存在

```bash
# 检查数据库
mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASSWORD -e "SHOW DATABASES LIKE '$DB_NAME'"
```

#### 4. 手动测试 SQL 导入

```bash
# 解压文件
TEMP_DIR=$(mktemp -d)
unzip -q gvs-backup-*.zip -d $TEMP_DIR

# 检查 SQL 文件
ls -lh $TEMP_DIR/db.sql

# 手动导入（替换变量）
mysql -h 127.0.0.1 -P 3306 -u goodvideo_user -p'your_password' goodvideo_archive < $TEMP_DIR/db.sql

# 清理
rm -rf $TEMP_DIR
```

### 常见错误及解决方案

#### 错误 1: "Cover directory not found in archive"

**原因：** ZIP 文件中的目录结构丢失

**解决：**
1. 使用修复后的 `export-data.ps1` 重新备份
2. 验证 ZIP 文件包含 `data/covers/` 目录

#### 错误 2: "Database restore failed"

**可能原因：**
- 数据库不存在
- 用户权限不足
- SQL 文件损坏
- 数据库连接失败

**排查步骤：**
```bash
# 1. 检查数据库是否存在
mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD -e "SHOW DATABASES"

# 2. 检查用户权限
mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD -e "SHOW GRANTS"

# 3. 检查 SQL 文件
head -20 $TEMP_DIR/db.sql

# 4. 测试连接
mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASSWORD -e "SELECT 1"
```

#### 错误 3: "mysql not found"

**解决：**
```bash
# Ubuntu/Debian
sudo apt-get install mysql-client

# CentOS/RHEL
sudo yum install mysql
```

#### 错误 4: "unzip not found"

**解决：**
```bash
# Ubuntu/Debian
sudo apt-get install unzip

# CentOS/RHEL
sudo yum install unzip
```

### 调试模式

运行恢复脚本时，现在会输出调试信息：

```bash
bash scripts/import_data.sh backup.zip
```

**调试输出包括：**
- 解压后的目录结构
- 查找封面目录的路径
- 数据库恢复的详细错误信息

### 验证恢复成功

#### 1. 检查数据库

```bash
mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME -e "SELECT COUNT(*) FROM history_records"
```

#### 2. 检查封面文件

```bash
ls -lh data/covers/ | wc -l
ls -lh data/covers/ | head -10
```

#### 3. 检查应用

访问应用页面，查看历史记录和封面是否正常显示。

### 完整测试流程

```bash
# 1. 在 Windows 上备份
.\scripts\export-data.ps1

# 2. 上传到服务器
scp backups/gvs-backup-*.zip user@server:/home/user/

# 3. 在服务器上恢复
cd ~/GoodVideoSearch
bash scripts/import_data.sh ~/gvs-backup-*.zip

# 4. 验证
mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME -e "SELECT COUNT(*) FROM history_records"
ls -lh data/covers/ | wc -l
```

### 如果问题仍然存在

1. **检查 ZIP 文件内容：
   ```bash
   unzip -l gvs-backup-*.zip
   ```

2. **手动解压并检查结构**：
   ```bash
   mkdir test
   cd test
   unzip ../gvs-backup-*.zip
   find . -type d
   find . -type f
   ```

3. **查看详细错误日志**：
   - 运行脚本时不要重定向错误输出
   - 检查数据库连接日志
   - 检查文件权限

4. **联系支持**：
   - 提供完整的错误信息
   - 提供 ZIP 文件内容列表
   - 提供 .env 配置（隐藏密码）

