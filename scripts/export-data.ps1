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
    # 使用临时文件捕获输出和错误
    $tempDumpFile = "$dbFile.tmp"
    $tempErrorFile = "$dbFile.err"
    
    # 执行 mysqldump，分离标准输出和错误输出
    # 使用 --no-tablespaces 选项避免 PROCESS 权限问题
    & mysqldump "--defaults-file=$mysqlConfigFile" `
        --single-transaction --quick --hex-blob --no-tablespaces $DB_NAME > $tempDumpFile 2> $tempErrorFile
    
    $exitCode = $LASTEXITCODE
    
    # 检查错误输出
    $errorContent = if (Test-Path $tempErrorFile) {
        Get-Content $tempErrorFile -Raw -ErrorAction SilentlyContinue
    } else {
        ""
    }
    
    # 验证 SQL 文件是否生成且不为空
    $sqlFileExists = Test-Path $tempDumpFile
    $sqlFileSize = if ($sqlFileExists) { (Get-Item $tempDumpFile).Length } else { 0 }
    
    # 如果 SQL 文件已生成且不为空，即使有警告也继续
    if ($sqlFileExists -and $sqlFileSize -gt 0) {
        # 显示警告但不中断
        if ($errorContent -match "PROCESS privilege" -or $errorContent -match "tablespaces") {
            Write-Host "[WARN] mysqldump warning (ignored): $errorContent" -ForegroundColor Yellow
        } elseif ($errorContent -and $exitCode -eq 0) {
            # 退出码为 0 但有错误输出，可能是警告
            Write-Host "[WARN] mysqldump warning: $errorContent" -ForegroundColor Yellow
        }
    } elseif ($exitCode -ne 0) {
        # SQL 文件未生成或为空，且退出码非 0，这是真正的错误
        throw "mysqldump failed with exit code ${exitCode}: $errorContent"
    } elseif (-not $sqlFileExists -or $sqlFileSize -eq 0) {
        # 退出码为 0 但文件为空，也是错误
        throw "SQL file is empty or not created. Error output: $errorContent"
    }
    
    # 读取内容并转换为 UTF-8 无 BOM（跨平台兼容）
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $content = [System.IO.File]::ReadAllText($tempDumpFile, [System.Text.Encoding]::Default)
    [System.IO.File]::WriteAllText($dbFile, $content, $utf8NoBom)
    
    # 清理临时文件
    if (Test-Path $tempDumpFile) {
        Remove-Item $tempDumpFile -Force
    }
    if (Test-Path $tempErrorFile) {
        Remove-Item $tempErrorFile -Force
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

# 复制封面图片（使用 Join-Path 确保跨平台兼容）
$coversSrc = Join-Path $ProjectDir (Join-Path "data" "covers")
if (Test-Path $coversSrc) {
    $coverFiles = Get-ChildItem $coversSrc -File -ErrorAction SilentlyContinue
    if ($coverFiles) {
        Write-Host "[INFO] Copying cover images..." -ForegroundColor Cyan
        $coversDst = Join-Path $workDir (Join-Path "data" "covers")
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
# 使用 .NET ZipFile 类确保使用正斜杠作为路径分隔符（跨平台兼容）
Add-Type -AssemblyName System.IO.Compression.FileSystem

# 删除已存在的归档文件
if (Test-Path $archivePath) {
    Remove-Item $archivePath -Force
}

# 创建 ZIP 文件并添加所有文件（使用正斜杠）
# 使用 CreateFromDirectory 方法更简单且兼容性更好
try {
    # 先创建空的 ZIP 文件
    $zip = [System.IO.Compression.ZipFile]::Open($archivePath, [System.IO.Compression.ZipArchiveMode]::Create)
    $zip.Dispose()
    
    # 重新打开并添加文件
    $zip = [System.IO.Compression.ZipFile]::Open($archivePath, [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        Get-ChildItem -Path $workDir -Recurse -File | ForEach-Object {
            # 计算相对路径（相对于 $workDir）
            $relativePath = $_.FullName.Substring($workDir.Length + 1)
            # 确保使用正斜杠（跨平台兼容）
            $relativePath = $relativePath.Replace('\', '/')
            # 添加到 ZIP
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $relativePath) | Out-Null
        }
    } finally {
        $zip.Dispose()
    }
} catch {
    # 如果 ZipArchiveMode 枚举不可用，使用替代方法
    Write-Host "[WARN] Using alternative ZIP creation method..." -ForegroundColor Yellow
    # 使用 Compress-Archive 创建临时 ZIP，然后重新打包修复路径分隔符
    $tempZip = "$archivePath.tmp"
    Push-Location $workDir
    try {
        Compress-Archive -Path * -DestinationPath $tempZip -Force
    } finally {
        Pop-Location
    }
    
    # 重新打开 ZIP 文件并修复路径分隔符
    try {
        $zip = [System.IO.Compression.ZipFile]::Open($tempZip, [System.IO.Compression.ZipArchiveMode]::Read)
        $newZip = [System.IO.Compression.ZipFile]::Open($archivePath, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($entry in $zip.Entries) {
                # 将反斜杠替换为正斜杠
                $fixedName = $entry.FullName.Replace('\', '/')
                $newEntry = $newZip.CreateEntry($fixedName)
                $entryStream = $entry.Open()
                $newEntryStream = $newEntry.Open()
                try {
                    $entryStream.CopyTo($newEntryStream)
                } finally {
                    $entryStream.Close()
                    $newEntryStream.Close()
                }
            }
        } finally {
            $zip.Dispose()
            $newZip.Dispose()
        }
        Remove-Item $tempZip -Force
    } catch {
        # 如果重新打包失败，使用原始 ZIP（Linux unzip 通常可以处理反斜杠）
        Write-Host "[WARN] Could not fix path separators, using original ZIP (Linux unzip should handle it)" -ForegroundColor Yellow
        if (Test-Path $archivePath) {
            Remove-Item $archivePath -Force
        }
        Move-Item $tempZip $archivePath -Force
    }
}

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

