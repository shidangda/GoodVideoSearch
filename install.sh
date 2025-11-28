#!/bin/bash

################################################################################
# GoodVideoSearch 一键安装部署脚本
# 适用于 Ubuntu 20.04 系统
# 
# 功能说明：
# 1. 更新系统软件包
# 2. 安装 Node.js 18+ (使用 NodeSource)
# 3. 安装 MySQL 数据库服务器
# 4. 安装 Nginx Web 服务器
# 5. 安装 PM2 进程管理器
# 6. 从 Git 仓库克隆项目
# 7. 安装项目依赖
# 8. 配置数据库和用户
# 9. 创建环境变量配置文件
# 10. 配置 Nginx 反向代理
# 11. 配置防火墙规则
# 12. 启动应用服务
#
# 使用方法：
#   chmod +x install.sh
#   sudo ./install.sh
#
# 注意：此脚本需要 root 权限执行
################################################################################

set -e  # 遇到任何错误立即退出，避免部分安装导致的问题

################################################################################
# 颜色定义 - 用于美化输出信息
################################################################################
RED='\033[0;31m'      # 错误信息 - 红色
GREEN='\033[0;32m'    # 成功信息 - 绿色
YELLOW='\033[1;33m'   # 警告信息 - 黄色
BLUE='\033[0;34m'     # 提示信息 - 蓝色
NC='\033[0m'          # 重置颜色

################################################################################
# 配置变量 - 可以根据需要修改这些默认值
################################################################################
# Git 仓库地址
GIT_REPO="https://github.com/shidangda/GoodVideoSearch.git"

# 项目安装目录（会在用户主目录下创建）
PROJECT_DIR="$HOME/GoodVideoSearch"

# Node.js 版本（推荐使用 18 或更高版本）
NODE_VERSION="18"

# 数据库相关配置
DB_NAME="goodvideo_archive"
DB_USER="goodvideo_user"
DB_HOST="127.0.0.1"
DB_PORT="3306"

# 应用端口
APP_PORT="3000"

# 域名（如果使用域名访问，请填写；否则留空使用 IP 访问）
DOMAIN_NAME=""

################################################################################
# 辅助函数 - 用于输出格式化的信息Ubuntu 20.04
################################################################################

# 打印带颜色的信息
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

# 打印分隔线
print_separator() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
    echo ""
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

################################################################################
# 检查运行环境
################################################################################
check_environment() {
    print_separator "检查运行环境"
    
    # 检查是否为 root 用户
    if [ "$EUID" -ne 0 ]; then 
        print_error "请使用 sudo 运行此脚本: sudo ./install.sh"
        exit 1
    fi
    
    # 检查操作系统
    if [ ! -f /etc/os-release ]; then
        print_error "无法检测操作系统版本"
        exit 1
    fi
    
    # 读取系统信息
    . /etc/os-release
    print_info "操作系统: $NAME $VERSION"
    
    # 检查是否为 Ubuntu 20.04
    if [[ "$ID" != "ubuntu" ]] || [[ "$VERSION_ID" != "20.04" ]]; then
        print_warning "此脚本主要针对 Ubuntu 20.04 设计，当前系统: $ID $VERSION_ID"
        read -p "是否继续？(y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    print_success "环境检查通过"
}

################################################################################
# 步骤 1: 更新系统软件包
################################################################################
update_system() {
    print_separator "步骤 1/13: 更新系统软件包"
    
    print_info "更新软件包列表..."
    apt-get update -y
    
    print_info "升级已安装的软件包..."
    apt-get upgrade -y
    
    print_info "安装基础工具..."
    apt-get install -y \
        curl \
        wget \
        git \
        build-essential \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release
    
    print_success "系统更新完成"
}

################################################################################
# 步骤 2: 安装 Node.js
################################################################################
install_nodejs() {
    print_separator "步骤 2/13: 安装 Node.js"
    
    # 检查 Node.js 是否已安装
    if command_exists node; then
        EXISTING_VERSION=$(node --version)
        print_warning "检测到已安装 Node.js: $EXISTING_VERSION"
        read -p "是否重新安装？(y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "跳过 Node.js 安装"
            return
        fi
    fi
    
    print_info "添加 NodeSource 仓库..."
    # 下载并执行 NodeSource 安装脚本
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash -
    
    print_info "安装 Node.js ${NODE_VERSION}.x..."
    apt-get install -y nodejs
    
    # 验证安装
    NODE_VER=$(node --version)
    NPM_VER=$(npm --version)
    print_success "Node.js 安装完成: $NODE_VER"
    print_success "npm 版本: $NPM_VER"
    
    # 配置 npm 镜像（可选，加速下载）
    # 检查是否已配置镜像
    CURRENT_REGISTRY=$(npm config get registry 2>/dev/null || echo "")
    
    if [ -n "$CURRENT_REGISTRY" ] && [ "$CURRENT_REGISTRY" != "https://registry.npmjs.org/" ]; then
        print_info "检测到已配置 npm 镜像: $CURRENT_REGISTRY"
        print_info "如果您使用的是腾讯云服务器，通常已配置内网镜像，无需再配置"
        read -p "是否覆盖现有镜像配置为淘宝镜像？(y/n，默认 n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            npm config set registry https://registry.npmmirror.com
            print_success "已配置 npm 使用淘宝镜像"
        else
            print_info "保持现有镜像配置: $CURRENT_REGISTRY"
        fi
    else
        # 未配置镜像，询问是否配置
        print_info "配置 npm 镜像（可选，用于加速下载）"
        print_info "提示："
        print_info "  - 腾讯云服务器通常已配置内网镜像，无需再配置"
        print_info "  - 如果下载速度慢，可以配置淘宝镜像"
        read -p "是否配置淘宝镜像？(y/n，默认 n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            npm config set registry https://registry.npmmirror.com
            print_success "已配置 npm 使用淘宝镜像: https://registry.npmmirror.com"
        else
            print_info "使用默认 npm 官方源"
        fi
    fi
}

################################################################################
# 步骤 3: 安装 MySQL
################################################################################
install_mysql() {
    print_separator "步骤 3/13: 安装 MySQL 数据库"
    
    # 检查 MySQL 是否已安装
    if command_exists mysql; then
        print_warning "检测到已安装 MySQL"
        read -p "是否重新安装？(y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "跳过 MySQL 安装"
            return
        fi
    fi
    
    print_info "安装 MySQL 服务器..."
    # 设置 MySQL root 密码（非交互式安装）
    debconf-set-selections <<< "mysql-server mysql-server/root_password password temp_root_pass"
    debconf-set-selections <<< "mysql-server mysql-server/root_password_again password temp_root_pass"
    
    apt-get install -y mysql-server
    
    # 启动 MySQL 服务
    systemctl start mysql
    systemctl enable mysql
    
    print_success "MySQL 安装完成"
    
    # 验证 MySQL 服务状态
    if systemctl is-active --quiet mysql; then
        print_success "MySQL 服务运行正常"
    else
        print_error "MySQL 服务启动失败"
        exit 1
    fi
}

################################################################################
# 步骤 4: 安装 Nginx
################################################################################
install_nginx() {
    print_separator "步骤 4/13: 安装 Nginx Web 服务器"
    
    # 检查 Nginx 是否已安装
    if command_exists nginx; then
        print_warning "检测到已安装 Nginx"
        read -p "是否重新安装？(y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "跳过 Nginx 安装"
            return
        fi
    fi
    
    print_info "安装 Nginx..."
    apt-get install -y nginx
    
    # 启动 Nginx 服务
    systemctl start nginx
    systemctl enable nginx
    
    print_success "Nginx 安装完成"
    
    # 验证 Nginx 服务状态
    if systemctl is-active --quiet nginx; then
        print_success "Nginx 服务运行正常"
    else
        print_error "Nginx 服务启动失败"
        exit 1
    fi
}

################################################################################
# 步骤 5: 安装 PM2
################################################################################
install_pm2() {
    print_separator "步骤 5/13: 安装 PM2 进程管理器"
    
    # 检查 PM2 是否已安装
    if command_exists pm2; then
        EXISTING_VERSION=$(pm2 --version)
        print_warning "检测到已安装 PM2: $EXISTING_VERSION"
        read -p "是否重新安装？(y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "跳过 PM2 安装"
            return
        fi
    fi
    
    print_info "全局安装 PM2..."
    npm install -g pm2
    
    # 配置 PM2 开机自启
    print_info "配置 PM2 开机自启..."
    pm2 startup systemd -u $SUDO_USER --hp $HOME
    
    PM2_VER=$(pm2 --version)
    print_success "PM2 安装完成: $PM2_VER"
}

################################################################################
# 步骤 6: 从 Git 克隆项目
################################################################################
clone_project() {
    print_separator "步骤 6/13: 从 Git 克隆项目"
    
    # 如果项目目录已存在，询问是否删除
    if [ -d "$PROJECT_DIR" ]; then
        print_warning "项目目录已存在: $PROJECT_DIR"
        read -p "是否删除并重新克隆？(y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "删除旧项目目录..."
            rm -rf "$PROJECT_DIR"
        else
            print_info "使用现有项目目录"
            return
        fi
    fi
    
    print_info "从 Git 仓库克隆项目..."
    print_info "仓库地址: $GIT_REPO"
    print_info "目标目录: $PROJECT_DIR"
    
    # 切换到用户主目录
    cd "$HOME"
    
    # 克隆项目
    git clone "$GIT_REPO" "$PROJECT_DIR"
    
    if [ -d "$PROJECT_DIR" ]; then
        print_success "项目克隆完成"
    else
        print_error "项目克隆失败"
        exit 1
    fi
}

################################################################################
# 步骤 7: 安装项目依赖
################################################################################
install_dependencies() {
    print_separator "步骤 7/13: 安装项目依赖"
    
    if [ ! -d "$PROJECT_DIR" ]; then
        print_error "项目目录不存在: $PROJECT_DIR"
        exit 1
    fi
    
    cd "$PROJECT_DIR"
    
    print_info "安装 npm 依赖包..."
    # 使用生产模式安装，不安装开发依赖
    npm install --production
    
    print_success "项目依赖安装完成"
}

################################################################################
# 步骤 8: 配置数据库
################################################################################
configure_database() {
    print_separator "步骤 8/13: 配置 MySQL 数据库"
    
    # 获取数据库密码
    print_info "需要设置数据库用户密码"
    read -sp "请输入数据库密码（将用于 $DB_USER 用户）: " DB_PASSWORD
    echo
    read -sp "请再次确认密码: " DB_PASSWORD_CONFIRM
    echo
    
    if [ "$DB_PASSWORD" != "$DB_PASSWORD_CONFIRM" ]; then
        print_error "两次输入的密码不一致"
        exit 1
    fi
    
    if [ -z "$DB_PASSWORD" ]; then
        print_error "密码不能为空"
        exit 1
    fi
    
    print_info "创建数据库和用户..."
    
    # 创建 SQL 脚本
    SQL_FILE=$(mktemp)
    cat > "$SQL_FILE" << EOF
-- 创建数据库
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 创建用户并设置密码
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';

-- 授予所有权限
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';

-- 刷新权限表
FLUSH PRIVILEGES;

-- 显示创建的数据库
SHOW DATABASES LIKE '${DB_NAME}';
EOF
    
    # 执行 SQL 脚本
    # 注意：这里使用 root 用户，需要 root 密码
    # 如果 MySQL 8.0+ 使用 auth_socket 认证，可能需要调整
    print_info "执行数据库配置脚本..."
    
    # 尝试使用 root 用户连接
    # 方法1: 尝试无密码连接（MySQL 8.0+ 可能使用 auth_socket）
    if mysql -u root -e "SELECT 1" >/dev/null 2>&1; then
        mysql -u root < "$SQL_FILE"
        print_success "使用 root 用户创建数据库和用户"
    # 方法2: 尝试使用临时密码连接
    elif mysql -u root -p"temp_root_pass" -e "SELECT 1" >/dev/null 2>&1; then
        mysql -u root -p"temp_root_pass" < "$SQL_FILE"
        print_success "使用 root 用户（临时密码）创建数据库和用户"
    # 方法3: 使用 sudo mysql（Ubuntu 默认配置）
    elif sudo mysql -u root -e "SELECT 1" >/dev/null 2>&1; then
        sudo mysql -u root < "$SQL_FILE"
        print_success "使用 sudo mysql 创建数据库和用户"
    else
        print_warning "无法自动连接 MySQL，需要手动配置"
        print_info "请手动执行以下 SQL 命令："
        cat "$SQL_FILE"
        echo ""
        print_info "连接方式："
        echo "  1. sudo mysql -u root"
        echo "  2. 或 mysql -u root -p（输入安装时设置的密码）"
        echo ""
        read -p "按 Enter 继续（假设您已手动执行 SQL）..."
    fi
    
    # 清理临时文件
    rm -f "$SQL_FILE"
    
    print_success "数据库配置完成"
}

################################################################################
# 步骤 9: 创建环境变量配置文件
################################################################################
create_env_file() {
    print_separator "步骤 9/13: 创建环境变量配置文件"
    
    cd "$PROJECT_DIR"
    
    # 如果 .env 文件已存在，询问是否覆盖
    if [ -f ".env" ]; then
        print_warning ".env 文件已存在"
        read -p "是否覆盖现有 .env 文件？(y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "保留现有 .env 文件"
            return
        fi
    fi
    
    # 获取应用端口
    read -p "请输入应用端口（默认: $APP_PORT）: " INPUT_PORT
    if [ -n "$INPUT_PORT" ]; then
        APP_PORT="$INPUT_PORT"
    fi
    
    # 创建 .env 文件
    print_info "创建 .env 文件..."
    cat > .env << EOF
# 数据库配置
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}

# 应用端口
PORT=${APP_PORT}
EOF
    
    # 设置文件权限（仅所有者可读写）
    chmod 600 .env
    chown $SUDO_USER:$SUDO_USER .env
    
    print_success ".env 文件创建完成"
    print_warning "请妥善保管 .env 文件，包含敏感信息！"
}

################################################################################
# 步骤 10: 创建数据表
################################################################################
create_database_tables() {
    print_separator "步骤 10/13: 创建数据表"
    
    print_info "创建项目所需的数据表..."
    
    # 检查 .env 文件是否存在
    if [ ! -f "$PROJECT_DIR/.env" ]; then
        print_error ".env 文件不存在，无法创建数据表"
        return 1
    fi
    
    # 从 .env 文件读取数据库配置（使用安全的方式，避免使用 source）
    # 使用 grep 和 cut 安全地读取环境变量，避免执行恶意代码
    print_info "读取数据库配置..."
    DB_HOST=$(grep "^DB_HOST=" "$PROJECT_DIR/.env" | cut -d '=' -f2- | tr -d ' ' | tr -d '"' | tr -d "'")
    DB_PORT=$(grep "^DB_PORT=" "$PROJECT_DIR/.env" | cut -d '=' -f2- | tr -d ' ' | tr -d '"' | tr -d "'")
    DB_NAME=$(grep "^DB_NAME=" "$PROJECT_DIR/.env" | cut -d '=' -f2- | tr -d ' ' | tr -d '"' | tr -d "'")
    DB_USER=$(grep "^DB_USER=" "$PROJECT_DIR/.env" | cut -d '=' -f2- | tr -d ' ' | tr -d '"' | tr -d "'")
    DB_PASSWORD=$(grep "^DB_PASSWORD=" "$PROJECT_DIR/.env" | cut -d '=' -f2- | tr -d ' ' | tr -d '"' | tr -d "'")
    
    # 设置默认值（如果从 .env 读取失败）
    DB_HOST=${DB_HOST:-127.0.0.1}
    DB_PORT=${DB_PORT:-3306}
    DB_NAME=${DB_NAME:-goodvideo_archive}
    DB_USER=${DB_USER:-goodvideo_user}
    
    # 验证必要的配置是否存在
    if [ -z "$DB_PASSWORD" ]; then
        print_error "无法从 .env 文件读取数据库密码"
        return 1
    fi
    
    print_info "数据库配置: $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"
    
    # 创建 SQL 脚本文件
    SQL_FILE=$(mktemp)
    cat > "$SQL_FILE" << EOF
-- 使用数据库
USE \`${DB_NAME}\`;

-- 创建 history_records 表（历史记录表，包含评分和封面）
CREATE TABLE IF NOT EXISTS history_records (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  resource_id VARCHAR(191) NOT NULL UNIQUE,
  title VARCHAR(512) NOT NULL,
  magnet TEXT,
  detail_url TEXT,
  heat INT,
  recorded_at DATETIME NULL,
  size_text VARCHAR(255),
  type_text VARCHAR(255),
  rating TINYINT,
  tags JSON,
  cover_path VARCHAR(255),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_resource_id (resource_id),
  INDEX idx_title (title(191)),
  INDEX idx_updated_at (updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 创建 history_common_records 表（通用历史记录表，用于隐藏资源）
CREATE TABLE IF NOT EXISTS history_common_records (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  resource_id VARCHAR(191) NOT NULL UNIQUE,
  title VARCHAR(512) NOT NULL,
  magnet TEXT,
  detail_url TEXT,
  heat INT,
  recorded_at DATETIME NULL,
  size_text VARCHAR(255),
  type_text VARCHAR(255),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_resource_id (resource_id),
  INDEX idx_title (title(191)),
  INDEX idx_updated_at (updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 显示创建的表
SHOW TABLES;
EOF
    
    # 执行 SQL 脚本
    print_info "执行表创建脚本..."
    
    # 尝试使用配置的用户连接数据库
    # 注意：mysql 命令的 -p 参数后面不能有空格，密码直接跟在后面
    print_info "使用数据库用户 $DB_USER 创建表..."
    if mysql -u "${DB_USER}" -p"${DB_PASSWORD}" -h "${DB_HOST}" -P "${DB_PORT}" "${DB_NAME}" < "$SQL_FILE" 2>/dev/null; then
        print_success "数据表创建成功"
    else
        # 如果使用配置用户失败，尝试使用 root 用户
        print_warning "使用配置用户连接失败，尝试使用 root 用户..."
        
        if mysql -u root -e "SELECT 1" >/dev/null 2>&1; then
            # 使用 root 用户执行，但需要先切换到目标数据库
            mysql -u root << EOF
USE \`${DB_NAME}\`;
$(cat "$SQL_FILE" | grep -v "^USE")
EOF
            print_success "数据表创建成功（使用 root 用户）"
        else
            print_error "无法连接数据库创建表"
            print_info "请手动执行以下 SQL 命令："
            cat "$SQL_FILE"
            echo ""
            read -p "按 Enter 继续（假设您已手动创建表）..."
        fi
    fi
    
    # 清理临时文件
    rm -f "$SQL_FILE"
    
    # 验证表是否创建成功
    print_info "验证表创建..."
    TABLE_CHECK=$(mysql -u "${DB_USER}" -p"${DB_PASSWORD}" -h "${DB_HOST}" -P "${DB_PORT}" "${DB_NAME}" -e "SHOW TABLES;" 2>/dev/null | grep -E "(history_records|history_common_records)" | wc -l)
    
    if [ "$TABLE_CHECK" -ge 2 ]; then
        print_success "数据表验证通过（找到 $TABLE_CHECK 个表）"
        print_info "已创建的表："
        mysql -u "${DB_USER}" -p"${DB_PASSWORD}" -h "${DB_HOST}" -P "${DB_PORT}" "${DB_NAME}" -e "SHOW TABLES;" 2>/dev/null | grep -E "(history_records|history_common_records)" || true
    else
        print_warning "数据表验证未完全通过（找到 $TABLE_CHECK 个表，期望 2 个）"
        print_info "应用启动时会自动创建缺失的表，这通常不是问题"
    fi
}

################################################################################
# 步骤 11: 配置 Nginx 反向代理
################################################################################
configure_nginx() {
    print_separator "步骤 11/13: 配置 Nginx 反向代理"
    
    # 获取域名或 IP
    if [ -z "$DOMAIN_NAME" ]; then
        print_info "请输入域名（如果使用域名访问）或按 Enter 使用服务器 IP"
        read -p "域名或 IP: " DOMAIN_NAME
    fi
    
    # 如果没有输入，使用服务器 IP
    if [ -z "$DOMAIN_NAME" ]; then
        DOMAIN_NAME=$(hostname -I | awk '{print $1}')
        print_info "将使用服务器 IP: $DOMAIN_NAME"
    fi
    
    # 创建 Nginx 配置文件
    NGINX_CONF="/etc/nginx/sites-available/goodvideosearch"
    
    print_info "创建 Nginx 配置文件: $NGINX_CONF"
    
    cat > "$NGINX_CONF" << EOF
server {
    listen 80;
    server_name ${DOMAIN_NAME};

    # 允许上传最大 10MB 的文件（封面图片）
    client_max_body_size 10M;

    # 访问日志
    access_log /var/log/nginx/goodvideosearch_access.log;
    error_log /var/log/nginx/goodvideosearch_error.log;

    location / {
        proxy_pass http://localhost:${APP_PORT};
        proxy_http_version 1.1;
        
        # WebSocket 支持
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        
        # 传递真实 IP 和主机信息
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # 超时设置
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # 缓存控制
        proxy_cache_bypass \$http_upgrade;
    }

    # 静态文件缓存优化
    location /static/ {
        proxy_pass http://localhost:${APP_PORT};
        proxy_cache_valid 200 1h;
        add_header Cache-Control "public, max-age=3600";
    }

    # 封面图片缓存优化
    location /covers/ {
        proxy_pass http://localhost:${APP_PORT};
        proxy_cache_valid 200 7d;
        add_header Cache-Control "public, max-age=604800";
    }
}
EOF
    
    # 创建符号链接启用配置
    if [ ! -L "/etc/nginx/sites-enabled/goodvideosearch" ]; then
        ln -s "$NGINX_CONF" /etc/nginx/sites-enabled/
    fi
    
    # 删除默认配置（如果存在）
    if [ -L "/etc/nginx/sites-enabled/default" ]; then
        rm /etc/nginx/sites-enabled/default
    fi
    
    # 测试 Nginx 配置
    print_info "测试 Nginx 配置..."
    if nginx -t; then
        print_success "Nginx 配置测试通过"
        
        # 重新加载 Nginx
        systemctl reload nginx
        print_success "Nginx 配置已应用"
    else
        print_error "Nginx 配置测试失败"
        exit 1
    fi
}

################################################################################
# 步骤 12: 配置防火墙
################################################################################
configure_firewall() {
    print_separator "步骤 12/13: 配置防火墙规则"
    
    # 检查 UFW 是否安装
    if ! command_exists ufw; then
        print_info "安装 UFW 防火墙..."
        apt-get install -y ufw
    fi
    
    # 检查防火墙状态
    UFW_STATUS=$(ufw status | head -n 1)
    
    if echo "$UFW_STATUS" | grep -q "inactive"; then
        print_info "配置防火墙规则..."
        
        # 允许 SSH（重要！避免被锁在外面）
        ufw allow 22/tcp comment 'SSH'
        
        # 允许 HTTP
        ufw allow 80/tcp comment 'HTTP'
        
        # 允许 HTTPS（如果后续配置 SSL）
        ufw allow 443/tcp comment 'HTTPS'
        
        # 启用防火墙
        print_warning "即将启用防火墙，请确保 SSH 端口 22 已开放！"
        read -p "是否启用防火墙？(y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            ufw --force enable
            print_success "防火墙已启用"
        else
            print_warning "防火墙未启用，请手动配置"
        fi
    else
        print_info "防火墙已启用，添加规则..."
        ufw allow 80/tcp comment 'HTTP' 2>/dev/null || true
        ufw allow 443/tcp comment 'HTTPS' 2>/dev/null || true
        print_success "防火墙规则已添加"
    fi
}

################################################################################
# 步骤 13: 启动应用
################################################################################
start_application() {
    print_separator "步骤 13/13: 启动应用"
    
    cd "$PROJECT_DIR"
    
    # 创建必要的目录
    print_info "创建必要的目录..."
    mkdir -p data/covers
    mkdir -p logs
    chown -R $SUDO_USER:$SUDO_USER data logs
    
    # 停止旧进程（如果存在）
    if pm2 list | grep -q "goodvideosearch"; then
        print_info "停止旧进程..."
        pm2 stop goodvideosearch || true
        pm2 delete goodvideosearch || true
    fi
    
    # 使用 ecosystem.config.js 启动（如果存在）
    if [ -f "ecosystem.config.js" ]; then
        print_info "使用 ecosystem.config.js 启动应用..."
        # 切换到项目所有者用户执行 PM2，并确保在项目目录中
        # PM2 的 env_file 配置需要从项目根目录读取 .env 文件
        sudo -u $SUDO_USER bash -c "cd $PROJECT_DIR && pm2 start ecosystem.config.js"
    else
        print_info "启动应用..."
        # 使用 --env-file 参数加载 .env 文件（PM2 5.1+ 支持）
        # 如果 PM2 版本不支持，需要手动设置环境变量
        if pm2 --version | grep -qE "^[5-9]|^[1-9][0-9]"; then
            sudo -u $SUDO_USER bash -c "cd $PROJECT_DIR && pm2 start src/app.js --name goodvideosearch --env-file .env"
        else
            # 旧版本 PM2，需要手动加载环境变量
            print_warning "PM2 版本较旧，手动加载环境变量..."
            sudo -u $SUDO_USER bash -c "cd $PROJECT_DIR && export \$(cat .env | xargs) && pm2 start src/app.js --name goodvideosearch"
        fi
    fi
    
    # 保存 PM2 配置
    sudo -u $SUDO_USER pm2 save
    
    # 等待几秒让应用启动
    sleep 3
    
    # 检查应用状态
    if pm2 list | grep -q "goodvideosearch.*online"; then
        print_success "应用启动成功！"
    else
        print_warning "应用可能启动失败，请检查日志: pm2 logs goodvideosearch"
    fi
}

################################################################################
# 显示安装总结信息
################################################################################
show_summary() {
    print_separator "安装完成！"
    
    echo ""
    echo -e "${GREEN}✓ 所有组件安装完成${NC}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "应用信息："
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  项目目录: $PROJECT_DIR"
    echo "  访问地址: http://${DOMAIN_NAME}"
    echo "  应用端口: $APP_PORT"
    echo ""
    echo "数据库信息："
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  数据库名: $DB_NAME"
    echo "  用户名: $DB_USER"
    echo "  主机: $DB_HOST:$DB_PORT"
    echo ""
    echo "常用命令："
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  查看应用状态: pm2 status"
    echo "  查看应用日志: pm2 logs goodvideosearch"
    echo "  重启应用: pm2 restart goodvideosearch"
    echo "  停止应用: pm2 stop goodvideosearch"
    echo "  查看 Nginx 日志: sudo tail -f /var/log/nginx/goodvideosearch_error.log"
    echo ""
    echo "配置文件位置："
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  环境变量: $PROJECT_DIR/.env"
    echo "  Nginx 配置: /etc/nginx/sites-available/goodvideosearch"
    echo ""
    echo -e "${YELLOW}重要提示：${NC}"
    echo "  1. 请妥善保管 .env 文件中的数据库密码"
    echo "  2. 建议配置 SSL 证书（使用 Let's Encrypt）"
    echo "  3. 定期备份数据库和 data/covers 目录"
    echo ""
}

################################################################################
# 主函数 - 执行所有安装步骤
################################################################################
main() {
    # 显示欢迎信息
    clear
    echo ""
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                                                          ║"
    echo "║        GoodVideoSearch 一键安装部署脚本                 ║"
    echo "║        适用于 Ubuntu 20.04                               ║"
    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    
    # 确认安装
    print_warning "此脚本将安装以下组件："
    echo "  - Node.js ${NODE_VERSION}.x"
    echo "  - MySQL 数据库服务器"
    echo "  - Nginx Web 服务器"
    echo "  - PM2 进程管理器"
    echo "  - GoodVideoSearch 应用"
    echo ""
    read -p "是否继续安装？(y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "安装已取消"
        exit 0
    fi
    
    # 记录开始时间
    START_TIME=$(date +%s)
    
    # 执行所有安装步骤
    check_environment
    update_system
    install_nodejs
    install_mysql
    install_nginx
    install_pm2
    clone_project
    install_dependencies
    configure_database
    create_env_file
    create_database_tables
    configure_nginx
    configure_firewall
    start_application
    
    # 计算安装时间
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    MINUTES=$((DURATION / 60))
    SECONDS=$((DURATION % 60))
    
    # 显示总结
    show_summary
    
    echo ""
    print_success "安装耗时: ${MINUTES} 分 ${SECONDS} 秒"
    echo ""
}

################################################################################
# 执行主函数
################################################################################
main "$@"

