#!/usr/bin/env bash
# GoodVideoSearch 数据恢复脚本 (Linux/macOS)
# 功能：从压缩包恢复数据库和封面图片
# 用法: bash scripts/import_data.sh <archive.tar.gz|archive.zip>

set -euo pipefail

ARCHIVE="${1:-}"

# 检查参数
if [[ -z "$ARCHIVE" || ! -f "$ARCHIVE" ]]; then
    echo "Usage: $0 <gvs-backup-*.tar.gz|gvs-backup-*.zip>" >&2
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

# 检查 .env 文件
if [[ ! -f .env ]]; then
    echo "[ERROR] .env file not found at: $PROJECT_DIR/.env" >&2
    exit 1
fi

# 读取数据库配置（安全方式）
DB_HOST=$(grep "^DB_HOST=" .env | cut -d '=' -f2- | tr -d '\r' | tr -d '"' | tr -d "'" | tr -d ' ' || true)
DB_PORT=$(grep "^DB_PORT=" .env | cut -d '=' -f2- | tr -d '\r' | tr -d '"' | tr -d "'" | tr -d ' ' || true)
DB_NAME=$(grep "^DB_NAME=" .env | cut -d '=' -f2- | tr -d '\r' | tr -d '"' | tr -d "'" | tr -d ' ' || true)
DB_USER=$(grep "^DB_USER=" .env | cut -d '=' -f2- | tr -d '\r' | tr -d '"' | tr -d "'" | tr -d ' ' || true)
DB_PASSWORD=$(grep "^DB_PASSWORD=" .env | cut -d '=' -f2- | tr -d '\r' | tr -d '"' | tr -d "'" | tr -d ' ' || true)

# 验证配置
if [[ -z "$DB_HOST" || -z "$DB_PORT" || -z "$DB_NAME" || -z "$DB_USER" || -z "$DB_PASSWORD" ]]; then
    echo "[ERROR] Missing database configuration in .env" >&2
    exit 1
fi

# 检查 mysql 命令
if ! command -v mysql >/dev/null 2>&1; then
    echo "[ERROR] mysql not found. Please install MySQL client tools." >&2
    exit 1
fi

# 创建临时解压目录
TEMP_DIR=$(mktemp -d)
trap "rm -rf '$TEMP_DIR'" EXIT

echo "[INFO] Extracting archive..."

# 检测文件类型并解压
if [[ "$ARCHIVE" == *.zip ]]; then
    if command -v unzip >/dev/null 2>&1; then
        unzip -q "$ARCHIVE" -d "$TEMP_DIR"
    else
        echo "[ERROR] unzip not found. Please install unzip: sudo apt-get install unzip" >&2
        exit 1
    fi
elif [[ "$ARCHIVE" == *.tar.gz ]] || [[ "$ARCHIVE" == *.tgz ]]; then
    tar -xzf "$ARCHIVE" -C "$TEMP_DIR"
else
    echo "[ERROR] Unsupported archive format. Please use .tar.gz or .zip" >&2
    exit 1
fi

# 调试：列出解压后的目录结构
echo "[DEBUG] Contents after extraction:" >&2
find "$TEMP_DIR" -maxdepth 3 -mindepth 0 -print | head -50 | sed 's|^|  |' >&2

# 恢复数据库
DB_FILE="$TEMP_DIR/db.sql"
if [[ -f "$DB_FILE" ]]; then
    echo "[INFO] Checking db.sql format..."

    # 1) 去除 UTF-8 BOM（如有）
    if [ "$(LC_ALL=C head -c 3 "$DB_FILE" | od -An -t x1 | tr -d ' \n')" = "efbbbf" ]; then
        echo "[WARN] Detected UTF-8 BOM, removing..."
        tail -c +4 "$DB_FILE" > "$DB_FILE.nobom" && mv "$DB_FILE.nobom" "$DB_FILE"
    fi

    # 2) 转换 CRLF -> LF
    if grep -q $'\r' "$DB_FILE" 2>/dev/null; then
        echo "[WARN] Detected CRLF line endings, normalizing to LF..."
        sed -i 's/\r$//' "$DB_FILE"
    fi

    # 3) 修复整行被双引号包裹的情况（启发式：检查前 200 行）
    QUOTED_LINES=$(head -n 200 "$DB_FILE" | grep -c '^".*"$' || true)
    if [ "${QUOTED_LINES}" -ge 5 ]; then
        echo "[WARN] Detected many fully-quoted lines ($QUOTED_LINES), stripping surrounding quotes..."
        sed -i 's/^"\(.*\)"$/\1/' "$DB_FILE"
    fi

    echo "[INFO] Restoring database..."
    echo "  Database: $DB_NAME@$DB_HOST:$DB_PORT"

    # 使用临时配置文件避免密码暴露
    MYSQL_CONFIG_FILE="$TEMP_DIR/.my.cnf"
    cat > "$MYSQL_CONFIG_FILE" <<EOF
[client]
host=$DB_HOST
port=$DB_PORT
user=$DB_USER
password=$DB_PASSWORD
EOF
    chmod 600 "$MYSQL_CONFIG_FILE"

    if mysql --defaults-file="$MYSQL_CONFIG_FILE" "$DB_NAME" < "$DB_FILE" 2>&1; then
        rm -f "$MYSQL_CONFIG_FILE"
        echo "[OK] Database restored successfully"
    else
        EXIT_CODE=$?
        echo "[ERROR] Database restore failed (exit code: $EXIT_CODE)" >&2
        echo "[ERROR] Please check:" >&2
        echo "[ERROR]   1. Database connection settings in .env" >&2
        echo "[ERROR]   2. Database '$DB_NAME' exists and user has permissions" >&2
        echo "[ERROR]   3. SQL file is valid" >&2
        rm -f "$MYSQL_CONFIG_FILE"
        exit 1
    fi
else
    echo "[WARN] db.sql not found in archive"
fi

# 恢复封面图片
COVERS_SRC="$TEMP_DIR/data/covers"
if [[ -d "$COVERS_SRC" ]]; then
    echo "[INFO] Restoring cover images..."
    COVERS_DST="$PROJECT_DIR/data/covers"
    mkdir -p "$COVERS_DST"

    COPIED=0
    SKIPPED=0

    if command -v find >/dev/null 2>&1; then
        while IFS= read -r file; do
            if [[ -f "$file" ]]; then
                DEST="$COVERS_DST/$(basename "$file")"
                if [[ ! -f "$DEST" ]]; then
                    cp "$file" "$DEST"
                    ((COPIED++))
                else
                    ((SKIPPED++))
                fi
            fi
        done < <(find "$COVERS_SRC" -type f 2>/dev/null)
    else
        for file in "$COVERS_SRC"/*; do
            if [[ -f "$file" ]]; then
                DEST="$COVERS_DST/$(basename "$file")"
                if [[ ! -f "$DEST" ]]; then
                    cp "$file" "$DEST"
                    ((COPIED++))
                else
                    ((SKIPPED++))
                fi
            fi
        done
    fi

    echo "[OK] Cover images restored: $COPIED new, $SKIPPED skipped"
else
    echo "[WARN] Cover directory not found in archive"
fi

echo ""
echo "[DONE] Restore completed successfully!"
