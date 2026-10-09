#!/bin/sh
# Amane fnOS 应用包 —— docker-compose.yaml 渲染器
#
# 由 cmd/ 下的生命周期脚本在安装、升级、配置变更和启动时调用，
# 把 fnOS 的应用设置（访问端口、授权目录）翻译成一份可用的 Compose 文件。
#
# 输入（全部来自 fnOS 运行环境，缺失时使用安全默认值）：
#   TRIM_APPNAME                应用名，默认 amane
#   TRIM_APPDEST                已安装的 target 目录
#   TRIM_DATA_SHARE_PATHS       config/resource 声明的共享目录（冒号分隔）
#   TRIM_DATA_ACCESSIBLE_PATHS  管理员在「授权目录」里放开的宿主机路径（冒号分隔）
#   TRIM_UID / TRIM_GID         应用用户（容器内进程身份）
#   TRIM_RUN_UID / TRIM_RUN_GID 当前脚本执行用户
#   TRIM_USERNAME               应用用户名
#   wizard_port                 访问端口，默认 8000
#   wizard_proxy                可选出网代理（http:// 或 https://），留空表示直连
#   AMANE_IMAGE_FILE            镜像定义文件，默认 <compose 所在目录>/image
#
# 用法：
#   . compose.sh && amane_render_compose [输出路径]
#   sh compose.sh [输出路径]
#
# 设计要点：
#   1. 只挂载管理员确实授权过的目录，不整卷挂载；
#   2. 任何异常/越界输入都会被拒绝并跳过，绝不生成非法 YAML；
#   3. 内容没有变化时不重写文件，避免无谓的容器重建。

AMANE_DEFAULT_PORT=8000
AMANE_CONTAINER_PORT=8000
AMANE_RESOLVED_PORT="$AMANE_DEFAULT_PORT"
AMANE_RESOLVED_PROXY=""

amane_log() {
    printf '[%s] [compose] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

# 端口状态文件：etc 目录在升级后仍然保留，用于记住用户选择的端口
amane_port_state_file() {
    [ -n "${TRIM_PKGETC:-}" ] || return 1
    printf '%s/web-port' "$TRIM_PKGETC"
}

# 解析访问端口：wizard_port > 上次保存的端口 > 8000
amane_resolve_port() {
    _state=$(amane_port_state_file || true)
    _p="${wizard_port:-}"
    case "$_p" in
    '' | *[!0-9]*) _p="" ;;
    esac
    if [ -n "$_p" ]; then
        _p=$(printf '%s' "$_p" | sed 's/^0*//')
    fi
    if [ -z "$_p" ] && [ -n "$_state" ] && [ -r "$_state" ]; then
        _p=$(head -n 1 "$_state" 2>/dev/null | tr -d ' \t\r\n')
        case "$_p" in
        '' | *[!0-9]*) _p="" ;;
        esac
    fi
    case "$_p" in
    '' | *[!0-9]*) _p="$AMANE_DEFAULT_PORT" ;;
    esac
    if [ "$_p" -lt 1024 ] || [ "$_p" -gt 65535 ]; then
        amane_log "端口 ${wizard_port:-<空>} 不在 1024-65535 范围内，改用 ${AMANE_DEFAULT_PORT}"
        _p="$AMANE_DEFAULT_PORT"
    fi
    if [ -n "$_state" ]; then
        {
            printf '%s\n' "$_p" >"$_state"
        } 2>/dev/null || true
    fi
    printf '%s' "$_p"
}

# 授权目录校验：必须在存储卷下，且不含可用于注入的字符
amane_path_is_acceptable() {
    case "$1" in
    /vol/* | /vol[0-9]*) ;;
    *) return 1 ;;
    esac
    case "$1" in
    *..* | *'"'* | *"'"* | *'\'* | *'$'* | *'`'* | *'#'*) return 1 ;;
    *'
'*) return 1 ;;
    esac
    return 0
}

# 代理状态文件：etc 目录在升级后仍然保留
amane_proxy_state_file() {
    [ -n "${TRIM_PKGETC:-}" ] || return 1
    printf '%s/proxy' "$TRIM_PKGETC"
}

# 解析容器出网代理：wizard_proxy 显式提交 > 上次保存 > 不使用代理
# 语义：留空＝沿用上次保存的值；填 off/none/direct/- ＝取消代理；
# 只接受 http:// 与 https://（mihomo 等混合端口同时支持 HTTP 与 SOCKS，
# 但 HTTP 形式对 Python 客户端最稳，socks 方案需要容器内额外依赖）。
amane_resolve_proxy() {
    _state=$(amane_proxy_state_file || true)
    _p=""
    if [ -n "$_state" ] && [ -r "$_state" ]; then
        _p=$(head -n 1 "$_state" 2>/dev/null | tr -d ' \t\r\n')
    fi
    if [ "${wizard_proxy+set}" = "set" ]; then
        _submitted=$(printf '%s' "${wizard_proxy}" | tr -d ' \t\r\n')
        case "$_submitted" in
        '') ;;
        off | OFF | Off | none | NONE | direct | DIRECT | -)
            _p=""
            ;;
        *)
            case "$_submitted" in
            http://* | https://*) _p="$_submitted" ;;
            *)
                amane_log "代理地址 ${_submitted} 不被支持（只接受 http:// 或 https://），沿用原设置"
                ;;
            esac
            ;;
        esac
    fi
    case "$_p" in
    *'"'* | *"'"* | *'$'* | *'`'* | *'\'* | *'#'*) _p="" ;;
    esac
    if [ -n "$_state" ]; then
        {
            if [ -n "$_p" ]; then
                printf '%s\n' "$_p" >"$_state"
            else
                : >"$_state"
            fi
        } 2>/dev/null || true
    fi
    printf '%s' "$_p"
}

# 应用数据目录：优先使用 data-share 声明的共享目录
amane_resolve_data_dir() {
    _share="${TRIM_DATA_SHARE_PATHS:-}"
    case "$_share" in
    *:*) _share="${_share%%:*}" ;;
    esac
    if [ -z "$_share" ]; then
        _share="/var/apps/${TRIM_APPNAME:-amane}/shares/data"
    fi
    printf '%s' "$_share"
}

# 容器运行身份：与 fnOS 应用用户对齐，授权目录的 ACL 才能生效
amane_resolve_identity() {
    _uid=""
    _gid=""
    if [ -n "${TRIM_USERNAME:-}" ]; then
        _uid=$(id -u "$TRIM_USERNAME" 2>/dev/null || true)
        _gid=$(id -g "$TRIM_USERNAME" 2>/dev/null || true)
    fi
    [ -n "$_uid" ] || _uid="${TRIM_UID:-}"
    [ -n "$_gid" ] || _gid="${TRIM_GID:-}"
    [ -n "$_uid" ] || _uid="${TRIM_RUN_UID:-1000}"
    [ -n "$_gid" ] || _gid="${TRIM_RUN_GID:-1000}"
    case "$_uid" in '' | *[!0-9]*) _uid=1000 ;; esac
    case "$_gid" in '' | *[!0-9]*) _gid=1000 ;; esac
    printf '%s:%s' "$_uid" "$_gid"
}

# amane_render_compose [输出路径]
# 成功返回 0，并把实际端口写入 AMANE_RESOLVED_PORT
amane_render_compose() {
    _out="$1"
    [ -n "$_out" ] || _out="${TRIM_APPDEST:-/var/apps/${TRIM_APPNAME:-amane}}/docker/docker-compose.yaml"

    _appname="${TRIM_APPNAME:-amane}"
    _docker_dir=$(dirname "$_out")
    _image_file="${AMANE_IMAGE_FILE:-}"
    if [ -z "$_image_file" ]; then
        # 允许在 etc 目录放 image-override 覆盖镜像地址（例如改用私有镜像代理），
        # 该文件在升级后依然保留。
        if [ -n "${TRIM_PKGETC:-}" ] && [ -r "${TRIM_PKGETC}/image-override" ]; then
            _image_file="${TRIM_PKGETC}/image-override"
        else
            _image_file="${_docker_dir}/image"
        fi
    fi

    _image=""
    if [ -r "$_image_file" ]; then
        _image=$(head -n 1 "$_image_file" 2>/dev/null | tr -d ' \t\r\n')
    fi
    case "$_image" in
    */*:*) ;;
    *) _image="" ;;
    esac
    if [ -z "$_image" ]; then
        amane_log "镜像定义无效或缺失：${_image_file}"
        return 1
    fi

    AMANE_RESOLVED_PORT=$(amane_resolve_port)
    _identity=$(amane_resolve_identity)
    _data_dir=$(amane_resolve_data_dir)

    if [ "${AMANE_COMPOSE_TEMPLATE:-0}" = "1" ]; then
        # 随包发布的默认文件：应用中心可能在 install_callback 之前就创建容器，
        # 这里改用 fnOS 注入到 compose 的环境变量，保证身份与数据目录仍然正确。
        _identity='${TRIM_UID:-1000}:${TRIM_GID:-1000}'
        _data_dir='${TRIM_DATA_SHARE_PATHS:-/var/apps/'"${_appname}"'/shares/data}'
    fi

    _volume_lines="      - \"${_data_dir}:/data\""

    # 存储卷整卷挂载：容器运行时身份就是 fnOS 应用用户，因此「授权目录」的 ACL 在宿主机侧
    # 实时生效——用户新增/取消授权目录后不需要重建容器即可读写（容器里只是多了看不见权限的目录名）。
    # 模板模式（随包默认文件）无法枚举卷，交给运行时渲染与 start 时的 up -d。
    if [ "${AMANE_COMPOSE_TEMPLATE:-0}" != "1" ]; then
        for _v in /vol[0-9] /vol[0-9][0-9]; do
            [ -d "$_v" ] || continue
            case "${_v##*/}" in
            vol0 | vol0[0-9]) continue ;;
            esac
            _volume_lines="${_volume_lines}
      - \"${_v}:${_v}\""
        done
    fi

    # 已授权目录再单独挂载一次：即使卷级 ACL 不允许穿越，精确挂载也能直接访问
    _seen="|"
    _rest="${TRIM_DATA_ACCESSIBLE_PATHS:-}"
    while [ -n "$_rest" ]; do
        case "$_rest" in
        *:*) _path="${_rest%%:*}" ; _rest="${_rest#*:}" ;;
        *) _path="$_rest" ; _rest="" ;;
        esac
        [ -n "$_path" ] || continue
        if ! amane_path_is_acceptable "$_path"; then
            amane_log "跳过不安全的授权路径：${_path}"
            continue
        fi
        if [ ! -d "$_path" ]; then
            amane_log "跳过不存在的授权路径：${_path}"
            continue
        fi
        # 解析符号链接后再校验一次，避免授权路径被指向 /vol 之外
        _real_path=$(readlink -f "$_path" 2>/dev/null || true)
        if [ -z "$_real_path" ] || ! amane_path_is_acceptable "$_real_path"; then
            amane_log "跳过指向存储卷之外的授权路径：${_path}"
            continue
        fi
        case "$_seen" in
        *"|${_real_path}|"*) continue ;;
        esac
        _volume_lines="${_volume_lines}
      - \"${_real_path}:${_real_path}\""
        _seen="${_seen}${_real_path}|"
    done

    if [ -f /etc/localtime ]; then
        _volume_lines="${_volume_lines}
      - \"/etc/localtime:/etc/localtime:ro\""
    fi

    # AMANE_SAFE_DIRS：默认 ALLOW_ALL —— 挂载范围由 compose 决定，能不能读写由 fnOS 授权目录的
    # ACL 决定；这样授权变更即时生效，不依赖容器重建（环境变量只在容器创建时写入）。
    # 需要 amane 自己的路径边界时，在应用配置目录放一个 safe-dirs 文件（逗号分隔的宿主机路径）。
    _safe_override="${TRIM_PKGETC:-}/safe-dirs"
    _env_safe="      # 边界交给 fnOS 授权目录的 ACL；如需严格模式，可在应用配置目录放 safe-dirs 文件"
    _env_safe="${_env_safe}
      AMANE_SAFE_DIRS: \"ALLOW_ALL\""
    if [ -n "${TRIM_PKGETC:-}" ] && [ -s "$_safe_override" ]; then
        _override_value=$(head -n 1 "$_safe_override" 2>/dev/null | tr -d '\r\n')
        case "$_override_value" in
        '' | *'"'* | *'$'* | *'`'* | *'\'*) _override_value="" ;;
        esac
        if [ -n "$_override_value" ]; then
            _env_safe="      # 来自 $(basename "$_safe_override")：严格路径边界"
            _env_safe="${_env_safe}
      AMANE_SAFE_DIRS: \"${_override_value}\""
        fi
    fi

    # 出网代理：设了才写，避免影响未使用代理的安装
    _proxy=$(amane_resolve_proxy)
    AMANE_RESOLVED_PROXY="$_proxy"
    _no_proxy="localhost,127.0.0.1,::1,host.docker.internal,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,100.64.0.0/10"
    if [ -n "$_proxy" ]; then
        _env_proxy="      HTTP_PROXY: \"${_proxy}\"
      HTTPS_PROXY: \"${_proxy}\"
      ALL_PROXY: \"${_proxy}\"
      http_proxy: \"${_proxy}\"
      https_proxy: \"${_proxy}\"
      all_proxy: \"${_proxy}\"
      NO_PROXY: \"${_no_proxy}\"
      no_proxy: \"${_no_proxy}\""
    else
        _env_proxy="      # 想让容器走代理时，在「应用设置」里填写代理地址（如 http://host.docker.internal:7890）并保存"
    fi

    _tmp="${_out}.tmp.$$"
    umask 022
    if [ "${AMANE_COMPOSE_OMIT_TIMESTAMP:-0}" = "1" ]; then
        _stamp_line="# 由 frilxy/amane-fnos 的 CI 生成；运行时会被生命周期脚本按应用设置重新生成。"
    else
        _stamp_line="# 生成时间：$(date '+%Y-%m-%d %H:%M:%S')"
    fi
    cat >"$_tmp" <<EOF
# 本文件由 frilxy/amane-fnos 的 cmd/ 生命周期脚本自动生成，手工修改会在下次启动或升级时被覆盖。
${_stamp_line}
# 镜像：${_image}
services:
  amane:
    image: ${_image}
    container_name: ${_appname}
    user: "${_identity}"
    restart: unless-stopped
    ports:
      - "${AMANE_RESOLVED_PORT}:${AMANE_CONTAINER_PORT}"
    # 让容器内的 http://host.docker.internal:<port> 始终指向 NAS 宿主，
    # 代理地址填它就不会因为 NAS 的 DHCP 地址变化而失效。
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
${_volume_lines}
    environment:
      AMANE_DATA_DIR: /data
      AMANE_SUPERVISED: "1"
      AMANE_HOST: 0.0.0.0
      AMANE_PORT: "${AMANE_CONTAINER_PORT}"
${_env_safe}
${_env_proxy}
    healthcheck:
      test:
        - CMD
        - python
        - -c
        - import urllib.request; urllib.request.urlopen('http://127.0.0.1:${AMANE_CONTAINER_PORT}/api/health')
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
EOF

    if [ ! -s "$_tmp" ]; then
        amane_log "渲染结果为空：${_tmp}"
        rm -f "$_tmp"
        return 1
    fi

    if [ -f "$_out" ] && cmp -s "$_tmp" "$_out"; then
        rm -f "$_tmp"
        return 0
    fi

    if ! mv -f "$_tmp" "$_out" 2>/dev/null; then
        amane_log "无法写入 ${_out}（权限不足？）"
        rm -f "$_tmp"
        return 1
    fi
    return 0
}

# 允许直接执行：sh compose.sh [输出路径]
if [ "${0##*/}" = "compose.sh" ]; then
    amane_render_compose "${1:-}"
    exit $?
fi
