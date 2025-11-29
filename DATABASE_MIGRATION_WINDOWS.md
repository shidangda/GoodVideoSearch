# Windows 数据库迁移指南

将 Windows 系统上的 MySQL 数据库迁移到云服务器的完整指南。

## 前置要求

### 1. 安装 MySQL 客户端工具

下载并安装 MySQL 客户端，包含 `mysqldump` 命令：

**下载地址**：
- https://dev.mysql.com/downloads/mysql/
- 或下载 MySQL Workbench（包含客户端工具）

**验证安装**：
```cmd
mysqldump --version
mysql --version
```

### 2. 安装 SSH 客户端（可选）

**选项 1：Windows 10/11 自带 OpenSSH**
- Windows 10 1809+ 和 Windows 11 自带
- 在"设置" → "应用" → "可选功能"中启用

**选项 2：安装 Git for Windows**
- 包含 Git Bash，可以使用 SSH 命令
- 下载：https://git-scm.com/download/win

**选项 3：使用 WinSCP 或 FileZilla**
- 图形化工具，更易使用
- WinSCP: https://winscp.net/
- FileZilla: https://filezilla-project.org/

## 方法 1：使用批处理脚本（推荐）

### 步骤 1：编辑脚本配置

编辑 `migrate_to_server_windows.bat`，修改以下配置：

```batch
set REMOTE_USER=ubuntu
set REMOTE_HOST=106.52.243.103
set REMOTE_DB_USER=goodvideo_user
set REMOTE_DB_NAME=goodvideo_archive
```

### 步骤 2：执行脚本

双击 `migrate_to_server_windows.bat` 或在 CMD 中执行：

```cmd
migrate_to_server_windows.bat
```

脚本会自动：
- 导出本地数据库
- 上传到服务器（如果配置了 SCP）
- 导入到服务器数据库
- 迁移封面图片（可选）

## 方法 2：手动迁移（分步执行）

### 步骤 1：在 Windows 上导出数据库

打开 **命令提示符（CMD）** 或 **PowerShell**：

```cmd
cd D:\pythonProject\GoodVideoSearch

mysqldump -u goodvideo_user -p ^
  --single-transaction ^
  --routines ^
  --triggers ^
  --add-drop-table ^
  goodvideo_archive > backup.sql
```

**注意**：
- `^` 是 CMD 的换行符
- 在 PowerShell 中使用 `` ` `` 作为换行符

### 步骤 2：上传备份文件到服务器

**方法 A：使用 SCP（如果已安装 OpenSSH）**

```cmd
scp backup.sql ubuntu@106.52.243.103:~/
```

**方法 B：使用 WinSCP（图形化工具）**

1. 打开 WinSCP
2. 连接到服务器：`ubuntu@106.52.243.103`
3. 拖拽 `backup.sql` 到服务器

**方法 C：使用 FileZilla**

1. 打开 FileZilla
2. 连接到服务器（SFTP）
3. 上传 `backup.sql`

### 步骤 3：在服务器上导入数据库

**方法 A：使用 SSH 命令**

```cmd
ssh ubuntu@106.52.243.103
```

然后在服务器上执行：

```bash
mysql -u goodvideo_user -p goodvideo_archive < backup.sql
```

**方法 B：使用 PuTTY 或 MobaXterm**

1. 使用 SSH 客户端连接到服务器
2. 执行导入命令

## 方法 3：使用 Git Bash（推荐，跨平台）

如果安装了 Git for Windows，可以使用 Git Bash：

### 步骤 1：打开 Git Bash

在项目目录右键 → "Git Bash Here"

### 步骤 2：执行迁移命令

```bash
# 导出数据库
mysqldump -u goodvideo_user -p \
  --single-transaction \
  --routines \
  --triggers \
  goodvideo_archive > backup.sql

# 上传到服务器
scp backup.sql ubuntu@106.52.243.103:~/

# 在服务器上导入（需要先 SSH 连接）
ssh ubuntu@106.52.243.103
mysql -u goodvideo_user -p goodvideo_archive < backup.sql
```

## 方法 4：使用 MySQL Workbench（图形化）

### 步骤 1：导出数据

1. 打开 MySQL Workbench
2. 连接到本地数据库
3. 菜单：Server → Data Export
4. 选择数据库和表
5. 选择导出选项
6. 点击 "Start Export"

### 步骤 2：上传并导入

1. 使用 WinSCP 上传 SQL 文件
2. 在服务器上使用 `mysql` 命令导入

## 迁移封面图片

### 使用 WinRAR 或 7-Zip

```cmd
REM 打包封面目录
"C:\Program Files\WinRAR\WinRAR.exe" a -afzip covers.zip data\covers\

REM 或使用 7-Zip
7z a -tzip covers.zip data\covers\
```

然后使用 WinSCP 上传 `covers.zip` 到服务器。

## 常见问题

### Q1: 找不到 mysqldump 命令？

**解决方案**：
1. 安装 MySQL 客户端工具
2. 或将 MySQL bin 目录添加到 PATH 环境变量：
   ```
   C:\Program Files\MySQL\MySQL Server 8.0\bin
   ```

### Q2: 找不到 scp 命令？

**解决方案**：
1. 安装 OpenSSH 客户端（Windows 10/11）
2. 或使用 WinSCP/FileZilla 图形化工具
3. 或使用 Git Bash

### Q3: 路径中包含空格？

**解决方案**：使用引号包裹路径

```cmd
mysqldump -u goodvideo_user -p "goodvideo archive" > backup.sql
```

### Q4: 字符编码问题？

**解决方案**：指定字符集

```cmd
mysqldump -u goodvideo_user -p ^
  --default-character-set=utf8mb4 ^
  goodvideo_archive > backup.sql
```

## 快速命令参考

### 导出数据库
```cmd
mysqldump -u goodvideo_user -p goodvideo_archive > backup.sql
```

### 上传文件（使用 SCP）
```cmd
scp backup.sql ubuntu@106.52.243.103:~/
```

### 上传文件（使用 WinSCP）
- 图形化操作，更简单

### 在服务器上导入
```bash
mysql -u goodvideo_user -p goodvideo_archive < backup.sql
```

## 推荐方案

1. **最简单**：使用 WinSCP 手动上传 + 服务器上导入
2. **自动化**：使用批处理脚本 `migrate_to_server_windows.bat`
3. **跨平台**：使用 Git Bash 执行 Linux 风格的命令

## 总结

- Windows 上可以使用批处理脚本或手动执行
- 需要安装 MySQL 客户端工具（mysqldump）
- 推荐使用 WinSCP 进行文件传输（图形化，更简单）
- 或者使用 Git Bash 执行跨平台命令





