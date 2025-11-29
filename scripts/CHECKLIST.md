# 迁移脚本检查清单

## ✅ 已修复的问题

### 1. 安全性改进
- ✅ **密码安全**：所有脚本现在使用 MySQL 配置文件（`.my.cnf`）而不是在命令行中暴露密码
- ✅ **文件权限**：配置文件设置为 600 权限（仅所有者可读写）

### 2. PowerShell 脚本修复
- ✅ **变量引用**：修复了 `$DB_NAME@$DB_HOST:$DB_PORT` 的变量边界问题，使用 `${}` 明确变量名
- ✅ **数据库导出**：使用 `--defaults-file` 参数替代命令行密码
- ✅ **文件复制**：改进了封面图片复制逻辑，避免空目录错误
- ✅ **压缩方式**：修复了 `Compress-Archive` 的路径问题
- ✅ **大文件处理**：使用 `-Raw` 参数处理大 SQL 文件

### 3. Bash 脚本修复
- ✅ **密码安全**：使用 MySQL 配置文件替代命令行密码
- ✅ **跨平台支持**：`import_data.sh` 现在支持 `.zip` 和 `.tar.gz` 两种格式
- ✅ **文件统计**：改进了封面图片恢复的统计逻辑，移除了不准确的 rsync 统计
- ✅ **兼容性**：改进了 `find` 命令的使用，增加了兼容性处理

### 4. 错误处理
- ✅ **异常捕获**：所有脚本都添加了 try-catch 或错误检查
- ✅ **清理逻辑**：确保临时文件和目录在出错时也能被清理
- ✅ **退出码**：所有脚本在失败时返回正确的退出码

## 📋 功能验证清单

### Windows PowerShell 备份 (`export-data.ps1`)
- [ ] 能够读取 `.env` 文件
- [ ] 能够执行 `mysqldump` 命令
- [ ] 能够复制封面图片目录
- [ ] 能够创建 ZIP 压缩包
- [ ] 生成的压缩包包含 `db.sql` 和 `data/covers/` 目录
- [ ] 临时文件被正确清理

### Windows PowerShell 恢复 (`import-data.ps1`)
- [ ] 能够解压 ZIP 文件
- [ ] 能够执行 `mysql` 命令导入数据库
- [ ] 能够合并封面图片（不覆盖已存在的）
- [ ] 临时文件被正确清理

### Linux/macOS Bash 备份 (`export_data.sh`)
- [ ] 能够读取 `.env` 文件
- [ ] 能够执行 `mysqldump` 命令
- [ ] 能够复制封面图片目录
- [ ] 能够创建 tar.gz 压缩包
- [ ] 生成的压缩包包含 `db.sql` 和 `data/covers/` 目录
- [ ] 临时文件被正确清理

### Linux/macOS Bash 恢复 (`import_data.sh`)
- [ ] 能够解压 tar.gz 和 zip 文件
- [ ] 能够执行 `mysql` 命令导入数据库
- [ ] 能够合并封面图片（不覆盖已存在的）
- [ ] 临时文件被正确清理

## 🔄 跨平台迁移流程

### 从 Windows 到 Ubuntu

1. **在 Windows 上备份**
   ```powershell
   cd D:\pythonProject\GoodVideoSearch
   .\scripts\export-data.ps1
   ```
   - 生成：`backups\gvs-backup-YYYYMMDD-HHMMSS.zip`

2. **上传到服务器**
   ```bash
   scp backups/gvs-backup-*.zip user@server:/home/user/
   ```

3. **在 Ubuntu 上恢复**
   ```bash
   cd ~/GoodVideoSearch
   bash scripts/import_data.sh ~/gvs-backup-*.zip
   ```
   - 脚本会自动检测 zip 格式并使用 `unzip` 解压

### 从 Ubuntu 到 Windows

1. **在 Ubuntu 上备份**
   ```bash
   cd ~/GoodVideoSearch
   bash scripts/export_data.sh
   ```
   - 生成：`backups/gvs-backup-YYYYMMDD-HHMMSS.tar.gz`

2. **上传到 Windows**
   - 使用 SCP、FTP 或其他工具

3. **在 Windows 上恢复**
   ```powershell
   cd D:\pythonProject\GoodVideoSearch
   .\scripts\import-data.ps1 backups\gvs-backup-*.tar.gz
   ```
   - 注意：PowerShell 的 `Expand-Archive` 可能不支持 tar.gz，需要先转换为 zip 或使用第三方工具

## ⚠️ 注意事项

1. **MySQL 客户端工具**：确保已安装并添加到 PATH
   - Windows: MySQL Client Tools
   - Ubuntu: `sudo apt-get install mysql-client`

2. **解压工具**：Ubuntu 上需要 `unzip` 来解压 Windows 生成的 zip 文件
   ```bash
   sudo apt-get install unzip
   ```

3. **文件权限**：确保脚本有执行权限（Linux/macOS）
   ```bash
   chmod +x scripts/*.sh
   ```

4. **数据库连接**：确保目标服务器的 `.env` 文件已正确配置

5. **数据覆盖**：恢复操作会**覆盖**现有数据库数据，请谨慎操作

6. **封面图片**：恢复时不会覆盖已存在的封面文件，只会添加新文件

## 🧪 测试建议

1. **在测试环境先验证**
2. **备份前先备份现有数据**
3. **检查生成的压缩包内容**
4. **验证数据库导入是否成功**
5. **检查封面图片是否完整**

