# GoodVideoSearch 数据恢复脚本 (Windows PowerShell)
# 功能：从压缩包恢复数据库和封面图片（含 db.sql 自动修复与重试）
# 用法: .\scripts\import-data.ps1 <archive.zip>

param(
    [Parameter(Mandatory=$true)]
    [string]$Archive
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# 实用函数 --------------------------------------------------------------
function Get-EnvValue {
    param([string]$Key, [string]$EnvPath)
    $line = Get-Content $EnvPath | Where-Object { $_ -match "^$Key=" }
    if ($line) { return ($line -replace "^$Key=", "").Trim() }
    return $null
}

function Remove-Bom {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
        [System.IO.File]::WriteAllBytes($Path, $bytes[3..($bytes.Length-1)])
    }
}

function Normalize-DbSql {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    # 去 BOM（再次确保）
    Remove-Bom -Path $Path
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    # 统一换行
    $text = $text -replace "`r`n", "`n"
    $text = $text -replace "`r", "`n"
    $lines = $text -split "`n", -1
    for ($i=0; $i -lt $lines.Length; $i++) {
        $l = $lines[$i]
        if ($l -match '^\s*".*"\s*$') {
            $l = $l -replace '^\s*"', ''
            $l = $l -replace '"\s*$', ''
        }
        # 去掉行首/行尾转义引号序列 \" 或 "
        $l = $l -replace '^\s*(\\+\")+\s*', ''
        $l = $l -replace '\s*(\\+\")+\s*$', ''
        # 句级："...;" → ...;
        $l = $l -replace '^\s*"(.*;)\s*"\s*$', '$1'
        # 尾部多余引号：;" → ;
        $l = $l -replace ';\s*"\s*$', ';'
        $lines[$i] = $l
    }
    $new = [string]::Join("`n", $lines)
    [System.IO.File]::WriteAllText($Path, $new, $utf8NoBom)
}

function Aggressive-Normalize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    $text = $text -replace "`r`n", "`n"
    $text = $text -replace "`r", "`n"
    $lines = $text -split "`n", -1
    for ($i=0; $i -lt $lines.Length; $i++) {
        $l = $lines[$i]
        # 更激进：移除行首/行尾所有引号与转义引号
        $l = $l -replace '^\s*(\"+|"+)+\s*', ''
        $l = $l -replace '\s*(\"+|"+)+\s*$', ''
        # 仍保留分号
        $l = $l -replace ';\s*(\"+|"+)+\s*$', ';'
        $lines[$i] = $l
    }
    $new = [string]::Join("`n", $lines)
    [System.IO.File]::WriteAllText($Path, $new, $utf8NoBom)
}

# 归档校验 --------------------------------------------------------------
if (-not (Test-Path $Archive)) {
    Write-Host "[ERROR] Archive file not found: $Archive" -ForegroundColor Red
    exit 1
}

# 项目与 .env ------------------------------------------------------------
$ProjectDir = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { $PWD }
$envPath = Join-Path $ProjectDir ".env"
if (-not (Test-Path $envPath)) {
    Write-Host "[ERROR] .env file not found at: $envPath" -ForegroundColor Red
    exit 1
}

$DB_HOST = Get-EnvValue "DB_HOST" $envPath
$DB_PORT = Get-EnvValue "DB_PORT" $envPath
$DB_NAME = Get-EnvValue "DB_NAME" $envPath
$DB_USER = Get-EnvValue "DB_USER" $envPath
$DB_PASSWORD = Get-EnvValue "DB_PASSWORD" $envPath

if (-not $DB_HOST -or -not $DB_PORT -or -not $DB_NAME -or -not $DB_USER -or -not $DB_PASSWORD) {
    Write-Host "[ERROR] Missing database configuration in .env" -ForegroundColor Red
    exit 1
}

# 检查 mysql -------------------------------------------------------------
$mysql = Get-Command mysql -ErrorAction SilentlyContinue
if (-not $mysql) {
    Write-Host "[ERROR] mysql not found. Please ensure MySQL client tools are installed and in PATH." -ForegroundColor Red
    exit 1
}

# 解压 ------------------------------------------------------------------
$tempDir = Join-Path $ProjectDir "restore-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

try {
    Write-Host "[INFO] Extracting archive..." -ForegroundColor Cyan
    if ($Archive -match '\.tar\.gz$|\.tgz$') {
        Write-Host "[ERROR] PowerShell's Expand-Archive does not support .tar.gz files." -ForegroundColor Red
        Write-Host "Use WSL/Git Bash: bash scripts/import_data.sh <archive>" -ForegroundColor Yellow
        exit 1
    } elseif ($Archive -match '\.zip$') {
        Expand-Archive -Path $Archive -DestinationPath $tempDir -Force
    } else {
        Write-Host "[ERROR] Unsupported archive format. Please use .zip files." -ForegroundColor Red
        exit 1
    }

    # 恢复数据库 --------------------------------------------------------
    $dbFile = Join-Path $tempDir "db.sql"
    if (Test-Path $dbFile) {
        Write-Host "[INFO] Checking db.sql format..." -ForegroundColor Cyan
        Remove-Bom -Path $dbFile
        Normalize-DbSql -Path $dbFile

        Write-Host "[INFO] Restoring database..." -ForegroundColor Cyan
        Write-Host "  Database: ${DB_NAME}@${DB_HOST}:${DB_PORT}" -ForegroundColor Gray

        # 临时 MySQL 配置
        $mysqlConfigFile = Join-Path $tempDir ".my.cnf"
        $configContent = @"
[client]
host=$DB_HOST
port=$DB_PORT
user=$DB_USER
password=$DB_PASSWORD
"@
        [System.IO.File]::WriteAllText($mysqlConfigFile, $configContent.Replace("`r`n", "`n"), [System.Text.Encoding]::ASCII)

        # 使用 Start-Process 进行标准输入重定向更稳定
        $stdOut = Join-Path $tempDir "mysql.out"
        $stdErr = Join-Path $tempDir "mysql.err"
        try {
            $p = Start-Process -FilePath "mysql" -ArgumentList "--defaults-file=$mysqlConfigFile", $DB_NAME `
                -RedirectStandardInput $dbFile -RedirectStandardOutput $stdOut -RedirectStandardError $stdErr `
                -NoNewWindow -Wait -PassThru
            $exitCode = $p.ExitCode
            $errText = if (Test-Path $stdErr) { Get-Content $stdErr -Raw } else { "" }

            if ($exitCode -ne 0 -and ($errText -match 'Unknown command.*\"')) {
                Write-Host "[WARN] Unknown command '"' detected; applying aggressive fix and retry..." -ForegroundColor Yellow
                Aggressive-Normalize -Path $dbFile
                $p = Start-Process -FilePath "mysql" -ArgumentList "--defaults-file=$mysqlConfigFile", $DB_NAME `
                    -RedirectStandardInput $dbFile -RedirectStandardOutput $stdOut -RedirectStandardError $stdErr `
                    -NoNewWindow -Wait -PassThru
                $exitCode = $p.ExitCode
                $errText = if (Test-Path $stdErr) { Get-Content $stdErr -Raw } else { "" }
            }

            if ($exitCode -eq 0) {
                Write-Host "[OK] Database restored successfully" -ForegroundColor Green
            } else {
                Write-Host "[ERROR] Database restore failed (exit code: $exitCode)" -ForegroundColor Red
                if ($errText) { Write-Host $errText -ForegroundColor Red }
                # 打印 40..70 行辅助诊断
                try {
                    $lines = Get-Content -LiteralPath $dbFile
                    $start = [Math]::Max(0, 39)
                    $end = [Math]::Min($lines.Count-1, 69)
                    Write-Host "[DEBUG] db.sql lines 40..70:" -ForegroundColor Yellow
                    for ($i=$start; $i -le $end; $i++) { '{0,5}: {1}' -f ($i+1), $lines[$i] | Write-Host }
                } catch {}
                exit 1
            }
        } finally {
            if (Test-Path $mysqlConfigFile) { Remove-Item -Force $mysqlConfigFile }
            if (Test-Path $stdOut) { Remove-Item -Force $stdOut }
            if (Test-Path $stdErr) { Remove-Item -Force $stdErr }
        }
    } else {
        Write-Host "[WARN] db.sql not found in archive" -ForegroundColor Yellow
    }

    # 恢复封面图片 ------------------------------------------------------
    $coversSrc = Join-Path $tempDir (Join-Path "data" "covers")
    if (-not (Test-Path $coversSrc)) { $coversSrc = Join-Path $tempDir "data\covers" }
    if (Test-Path $coversSrc) {
        $coversDst = Join-Path $ProjectDir (Join-Path "data" "covers")
        New-Item -ItemType Directory -Force -Path $coversDst | Out-Null
        $copied = 0; $skipped = 0
        Get-ChildItem $coversSrc -File -ErrorAction SilentlyContinue | ForEach-Object {
            $dest = Join-Path $coversDst $_.Name
            if (-not (Test-Path $dest)) { Copy-Item $_.FullName $dest; $copied++ } else { $skipped++ }
        }
        Write-Host "[OK] Cover images restored: $copied new, $skipped skipped" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Cover directory not found in archive" -ForegroundColor Yellow
    }

    Write-Host ""; Write-Host "[DONE] Restore completed successfully!" -ForegroundColor Green
}
finally {
    if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
}
