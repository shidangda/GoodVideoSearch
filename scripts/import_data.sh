#!/usr/bin/env bash
# GoodVideoSearch 数据恢复脚本 (Linux/macOS)
# 功能：从压缩包恢复数据库和封面图片
# 用法: bash scripts/import_data.sh <archive.tar.gz|archive.zip>

set -euo pipefail

ARCHIVE="${1:-}"

# 参数校验
if [[ -z "$ARCHIVE" || ! -f "$ARCHIVE" ]]; then
  echo "Usage: $0 <gvs-backup-*.tar.gz|gvs-backup-*.zip>" >&2
  exit 1
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

# 校验 .env
if [[ ! -f .env ]]; then
  echo "[ERROR] .env file not found at: $PROJECT_DIR/.env" >&2
  exit 1
fi

# 读取数据库配置（剔除多余空白/引号/CR）
read_kv() { grep "^$1=" .env | cut -d '=' -f2- | tr -d '\r' | tr -d '"' | tr -d "'" | tr -d ' ' || true; }
DB_HOST=$(read_kv DB_HOST)
DB_PORT=$(read_kv DB_PORT)
DB_NAME=$(read_kv DB_NAME)
DB_USER=$(read_kv DB_USER)
DB_PASSWORD=$(read_kv DB_PASSWORD)

if [[ -z "$DB_HOST" || -z "$DB_PORT" || -z "$DB_NAME" || -z "$DB_USER" || -z "$DB_PASSWORD" ]]; then
  echo "[ERROR] Missing database configuration in .env" >&2
  exit 1
fi

# 检查 mysql
if ! command -v mysql >/dev/null 2>&1; then
  echo "[ERROR] mysql not found. Please install MySQL client tools." >&2
  exit 1
fi

# 解压
TEMP_DIR=$(mktemp -d)
trap "rm -rf '$TEMP_DIR'" EXIT

echo "[INFO] Extracting archive..."
if [[ "$ARCHIVE" == *.zip ]]; then
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$ARCHIVE" -d "$TEMP_DIR"
  else
    echo "[ERROR] unzip not found. Please install unzip: sudo apt-get install unzip" >&2
    exit 1
  fi
elif [[ "$ARCHIVE" == *.tar.gz || "$ARCHIVE" == *.tgz ]]; then
  tar -xzf "$ARCHIVE" -C "$TEMP_DIR"
else
  echo "[ERROR] Unsupported archive format. Please use .tar.gz or .zip" >&2
  exit 1
fi

# 调试目录结构
echo "[DEBUG] Contents after extraction:" >&2
find "$TEMP_DIR" -maxdepth 3 -mindepth 0 -print | sed 's|^|  |' | head -100 >&2

# 恢复数据库
DB_FILE="$TEMP_DIR/db.sql"
if [[ -f "$DB_FILE" ]]; then
  echo "[INFO] Checking db.sql format..."

  # 1) 去除 UTF-8 BOM
  if [[ "$(LC_ALL=C head -c 3 "$DB_FILE" | od -An -t x1 | tr -d ' \n')" == "efbbbf" ]]; then
    echo "[WARN] Detected UTF-8 BOM, removing..."
    tail -c +4 "$DB_FILE" > "$DB_FILE.nobom" && mv "$DB_FILE.nobom" "$DB_FILE"
  fi

  # 2) CRLF -> LF
  if grep -q $'\r' "$DB_FILE" 2>/dev/null; then
    echo "[WARN] Detected CRLF line endings, normalizing to LF..."
    sed -i 's/\r$//' "$DB_FILE"
  fi

  # 3) 若大量行整行被双引号包裹，剥离（含空白）
  QUOTED_LINES=$(head -n 200 "$DB_FILE" | grep -c '^[[:space:]]*".*"[[:space:]]*$' || true)
  if [[ "${QUOTED_LINES}" -ge 3 ]]; then
    echo "[WARN] Detected many fully-quoted lines ($QUOTED_LINES), stripping surrounding quotes..."
    sed -i -E 's/^[[:space:]]*"(.*)"[[:space:]]*$/\1/' "$DB_FILE"
  fi

  # 4) 处理行首/行尾转义引号 \" —— 仅限行边界
  if command -v perl >/dev/null 2>&1; then
    perl -0777 -i -pe 's/^\s*(?:\\+\")+\s*//mg; s/\s*(?:\\+\")+\s*$//mg' "$DB_FILE"
  else
    # sed 近似处理（重复三次以尽可能剥离多重前后缀）
    for _ in 1 2 3; do
      sed -i -E 's/^[[:space:]]*\\"[[:space:]]*//' "$DB_FILE" || true
      sed -i -E 's/[[:space:]]*\\"[[:space:]]*$//' "$DB_FILE" || true
    done
  fi

  # 5) 兜底：整句被 "...;" 包裹 → 去外层引号
  sed -i -E 's/^[[:space:]]*"(.*;)[[:space:]]*"[[:space:]]*$/\1/' "$DB_FILE"
  # 6) 兜底：语句末尾多余的引号
  sed -i -E 's/;[[:space:]]*"[[:space:]]*$/;/' "$DB_FILE"

  echo "[INFO] Restoring database..."
  echo "  Database: $DB_NAME@$DB_HOST:$DB_PORT"

  # 临时 MySQL 配置
  MYSQL_CONFIG_FILE="$TEMP_DIR/.my.cnf"
  cat > "$MYSQL_CONFIG_FILE" <<EOF
[client]
host=$DB_HOST
port=$DB_PORT
user=$DB_USER
password=$DB_PASSWORD
EOF
  chmod 600 "$MYSQL_CONFIG_FILE"

  attempt_import() {
    set +e
    local out
    out=$(mysql --defaults-file="$MYSQL_CONFIG_FILE" "$DB_NAME" < "$DB_FILE" 2>&1)
    local code=$?
    set -e
    echo "$out"
    return $code
  }

  MYSQL_OUTPUT=$(attempt_import)
  EXIT_CODE=$?

  # 若因 Unknown command '"' 失败，再进行一次更激进修复并重试一次
  if [[ $EXIT_CODE -ne 0 && "$MYSQL_OUTPUT" =~ Unknown\ command.*\\\" ]]; then
    echo "[WARN] MySQL reported Unknown command '"' — applying aggressive quote fixes and retrying..." >&2
    if command -v perl >/dev/null 2>&1; then
      # 去除行首所有由反斜杠+引号组成的串；去除行尾同类串
      perl -0777 -i -pe 's/^\s*(?:\\*\"|\")+//mg; s/(?:\\*\"|\")+\s*$//mg' "$DB_FILE"
    else
      for _ in 1 2 3; do
        sed -i -E 's/^[[:space:]]*"[[:space:]]*//' "$DB_FILE" || true
        sed -i -E 's/[[:space:]]*"[[:space:]]*$//' "$DB_FILE" || true
      done
    fi
    # 再次尝试
    MYSQL_OUTPUT=$(attempt_import)
    EXIT_CODE=$?
  fi

  if [[ $EXIT_CODE -eq 0 ]]; then
    rm -f "$MYSQL_CONFIG_FILE"
    echo "[OK] Database restored successfully"
  else
    echo "[ERROR] Database restore failed (exit code: $EXIT_CODE)" >&2
    if echo "$MYSQL_OUTPUT" | grep -q 'Unknown command.*\\"'; then
      echo "[DEBUG] Suspect quotes remain around line. Showing lines 40..70:" >&2
      nl -ba "$DB_FILE" | sed -n '40,70p' >&2 || true
    else
      echo "[DEBUG] MySQL output:" >&2
      echo "$MYSQL_OUTPUT" >&2
    fi
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
      [[ -f "$file" ]] || continue
      DEST="$COVERS_DST/$(basename "$file")"
      if [[ ! -f "$DEST" ]]; then
        cp "$file" "$DEST"
        ((COPIED++))
      else
        ((SKIPPED++))
      fi
    done < <(find "$COVERS_SRC" -type f 2>/dev/null)
  else
    for file in "$COVERS_SRC"/*; do
      [[ -f "$file" ]] || continue
      DEST="$COVERS_DST/$(basename "$file")"
      if [[ ! -f "$DEST" ]]; then
        cp "$file" "$DEST"
        ((COPIED++))
      else
        ((SKIPPED++))
      fi
    done
  fi

  echo "[OK] Cover images restored: $COPIED new, $SKIPPED skipped"
else
  echo "[WARN] Cover directory not found in archive"
fi

echo ""
echo "[DONE] Restore completed successfully!"
