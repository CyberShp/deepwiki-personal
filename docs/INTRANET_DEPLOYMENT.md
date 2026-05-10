# DeepWiki 内网部署指南

本指南适用于在无法访问公网的企业内网环境中部署 DeepWiki。

---

## 目录

1. [环境变量清单](#环境变量清单)
2. [裸机部署（无 Docker）](#裸机部署无-docker)
3. [常见问题排查](#常见问题排查)

---

## 环境变量清单

### 必填变量

| 变量名 | 说明 | 示例值 |
|--------|------|--------|
| `OPENAI_API_KEY` | OpenAI API 密钥（或兼容接口密钥） | `sk-...` |
| `GOOGLE_API_KEY` | Google API 密钥（使用 Google 模型时必填） | `AIza...` |

> 如果使用内网自定义 LLM（如 OpenAI 兼容接口），`OPENAI_API_KEY` 填入对应密钥即可，`GOOGLE_API_KEY` 可留空。

### 可选变量 — 服务配置

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `PORT` | API 后端监听端口 | `8001` |
| `NODE_ENV` | Node.js 运行环境 | `production` |
| `SERVER_BASE_URL` | 前端访问后端的基础 URL | `http://localhost:8001` |
| `LOG_LEVEL` | 日志级别 (`DEBUG`/`INFO`/`WARNING`/`ERROR`) | `INFO` |
| `LOG_FILE_PATH` | 日志文件路径 | `api/logs/application.log` |

### 可选变量 — 自定义 LLM 接入

| 变量名 | 说明 | 示例值 |
|--------|------|--------|
| `OPENAI_API_KEY` | OpenAI 兼容接口的 API Key | `your-custom-key` |
| `OPENAI_BASE_URL` | 自定义 LLM 的 API 地址（OpenAI 兼容格式） | `https://llm.intranet.company.com/v1` |
| `OPENROUTER_API_KEY` | OpenRouter API 密钥（如使用 OpenRouter） | `or-...` |
| `DASHSCOPE_API_KEY` | 阿里云 DashScope API 密钥 | `sk-...` |
| `DEEPWIKI_CONFIG_DIR` | 自定义配置目录路径（覆盖 `api/config/`） | `/app/custom-config` |

### 可选变量 — SSL 证书

| 变量名 | 说明 | 示例值 |
|--------|------|--------|
| `SSL_CERT_FILE` | Python SSL 证书捆绑包路径 | `/etc/ssl/certs/ca-certificates.crt` |
| `REQUESTS_CA_BUNDLE` | requests/httpx 库的证书捆绑包路径 | `/etc/ssl/certs/ca-certificates.crt` |
| `GIT_SSL_CAINFO` | Git 使用的 CA 证书文件路径 | `/etc/ssl/certs/ca-certificates.crt` |
| `GIT_SSL_NO_VERIFY` | 跳过 Git SSL 验证（不推荐，仅测试用） | `true` |

### 可选变量 — tiktoken 离线缓存

| 变量名 | 说明 | 示例值 |
|--------|------|--------|
| `TIKTOKEN_CACHE_DIR` | tiktoken 编码文件的本地缓存目录 | `/opt/tiktoken_cache` |

### 可选变量 — 认证

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `DEEPWIKI_AUTH_MODE` | 启用访问码认证 | `False` |
| `DEEPWIKI_AUTH_CODE` | 访问码（`AUTH_MODE=true` 时必填） | （自定义） |

### 可选变量 — Embedding 配置

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `DEEPWIKI_EMBEDDER_TYPE` | Embedding 类型 (`openai`/`google`/`ollama`/`bedrock`) | `openai` |

---

## 裸机部署（无 Docker）

适用场景：内网 PC 不允许安装 Docker，需要直接在操作系统上运行前后端服务。

### 环境要求

| 组件 | 最低版本 | 推荐版本 | 说明 |
|------|---------|---------|------|
| Python | 3.11 | 3.11 / 3.12 | 后端运行时 |
| Node.js | 18 | 20 LTS | 前端运行时 |
| npm | 9 | 10+ | 随 Node.js 一起安装 |
| uv（可选） | — | 最新 | Python 包管理器，推荐使用 |

> **Windows 用户**：推荐从 [python.org](https://www.python.org/downloads/) 下载 Python，
> 从 [nodejs.org](https://nodejs.org/) 下载 Node.js LTS 版本。安装时勾选"Add to PATH"。

---

### 快速开始（推荐方式）

项目提供了开箱即用的启动脚本，**绝大多数情况下只需两步**：

#### 第一步：配置环境变量

```bash
# Linux/macOS
cp .env.example .env
# 编辑 .env，填入 LLM API 密钥等必要配置

# Windows
copy .env.example .env
# 用记事本或 VS Code 编辑 .env
```

`.env` 文件的关键配置（内网场景）：

```dotenv
# 内网 LLM（OpenAI 兼容接口）
CUSTOM_LLM_BASE_URL=http://llm.intranet.company.com/v1
CUSTOM_LLM_API_KEY=your-llm-key
CUSTOM_LLM_MODEL=your-model-name

# 自签名证书（如内网 LLM 使用 HTTPS）
SSL_CERT_FILE=C:\certs\internal-ca.crt
REQUESTS_CA_BUNDLE=C:\certs\internal-ca.crt

# tiktoken 离线缓存（离线部署必填）
TIKTOKEN_CACHE_DIR=C:\Users\your-username\.tiktoken
```

#### 第二步：运行启动脚本

**Windows**（在两个命令行窗口分别执行）：

```bat
REM 窗口 1：启动后端
start-backend.bat

REM 窗口 2：启动前端（等后端启动后再执行）
start-frontend.bat
```

**Linux / macOS**（在两个终端窗口分别执行）：

```bash
# 窗口 1：启动后端
chmod +x start-backend.sh start-frontend.sh
./start-backend.sh

# 窗口 2：启动前端
./start-frontend.sh
```

启动成功后：
- 后端 API：`http://localhost:8001`（或 `http://localhost:{PORT}`）
- 前端界面：`http://localhost:3000`（或 `http://localhost:{FRONTEND_PORT}`）

---

### 手动安装步骤（详细说明）

如果启动脚本报错，或需要了解每一步的细节，请参考以下手动流程。

#### 1. 安装 Python 依赖

**推荐：使用 uv**

```bash
# 安装 uv（如未安装）
# Linux/macOS:
curl -LsSf https://astral.sh/uv/install.sh | sh
# Windows PowerShell:
powershell -c "irm https://astral.sh/uv/install.ps1 | iex"

# 在项目根目录安装后端依赖
uv sync --directory api/
```

**备选：使用 pip**

```bash
# Linux/macOS
pip3 install fastapi "uvicorn[standard]" pydantic tiktoken adalflow numpy faiss-cpu \
    langid requests jinja2 python-dotenv openai ollama aiohttp boto3 \
    websockets azure-identity azure-core google-generativeai

# Windows
python -m pip install fastapi "uvicorn[standard]" pydantic tiktoken adalflow numpy faiss-cpu ^
    langid requests jinja2 python-dotenv openai ollama aiohttp boto3 ^
    websockets azure-identity azure-core google-generativeai
```

#### 2. tiktoken 离线缓存

内网环境首次启动时，tiktoken 会尝试从 `cdn.openai.com` 下载编码文件。若网络不通，服务将启动失败。**必须提前缓存。**

**在有网络的机器上预下载：**

```bash
# Linux/macOS
mkdir -p ~/.tiktoken
TIKTOKEN_CACHE_DIR=~/.tiktoken python3 -c "
import tiktoken
tiktoken.get_encoding('cl100k_base')
tiktoken.encoding_for_model('text-embedding-3-small')
print('缓存文件已下载到 ~/.tiktoken/')
"

# Windows（命令提示符）
mkdir %USERPROFILE%\.tiktoken
python -c "import os; os.environ['TIKTOKEN_CACHE_DIR']=r'%USERPROFILE%\.tiktoken'; import tiktoken; tiktoken.get_encoding('cl100k_base'); tiktoken.encoding_for_model('text-embedding-3-small'); print('完成')"
```

**将缓存文件复制到内网机器：**

```bash
# 缓存文件通常在 ~/.tiktoken/（Linux/macOS）
# 或 %USERPROFILE%\.tiktoken\（Windows）
# 复制该目录到内网机器的同一路径即可

# 然后在 .env 中配置：
# TIKTOKEN_CACHE_DIR=C:\Users\your-username\.tiktoken
```

#### 3. SSL 证书配置

如果内网 LLM 或 Git 仓库使用自签名 HTTPS 证书：

**导出 Windows 系统证书：**

```powershell
# 找到证书颁发机构名称（证书管理器中查看）
# 方法 1：导出 PEM 格式
$cert = Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object { $_.Subject -like "*InternalCA*" }
$cert | Export-Certificate -FilePath C:\certs\internal-ca.cer -Type CERT
# 转换为 PEM 格式（需要 OpenSSL）
openssl x509 -inform DER -in C:\certs\internal-ca.cer -out C:\certs\internal-ca.crt

# 方法 2：直接导出 PEM（通过 certmgr.msc 图形界面操作）
# 打开 certmgr.msc → 找到证书 → 右键导出 → 选择 Base-64 encoded X.509 (.CER)
```

**在 `.env` 中配置：**

```dotenv
SSL_CERT_FILE=C:\certs\internal-ca.crt
REQUESTS_CA_BUNDLE=C:\certs\internal-ca.crt
GIT_SSL_CAINFO=C:\certs\internal-ca.crt
```

#### 4. 安装前端依赖并构建

```bash
# 安装依赖
npm install

# 构建（生产模式）
npm run build
```

#### 5. 启动服务

**后端：**

```bash
# Linux/macOS（使用 uv）
uv run -m api.main

# Linux/macOS（使用 python3）
python3 -m api.main

# Windows（使用 uv）
uv run -m api.main

# Windows（使用 python）
python -m api.main
```

**前端：**

```bash
# 默认端口 3000
npm run start

# 指定端口
npm run start -- --port 3000
```

---

### 离线环境准备

如果内网机器完全无法联网，需要在有网络的机器上提前下载所有依赖。

**一键准备（推荐）：**

```bash
# Linux/macOS
chmod +x setup-offline.sh
./setup-offline.sh

# Windows
setup-offline.bat
```

脚本执行完成后，会生成 `offline-packages/` 目录，包含：
- `python-wheels/` — 所有 Python 依赖的 wheel 包
- `npm-cache/` — npm 包缓存
- `tiktoken-cache/` — tiktoken BPE 编码文件
- `README.txt` — 内网机器安装步骤

将整个 `offline-packages/` 目录复制到内网机器的项目根目录后，按 `README.txt` 操作即可。

**离线安装 Python 依赖：**

```bash
# Linux/macOS
pip3 install --no-index --find-links=offline-packages/python-wheels \
    fastapi "uvicorn[standard]" pydantic tiktoken ...

# Windows
python -m pip install --no-index --find-links=offline-packages\python-wheels ^
    fastapi "uvicorn[standard]" pydantic tiktoken ...
```

**离线安装 npm 依赖：**

```bash
npm install --cache offline-packages/npm-cache --prefer-offline --offline
```

---

### 端到端验证清单（裸机）

部署完成后，按顺序验证：

- [ ] **后端启动不卡死**：命令行输出 `Uvicorn running on http://0.0.0.0:8001`，无 tiktoken 下载超时错误
  ```bash
  curl http://localhost:8001/health
  # 期望返回：{"status": "ok"} 或类似响应
  ```

- [ ] **前端可访问**：浏览器打开 `http://localhost:3000`，页面正常加载

- [ ] **自定义 LLM 可连接**：前端选择目标 provider，发送测试消息，收到正常响应

- [ ] **SSL 证书正常**：LLM API 调用无 `certificate verify failed` 错误（查看后端控制台）

- [ ] **Git 仓库可克隆**：在 DeepWiki 前端输入内网 Git 仓库 URL，仓库索引正常启动

- [ ] **Wiki 生成全流程正常**：选择已索引的仓库，生成 Wiki，页面正常展示内容

---

## 常见问题排查

### 问题 1：后端启动卡在 tiktoken 下载

**症状：** 控制台出现 `Downloading...` 或长时间无响应，网络超时错误。

**原因：** tiktoken 首次运行需要从 `cdn.openai.com` 下载编码文件，内网无法访问。

**解决方案：**

```bash
# 确认 TIKTOKEN_CACHE_DIR 环境变量已设置
echo %TIKTOKEN_CACHE_DIR%          # Windows
echo $TIKTOKEN_CACHE_DIR           # Linux/macOS

# 确认缓存文件存在
dir %TIKTOKEN_CACHE_DIR%           # Windows
ls -la $TIKTOKEN_CACHE_DIR         # Linux/macOS

# 手动测试 tiktoken 加载
python -c "import tiktoken; enc = tiktoken.get_encoding('cl100k_base'); print('OK:', len(enc.encode('test')))"
```

**如缓存目录为空：** 参考 [tiktoken 离线缓存](#2-tiktoken-离线缓存) 章节重新准备缓存文件。

---

### 问题 2：连接内网 LLM 时 SSL 证书验证失败

**症状：** 日志中出现 `SSL: CERTIFICATE_VERIFY_FAILED` 或 `certificate verify failed`。

**原因：** 内网 LLM 使用自签名证书，Python requests/httpx 默认不信任。

**解决方案：**

1. **确认环境变量已设置：**

```bash
# 检查 .env 中是否配置了以下变量
# SSL_CERT_FILE=C:\certs\internal-ca.crt
# REQUESTS_CA_BUNDLE=C:\certs\internal-ca.crt
```

2. **验证证书文件存在且路径正确：**

```bash
# Windows
dir C:\certs\internal-ca.crt

# Linux/macOS
ls -la /path/to/internal-ca.crt
```

3. **临时验证（仅排查用，不用于生产）：**

在 `.env` 中加入：
```dotenv
# 警告：仅用于临时调试，生产环境必须使用正式证书
PYTHONHTTPSVERIFY=0
```

---

### 问题 3：克隆内网 Git 仓库失败

**症状：** `git clone` 报错 `SSL certificate problem: unable to get local issuer certificate`。

**解决方案：**

1. **确认 GIT_SSL_CAINFO 已设置：**

```bash
git config --global http.sslCAInfo
```

2. **手动测试克隆：**

```bash
git clone https://<internal-git-repo> /tmp/test-clone
```

3. **临时跳过 SSL 验证（仅测试用）：**

```bash
git config --global http.sslVerify false
# 或在 .env 中设置 GIT_SSL_NO_VERIFY=true
```

---

### 问题 4：Wiki 生成中途失败

**症状：** Wiki 生成进度停止，日志出现 API 连接错误或超时。

**排查步骤：**

```bash
# 1. 检查 API 服务状态
curl http://localhost:8001/health

# 2. 检查 LLM 连通性（替换为你的 LLM 地址和 Key）
curl -v -H "Authorization: Bearer YOUR_API_KEY" http://your-llm-host:port/v1/models

# 3. 查看后端日志
# 检查启动后端的控制台窗口，关注 ERROR、WARNING、Exception 信息
# 或查看日志文件：api/logs/application.log
```

---

### 问题 5：前端无法选择自定义 LLM

**症状：** 前端无法选择 `custom_openai`，或选择后报模型不存在错误。

**解决方案：**

确认 `.env` 中正确配置了自定义 LLM 变量：

```dotenv
CUSTOM_LLM_BASE_URL=http://your-llm-host:port/v1
CUSTOM_LLM_API_KEY=your-key
CUSTOM_LLM_MODEL=your-model-name
```

如需进一步自定义，可通过 `DEEPWIKI_CONFIG_DIR` 环境变量指向自定义配置目录，覆盖 `api/config/generator.json`。

---

*如有问题，请查看后端控制台输出或日志文件 `api/logs/application.log`*
