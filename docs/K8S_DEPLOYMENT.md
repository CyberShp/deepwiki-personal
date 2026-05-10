# DeepWiki K8s + Harbor 内网部署指南

本指南说明如何将 DeepWiki 部署到内网 Kubernetes 集群，并使用 Harbor 私有镜像仓库管理镜像。

> Harbor 为**推荐方案**，但非强制。若无 Harbor，可用 `docker save / load` 将镜像导入集群节点（见[方案 B：无 Harbor 导入镜像](#方案-b无-harbor-导入镜像)）。

---

## 目录

1. [前置要求](#前置要求)
2. [Harbor 镜像准备](#harbor-镜像准备)
   - [方案 A：使用 Harbor（推荐）](#方案-a使用-harbor推荐)
   - [方案 B：无 Harbor 导入镜像](#方案-b无-harbor-导入镜像)
3. [K8s 清单部署](#k8s-清单部署)
   - [1. 创建 Secret](#1-创建-secret)
   - [2. 部署所有资源](#2-部署所有资源)
   - [3. 可选：启用 Ingress](#3-可选启用-ingress)
4. [验证清单](#验证清单)
5. [Harbor 配置参考](#harbor-配置参考)
6. [常见问题](#常见问题)

---

## 前置要求

| 组件 | 最低版本 | 说明 |
|------|---------|------|
| Kubernetes | 1.24 | 节点可访问 Harbor 镜像地址 |
| kubectl | 1.24 | 与集群版本对应 |
| Harbor | 2.x | 内网镜像仓库（可选） |
| Docker | 20.x | 用于构建和推送镜像（有 Harbor 时需要） |
| StorageClass | — | 集群需有可用的 StorageClass 供 PVC 使用 |

---

## Harbor 镜像准备

### 方案 A：使用 Harbor（推荐）

#### 步骤 1：在 Harbor 中创建项目

1. 登录 Harbor Web UI（`https://harbor.intranet.company.com`）
2. 点击 **Projects → New Project**
3. 项目名称填 `deepwiki`，访问级别选 **Private**
4. 点击 **OK** 创建

#### 步骤 2：创建 Robot 账号（推荐）

Robot 账号专用于 CI/CD 和 K8s 拉取镜像，权限最小化。

1. 进入 `deepwiki` 项目 → **Robot Accounts → New Robot Account**
2. 填写名称（如 `deepwiki-puller`），选择 **Pull** 权限
3. 保存生成的 **token**（只显示一次，请立即保存）

> 若需要从 CI/CD 机器推送镜像，还需创建一个具有 **Push** 权限的 Robot 账号。

#### 步骤 3：信任 Harbor 自签名证书（如适用）

若 Harbor 使用自签名 TLS 证书：

```bash
# Linux：将 Harbor CA 证书添加到 Docker 信任列表
sudo mkdir -p /etc/docker/certs.d/harbor.intranet.company.com
sudo cp /path/to/harbor-ca.crt /etc/docker/certs.d/harbor.intranet.company.com/ca.crt
sudo systemctl restart docker

# macOS：通过 Keychain 导入证书后重启 Docker Desktop
```

#### 步骤 4：构建并推送镜像

```bash
# 在项目根目录执行
chmod +x scripts/push-to-harbor.sh

# 使用默认配置（需修改脚本中的 HARBOR_HOST）
./scripts/push-to-harbor.sh

# 或通过环境变量覆盖
HARBOR_HOST=harbor.intranet.company.com \
HARBOR_PROJECT=deepwiki \
IMAGE_TAG=v1.0.0 \
./scripts/push-to-harbor.sh
```

脚本执行完成后，终端会输出完整镜像地址，例如：

```
harbor.intranet.company.com/deepwiki/deepwiki:v1.0.0
```

将此地址填入 `k8s/deployment.yaml` 的 `image` 字段。

---

### 方案 B：无 Harbor 导入镜像

若集群节点无法访问 Harbor，可通过 `docker save / load` 手动导入：

```bash
# 1. 在有网络的机器上构建镜像
docker build -t deepwiki:latest .

# 2. 导出为 tar 包
docker save deepwiki:latest -o deepwiki.tar

# 3. 将 tar 包复制到每个 K8s 节点（可用 scp）
scp deepwiki.tar user@k8s-node-1:/tmp/

# 4. 在每个节点上导入镜像
# Docker 运行时：
ssh user@k8s-node-1 "docker load -i /tmp/deepwiki.tar"
# containerd 运行时（K8s 1.24+ 默认）：
# ssh user@k8s-node-1 "ctr -n k8s.io images import /tmp/deepwiki.tar"
```

导入后，修改 `k8s/deployment.yaml`：

```yaml
image: deepwiki:latest
imagePullPolicy: Never
```

---

## K8s 清单部署

### 1. 创建 Secret

Secret 包含 API 密钥等敏感信息，**不应**提交到版本控制，需手动创建：

```bash
# 方式一：命令行创建（推荐，避免明文写入文件）
kubectl create secret generic deepwiki-secret \
  --from-literal=OPENAI_API_KEY=sk-your-key \
  --from-literal=GOOGLE_API_KEY=AIza-your-key \
  -n deepwiki

# 若使用内网 LLM（OpenAI 兼容接口）
kubectl create secret generic deepwiki-secret \
  --from-literal=OPENAI_API_KEY=your-internal-key \
  --from-literal=OPENAI_BASE_URL=http://llm.intranet.company.com/v1 \
  --from-literal=GOOGLE_API_KEY="" \
  -n deepwiki

# 方式二：编辑 k8s/secret.yaml 模板后应用
# （先替换文件中的 <your-*> 占位符）
kubectl apply -f k8s/secret.yaml
```

若 Harbor 需要认证拉取镜像（使用 Robot 账号）：

```bash
kubectl create secret docker-registry harbor-credentials \
  --docker-server=harbor.intranet.company.com \
  --docker-username="robot\$deepwiki-puller" \
  --docker-password=<robot-token> \
  -n deepwiki
```

然后在 `k8s/deployment.yaml` 中取消注释 `imagePullSecrets` 部分。

### 2. 部署所有资源

```bash
# 一键部署（使用 kustomize，包含 namespace/configmap/pvc/deployment/service）
kubectl apply -k k8s/

# 或逐文件部署
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/pvc.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
```

查看部署状态：

```bash
# 等待 Pod 就绪
kubectl rollout status deployment/deepwiki -n deepwiki

# 查看 Pod 状态
kubectl get pods -n deepwiki

# 查看日志（首次启动可能需要 30 秒）
kubectl logs -f deployment/deepwiki -n deepwiki
```

### 3. 可选：启用 Ingress

确认集群已安装 Ingress Controller，并修改 `k8s/ingress.yaml` 中的域名和 `ingressClassName`：

```bash
# 编辑后应用
kubectl apply -f k8s/ingress.yaml
```

若暂无 Ingress Controller，可用端口转发临时访问：

```bash
# 访问前端
kubectl port-forward svc/deepwiki 3000:3000 -n deepwiki
# 浏览器打开 http://localhost:3000

# 访问后端 API（可选，前端已通过 localhost:8001 访问后端）
kubectl port-forward svc/deepwiki 8001:8001 -n deepwiki
```

---

## 验证清单

部署完成后，按顺序验证：

- [ ] **Pod 运行正常**
  ```bash
  kubectl get pods -n deepwiki
  # 期望：STATUS=Running，READY=1/1
  ```

- [ ] **健康检查通过**
  ```bash
  kubectl exec -n deepwiki deployment/deepwiki -- curl -sf http://localhost:8001/health
  # 期望：{"status": "ok"} 或类似响应
  ```

- [ ] **前端可访问**：浏览器打开 `http://localhost:3000`（port-forward）或 Ingress 域名

- [ ] **PVC 正常绑定**
  ```bash
  kubectl get pvc -n deepwiki
  # 期望：STATUS=Bound
  ```

- [ ] **自定义 LLM 可连接**：在 DeepWiki 前端选择内网 LLM provider，发送测试消息，收到响应

- [ ] **Git 仓库可索引**：输入内网 Git 仓库 URL，仓库索引正常启动

- [ ] **Wiki 生成全流程正常**：选择已索引的仓库，生成 Wiki，页面正常展示

---

## Harbor 配置参考

### 项目结构建议

```
harbor.intranet.company.com/
└── deepwiki/                  ← Harbor 项目
    ├── deepwiki:latest        ← 最新镜像
    └── deepwiki:v1.0.0        ← 带版本 tag
```

### Robot 账号权限配置

| 角色 | 用途 | 权限 |
|------|------|------|
| `deepwiki-puller` | K8s 拉取镜像 | Pull |
| `deepwiki-pusher` | CI/CD 推送镜像 | Push + Pull |

---

## 常见问题

### ImagePullBackOff / ErrImagePull

**原因**：K8s 无法从 Harbor 拉取镜像。

```bash
kubectl describe pod <pod-name> -n deepwiki
# 查看 Events 中的错误信息
```

常见原因：
1. Harbor 证书不受信任 → 在所有节点上添加 Harbor CA 证书到 `/etc/docker/certs.d/`
2. 未配置 `imagePullSecrets` → 创建 docker-registry secret 并配置
3. Robot 账号 token 过期 → 在 Harbor 中重新生成 token 并更新 secret

### Pod 一直处于 Pending 状态

通常是 PVC 未绑定或资源不足：

```bash
kubectl describe pod <pod-name> -n deepwiki
kubectl describe pvc deepwiki-adalflow-pvc -n deepwiki
```

若 PVC 处于 Pending：检查集群是否有可用的 StorageClass，或在 `k8s/pvc.yaml` 中指定 `storageClassName`。

### 健康检查失败，Pod 反复重启

后端首次启动较慢（加载 tiktoken 编码等），可增大探针初始等待时间（`k8s/deployment.yaml`）：

```yaml
livenessProbe:
  initialDelaySeconds: 60
```

### 前端无法访问后端 API

确认 `k8s/configmap.yaml` 中的 `SERVER_BASE_URL`：
- 同一 Pod 内（默认）：`http://localhost:8001`
- 通过 Service 访问：`http://deepwiki.deepwiki.svc.cluster.local:8001`

---

*其他问题请查看 Pod 日志：`kubectl logs -f deployment/deepwiki -n deepwiki`*

*裸机部署请参阅 [INTRANET_DEPLOYMENT.md](./INTRANET_DEPLOYMENT.md)*
