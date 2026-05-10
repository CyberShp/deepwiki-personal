#!/usr/bin/env bash
# DeepWiki 离线环境准备脚本（Linux / macOS）
#
# 使用场景：在【有网络】的机器上运行，预下载所有依赖，
# 然后将生成的离线包拷贝到内网机器上使用。
#
# 生成产物：
#   offline-packages/
#   ├── python-wheels/     Python 依赖 wheel 包
#   ├── npm-cache/         npm 离线缓存
#   ├── tiktoken-cache/    tiktoken BPE 编码文件
#   └── README.txt         离线安装说明

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OFFLINE_DIR="$SCRIPT_DIR/offline-packages"

info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }
step()  { echo ""; echo "=== $* ==="; }

echo ""
echo "============================================================"
echo "  DeepWiki 离线包准备脚本（需要网络连接）"
echo "============================================================"
echo ""
echo "  运行此脚本后，将在以下目录生成离线安装包："
echo "  $OFFLINE_DIR"
echo ""
echo "  将该目录复制到内网机器后，按 README.txt 的说明安装。"
echo ""

###############################################################################
# 前置检查
###############################################################################
if ! command -v python3 &>/dev/null; then
    error "未找到 python3，请先安装 Python 3.11+。"
fi
if ! command -v pip3 &>/dev/null; then
    error "未找到 pip3，请确认 Python 安装完整。"
fi
if ! command -v node &>/dev/null; then
    error "未找到 node，请先安装 Node.js 18+。"
fi
if ! command -v npm &>/dev/null; then
    error "未找到 npm，请确认 Node.js 安装完整。"
fi

# 确认网络可达
if ! curl -s --max-time 5 https://pypi.org/pypi/pip/json >/dev/null 2>&1; then
    warn "无法访问 pypi.org，请确认网络连接后再运行本脚本。"
    read -r -p "是否仍要继续？[y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
fi

mkdir -p "$OFFLINE_DIR"

###############################################################################
# Step 1: 下载 Python wheel 包
###############################################################################
step "1. 下载 Python 依赖 wheel 包"
WHEEL_DIR="$OFFLINE_DIR/python-wheels"
mkdir -p "$WHEEL_DIR"
info "下载 wheel 到 $WHEEL_DIR ..."
pip3 download \
    fastapi "uvicorn[standard]" pydantic tiktoken adalflow numpy faiss-cpu \
    langid requests jinja2 python-dotenv openai ollama aiohttp boto3 \
    websockets azure-identity azure-core google-generativeai \
    --dest "$WHEEL_DIR"
info "Python wheel 下载完成 ✓  ($(ls "$WHEEL_DIR" | wc -l) 个文件)"

###############################################################################
# Step 2: 下载 npm 离线缓存
###############################################################################
step "2. 下载 npm 依赖缓存"
NPM_CACHE_DIR="$OFFLINE_DIR/npm-cache"
mkdir -p "$NPM_CACHE_DIR"
info "通过 npm install 填充本地缓存 $NPM_CACHE_DIR ..."
npm install --cache "$NPM_CACHE_DIR" --prefer-offline 2>/dev/null || npm install --cache "$NPM_CACHE_DIR"
info "npm 缓存准备完成 ✓"

###############################################################################
# Step 3: 下载 tiktoken BPE 缓存
###############################################################################
step "3. 下载 tiktoken 编码文件"
TIKTOKEN_DIR="$OFFLINE_DIR/tiktoken-cache"
mkdir -p "$TIKTOKEN_DIR"
info "下载 tiktoken 编码文件到 $TIKTOKEN_DIR ..."
TIKTOKEN_CACHE_DIR="$TIKTOKEN_DIR" python3 -c "
import tiktoken
print('  下载 cl100k_base...')
tiktoken.get_encoding('cl100k_base')
print('  下载 text-embedding-3-small...')
tiktoken.encoding_for_model('text-embedding-3-small')
print('  完成。')
"
info "tiktoken 缓存准备完成 ✓  ($(ls "$TIKTOKEN_DIR" | wc -l) 个文件)"
ls -lh "$TIKTOKEN_DIR"

###############################################################################
# Step 4: 生成离线安装说明
###############################################################################
step "4. 生成离线安装说明"
cat > "$OFFLINE_DIR/README.txt" << 'OFFLINE_README'
DeepWiki 离线安装说明
======================

将 offline-packages/ 目录整体复制到内网机器的项目根目录下，然后执行以下步骤：

--- Linux/macOS ---

1. 安装 Python 依赖（离线）：
   pip3 install --no-index --find-links=offline-packages/python-wheels \
       fastapi "uvicorn[standard]" pydantic tiktoken adalflow numpy faiss-cpu \
       langid requests jinja2 python-dotenv openai ollama aiohttp boto3 \
       websockets azure-identity azure-core google-generativeai

2. 复制 tiktoken 缓存：
   mkdir -p ~/.tiktoken
   cp offline-packages/tiktoken-cache/* ~/.tiktoken/
   export TIKTOKEN_CACHE_DIR=~/.tiktoken

3. 安装 npm 依赖（离线）：
   npm install --cache offline-packages/npm-cache --prefer-offline --offline

4. 构建并启动：
   chmod +x start-backend.sh start-frontend.sh
   # 终端 1：
   TIKTOKEN_CACHE_DIR=~/.tiktoken ./start-backend.sh
   # 终端 2：
   ./start-frontend.sh

--- Windows ---

1. 安装 Python 依赖（离线）：
   python -m pip install --no-index --find-links=offline-packages\python-wheels ^
       fastapi "uvicorn[standard]" pydantic tiktoken adalflow numpy faiss-cpu ^
       langid requests jinja2 python-dotenv openai ollama aiohttp boto3 ^
       websockets azure-identity azure-core google-generativeai

2. 复制 tiktoken 缓存：
   mkdir %USERPROFILE%\.tiktoken
   copy offline-packages\tiktoken-cache\* %USERPROFILE%\.tiktoken\

3. 安装 npm 依赖（离线）：
   npm install --cache offline-packages\npm-cache --prefer-offline --offline

4. 在 .env 文件中设置 TIKTOKEN_CACHE_DIR：
   TIKTOKEN_CACHE_DIR=C:\Users\<你的用户名>\.tiktoken

5. 在两个命令行窗口分别运行：
   start-backend.bat
   start-frontend.bat

注意：
- 内网机器需要已安装 Python 3.11+ 和 Node.js 18+（运行时无法离线打包）
- 如遇依赖版本冲突，请检查 api/pyproject.toml 中的版本要求
- 更多文档请参考 docs/INTRANET_DEPLOYMENT.md
OFFLINE_README

info "离线安装说明已生成：$OFFLINE_DIR/README.txt ✓"

###############################################################################
# 完成
###############################################################################
echo ""
echo "============================================================"
echo "  离线包准备完成！"
echo "  目录：$OFFLINE_DIR"
echo ""
du -sh "$OFFLINE_DIR"
echo ""
echo "  下一步："
echo "  1. 将 offline-packages/ 目录复制到内网机器的项目根目录"
echo "  2. 按照 offline-packages/README.txt 的步骤安装"
echo "============================================================"
echo ""
