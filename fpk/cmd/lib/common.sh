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
        AMANE_PROXY="${AMANE_RESOLVED_PROXY:-}"
        if [ -n "$AMANE_PROXY" ]; then
            amane_log "已生成 ${AMANE_COMPOSE_FILE}（访问端口 ${AMANE_PORT}，出网代理 ${AMANE_PROXY}）"
        else
            amane_log "已生成 ${AMANE_COMPOSE_FILE}（访问端口 ${AMANE_PORT}，未设置出网代理）"
        fi
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
    if ! command -v docker >/dev/null 2>&1; then
        amane_log "未找到 docker 命令，跳过自动重建容器"
        return 0
    fi
    if ! amane_docker_available; then
        # 应用用户默认不在 docker 组，属正常情况：把结论和补救命令写清楚，而不是静默跳过
        amane_log "当前身份无权访问 Docker，未自动重建容器。授权目录/端口/代理的改动要生效，请二选一："
        amane_log "  1) 打开「Docker」应用 → 项目 → ${AMANE_PROJECT} → 重新部署（重建容器）"
        amane_log "  2) SSH 执行：sudo docker compose -p ${AMANE_PROJECT} -f ${AMANE_COMPOSE_FILE} up -d"
        return 0
    fi
    docompose() {
        docker compose -p "$AMANE_PROJECT" -f "$AMANE_COMPOSE_FILE" up -d >/dev/null 2>&1
    }

    if ! amane_container_exists; then
        amane_log "容器 ${AMANE_PROJECT} 尚未创建，应用中心启动时会按最新 compose 创建"
        return 0
    fi

    # 同名容器可能来自别的 compose 项目（例如手工部署的旧项目），这时必须点明
    _existing_project=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$AMANE_PROJECT" 2>/dev/null)
    if [ -n "$_existing_project" ] && [ "$_existing_project" != "$AMANE_PROJECT" ]; then
        amane_log "检测到容器 ${AMANE_PROJECT} 由其它 Compose 项目（${_existing_project}）创建，本应用无法接管它，"
        amane_log "这时的界面并不是本应用包创建的容器（常见表现：选路径报 No safe directories configured）。"
        amane_log "修复：sudo docker rm -f ${AMANE_PROJECT} && sudo docker compose -p ${AMANE_PROJECT} -f ${AMANE_COMPOSE_FILE} up -d"
        return 1
    fi

    if ! amane_container_running; then
        amane_log "容器 ${AMANE_PROJECT} 未运行，配置改动会在下次启动时生效"
        return 0
    fi

    if docompose; then
        amane_log "已按最新配置重建容器 ${AMANE_PROJECT}"
        return 0
    fi
    amane_log "自动重建容器失败，请在「Docker」应用 → 项目 → ${AMANE_PROJECT} 里点『重新部署』，或执行："
    amane_log "  sudo docker compose -p ${AMANE_PROJECT} -f ${AMANE_COMPOSE_FILE} up -d"
    return 1
}

# 端口是否已被占用（无需 root：ss 优先，退化到 /proc/net/tcp）
amane_port_in_use() {
    _port="$1"
    case "$_port" in '' | *[!0-9]*) return 1 ;; esac
    if command -v ss >/dev/null 2>&1; then
        ss -ltn 2>/dev/null | awk '{ print $4 }' | grep -qE "[:.]${_port}\$" && return 0
        return 1
    fi
    if [ -r /proc/net/tcp ]; then
        _hex=$(printf '%04X' "$_port")
        awk -v want="$_hex" '
            NR > 1 && $4 == "0A" {
                split($2, parts, ":")
                if (toupper(parts[2]) == want) { found = 1 }
            }
            END { exit found ? 0 : 1 }
        ' /proc/net/tcp && return 0
    fi
    return 1
}

# 占用指定宿主机端口的容器名（docker 不可用时为空）
amane_port_owner() {
    amane_docker_available || return 0
    docker ps --filter "publish=$1" --format '{{.Names}}' 2>/dev/null | head -n 1
}

# 端口冲突检查：优先识别占用者，无法识别时给出通用提示
amane_warn_port_conflict() {
    _port="$1"
    amane_port_in_use "$_port" || return 0
    _owner=$(amane_port_owner "$_port")
    if [ -n "$_owner" ] && [ "$_owner" = "$AMANE_PROJECT" ]; then
        return 0
    fi
    if [ -n "$_owner" ]; then
        amane_user_error "端口 ${_port} 已被容器 ${_owner} 占用（不是本应用的容器）。请先停止/删除它，或在应用设置里改用其它端口。"
    else
        amane_user_error "端口 ${_port} 当前已被占用，且不是本应用的容器（常见于早先在「Docker」应用里手工创建的 amane 容器）。请先停止/删除占用者，或在应用设置里改用其它端口。"
    fi
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
