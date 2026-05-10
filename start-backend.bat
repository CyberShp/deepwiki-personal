@echo off
REM DeepWiki 后端启动脚本（Windows）
REM 用途：裸机部署，无需 Docker
REM 在项目根目录下以管理员或普通用户权限运行均可

setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

echo.
echo ========================================
echo   DeepWiki 后端启动脚本 (Windows)
echo ========================================
echo.

REM =============================================================================
REM 1. 检查 Python 版本（要求 3.11+）
REM =============================================================================
echo [INFO]  检查 Python 环境...
where python >nul 2>&1
if errorlevel 1 (
    echo [ERROR] 未找到 python，请先安装 Python 3.11 或更高版本。
    echo         下载地址：https://www.python.org/downloads/
    pause
    exit /b 1
)

for /f "tokens=*" %%i in ('python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"') do set PY_VER=%%i
echo [INFO]  Python 版本：%PY_VER%

for /f "tokens=1,2 delims=." %%a in ("%PY_VER%") do (
    set PY_MAJOR=%%a
    set PY_MINOR=%%b
)
if !PY_MAJOR! LSS 3 (
    echo [ERROR] Python 版本过低：%PY_VER%，要求 3.11+。
    pause
    exit /b 1
)
if !PY_MAJOR! EQU 3 if !PY_MINOR! LSS 11 (
    echo [ERROR] Python 版本过低：%PY_VER%，要求 3.11+。
    pause
    exit /b 1
)
echo [INFO]  Python 版本检查通过 ✓

REM =============================================================================
REM 2. 加载 .env 文件（如果存在）
REM =============================================================================
if exist "%SCRIPT_DIR%.env" (
    echo [INFO]  加载 .env 文件...
    for /f "usebackq tokens=1,* delims==" %%a in ("%SCRIPT_DIR%.env") do (
        set "LINE=%%a"
        if not "!LINE:~0,1!"=="#" (
            if not "%%a"=="" (
                set "%%a=%%b"
            )
        )
    )
)

REM =============================================================================
REM 3. 安装 Python 依赖
REM =============================================================================
echo [INFO]  安装 Python 依赖...
where uv >nul 2>&1
if not errorlevel 1 (
    echo [INFO]  使用 uv 安装依赖...
    uv sync --directory api\
    if errorlevel 1 (
        uv pip install fastapi "uvicorn[standard]" pydantic tiktoken adalflow numpy faiss-cpu langid requests jinja2 python-dotenv openai ollama aiohttp boto3 websockets azure-identity azure-core google-generativeai
    )
) else (
    echo [INFO]  使用 pip 安装依赖...
    python -m pip install fastapi "uvicorn[standard]" pydantic tiktoken adalflow numpy faiss-cpu langid requests jinja2 python-dotenv openai ollama aiohttp boto3 websockets azure-identity azure-core google-generativeai
    if errorlevel 1 (
        echo [ERROR] 依赖安装失败，请检查网络连接或离线包。
        pause
        exit /b 1
    )
)
echo [INFO]  依赖安装完成 ✓

REM =============================================================================
REM 4. 预缓存 tiktoken 编码文件（离线环境必需）
REM =============================================================================
if "%TIKTOKEN_CACHE_DIR%"=="" (
    set "TIKTOKEN_CACHE_DIR=%USERPROFILE%\.tiktoken"
)
echo [INFO]  tiktoken 缓存目录：%TIKTOKEN_CACHE_DIR%

if exist "%TIKTOKEN_CACHE_DIR%\" (
    dir /b "%TIKTOKEN_CACHE_DIR%" 2>nul | findstr /r "." >nul 2>&1
    if not errorlevel 1 (
        echo [INFO]  tiktoken 缓存已存在 ✓
        goto tiktoken_done
    )
)

echo [INFO]  预缓存 tiktoken 编码文件...
if not exist "%TIKTOKEN_CACHE_DIR%\" mkdir "%TIKTOKEN_CACHE_DIR%"
python -c "import os; os.environ['TIKTOKEN_CACHE_DIR']=r'%TIKTOKEN_CACHE_DIR%'; import tiktoken; print('  下载 cl100k_base...'); tiktoken.get_encoding('cl100k_base'); print('  下载 text-embedding-3-small...'); tiktoken.encoding_for_model('text-embedding-3-small'); print('  tiktoken 预缓存完成。')"
if errorlevel 1 (
    echo [WARN]  tiktoken 预缓存失败（离线环境可能无法下载）
    echo [WARN]  请手动复制缓存文件到 %TIKTOKEN_CACHE_DIR%
    echo [WARN]  参考文档：docs\INTRANET_DEPLOYMENT.md
)

:tiktoken_done

REM =============================================================================
REM 5. SSL 证书检查
REM =============================================================================
if "%SSL_CERT_FILE%"=="" if "%REQUESTS_CA_BUNDLE%"=="" (
    echo [WARN]  未设置 SSL_CERT_FILE / REQUESTS_CA_BUNDLE。
    echo [WARN]  如果内网 LLM 使用自签名证书，请在 .env 中配置这两个变量。
    echo [WARN]  示例：SSL_CERT_FILE=C:\path\to\your-ca-bundle.crt
) else (
    echo [INFO]  SSL 证书变量已配置 ✓
    if not "%SSL_CERT_FILE%"=="" echo [INFO]    SSL_CERT_FILE=%SSL_CERT_FILE%
    if not "%REQUESTS_CA_BUNDLE%"=="" echo [INFO]    REQUESTS_CA_BUNDLE=%REQUESTS_CA_BUNDLE%
)

REM =============================================================================
REM 6. 启动 FastAPI 后端
REM =============================================================================
if "%PORT%"=="" set PORT=8001
echo.
echo [INFO]  启动后端服务（端口 %PORT%）...
echo [INFO]  API 文档地址：http://localhost:%PORT%/docs
echo [INFO]  按 Ctrl+C 停止服务
echo.

where uv >nul 2>&1
if not errorlevel 1 (
    uv run -m api.main
) else (
    python -m api.main
)

if errorlevel 1 (
    echo.
    echo [ERROR] 后端服务异常退出，错误码：%errorlevel%
    pause
)

endlocal
