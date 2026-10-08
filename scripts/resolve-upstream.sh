#!/usr/bin/env bash
# 解析上游 amane 的最新发布版本，并读取该版本镜像在 GHCR 上的 manifest digest。
#
# 输出（写入 $GITHUB_OUTPUT，本地执行时打印到 stdout）：
#   version=0.18.0
#   tag=v0.18.0
#   image=ghcr.io/sqzw-x/amane:0.18.0
#   digest=sha256:...
#
# 环境变量：
#   UPSTREAM_REPO     默认 sqzw-x/amane
#   UPSTREAM_VERSION  指定版本（可带 v 前缀），用于手动重跑某个版本
set -euo pipefail

UPSTREAM_REPO="${UPSTREAM_REPO:-sqzw-x/amane}"
REGISTRY_HOST="${REGISTRY_HOST:-ghcr.io}"
REGISTRY_PATH="$(printf '%s' "$UPSTREAM_REPO" | tr '[:upper:]' '[:lower:]')"
IMAGE_BASE="${REGISTRY_HOST}/${REGISTRY_PATH}"

emit() {
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
        printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"
    fi
    printf '%s=%s\n' "$1" "$2"
}

fetch_digest() {
    version="$1"
    token=$(curl -fsS --max-time 30 \
        "https://${REGISTRY_HOST}/token?scope=repository:${REGISTRY_PATH}:pull&service=${REGISTRY_HOST}" |
        jq -r '.token // empty')
    [ -n "$token" ] || return 1
    curl -fsSI --max-time 30 \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: application/vnd.oci.image.index.v1+json" \
        -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
        -H "Accept: application/vnd.oci.image.manifest.v1+json" \
        -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        "https://${REGISTRY_HOST}/v2/${REGISTRY_PATH}/manifests/${version}" 2>/dev/null |
        tr -d '\r' | awk 'tolower($1) == "docker-content-digest:" { print $2 }' | head -n 1
}

# 1. 候选版本列表（新版本在前）
if [ -n "${UPSTREAM_VERSION:-}" ]; then
    candidates=$(printf '%s\n' "${UPSTREAM_VERSION#v}")
else
    candidates=$(git ls-remote --tags --refs "https://github.com/${UPSTREAM_REPO}.git" 'v*' 2>/dev/null |
        awk -F'refs/tags/' '{ print $2 }' |
        grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' |
        sed 's/^v//' |
        sort -Vr)
fi
[ -n "$candidates" ] || {
    echo "无法从 ${UPSTREAM_REPO} 解析任何版本标签" >&2
    exit 1
}

# 2. 取第一个在镜像仓库中确实存在的版本（tag 可能先于镜像推送）
version=""
digest=""
for candidate in $candidates; do
    if digest=$(fetch_digest "$candidate"); then
        if [ -n "$digest" ]; then
            version="$candidate"
            break
        fi
    fi
    echo "跳过 ${candidate}：镜像尚未发布" >&2
    digest=""
done

[ -n "$version" ] || {
    echo "所有候选版本都没有可用镜像" >&2
    exit 1
}

emit version "$version"
emit tag "v${version}"
emit image "${IMAGE_BASE}:${version}"
emit digest "$digest"
