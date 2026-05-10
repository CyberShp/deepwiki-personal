@echo off
REM DeepWiki 离线环境准备脚本（Windows）
REM
REM 使用场景：在【有网络】的机器上运行，预下载所有依赖，
REM 然后将生成的 offline-packages\ 目录拷贝到内网机器使用。
REM
REM 生成产物：
REM   offline-packages\
REM   ├── python-wheels\   Python 依赖 wheel 包
REM   ├── npm-cache\       npm 离线缓存
REM   ├── tiktoken-cache\  tiktoken BPE 编码文件
REM   └── README.txt       离线安装说明

setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

set "OFFLINE_DIR=%SCRIPT_DIR%offline-packages"

echo.
echo ============================================================
echo   DeepWiki 离线包准备脚本（Windows，需要网络连接）
echo ============================================================
echo.
echo   运行此脚本后，将在以下目录生成离线安装包：
echo   %OFFLINE_DIR%
echo.
echo   将该目录复制到内网机器后，按 README.txt 的说明安装。
echo.

REM =============================================================================
REM 前置检查
REM =============================================================================
where python >nul 2>&1
if errorlevel 1 (
    echo [ERROR] 未找到 python，请先安装 Python 3.11+。
    pause
    exit /b 1
)
where node >nul 2>&1
if errorlevel 1 (
    echo [ERROR] 未找到 node，请先安装 Node.js 18+。
    pause
    exit /b 1
)
where npm >nul 2>&1
if errorlevel 1 (
    echo [ERROR] 未找到 npm，请确认 Node.js 安装完整。
    pause
    exit /b 1
)

echo [INFO]  前置环境检查通过 ✓
echo.

if not exist "%OFFLINE_DIR%\" mkdir "%OFFLINE_DIR%"

REM =============================================================================
REM Step 1: 下载 Python wheel 包
REM =============================================================================
echo.
echo === 1. 下载 Python 依赖 wheel 包 ===
set "WHEEL_DIR=%OFFLINE_DIR%\python-wheels"
if not exist "%WHEEL_DIR%\" mkdir "%WHEEL_DIR%"
echo [INFO]  下载 wheel 到 %WHEEL_DIR% ...
python -m pip download ^
    fastapi "uvicorn[standard]" pydantic tiktoken adalflow numpy faiss-cpu ^
    langid requests jinja2 python-dotenv openai ollama aiohttp boto3 ^
    websockets azure-identity azure-core google-generativeai ^
    --dest "%WHEEL_DIR%"
if errorlevel 1 (
    echo [ERROR] Python wheel 下载失败，请检查网络连接。
    pause
    exit /b 1
)
echo [INFO]  Python wheel 下载完成 ✓

REM =============================================================================
REM Step 2: 下载 npm 离线缓存
REM =============================================================================
echo.
echo === 2. 下载 npm 依赖缓存 ===
set "NPM_CACHE_DIR=%OFFLINE_DIR%\npm-cache"
if not exist "%NPM_CACHE_DIR%\" mkdir "%NPM_CACHE_DIR%"
echo [INFO]  通过 npm install 填充本地缓存 %NPM_CACHE_DIR% ...
npm install --cache "%NPM_CACHE_DIR%"
if errorlevel 1 (
    echo [ERROR] npm install 失败，请检查网络连接。
    pause
    exit /b 1
)
echo [INFO]  npm 缓存准备完成 ✓

REM =============================================================================
REM Step 3: 下载 tiktoken BPE 缓存
REM =============================================================================
echo.
echo === 3. 下载 tiktoken 编码文件 ===
set "TIKTOKEN_DIR=%OFFLINE_DIR%\tiktoken-cache"
if not exist "%TIKTOKEN_DIR%\" mkdir "%TIKTOKEN_DIR%"
echo [INFO]  下载 tiktoken 编码文件到 %TIKTOKEN_DIR% ...
python -c "import os; os.environ['TIKTOKEN_CACHE_DIR']=r'%TIKTOKEN_DIR%'; import tiktoken; print('  下载 cl100k_base...'); tiktoken.get_encoding('cl100k_base'); print('  下载 text-embedding-3-small...'); tiktoken.encoding_for_model('text-embedding-3-small'); print('  完成。')"
if errorlevel 1 (
    echo [ERROR] tiktoken 下载失败，请检查网络连接。
    pause
    exit /b 1
)
echo [INFO]  tiktoken 缓存准备完成 ✓

REM =============================================================================
REM Step 4: 生成离线安装说明
REM =============================================================================
echo.
echo === 4. 生成离线安装说明 ===
(
echo DeepWiki 离线安装说明
echo ======================
echo.
echo 将 offline-packages\ 目录整体复制到内网机器的项目根目录下，然后执行以下步骤：
echo.
echo --- Windows ---
echo.
echo 1. 安装 Python 依赖（离线）：
echo    python -m pip install --no-index --find-links=offline-packages\python-wheels ^
echo        fastapi "uvicorn[standard]" pydantic tiktoken adalflow numpy faiss-cpu ^
echo        langid requests jinja2 python-dotenv openai ollama aiohttp boto3 ^
echo        websockets azure-identity azure-core google-generativeai
echo.
echo 2. 复制 tiktoken 缓存：
echo    mkdir %%USERPROFILE%%\.tiktoken
echo    copy offline-packages\tiktoken-cache\* %%USERPROFILE%%\.tiktoken\
echo.
echo 3. 安装 npm 依赖（离线）：
echo    npm install --cache offline-packages\npm-cache --prefer-offline --offline
echo.
echo 4. 在 .env 文件中设置（将 USERNAME 替换为实际用户名）：
echo    TIKTOKEN_CACHE_DIR=C:\Users\USERNAME\.tiktoken
echo.
echo 5. 在两个命令行窗口分别运行：
echo    start-backend.bat
echo    start-frontend.bat
echo.
echo --- Linux/macOS ---
echo.
echo 1. pip3 install --no-index --find-links=offline-packages/python-wheels \
echo        fastapi "uvicorn[standard]" pydantic ... （完整列表见 api/pyproject.toml）
echo.
echo 2. cp offline-packages/tiktoken-cache/* ~/.tiktoken/
echo    export TIKTOKEN_CACHE_DIR=~/.tiktoken
echo.
echo 3. npm install --cache offline-packages/npm-cache --prefer-offline --offline
echo.
echo 4. chmod +x start-backend.sh start-frontend.sh
echo    TIKTOKEN_CACHE_DIR=~/.tiktoken ./start-backend.sh
echo    ./start-frontend.sh
echo.
echo 注意：
echo - 内网机器需已安装 Python 3.11+ 和 Node.js 18+
echo - 更多文档请参考 docs\INTRANET_DEPLOYMENT.md
) > "%OFFLINE_DIR%\README.txt"

echo [INFO]  离线安装说明已生成：%OFFLINE_DIR%\README.txt ✓

REM =============================================================================
REM 完成
REM =============================================================================
echo.
echo ============================================================
echo   离线包准备完成！
echo   目录：%OFFLINE_DIR%
echo.
echo   下一步：
echo   1. 将 offline-packages\ 目录复制到内网机器的项目根目录
echo   2. 按照 offline-packages\README.txt 的步骤安装
echo ============================================================
echo.

pause
endlocal
