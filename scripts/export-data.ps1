# GoodVideoSearch 数据备份脚本 (Windows PowerShell)
# 功能：导出数据库和封面图片到压缩包
# 用法: .\scripts\export-data.ps1 [-OutDir <输出目录>] 或 .\scripts\export-data.ps1 --out <输出目录>

param(
    [string]$OutDir = ""
)

# 解析 --out 参数（兼容性处理，支持 --out 格式）
# PowerShell 会把 --out 当作位置参数绑定到 $OutDir，实际值在 $args[0]
if ($OutDir -eq '--out' -and $args.Count -gt 0) {
    $OutDir = $args[0]
} elseif ([string]::IsNullOrEmpty($OutDir) -and $args.Count -ge 2) {
    # 如果 $OutDir 为空，尝试从 $args 中查找 --out
    for ($i = 0; $i -lt ($args.Count - 1); $i++) {
        if ($args[$i] -eq '--out') {
            $OutDir = $args[$i + 1]
            break
        }
    }
}

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# 获取项目根目录
$ProjectDir = if ($PSScriptRoot) {
    Split-Path -Parent $PSScriptRoot
} else {
    $PWD
}

# 检查 .env 文件
$envPath = Join-Path $ProjectDir ".env"
if (-not (Test-Path $envPath)) {
    Write-Host "[ERROR] .env file not found at: $envPath" -ForegroundColor Red
    exit 1
}

# 读取数据库配置
function Get-EnvValue {
    param([string]$Key)
    $line = Get-Content $envPath | Where-Object { $_ -match "^$Key=" }
    if ($line) {
        return ($line -replace "^$Key=", "").Trim()
    }
    return $null
}

$DB_HOST = Get-EnvValue "DB_HOST"
$DB_PORT = Get-EnvValue "DB_PORT"
$DB_NAME = Get-EnvValue "DB_NAME"
$DB_USER = Get-EnvValue "DB_USER"
$DB_PASSWORD = Get-EnvValue "DB_PASSWORD"

if (-not $DB_HOST -or -not $DB_PORT -or -not $DB_NAME -or -not $DB_USER -or -not $DB_PASSWORD) {
    Write-Host "[ERROR] Missing database configuration in .env" -ForegroundColor Red
    exit 1
}

# 检查 mysqldump
$mysqldump = Get-Command mysqldump -ErrorAction SilentlyContinue
if (-not $mysqldump) {
    Write-Host "[ERROR] mysqldump not found. Please ensure MySQL client tools are installed and in PATH." -ForegroundColor Red
    exit 1
}

# 创建备份目录
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = if ($OutDir) { $OutDir } else { Join-Path $ProjectDir "backups" }
$workDir = Join-Path $ProjectDir "backup-$timestamp"
$archivePath = Join-Path $backupDir "gvs-backup-$timestamp.zip"

New-Item -ItemType Directory -Force -Path $backupDir, $workDir | Out-Null

Write-Host "[INFO] Starting backup..." -ForegroundColor Cyan
Write-Host "  Database: ${DB_NAME}@${DB_HOST}:${DB_PORT}" -ForegroundColor Gray
Write-Host "  Covers: data/covers" -ForegroundColor Gray

# 导出数据库
Write-Host "[INFO] Exporting database..." -ForegroundColor Cyan
$dbFile = Join-Path $workDir "db.sql"

# 使用临时配置文件避免密码暴露在进程列表中
$mysqlConfigFile = Join-Path $workDir ".my.cnf"
$configContent = @"
[client]
host=$DB_HOST
port=$DB_PORT
user=$DB_USER
password=$DB_PASSWORD
"@
# 使用 ASCII 编码并确保 Unix 换行符（LF）
[System.IO.File]::WriteAllText($mysqlConfigFile, $configContent.Replace("`r`n", "`n"), [System.Text.Encoding]::ASCII)

try {
    & mysqldump "--defaults-file=$mysqlConfigFile" `
        --single-transaction --quick --hex-blob $DB_NAME | Out-File -FilePath $dbFile -Encoding utf8 -NoNewline
    
    if ($LASTEXITCODE -ne 0) {
        throw "mysqldump failed with exit code $LASTEXITCODE"
    }
} catch {
    Write-Host "[ERROR] Database export failed: $_" -ForegroundColor Red
    Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue
    exit 1
} finally {
    # 清理配置文件
    if (Test-Path $mysqlConfigFile) {
        Remove-Item -Force $mysqlConfigFile
    }
}

# 复制封面图片
$coversSrc = Join-Path $ProjectDir "data\covers"
if (Test-Path $coversSrc) {
    $coverFiles = Get-ChildItem $coversSrc -File -ErrorAction SilentlyContinue
    if ($coverFiles) {
        Write-Host "[INFO] Copying cover images..." -ForegroundColor Cyan
        $coversDst = Join-Path $workDir "data\covers"
        New-Item -ItemType Directory -Force -Path $coversDst | Out-Null
        Copy-Item -Path $coverFiles.FullName -Destination $coversDst -Force
        $coverCount = $coverFiles.Count
        Write-Host "  Copied $coverCount cover images" -ForegroundColor Gray
    } else {
        Write-Host "[WARN] Cover directory is empty: $coversSrc" -ForegroundColor Yellow
    }
} else {
    Write-Host "[WARN] Cover directory not found: $coversSrc" -ForegroundColor Yellow
}

# 创建清单文件
$manifest = @{
    project = "GoodVideoSearch"
    db = $DB_NAME
    time = $timestamp
    format = "zip"
} | ConvertTo-Json -Compress

$manifest | Out-File -FilePath (Join-Path $workDir "manifest.json") -Encoding utf8

# 压缩
Write-Host "[INFO] Creating archive..." -ForegroundColor Cyan
Get-ChildItem -Path $workDir -File -Recurse | Compress-Archive -DestinationPath $archivePath -Force

# 清理临时目录
Remove-Item -Recurse -Force $workDir

# 显示结果
$fileSize = (Get-Item $archivePath).Length / 1MB
Write-Host "[OK] Backup completed successfully!" -ForegroundColor Green
Write-Host "  Archive: $archivePath" -ForegroundColor Gray
Write-Host "  Size: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Gray
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Upload the archive to your server" -ForegroundColor Gray
Write-Host "  2. Run: bash scripts/import_data.sh <archive>" -ForegroundColor Gray

