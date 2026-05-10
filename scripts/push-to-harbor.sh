#!/usr/bin/env bash
# push-to-harbor.sh — 构建 DeepWiki 镜像并推送到 Harbor 私有仓库
#
# 使用方式：
#   chmod +x scripts/push-to-harbor.sh
#   ./scripts/push-to-harbor.sh
#
# 可通过环境变量覆盖默认值：
#   HARBOR_HOST=harbor.example.com IMAGE_TAG=v1.2.3 ./scripts/push-to-harbor.sh

set -euo pipefail

# ── 配置（修改为实际 Harbor 地址）────────────────────────────────────────────
HARBOR_HOST="${HARBOR_HOST:-harbor.intranet.company.com}"
HARBOR_PROJECT="${HARBOR_PROJECT:-deepwiki}"
IMAGE_NAME="${IMAGE_NAME:-deepwiki}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

FULL_IMAGE="${HARBOR_HOST}/${HARBOR_PROJECT}/${IMAGE_NAME}:${IMAGE_TAG}"

# ── 颜色输出 ──────────────────────────────────────────────────────────────────
info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }
error()   { echo "[ERROR] $*" >&2; exit 1; }

# ── 1. 检查依赖 ───────────────────────────────────────────────────────────────
command -v docker >/dev/null 2>&1 || error "未找到 docker 命令，请先安装 Docker"

# ── 2. 登录 Harbor ────────────────────────────────────────────────────────────
info "登录 Harbor: ${HARBOR_HOST}"
info "（若 Harbor 启用了自签名证书，请确保已将 CA 证书添加到 Docker 信任列表）"
info "  Linux: /etc/docker/certs.d/${HARBOR_HOST}/ca.crt"
info "  macOS: Keychain 导入证书后重启 Docker Desktop"
docker login "${HARBOR_HOST}"

# ── 3. 构建镜像 ───────────────────────────────────────────────────────────────
info "构建镜像: ${FULL_IMAGE}"
# 若有自签名证书，将证书目录放在项目根 certs/ 下，Dockerfile 会自动安装
docker build \
  --tag "${FULL_IMAGE}" \
  --file Dockerfile \
  .
success "镜像构建完成"

# ── 4. 推送镜像 ───────────────────────────────────────────────────────────────
info "推送镜像: ${FULL_IMAGE}"
docker push "${FULL_IMAGE}"
success "镜像已推送至 Harbor"

echo ""
echo "================================================"
echo "  镜像地址: ${FULL_IMAGE}"
echo "  更新 k8s/deployment.yaml 中的 image 字段为上述地址"
echo "  然后执行: kubectl apply -k k8s/"
echo "================================================"
