#!/usr/bin/env bash
# DeepWiki 前端启动脚本（Linux / macOS）
# 用途：裸机部署，无需 Docker
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

###############################################################################
# 辅助函数
###############################################################################
info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

###############################################################################
# 1. 检查 Node.js 版本（要求 18+）
###############################################################################
info "检查 Node.js 环境..."
if ! command -v node &>/dev/null; then
    error "未找到 node，请先安装 Node.js 18 或更高版本。"
fi
NODE_VER=$(node --version | sed 's/v//')
NODE_MAJOR=$(echo "$NODE_VER" | cut -d. -f1)
if [ "$NODE_MAJOR" -lt 18 ]; then
    error "Node.js 版本过低：v$NODE_VER，要求 18+。"
fi
info "Node.js 版本：v$NODE_VER ✓"

if ! command -v npm &>/dev/null; then
    error "未找到 npm，请确认 Node.js 安装完整。"
fi
NPM_VER=$(npm --version)
info "npm 版本：v$NPM_VER ✓"

###############################################################################
# 2. 加载 .env 文件（如果存在）
###############################################################################
if [ -f "$SCRIPT_DIR/.env" ]; then
    info "加载 .env 文件..."
    set -a
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env"
    set +a
fi

###############################################################################
# 3. 检查后端地址配置
###############################################################################
SERVER_BASE_URL="${SERVER_BASE_URL:-http://localhost:8001}"
info "后端 API 地址：$SERVER_BASE_URL"
if [[ "$SERVER_BASE_URL" == *"localhost"* ]] || [[ "$SERVER_BASE_URL" == *"127.0.0.1"* ]]; then
    info "  (本机部署，前后端同机运行)"
else
    info "  (远程后端，确认后端服务已在目标机器上启动)"
fi
export SERVER_BASE_URL

###############################################################################
# 4. 安装前端依赖
###############################################################################
info "安装前端依赖（npm install）..."
npm install
info "依赖安装完成 ✓"

###############################################################################
# 5. 构建前端
###############################################################################
info "构建前端（npm run build）..."
npm run build
info "构建完成 ✓"

###############################################################################
# 6. 启动前端服务
###############################################################################
FRONTEND_PORT="${FRONTEND_PORT:-3000}"
info "启动前端服务（端口 $FRONTEND_PORT）..."
info "访问地址：http://localhost:$FRONTEND_PORT"
info "按 Ctrl+C 停止服务"
echo ""

npm run start -- --port "$FRONTEND_PORT"
