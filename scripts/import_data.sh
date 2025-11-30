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
        # 解压 ZIP 文件，忽略路径分隔符警告（unzip 可以处理，只是警告）
        # 将警告信息过滤掉，但保留错误信息
        unzip -q "$ARCHIVE" -d "$TEMP_DIR" 2>&1 | grep -v "backslashes" || {
            # 检查解压是否真的失败（退出码非0）
            if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
                echo "[ERROR] Failed to extract ZIP file" >&2
                exit 1
            fi
        }
        # 调试：列出解压后的目录结构
        echo "[DEBUG] Contents after extraction:" >&2
        find "$TEMP_DIR" -type f -o -type d | head -20 | sed 's|^|  |' >&2
    else
        echo "[ERROR] unzip not found. Please install unzip: sudo apt-get install unzip" >&2
        exit 1
    fi
elif [[ "$ARCHIVE" == *.tar.gz ]] || [[ "$ARCHIVE" == *.tgz ]]; then
    # Linux tar.gz 文件
    tar -xzf "$ARCHIVE" -C "$TEMP_DIR"
    # 调试：列出解压后的目录结构
    echo "[DEBUG] Contents after extraction:" >&2
    find "$TEMP_DIR" -type f -o -type d | head -20 | sed 's|^|  |' >&2
else
    echo "[ERROR] Unsupported archive format. Please use .tar.gz or .zip" >&2
    exit 1
fi

# 恢复数据库
DB_FILE="$TEMP_DIR/db.sql"
if [[ -f "$DB_FILE" ]]; then
    # 自动修复 db.sql 常见格式问题（BOM、CRLF、整行被双引号包裹）
    echo "[INFO] Checking db.sql format..."
    
    # 1) 去除 UTF-8 BOM（如有）
    if [ "$(LC_ALL=C head -c 3 "$DB_FILE" | od -An -t x1 | tr -d ' \n')" = "efbbbf" ]; then
        echo "[WARN] Detected UTF-8 BOM, removing..."
        tail -c +4 "$DB_FILE" > "$DB_FILE.nobom" && mv "$DB_FILE.nobom" "$DB_FILE"
    fi
    
    # 2) 转换 CRLF -> LF
    if grep -q 
[client]
host=$DB_HOST
port=$DB_PORT
user=$DB_USER
password=$DB_PASSWORD
EOF
    chmod 600 "$MYSQL_CONFIG_FILE"
    
    # 使用 UTF-8 编码读取 SQL 文件（跨平台兼容）
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
# 调试：检查可能的路径
if [[ ! -d "$COVERS_SRC" ]]; then
    echo "[DEBUG] Checking alternative paths..." >&2
    echo "[DEBUG]  Looking for: $COVERS_SRC" >&2
    echo "[DEBUG]  Temp dir contents:" >&2
    ls -la "$TEMP_DIR" 2>/dev/null | head -10 | sed 's|^|    |' >&2 || true
    if [[ -d "$TEMP_DIR/data" ]]; then
        echo "[DEBUG]  data/ directory contents:" >&2
        ls -la "$TEMP_DIR/data" 2>/dev/null | sed 's|^|    |' >&2 || true
    fi
fi
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
\r' "$DB_FILE" 2>/dev/null; then
        echo "[WARN] Detected CRLF line endings, normalizing to LF..."
        sed -i 's/\r$//' "$DB_FILE"
    fi
    
    # 3) 修复整行被双引号包裹的情况（仅处理前 200 行做启发式判断）
    QUOTED_LINES=$(head -n 200 "$DB_FILE" | grep -c '^".*"
[client]
host=$DB_HOST
port=$DB_PORT
user=$DB_USER
password=$DB_PASSWORD
EOF
    chmod 600 "$MYSQL_CONFIG_FILE"
    
    # 使用 UTF-8 编码读取 SQL 文件（跨平台兼容）
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
# 调试：检查可能的路径
if [[ ! -d "$COVERS_SRC" ]]; then
    echo "[DEBUG] Checking alternative paths..." >&2
    echo "[DEBUG]  Looking for: $COVERS_SRC" >&2
    echo "[DEBUG]  Temp dir contents:" >&2
    ls -la "$TEMP_DIR" 2>/dev/null | head -10 | sed 's|^|    |' >&2 || true
    if [[ -d "$TEMP_DIR/data" ]]; then
        echo "[DEBUG]  data/ directory contents:" >&2
        ls -la "$TEMP_DIR/data" 2>/dev/null | sed 's|^|    |' >&2 || true
    fi
fi
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
 || true)
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
    
    # 使用 UTF-8 编码读取 SQL 文件（跨平台兼容）
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
# 调试：检查可能的路径
if [[ ! -d "$COVERS_SRC" ]]; then
    echo "[DEBUG] Checking alternative paths..." >&2
    echo "[DEBUG]  Looking for: $COVERS_SRC" >&2
    echo "[DEBUG]  Temp dir contents:" >&2
    ls -la "$TEMP_DIR" 2>/dev/null | head -10 | sed 's|^|    |' >&2 || true
    if [[ -d "$TEMP_DIR/data" ]]; then
        echo "[DEBUG]  data/ directory contents:" >&2
        ls -la "$TEMP_DIR/data" 2>/dev/null | sed 's|^|    |' >&2 || true
    fi
fi
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
