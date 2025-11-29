# 数据迁移脚本使用指南

本目录包含跨平台的数据备份和恢复脚本，支持在 Windows 和 Linux/macOS 之间迁移数据。

## 文件说明

- `export-data.ps1` - Windows PowerShell 备份脚本
- `import-data.ps1` - Windows PowerShell 恢复脚本
- `export_data.sh` - Linux/macOS Bash 备份脚本
- `import_data.sh` - Linux/macOS Bash 恢复脚本

## 快速开始

### Windows 备份

```powershell
# 在项目根目录执行
.\scripts\export-data.ps1
```

备份文件将保存在 `backups/gvs-backup-YYYYMMDD-HHMMSS.zip`

### Windows 恢复

```powershell
.\scripts\import-data.ps1 backups\gvs-backup-20240101-120000.zip
```

### Linux/macOS 备份

```bash
bash scripts/export_data.sh
```

备份文件将保存在 `backups/gvs-backup-YYYYMMDD-HHMMSS.tar.gz`

### Linux/macOS 恢复

```bash
bash scripts/import_data.sh backups/gvs-backup-20240101-120000.tar.gz
```

## 迁移流程

### 从 Windows 迁移到 Ubuntu 服务器

1. **在 Windows 上备份**
   ```powershell
   cd D:\pythonProject\GoodVideoSearch
   .\scripts\export-data.ps1
   ```

2. **上传备份文件到服务器**
   ```bash
   # 使用 scp 或其他工具
   scp backups/gvs-backup-*.zip user@server:/home/user/
   ```

3. **在服务器上解压并恢复**
   ```bash
   # 如果是 zip 文件，先解压
   unzip gvs-backup-*.zip
   # 或者转换为 tar.gz（可选）
   
   # 恢复数据
   cd ~/GoodVideoSearch
   bash scripts/import_data.sh ~/gvs-backup-*.tar.gz
   ```

## 注意事项

1. **数据库配置**：确保目标服务器的 `.env` 文件已正确配置
2. **MySQL 客户端**：需要安装 MySQL 客户端工具
3. **文件权限**：Linux/macOS 脚本可能需要执行权限：`chmod +x scripts/*.sh`
4. **数据覆盖**：恢复操作会覆盖现有数据库，请谨慎操作
5. **封面图片**：恢复时不会覆盖已存在的封面文件

## 故障排除

### Windows: "mysqldump not found"
- 确保 MySQL 客户端工具已安装并添加到 PATH
- 或使用完整路径：`C:\Program Files\MySQL\MySQL Server 8.0\bin\mysqldump.exe`

### Linux: "Permission denied"
```bash
chmod +x scripts/export_data.sh scripts/import_data.sh
```

### 数据库连接失败
- 检查 `.env` 文件中的数据库配置
- 确保数据库服务正在运行
- 检查网络连接和防火墙设置

