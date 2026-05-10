@echo off
REM DeepWiki 前端启动脚本（Windows）
REM 用途：裸机部署，无需 Docker
REM 在项目根目录下双击运行或从命令行执行

setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

echo.
echo ========================================
echo   DeepWiki 前端启动脚本 (Windows)
echo ========================================
echo.

REM =============================================================================
REM 1. 检查 Node.js 版本（要求 18+）
REM =============================================================================
echo [INFO]  检查 Node.js 环境...
where node >nul 2>&1
if errorlevel 1 (
    echo [ERROR] 未找到 node，请先安装 Node.js 18 或更高版本。
    echo         下载地址：https://nodejs.org/
    pause
    exit /b 1
)

for /f "tokens=*" %%i in ('node --version') do set NODE_VER=%%i
set NODE_VER=%NODE_VER:v=%
echo [INFO]  Node.js 版本：v%NODE_VER%

for /f "tokens=1 delims=." %%a in ("%NODE_VER%") do set NODE_MAJOR=%%a
if !NODE_MAJOR! LSS 18 (
    echo [ERROR] Node.js 版本过低：v%NODE_VER%，要求 18+。
    pause
    exit /b 1
)
echo [INFO]  Node.js 版本检查通过 ✓

where npm >nul 2>&1
if errorlevel 1 (
    echo [ERROR] 未找到 npm，请确认 Node.js 安装完整。
    pause
    exit /b 1
)
for /f "tokens=*" %%i in ('npm --version') do set NPM_VER=%%i
echo [INFO]  npm 版本：v%NPM_VER% ✓

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
REM 3. 检查后端地址配置
REM =============================================================================
if "%SERVER_BASE_URL%"=="" set SERVER_BASE_URL=http://localhost:8001
echo [INFO]  后端 API 地址：%SERVER_BASE_URL%

REM =============================================================================
REM 4. 安装前端依赖
REM =============================================================================
echo [INFO]  安装前端依赖（npm install）...
npm install
if errorlevel 1 (
    echo [ERROR] npm install 失败，请检查 Node.js 环境或离线包。
    pause
    exit /b 1
)
echo [INFO]  依赖安装完成 ✓

REM =============================================================================
REM 5. 构建前端
REM =============================================================================
echo [INFO]  构建前端（npm run build）...
npm run build
if errorlevel 1 (
    echo [ERROR] 前端构建失败，请检查错误信息。
    pause
    exit /b 1
)
echo [INFO]  构建完成 ✓

REM =============================================================================
REM 6. 启动前端服务
REM =============================================================================
if "%FRONTEND_PORT%"=="" set FRONTEND_PORT=3000
echo.
echo [INFO]  启动前端服务（端口 %FRONTEND_PORT%）...
echo [INFO]  访问地址：http://localhost:%FRONTEND_PORT%
echo [INFO]  按 Ctrl+C 停止服务
echo.

npm run start -- --port %FRONTEND_PORT%

if errorlevel 1 (
    echo.
    echo [ERROR] 前端服务异常退出，错误码：%errorlevel%
    pause
)

endlocal
