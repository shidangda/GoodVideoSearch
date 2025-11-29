#!/usr/bin/env bash
# GoodVideoSearch 数据备份脚本 (Linux/macOS)
# 功能：导出数据库和封面图片到压缩包
# 用法: bash scripts/export_data.sh [--out <输出目录>]

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR=""

# 解析参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --out)
            OUT_DIR="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 2
            ;;
    esac
done

cd "$PROJECT_DIR"

# 检查 .env 文件
if [[ ! -f .env ]]; then
    echo "[ERROR] .env file not found at: $PROJECT_DIR/.env" >&2
    exit 1
fi

# 读取数据库配置（安全方式）
DB_HOST=$(grep "^DB_HOST=" .env | cut -d '=' -f2- | tr -d ' ' | tr -d '"' | tr -d "'" || echo "")
DB_PORT=$(grep "^DB_PORT=" .env | cut -d '=' -f2- | tr -d ' ' | tr -d '"' | tr -d "'" || echo "")
DB_NAME=$(grep "^DB_NAME=" .env | cut -d '=' -f2- | tr -d ' ' | tr -d '"' | tr -d "'" || echo "")
DB_USER=$(grep "^DB_USER=" .env | cut -d '=' -f2- | tr -d ' ' | tr -d '"' | tr -d "'" || echo "")
DB_PASSWORD=$(grep "^DB_PASSWORD=" .env | cut -d '=' -f2- | tr -d ' ' | tr -d '"' | tr -d "'" || echo "")

# 验证配置
if [[ -z "$DB_HOST" || -z "$DB_PORT" || -z "$DB_NAME" || -z "$DB_USER" || -z "$DB_PASSWORD" ]]; then
    echo "[ERROR] Missing database configuration in .env" >&2
    exit 1
fi

# 检查 mysqldump
if ! command -v mysqldump >/dev/null 2>&1; then
    echo "[ERROR] mysqldump not found. Please install MySQL client tools." >&2
    exit 1
fi

# 创建备份目录
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUT_DIR="${OUT_DIR:-$PROJECT_DIR/backups}"
WORK_DIR="$PROJECT_DIR/backup-$TIMESTAMP"
ARCHIVE="$OUT_DIR/gvs-backup-$TIMESTAMP.tar.gz"

mkdir -p "$OUT_DIR" "$WORK_DIR"

echo "[INFO] Starting backup..."
echo "  Database: $DB_NAME@$DB_HOST:$DB_PORT"
echo "  Covers: data/covers"

# 导出数据库
echo "[INFO] Exporting database..."

# 使用临时配置文件避免密码暴露在进程列表中
MYSQL_CONFIG_FILE="$WORK_DIR/.my.cnf"
cat > "$MYSQL_CONFIG_FILE" <<EOF
[client]
host=$DB_HOST
port=$DB_PORT
user=$DB_USER
password=$DB_PASSWORD
EOF
chmod 600 "$MYSQL_CONFIG_FILE"

if mysqldump --defaults-file="$MYSQL_CONFIG_FILE" \
    --single-transaction --quick --hex-blob "$DB_NAME" > "$WORK_DIR/db.sql" 2>/dev/null; then
    rm -f "$MYSQL_CONFIG_FILE"
else
    echo "[ERROR] Database export failed" >&2
    rm -f "$MYSQL_CONFIG_FILE"
    rm -rf "$WORK_DIR"
    exit 1
fi

# 复制封面图片
COVERS_SRC="$PROJECT_DIR/data/covers"
if [[ -d "$COVERS_SRC" ]]; then
    echo "[INFO] Copying cover images..."
    mkdir -p "$WORK_DIR/data"
    cp -a "$COVERS_SRC" "$WORK_DIR/data/"
    COVER_COUNT=$(find "$WORK_DIR/data/covers" -type f 2>/dev/null | wc -l)
    echo "  Copied $COVER_COUNT cover images"
else
    echo "[WARN] Cover directory not found: $COVERS_SRC"
fi

# 创建清单文件
cat > "$WORK_DIR/manifest.json" <<EOF
{
  "project": "GoodVideoSearch",
  "db": "$DB_NAME",
  "time": "$TIMESTAMP",
  "format": "tar.gz"
}
EOF

# 压缩
echo "[INFO] Creating archive..."
tar -czf "$ARCHIVE" -C "$WORK_DIR" .

# 清理临时目录
rm -rf "$WORK_DIR"

# 显示结果
FILE_SIZE=$(du -h "$ARCHIVE" | cut -f1)
echo "[OK] Backup completed successfully!"
echo "  Archive: $ARCHIVE"
echo "  Size: $FILE_SIZE"
echo ""
echo "Next steps:"
echo "  1. Upload the archive to your server"
echo "  2. Run: bash scripts/import_data.sh $ARCHIVE"
