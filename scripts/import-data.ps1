# GoodVideoSearch 数据恢复脚本 (Windows PowerShell)
# 功能：从压缩包恢复数据库和封面图片
# 用法: .\scripts\import-data.ps1 <archive.zip>

param(
    [Parameter(Mandatory=$true)]
    [string]$Archive
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# 检查归档文件
if (-not (Test-Path $Archive)) {
    Write-Host "[ERROR] Archive file not found: $Archive" -ForegroundColor Red
    exit 1
}

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

# 检查 mysql 命令
$mysql = Get-Command mysql -ErrorAction SilentlyContinue
if (-not $mysql) {
    Write-Host "[ERROR] mysql not found. Please ensure MySQL client tools are installed and in PATH." -ForegroundColor Red
    exit 1
}

# 创建临时解压目录
$tempDir = Join-Path $ProjectDir "restore-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

try {
    Write-Host "[INFO] Extracting archive..." -ForegroundColor Cyan
    
    # 检测文件格式
    if ($Archive -match '\.tar\.gz$|\.tgz$') {
        Write-Host "[ERROR] PowerShell's Expand-Archive does not support .tar.gz files." -ForegroundColor Red
        Write-Host "Please use one of the following options:" -ForegroundColor Yellow
        Write-Host "  1. Use WSL: wsl bash scripts/import_data.sh <archive>" -ForegroundColor Gray
        Write-Host "  2. Use Git Bash: bash scripts/import_data.sh <archive>" -ForegroundColor Gray
        Write-Host "  3. Convert to zip format first" -ForegroundColor Gray
        exit 1
    } elseif ($Archive -match '\.zip$') {
        Expand-Archive -Path $Archive -DestinationPath $tempDir -Force
    } else {
        Write-Host "[ERROR] Unsupported archive format. Please use .zip files." -ForegroundColor Red
        exit 1
    }

    # 恢复数据库
    $dbFile = Join-Path $tempDir "db.sql"
    if (Test-Path $dbFile) {
        Write-Host "[INFO] Restoring database..." -ForegroundColor Cyan
        Write-Host "  Database: ${DB_NAME}@${DB_HOST}:${DB_PORT}" -ForegroundColor Gray
        
        # 使用临时配置文件避免密码暴露
        $mysqlConfigFile = Join-Path $tempDir ".my.cnf"
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
            Get-Content $dbFile -Raw | & mysql "--defaults-file=$mysqlConfigFile" $DB_NAME
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] Database restored successfully" -ForegroundColor Green
            } else {
                throw "mysql failed with exit code $LASTEXITCODE"
            }
        } catch {
            Write-Host "[ERROR] Database restore failed: $_" -ForegroundColor Red
            exit 1
        } finally {
            # 清理配置文件
            if (Test-Path $mysqlConfigFile) {
                Remove-Item -Force $mysqlConfigFile
            }
        }
    } else {
        Write-Host "[WARN] db.sql not found in archive" -ForegroundColor Yellow
    }

    # 恢复封面图片（使用 Join-Path 确保跨平台兼容）
    $coversSrc = Join-Path $tempDir (Join-Path "data" "covers")
    # 也检查可能的反斜杠路径（兼容旧备份）
    if (-not (Test-Path $coversSrc)) {
        $coversSrcAlt = Join-Path $tempDir "data\covers"
        if (Test-Path $coversSrcAlt) {
            $coversSrc = $coversSrcAlt
        }
    }
    
    if (Test-Path $coversSrc) {
        $coverFiles = Get-ChildItem $coversSrc -File -ErrorAction SilentlyContinue
        if ($coverFiles) {
            Write-Host "[INFO] Restoring cover images..." -ForegroundColor Cyan
            $coversDst = Join-Path $ProjectDir (Join-Path "data" "covers")
            New-Item -ItemType Directory -Force -Path $coversDst | Out-Null
            
            # 复制文件，避免覆盖已存在的
            $copied = 0
            $skipped = 0
            $coverFiles | ForEach-Object {
                $dest = Join-Path $coversDst $_.Name
                if (-not (Test-Path $dest)) {
                    Copy-Item $_.FullName $dest
                    $copied++
                } else {
                    $skipped++
                }
            }
            
            Write-Host "[OK] Cover images restored: $copied new, $skipped skipped" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Cover directory is empty in archive" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[WARN] Cover directory not found in archive" -ForegroundColor Yellow
        Write-Host "[DEBUG] Checked path: $coversSrc" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "[DONE] Restore completed successfully!" -ForegroundColor Green
} finally {
    # 清理临时目录
    if (Test-Path $tempDir) {
        Remove-Item -Recurse -Force $tempDir
    }
}

