# DeepWiki Personal

基于 [AsyncFuncAI/deepwiki-open](https://github.com/AsyncFuncAI/deepwiki-open) 的内网部署改造版。

输入一个 Git 仓库地址，自动生成结构化的 Wiki 文档和可视化架构图。

## 改造内容

在上游项目基础上，针对**内网/离线环境**做了以下适配：

- **自定义 LLM 接入** — 新增 `custom_openai` provider，支持任意 OpenAI 兼容接口（vLLM、LM Studio、Ollama 等）
- **自定义 Embedder** — 独立配置 Embedding 服务地址和模型
- **tiktoken 离线缓存** — 预加载 `cl100k_base` 编码，无需运行时联网下载
- **SSL 自签名证书** — 通过 `SSL_CERT_FILE` 传递内网 CA 证书给 httpx 客户端
- **裸机部署脚本** — 提供 Windows (.bat) 和 Linux (.sh) 一键启动脚本，无需 Docker

## 快速开始

### 环境要求

- Python 3.11+
- Node.js 18+
- Git

### 部署步骤

```bash
# 1. 克隆仓库
git clone https://github.com/CyberShp/deepwiki-personal.git
cd deepwiki-personal

# 2. 配置环境变量
cp .env.example .env
# 编辑 .env，填入内网 LLM 地址和 API Key

# 3. 安装依赖
pip install uv && uv pip install -r requirements.txt
npm install && npm run build

# 4. 启动后端（端口 8001）
start-backend.sh   # Linux
start-backend.bat   # Windows

# 5. 启动前端（端口 3000）
start-frontend.sh   # Linux
start-frontend.bat   # Windows
```

浏览器打开 `http://localhost:3000` 即可使用。

### 关键环境变量

```ini
# 内网 LLM
CUSTOM_LLM_BASE_URL=http://your-llm-host:port/v1
CUSTOM_LLM_API_KEY=your-key
CUSTOM_LLM_MODEL=your-model

# 内网 Embedder
CUSTOM_EMBEDDER_BASE_URL=http://your-embedder-host:port/v1
CUSTOM_EMBEDDER_API_KEY=your-key
CUSTOM_EMBEDDER_MODEL=your-model
DEEPWIKI_EMBEDDER_TYPE=custom

# tiktoken 离线缓存（内网必填）
TIKTOKEN_CACHE_DIR=C:\Users\<username>\.tiktoken

# 自签名证书（如需要）
SSL_CERT_FILE=C:\certs\internal-ca.crt
```

完整变量说明见 [.env.example](.env.example)。

## 文档

- [内网部署指南](docs/INTRANET_DEPLOYMENT.md) — 详细的部署步骤、离线打包、故障排查

## 致谢

上游项目：[AsyncFuncAI/deepwiki-open](https://github.com/AsyncFuncAI/deepwiki-open)

## License

MIT
