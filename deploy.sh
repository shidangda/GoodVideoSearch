#!/bin/bash

# GoodVideoSearch 部署脚本
# 使用方法: bash deploy.sh

set -e  # 遇到错误立即退出

echo "=========================================="
echo "GoodVideoSearch 部署脚本"
echo "=========================================="

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查 Node.js
echo -e "${YELLOW}检查 Node.js...${NC}"
if ! command -v node &> /dev/null; then
    echo -e "${RED}错误: 未找到 Node.js，请先安装 Node.js${NC}"
    exit 1
fi
NODE_VERSION=$(node --version)
echo -e "${GREEN}✓ Node.js 版本: $NODE_VERSION${NC}"

# 检查 npm
echo -e "${YELLOW}检查 npm...${NC}"
if ! command -v npm &> /dev/null; then
    echo -e "${RED}错误: 未找到 npm${NC}"
    exit 1
fi
NPM_VERSION=$(npm --version)
echo -e "${GREEN}✓ npm 版本: $NPM_VERSION${NC}"

# 检查 .env 文件
echo -e "${YELLOW}检查环境变量配置...${NC}"
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        echo -e "${YELLOW}未找到 .env 文件，从 .env.example 创建...${NC}"
        cp .env.example .env
        echo -e "${YELLOW}请编辑 .env 文件并设置正确的数据库配置！${NC}"
        echo -e "${YELLOW}按 Enter 继续，或 Ctrl+C 取消...${NC}"
        read
    else
        echo -e "${RED}错误: 未找到 .env 或 .env.example 文件${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ 找到 .env 文件${NC}"
fi

# 安装依赖
echo -e "${YELLOW}安装项目依赖...${NC}"
npm install --production
echo -e "${GREEN}✓ 依赖安装完成${NC}"

# 创建必要的目录
echo -e "${YELLOW}创建必要的目录...${NC}"
mkdir -p data/covers
mkdir -p logs
chmod 755 data/covers
echo -e "${GREEN}✓ 目录创建完成${NC}"

# 检查 PM2
echo -e "${YELLOW}检查 PM2...${NC}"
if ! command -v pm2 &> /dev/null; then
    echo -e "${YELLOW}未找到 PM2，正在安装...${NC}"
    sudo npm install -g pm2
    echo -e "${GREEN}✓ PM2 安装完成${NC}"
else
    PM2_VERSION=$(pm2 --version)
    echo -e "${GREEN}✓ PM2 版本: $PM2_VERSION${NC}"
fi

# 停止旧进程（如果存在）
echo -e "${YELLOW}检查并停止旧进程...${NC}"
if pm2 list | grep -q "goodvideosearch"; then
    echo -e "${YELLOW}发现运行中的进程，正在停止...${NC}"
    pm2 stop goodvideosearch || true
    pm2 delete goodvideosearch || true
fi

# 启动应用
echo -e "${YELLOW}启动应用...${NC}"
if [ -f ecosystem.config.js ]; then
    pm2 start ecosystem.config.js
    echo -e "${GREEN}✓ 使用 ecosystem.config.js 启动应用${NC}"
else
    pm2 start src/app.js --name goodvideosearch
    echo -e "${GREEN}✓ 应用启动完成${NC}"
fi

# 保存 PM2 配置
echo -e "${YELLOW}保存 PM2 配置...${NC}"
pm2 save
echo -e "${GREEN}✓ PM2 配置已保存${NC}"

# 显示状态
echo ""
echo -e "${GREEN}=========================================="
echo "部署完成！"
echo "==========================================${NC}"
echo ""
echo "应用状态:"
pm2 status
echo ""
echo "查看日志: pm2 logs goodvideosearch"
echo "重启应用: pm2 restart goodvideosearch"
echo "停止应用: pm2 stop goodvideosearch"
echo ""
echo -e "${YELLOW}提示: 如果这是首次部署，请确保:${NC}"
echo "1. MySQL 数据库已创建并配置正确"
echo "2. .env 文件中的数据库配置正确"
echo "3. 防火墙已开放相应端口（80, 443, 3000）"
echo "4. Nginx 已配置反向代理（如需要）"
echo ""

