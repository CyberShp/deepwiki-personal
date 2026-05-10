#!/usr/bin/env bash
# DeepWiki 后端启动脚本（Linux / macOS）
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
# 1. 检查 Python 版本（要求 3.11+）
###############################################################################
info "检查 Python 环境..."
if ! command -v python3 &>/dev/null; then
    error "未找到 python3，请先安装 Python 3.11 或更高版本。"
fi
PY_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
PY_MAJOR=$(echo "$PY_VER" | cut -d. -f1)
PY_MINOR=$(echo "$PY_VER" | cut -d. -f2)
if [ "$PY_MAJOR" -lt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 11 ]; }; then
    error "Python 版本过低：$PY_VER，要求 3.11+。"
fi
info "Python 版本：$PY_VER ✓"

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
# 3. 安装 Python 依赖
###############################################################################
info "安装 Python 依赖..."
if command -v uv &>/dev/null; then
    info "使用 uv 安装依赖..."
    uv sync --directory api/ 2>/dev/null || \
        uv pip install fastapi "uvicorn[standard]" pydantic tiktoken adalflow numpy faiss-cpu \
            langid requests jinja2 python-dotenv openai ollama aiohttp boto3 \
            websockets azure-identity azure-core google-generativeai
elif command -v pip3 &>/dev/null; then
    info "使用 pip3 安装依赖..."
    pip3 install fastapi "uvicorn[standard]" pydantic tiktoken adalflow numpy faiss-cpu \
        langid requests jinja2 python-dotenv openai ollama aiohttp boto3 \
        websockets azure-identity azure-core google-generativeai
else
    error "未找到 uv 或 pip3，请先安装 Python 包管理器。"
fi
info "依赖安装完成 ✓"

###############################################################################
# 4. 预缓存 tiktoken 编码文件（离线环境必需）
###############################################################################
TIKTOKEN_CACHE_DIR="${TIKTOKEN_CACHE_DIR:-$HOME/.tiktoken}"
if [ -d "$TIKTOKEN_CACHE_DIR" ] && [ -n "$(ls -A "$TIKTOKEN_CACHE_DIR" 2>/dev/null)" ]; then
    info "tiktoken 缓存已存在：$TIKTOKEN_CACHE_DIR ✓"
else
    info "预缓存 tiktoken 编码文件到 $TIKTOKEN_CACHE_DIR ..."
    mkdir -p "$TIKTOKEN_CACHE_DIR"
    TIKTOKEN_CACHE_DIR="$TIKTOKEN_CACHE_DIR" python3 -c "
import tiktoken
print('  下载 cl100k_base...')
tiktoken.get_encoding('cl100k_base')
print('  下载 text-embedding-3-small...')
tiktoken.encoding_for_model('text-embedding-3-small')
print('  tiktoken 预缓存完成。')
" || warn "tiktoken 预缓存失败（离线环境可能无法下载），请手动复制缓存文件到 $TIKTOKEN_CACHE_DIR"
fi
export TIKTOKEN_CACHE_DIR

###############################################################################
# 5. SSL 证书检查
###############################################################################
if [ -z "$SSL_CERT_FILE" ] && [ -z "$REQUESTS_CA_BUNDLE" ]; then
    warn "未设置 SSL_CERT_FILE / REQUESTS_CA_BUNDLE。"
    warn "如果内网 LLM 使用自签名证书，请在 .env 中配置这两个变量。"
    warn "示例：SSL_CERT_FILE=/path/to/your-ca-bundle.crt"
else
    info "SSL 证书变量已配置 ✓"
    [ -n "$SSL_CERT_FILE" ] && info "  SSL_CERT_FILE=$SSL_CERT_FILE"
    [ -n "$REQUESTS_CA_BUNDLE" ] && info "  REQUESTS_CA_BUNDLE=$REQUESTS_CA_BUNDLE"
fi

###############################################################################
# 6. 启动 FastAPI 后端
###############################################################################
PORT="${PORT:-8001}"
info "启动后端服务（端口 $PORT）..."
info "API 文档地址：http://localhost:$PORT/docs"
info "按 Ctrl+C 停止服务"
echo ""

if command -v uv &>/dev/null; then
    uv run -m api.main
else
    python3 -m api.main
fi
