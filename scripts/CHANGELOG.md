# 迁移脚本更新日志

## 2024-11-30 - 跨平台兼容性修复

### 🔧 修复的问题

#### 1. 路径分隔符兼容性
- **问题**：PowerShell 脚本中硬编码了反斜杠 `\`，导致跨平台问题
- **修复**：
  - 所有路径操作使用 `Join-Path` 替代硬编码反斜杠
  - ZIP 文件使用 .NET ZipFile 类确保所有路径使用正斜杠（`/`）
  - 解压脚本自动处理路径分隔符警告

#### 2. ZIP 文件路径分隔符
- **问题**：PowerShell 的 `Compress-Archive` 使用反斜杠，Linux `unzip` 报错
- **修复**：
  - 改用 .NET `ZipFile` 类创建 ZIP 文件
  - 确保所有路径使用正斜杠（`/`）
  - 解压脚本自动忽略路径分隔符警告

#### 3. 文件编码兼容性
- **问题**：SQL 文件编码可能导致跨平台问题
- **修复**：
  - SQL 文件使用 UTF-8 无 BOM 编码
  - MySQL 配置文件使用 ASCII + Unix 换行符（LF）
  - 清单文件使用 UTF-8 编码

#### 4. 目录结构丢失
- **问题**：使用管道传递文件列表导致目录结构丢失
- **修复**：
  - 使用 .NET ZipFile 类直接添加文件，保留完整目录结构
  - 确保 `data/covers/` 目录结构正确

#### 5. 错误处理改进
- **问题**：错误信息不够详细
- **修复**：
  - 添加详细的错误提示
  - 改进数据库恢复失败时的诊断信息
  - 添加调试输出（可选）

### 📝 文件变更

#### `scripts/export-data.ps1`
- ✅ 修复路径分隔符（使用 `Join-Path`）
- ✅ 修复 ZIP 压缩方式（使用 .NET ZipFile）
- ✅ 改进 SQL 文件编码（UTF-8 无 BOM）
- ✅ 改进错误处理

#### `scripts/import-data.ps1`
- ✅ 修复路径分隔符（使用 `Join-Path`）
- ✅ 添加路径兼容性检查（支持旧备份）
- ✅ 改进错误处理

#### `scripts/import_data.sh`
- ✅ 添加路径分隔符警告过滤
- ✅ 添加调试输出
- ✅ 改进错误处理
- ✅ 改进数据库恢复失败提示

### 🧪 测试建议

1. **Windows → Linux 迁移**
   ```powershell
   # Windows 备份
   .\scripts\export-data.ps1
   ```
   ```bash
   # Linux 恢复
   bash scripts/import_data.sh backups/gvs-backup-*.zip
   ```

2. **验证 ZIP 文件结构**
   ```powershell
   # Windows 上检查
   Add-Type -AssemblyName System.IO.Compression.FileSystem
   $zip = [System.IO.Compression.ZipFile]::OpenRead("backups\gvs-backup-*.zip")
   $zip.Entries | Select-Object FullName
   $zip.Dispose()
   ```

3. **验证文件编码**
   ```bash
   # Linux 上检查
   file backups/gvs-backup-*.zip
   unzip -l backups/gvs-backup-*.zip | head -20
   ```

### ⚠️ 已知限制

1. **tar.gz 在 Windows PowerShell**
   - PowerShell 的 `Expand-Archive` 不支持 tar.gz
   - **解决方案**：使用 WSL 或 Git Bash 运行 Bash 脚本

2. **旧备份文件**
   - 使用旧版本脚本创建的备份可能使用反斜杠
   - **解决方案**：使用新脚本重新备份，或忽略警告（不影响使用）

### 📚 相关文档

- `CROSS_PLATFORM_CHECK.md` - 跨平台兼容性检查清单
- `TROUBLESHOOTING.md` - 故障排除指南
- `README.md` - 使用说明

