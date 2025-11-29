#!/bin/bash

################################################################################
# 数据库迁移脚本 - 从本地迁移到云服务器
# 
# 使用方法：
#   1. 编辑脚本，配置服务器信息
#   2. chmod +x migrate_to_server.sh
#   3. ./migrate_to_server.sh
################################################################################

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# 配置区域 - 请根据实际情况修改
# ============================================================================

# 本地数据库配置
LOCAL_DB_USER="goodvideo_user"
LOCAL_DB_NAME="goodvideo_archive"
LOCAL_DB_HOST="127.0.0.1"
LOCAL_DB_PORT="3306"

# 服务器信息
REMOTE_USER="ubuntu"
REMOTE_HOST="106.52.243.103"  # 替换为你的服务器IP或域名
REMOTE_DB_USER="goodvideo_user"
REMOTE_DB_NAME="goodvideo_archive"
REMOTE_DB_HOST="127.0.0.1"
REMOTE_DB_PORT="3306"

# 迁移选项
BACKUP_FILE="backup_$(date +%Y%m%d_%H%M%S).sql"
USE_COMPRESSION=true  # 是否使用压缩（大数据量推荐）
MIGRATE_COVERS=true    # 是否迁移封面图片

# ============================================================================
# 函数定义
# ============================================================================

print_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# ============================================================================
# 主流程
# ============================================================================

echo ""
echo "=========================================="
echo "数据库迁移工具 - 本地 → 云服务器"
echo "=========================================="
echo ""

# 1. 检查本地数据库连接
print_info "检查本地数据库连接..."
if ! mysql -u "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -P "$LOCAL_DB_PORT" -e "USE $LOCAL_DB_NAME;" 2>/dev/null; then
    print_error "无法连接本地数据库，请检查配置"
    exit 1
fi
print_success "本地数据库连接正常"

# 2. 检查数据库大小
print_info "检查数据库大小..."
DB_SIZE=$(mysql -u "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -P "$LOCAL_DB_PORT" -N -e "
    SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) 
    FROM information_schema.tables 
    WHERE table_schema = '$LOCAL_DB_NAME';" 2>/dev/null)
print_info "数据库大小: ${DB_SIZE} MB"

# 3. 检查记录数
print_info "检查数据记录数..."
HISTORY_COUNT=$(mysql -u "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -P "$LOCAL_DB_PORT" -N -e "
    SELECT COUNT(*) FROM $LOCAL_DB_NAME.history_records;" 2>/dev/null || echo "0")
COMMON_COUNT=$(mysql -u "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -P "$LOCAL_DB_PORT" -N -e "
    SELECT COUNT(*) FROM $LOCAL_DB_NAME.history_common_records;" 2>/dev/null || echo "0")
print_info "history_records: $HISTORY_COUNT 条"
print_info "history_common_records: $COMMON_COUNT 条"

# 4. 确认迁移
echo ""
print_warning "即将执行以下操作："
echo "  1. 导出本地数据库: $LOCAL_DB_NAME"
echo "  2. 上传到服务器: $REMOTE_USER@$REMOTE_HOST"
echo "  3. 导入到服务器数据库: $REMOTE_DB_NAME"
if [ "$MIGRATE_COVERS" = true ]; then
    echo "  4. 迁移封面图片目录"
fi
echo ""
read -p "是否继续？(y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "已取消"
    exit 0
fi

# 5. 导出数据库
print_info "正在导出数据库..."
if [ "$USE_COMPRESSION" = true ]; then
    BACKUP_FILE="${BACKUP_FILE}.gz"
    mysqldump -u "$LOCAL_DB_USER" -p \
        -h "$LOCAL_DB_HOST" \
        -P "$LOCAL_DB_PORT" \
        --single-transaction \
        --routines \
        --triggers \
        --add-drop-table \
        "$LOCAL_DB_NAME" | gzip > "$BACKUP_FILE"
    print_success "数据库已导出并压缩: $BACKUP_FILE"
else
    mysqldump -u "$LOCAL_DB_USER" -p \
        -h "$LOCAL_DB_HOST" \
        -P "$LOCAL_DB_PORT" \
        --single-transaction \
        --routines \
        --triggers \
        --add-drop-table \
        "$LOCAL_DB_NAME" > "$BACKUP_FILE"
    print_success "数据库已导出: $BACKUP_FILE"
fi

# 6. 上传到服务器
print_info "正在上传到服务器..."
if [ "$USE_COMPRESSION" = true ]; then
    scp "$BACKUP_FILE" "$REMOTE_USER@$REMOTE_HOST:~/" || {
        print_error "上传失败"
        exit 1
    }
else
    scp "$BACKUP_FILE" "$REMOTE_USER@$REMOTE_HOST:~/" || {
        print_error "上传失败"
        exit 1
    }
fi
print_success "文件已上传到服务器"

# 7. 在服务器上导入数据库
print_info "正在导入到服务器数据库..."
if [ "$USE_COMPRESSION" = true ]; then
    ssh "$REMOTE_USER@$REMOTE_HOST" \
        "gunzip < ~/$BACKUP_FILE | mysql -u $REMOTE_DB_USER -p -h $REMOTE_DB_HOST -P $REMOTE_DB_PORT $REMOTE_DB_NAME" || {
        print_error "导入失败"
        exit 1
    }
else
    ssh "$REMOTE_USER@$REMOTE_HOST" \
        "mysql -u $REMOTE_DB_USER -p -h $REMOTE_DB_HOST -P $REMOTE_DB_PORT $REMOTE_DB_NAME < ~/$BACKUP_FILE" || {
        print_error "导入失败"
        exit 1
    }
fi
print_success "数据库已导入到服务器"

# 8. 迁移封面图片（如果启用）
if [ "$MIGRATE_COVERS" = true ] && [ -d "data/covers" ]; then
    print_info "正在迁移封面图片..."
    
    # 打包封面目录
    tar -czf covers.tar.gz data/covers/ 2>/dev/null || {
        print_warning "封面目录不存在或无法打包，跳过"
        MIGRATE_COVERS=false
    }
    
    if [ "$MIGRATE_COVERS" = true ]; then
        # 上传封面
        scp covers.tar.gz "$REMOTE_USER@$REMOTE_HOST:~/" || {
            print_warning "封面上传失败，跳过"
        }
        
        # 在服务器上解压
        ssh "$REMOTE_USER@$REMOTE_HOST" \
            "cd ~/GoodVideoSearch && tar -xzf ~/covers.tar.gz && rm ~/covers.tar.gz" || {
            print_warning "封面解压失败"
        }
        
        # 清理本地临时文件
        rm covers.tar.gz
        
        print_success "封面图片已迁移"
    fi
fi

# 9. 清理临时文件
print_info "清理临时文件..."
rm -f "$BACKUP_FILE"
ssh "$REMOTE_USER@$REMOTE_HOST" "rm -f ~/$BACKUP_FILE" 2>/dev/null || true

# 10. 验证迁移结果
print_info "验证迁移结果..."
REMOTE_COUNT=$(ssh "$REMOTE_USER@$REMOTE_HOST" \
    "mysql -u $REMOTE_DB_USER -p -h $REMOTE_DB_HOST -P $REMOTE_DB_PORT -N -e 'SELECT COUNT(*) FROM $REMOTE_DB_NAME.history_records;' 2>/dev/null" || echo "0")

if [ "$HISTORY_COUNT" = "$REMOTE_COUNT" ]; then
    print_success "数据验证通过: 本地 $HISTORY_COUNT 条 = 服务器 $REMOTE_COUNT 条"
else
    print_warning "数据数量不一致: 本地 $HISTORY_COUNT 条 ≠ 服务器 $REMOTE_COUNT 条"
fi

echo ""
print_success "=========================================="
print_success "迁移完成！"
print_success "=========================================="
echo ""
print_info "下一步："
echo "  1. 在服务器上重启应用: pm2 restart goodvideosearch"
echo "  2. 检查应用日志: pm2 logs goodvideosearch"
echo "  3. 访问应用验证功能"
echo ""





