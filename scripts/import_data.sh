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
    # Windows zip 文件
    if command -v unzip >/dev/null 2>&1; then
        unzip -q "$ARCHIVE" -d "$TEMP_DIR"
    else
        echo "[ERROR] unzip not found. Please install unzip: sudo apt-get install unzip" >&2
        exit 1
    fi
elif [[ "$ARCHIVE" == *.tar.gz ]] || [[ "$ARCHIVE" == *.tgz ]]; then
    # Linux tar.gz 文件
    tar -xzf "$ARCHIVE" -C "$TEMP_DIR"
else
    echo "[ERROR] Unsupported archive format. Please use .tar.gz or .zip" >&2
    exit 1
fi

# 恢复数据库
DB_FILE="$TEMP_DIR/db.sql"
if [[ -f "$DB_FILE" ]]; then
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
    
    if mysql --defaults-file="$MYSQL_CONFIG_FILE" "$DB_NAME" < "$DB_FILE" 2>/dev/null; then
        rm -f "$MYSQL_CONFIG_FILE"
        echo "[OK] Database restored successfully"
    else
        echo "[ERROR] Database restore failed" >&2
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
    
    # 使用 cp 合并文件（避免覆盖已存在的）
    COPIED=0
    SKIPPED=0
    
    # 兼容性更好的方式：使用 find + while read
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
        # 如果没有 find，使用通配符（可能不处理子目录）
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
