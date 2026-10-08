#!/bin/sh
# Amane fnOS 应用包 —— 生命周期脚本共享工具
#
# 用法（在 cmd/ 下的脚本里）：
#   AMANE_SCRIPT_TAG=main
#   . "$(dirname "$0")/lib/common.sh"

AMANE_SCRIPT_TAG="${AMANE_SCRIPT_TAG:-amane}"
AMANE_CMD_DIR=$(CDPATH= cd -- "$(dirname -- "${0:-.}")" 2>/dev/null && pwd)
AMANE_APPDEST="${TRIM_APPDEST:-/var/apps/${TRIM_APPNAME:-amane}}"
AMANE_DOCKER_DIR="${AMANE_APPDEST}/docker"
AMANE_COMPOSE_FILE="${AMANE_DOCKER_DIR}/docker-compose.yaml"
AMANE_PROJECT="${TRIM_APPNAME:-amane}"
AMANE_PORT=8000

amane_log() {
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$AMANE_SCRIPT_TAG" "$*" >&2
}

# 记录用户可见的错误：应用中心会把它展示在安装/升级失败提示里
amane_user_error() {
    amane_log "$*"
    if [ -n "${TRIM_TEMP_LOGFILE:-}" ]; then
        printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$TRIM_TEMP_LOGFILE" 2>/dev/null || true
    fi
}

# 从已生成的 compose 中读回访问端口
amane_port_from_compose() {
    [ -r "$AMANE_COMPOSE_FILE" ] || return 0
    sed -n 's/^[[:space:]]*-[[:space:]]*"\{0,1\}\([0-9][0-9]*\):[0-9][0-9]*"\{0,1\}[[:space:]]*$/\1/p' "$AMANE_COMPOSE_FILE" | head -n 1
}

# 渲染 docker-compose.yaml；结果端口写入 AMANE_PORT
amane_render() {
    _lib="${AMANE_CMD_DIR}/lib/compose.sh"
    if [ ! -r "$_lib" ]; then
        amane_log "未找到渲染器 ${_lib}，沿用已有 docker-compose.yaml"
        AMANE_PORT=$(amane_port_from_compose)
        [ -n "$AMANE_PORT" ] || AMANE_PORT=8000
        return 0
    fi
    # shellcheck source=compose.sh
    . "$_lib"
    if amane_render_compose "$AMANE_COMPOSE_FILE"; then
        AMANE_PORT="${AMANE_RESOLVED_PORT:-8000}"
        amane_log "已生成 ${AMANE_COMPOSE_FILE}（访问端口 ${AMANE_PORT}）"
        return 0
    fi
    amane_log "生成 ${AMANE_COMPOSE_FILE} 失败"
    AMANE_PORT=$(amane_port_from_compose)
    [ -n "$AMANE_PORT" ] || AMANE_PORT=8000
    return 1
}

amane_docker_available() {
    command -v docker >/dev/null 2>&1 || return 1
    docker info >/dev/null 2>&1 || return 1
    return 0
}

amane_container_exists() {
    amane_docker_available || return 1
    docker inspect "$AMANE_PROJECT" >/dev/null 2>&1
}

amane_container_running() {
    amane_docker_available || return 1
    _state=$(docker inspect -f '{{.State.Running}}' "$AMANE_PROJECT" 2>/dev/null) || return 1
    [ "$_state" = "true" ]
}

# 容器已在运行但配置刚变化时，用与容器名一致的项目名重建一次。
# 失败不致命：应用中心下次启动容器时会使用新配置。
amane_apply_compose() {
    amane_docker_available || return 0
    amane_container_running || return 0
    docker compose version >/dev/null 2>&1 || return 0
    # 沿用创建该容器的 Compose 项目名，避免生成一个平行项目
    _existing_project=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$AMANE_PROJECT" 2>/dev/null)
    [ -n "$_existing_project" ] && AMANE_PROJECT="$_existing_project"
    if docker compose -p "$AMANE_PROJECT" -f "$AMANE_COMPOSE_FILE" up -d >/dev/null 2>&1; then
        amane_log "已按最新配置重建容器 ${AMANE_PROJECT}"
        return 0
    fi
    amane_log "自动重建容器失败，请到应用中心手动重启一次 Amane"
    return 1
}

# 服务健康探测（docker 不可用时的兜底）
amane_http_ready() {
    _url="http://127.0.0.1:$1/api/health"
    if command -v curl >/dev/null 2>&1; then
        curl -fsS --max-time 3 "$_url" >/dev/null 2>&1 && return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -q -T 3 -O /dev/null "$_url" 2>/dev/null && return 0
    fi
    return 1
}
