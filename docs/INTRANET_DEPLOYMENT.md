# DeepWiki 内网部署指南

本指南适用于在无法访问公网的企业内网环境中部署 DeepWiki。

---

## 目录

1. [环境变量清单](#环境变量清单)
2. [Docker 镜像构建步骤](#docker-镜像构建步骤)
3. [docker-compose 配置示例](#docker-compose-配置示例)
4. [常见问题排查](#常见问题排查)

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
| `TIKTOKEN_CACHE_DIR` | tiktoken 编码文件的本地缓存目录 | `/app/tiktoken_cache` |

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

## Docker 镜像构建步骤

### 1. 准备 tiktoken 离线缓存

tiktoken 在首次运行时会从互联网下载 BPE 编码文件（约 2MB）。内网环境需提前缓存。

**方法一：在有网络的机器上预下载**

```bash
# 在联网机器上安装 tiktoken 并触发缓存下载
pip install tiktoken

python3 -c "
import tiktoken
# 下载 cl100k_base（用于 OpenAI/Ollama/Google/Bedrock 模式）
tiktoken.get_encoding('cl100k_base')
# 下载 text-embedding-3-small 专用编码（用于 OpenAI embedder）
tiktoken.encoding_for_model('text-embedding-3-small')
print('Cache files downloaded.')
"

# 查看缓存路径（通常在 ~/.tiktoken/）
python3 -c "import tiktoken; import os; print(os.path.expanduser('~/.tiktoken/'))"
```

**方法二：在 Dockerfile 构建阶段预缓存**

在 `Dockerfile` 的 `py_deps` 阶段添加：

```dockerfile
FROM python:3.11-slim AS py_deps
# ... (existing setup) ...

# Pre-cache tiktoken encoding files during build
# Requires internet access at build time (not at runtime)
RUN python3 -c "
import tiktoken
tiktoken.get_encoding('cl100k_base')
tiktoken.encoding_for_model('text-embedding-3-small')
"
```

然后在最终镜像中复制缓存并设置环境变量：

```dockerfile
# Copy tiktoken cache from build stage
COPY --from=py_deps /root/.tiktoken /app/tiktoken_cache

# Set tiktoken to use local cache
ENV TIKTOKEN_CACHE_DIR=/app/tiktoken_cache
```

### 2. 准备内网 SSL 证书

如果内网 LLM 或 Git 服务使用自签名证书，需将证书放入 `certs/` 目录（PEM 格式，`.crt` 扩展名）。

```bash
# 项目根目录结构
deepwiki-open/
├── certs/                      # 自签名证书目录（须自行创建）
│   ├── internal-ca.crt         # 内网 CA 根证书
│   └── llm-server.crt          # LLM 服务证书（可选）
├── Dockerfile
└── docker-compose.yml
```

**导出证书（以 Windows 为例）：**

```powershell
# 从 Windows 证书存储导出 PEM 格式
certutil -exportPFX -p "" "CertificateName" cert.pfx
openssl pkcs12 -in cert.pfx -nokeys -out internal-ca.crt
```

**构建镜像（包含证书）：**

```bash
# 构建时证书将被自动安装到系统证书库
docker build \
  --build-arg CUSTOM_CERT_DIR=certs \
  -t deepwiki:intranet \
  .
```

### 3. 完整构建示例

```bash
# 1. 创建证书目录并放入证书
mkdir -p certs
cp /path/to/your-internal-ca.crt certs/

# 2. 创建 tiktoken 缓存目录（如使用方法一）
mkdir -p tiktoken_cache
cp ~/.tiktoken/* tiktoken_cache/

# 3. 构建镜像
docker build \
  --build-arg CUSTOM_CERT_DIR=certs \
  --no-cache \
  -t deepwiki:intranet \
  .

# 4. 验证镜像
docker run --rm deepwiki:intranet python3 -c "
import ssl, certifi
print('SSL cert file:', ssl.get_default_verify_paths())
import tiktoken
enc = tiktoken.get_encoding('cl100k_base')
print('tiktoken OK:', len(enc.encode('hello world')), 'tokens')
"
```

---

## docker-compose 配置示例

以下是适用于内网环境的完整 `docker-compose.yml` 示例：

```yaml
services:
  deepwiki:
    image: deepwiki:intranet          # 使用本地构建的镜像
    # build:                          # 或者在 compose 中直接构建
    #   context: .
    #   dockerfile: Dockerfile
    #   args:
    #     CUSTOM_CERT_DIR: certs
    ports:
      - "${PORT:-8001}:${PORT:-8001}" # API 端口
      - "3000:3000"                   # Next.js 前端端口
    env_file:
      - .env                          # 从 .env 文件读取密钥
    environment:
      # 服务配置
      - PORT=${PORT:-8001}
      - NODE_ENV=production
      - SERVER_BASE_URL=http://localhost:${PORT:-8001}
      - LOG_LEVEL=${LOG_LEVEL:-INFO}
      - LOG_FILE_PATH=${LOG_FILE_PATH:-api/logs/application.log}

      # SSL 证书路径（自签名证书场景）
      - SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
      - REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

      # Git SSL 证书（内网 Git 仓库场景）
      - GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt

      # tiktoken 离线缓存
      - TIKTOKEN_CACHE_DIR=/app/tiktoken_cache

      # 自定义 LLM（OpenAI 兼容接口示例）
      # - OPENAI_BASE_URL=https://llm.intranet.company.com/v1
      # - OPENAI_API_KEY=your-intranet-llm-key

    volumes:
      # 持久化 adalflow 数据（仓库和 Embedding 数据库）
      - ~/.adalflow:/root/.adalflow

      # 持久化日志
      - ./api/logs:/app/api/logs

      # 挂载 tiktoken 离线缓存（如未打入镜像）
      # - ./tiktoken_cache:/app/tiktoken_cache:ro

      # 挂载自定义 LLM 配置（可选）
      # - ./custom-config:/app/custom-config:ro

    mem_limit: 6g
    mem_reservation: 2g

    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:${PORT:-8001}/health"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 30s
```

### .env 文件示例

```dotenv
# LLM API 密钥
OPENAI_API_KEY=your-key-here
# GOOGLE_API_KEY=your-google-key-here

# 内网 LLM 接口（OpenAI 兼容）
# OPENAI_BASE_URL=https://llm.intranet.company.com/v1

# Embedding 类型（openai/google/ollama/bedrock）
DEEPWIKI_EMBEDDER_TYPE=openai

# 端口配置
PORT=8001

# 访问认证（可选）
# DEEPWIKI_AUTH_MODE=true
# DEEPWIKI_AUTH_CODE=your-secret-code
```

---

## 常见问题排查

### 问题 1：容器启动后卡在 tiktoken 下载

**症状：** 容器日志中出现 `Downloading...` 或长时间无响应，网络超时错误。

**原因：** tiktoken 首次运行需要从 `cdn.openai.com` 下载编码文件，内网无法访问。

**解决方案：**

```bash
# 确认 TIKTOKEN_CACHE_DIR 已正确设置
docker exec <container_id> env | grep TIKTOKEN

# 确认缓存文件存在
docker exec <container_id> ls -la /app/tiktoken_cache/

# 手动测试 tiktoken 加载
docker exec <container_id> python3 -c "
import tiktoken
enc = tiktoken.get_encoding('cl100k_base')
print('OK:', len(enc.encode('test')))
"
```

**如缓存目录为空：** 参考 [tiktoken 离线缓存](#1-准备-tiktoken-离线缓存) 章节重新准备缓存文件。

---

### 问题 2：连接内网 LLM 时 SSL 证书验证失败

**症状：** 日志中出现 `SSL: CERTIFICATE_VERIFY_FAILED` 或 `certificate verify failed`。

**原因：** 内网 LLM 使用自签名证书，Python requests/httpx 默认不信任。

**解决方案：**

1. **确认证书已安装到镜像：**

```bash
# 检查系统证书库
docker exec <container_id> ls /usr/local/share/ca-certificates/
docker exec <container_id> openssl s_client -connect <llm-host>:443 -CAfile /etc/ssl/certs/ca-certificates.crt
```

2. **确认环境变量已设置：**

```bash
docker exec <container_id> env | grep -E "SSL|REQUESTS|CERT"
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
docker exec <container_id> env | grep GIT
docker exec <container_id> git config --global http.sslCAInfo
```

2. **手动测试克隆：**

```bash
docker exec <container_id> git clone https://<internal-git-repo> /tmp/test-clone
```

3. **临时跳过 SSL 验证（仅测试用）：**

```bash
docker exec <container_id> git config --global http.sslVerify false
```

---

### 问题 4：Wiki 生成中途失败

**症状：** Wiki 生成进度停止，日志出现 API 连接错误或超时。

**排查步骤：**

```bash
# 1. 检查 API 服务状态
curl http://localhost:8001/health

# 2. 检查 LLM 连通性
docker exec <container_id> curl -v \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  "${OPENAI_BASE_URL:-https://api.openai.com/v1}/models"

# 3. 查看实时日志
docker logs -f <container_id> 2>&1 | grep -E "ERROR|WARNING|Exception"

# 4. 检查 Embedding 数据库
docker exec <container_id> ls -la /root/.adalflow/
```

---

### 问题 5：自定义 LLM 无法切换

**症状：** 前端无法选择自定义 LLM，或选择后报模型不存在错误。

**解决方案：**

自定义 LLM 通过 `api/config/generator.json` 配置。可通过挂载自定义配置覆盖：

```yaml
# docker-compose.yml
volumes:
  - ./custom-config:/app/custom-config:ro
environment:
  - DEEPWIKI_CONFIG_DIR=/app/custom-config
```

`custom-config/generator.json` 示例（OpenAI 兼容内网模型）：

```json
{
  "default_provider": "openai",
  "providers": {
    "openai": {
      "default_model": "your-model-name",
      "supportsCustomModel": true,
      "models": {
        "your-model-name": {
          "temperature": 0.7,
          "top_p": 0.8
        }
      }
    }
  }
}
```

---

## 端到端验证清单

部署完成后，按顺序执行以下验证：

- [ ] **离线启动不卡死**：容器启动后 60 秒内完成，无 tiktoken 下载超时错误
  ```bash
  docker compose up -d && docker compose logs -f | head -50
  ```

- [ ] **健康检查通过**：
  ```bash
  curl -f http://localhost:8001/health && echo "API OK"
  curl -f http://localhost:3000 && echo "Frontend OK"
  ```

- [ ] **自定义 LLM 可连接**：前端选择目标 provider，发送测试消息，收到正常响应

- [ ] **SSL 证书正常**：LLM API 调用无证书错误（查看 `docker compose logs`）

- [ ] **Git 仓库可克隆**：在 DeepWiki 前端输入内网 Git 仓库 URL，仓库索引正常启动

- [ ] **Wiki 生成全流程正常**：选择已索引的仓库，生成 Wiki，页面正常展示内容

---

*如有问题，请查看容器日志：`docker compose logs -f deepwiki`*
