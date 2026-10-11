#!/usr/bin/env bash
# amane-fnos 体检脚本 —— 在飞牛 fnOS 上以 root 运行：
#
#   sudo bash tools/doctor.sh
#
# 只做只读检查（docker inspect / exec 读操作），不会修改任何配置或容器。
# 输出可直接贴到 Issue 里；贴之前请自行确认没有 Token 等敏感信息。
set -u

APP="amane"
MANIFEST="/var/apps/${APP}/manifest"
TARGET_DIR="/vol6/@appcenter" # 兜底用；真正路径从符号链接解析
APP_LOG="/var/log/apps/${APP}.log"

CYAN=$'\033[36m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; DIM=$'\033[2m'; NC=$'\033[0m'
if [ ! -t 1 ]; then CYAN=""; GREEN=""; YELLOW=""; RED=""; DIM=""; NC=""; fi

section() { printf '\n%s== %s ==%s\n' "$CYAN" "$1" "$NC"; }
ok()      { printf '  %s✓%s %s\n' "$GREEN" "$NC" "$1"; }
warn()    { printf '  %s!%s %s\n' "$YELLOW" "$NC" "$1"; }
bad()     { printf '  %s✗%s %s\n' "$RED" "$NC" "$1"; }
info()    { printf '    %s%s%s\n' "$DIM" "$1" "$NC"; }

ISSUES=()
note_issue() { ISSUES+=("$1"); }

TARGET_REAL=""
CONTAINER_EXISTS=0
CONTAINER_OURS=0
MOUNTS_RAW=""

section "环境"
printf '  时间        : %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
printf '  内核/架构   : %s / %s\n' "$(uname -r)" "$(uname -m)"
if [ -r /etc/trim_version ]; then
    printf '  fnOS 版本   : %s\n' "$(cat /etc/trim_version)"
elif [ -r /usr/trim/etc/version ]; then
    printf '  fnOS 版本   : %s\n' "$(cat /usr/trim/etc/version)"
fi
if [ "$(id -u)" -eq 0 ]; then
    ok "以 root 运行（所有检查可用）"
else
    warn "不是 root：docker 相关检查可能因权限不足而失败，建议 sudo 运行"
    note_issue "脚本未以 root 运行，部分检查不可用"
fi

section "应用包"
if [ -r "$MANIFEST" ]; then
    ver=$(sed -n 's/^version[[:space:]]*=[[:space:]]*//p' "$MANIFEST" | head -n1 | tr -d ' \r')
    plat=$(sed -n 's/^platform[[:space:]]*=[[:space:]]*//p' "$MANIFEST" | head -n1 | tr -d ' \r')
    ok "已安装：version=${ver:-未知} platform=${plat:-未知}"
else
    bad "未找到 $MANIFEST —— 应用可能没安装"
    note_issue "应用未安装"
fi

if [ -L "/var/apps/${APP}/target" ]; then
    TARGET_REAL=$(readlink -f "/var/apps/${APP}/target" 2>/dev/null || true)
else
    TARGET_REAL=$(readlink -f "/var/apps/${APP}/target" 2>/dev/null || echo "/var/apps/${APP}/target")
fi
COMPOSE_FILE="${TARGET_REAL}/docker/docker-compose.yaml"
printf '  安装目录    : %s\n' "${TARGET_REAL:-未知}"
printf '  compose     : %s\n' "$COMPOSE_FILE"

if [ -r "$COMPOSE_FILE" ]; then
    ok "compose 文件可读"
    safe_dirs=$(sed -n 's/^[[:space:]]*AMANE_SAFE_DIRS:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' "$COMPOSE_FILE" | head -n1)
    info "compose 里的 AMANE_SAFE_DIRS: ${safe_dirs:-<未写>}"
else
    bad "compose 文件不存在或不可读：$COMPOSE_FILE"
    note_issue "compose 文件缺失"
fi

section "容器"
if ! command -v docker >/dev/null 2>&1; then
    bad "找不到 docker 命令"
    note_issue "没有 docker 命令"
elif ! docker info >/dev/null 2>&1; then
    warn "无法访问 Docker 守护进程（权限不足？请用 sudo 运行本脚本）——跳过容器检查"
    note_issue "无法访问 Docker（可能没有用 sudo 运行）"
else
    if container_json=$(docker inspect "$APP" 2>/dev/null); then
        CONTAINER_EXISTS=1
        ok "容器 $APP 存在"

        cfg_files=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.config_files"}}' "$APP" 2>/dev/null)
        project=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$APP" 2>/dev/null)
        user=$(docker inspect -f '{{.Config.User}}' "$APP" 2>/dev/null)
        state=$(docker inspect -f '{{.State.Status}}' "$APP" 2>/dev/null)

        printf '  状态        : %s\n' "${state:-未知}"
        printf '  运行身份    : %s\n' "${user:-<未设置>}"
        printf '  compose 项目: %s\n' "${project:-<无标签>}"
        printf '  配置来源    : %s\n' "${cfg_files:-<无标签>}"

        if [ -n "$cfg_files" ]; then
            case "$cfg_files" in
                *"${APP}/docker/docker-compose.yaml"*) CONTAINER_OURS=1 ;;
            esac
        fi
        if [ "$CONTAINER_OURS" -eq 1 ]; then
            ok "容器由本应用的 compose 创建"
        else
            bad "容器不是本应用的 compose 创建的（很可能是手工容器占用了容器名）"
            note_issue "容器不是应用创建的"
        fi

        MOUNTS_RAW=$(docker inspect -f '{{range .Mounts}}{{printf "%s -> %s | RW=%v\n" .Source .Destination .RW}}{{end}}' "$APP" 2>/dev/null)
        echo "  挂载："
        printf '%s\n' "${MOUNTS_RAW:-    <无>}" | sed 's/^/    /'

        env_dump=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$APP" 2>/dev/null | grep '^AMANE' || true)
        if [ -n "$env_dump" ]; then
            echo "  环境变量："
            printf '%s\n' "$env_dump" | sed 's/^/    /'
        else
            bad "容器里没有任何 AMANE_* 环境变量（典型的手工容器特征）"
            note_issue "容器缺少 AMANE_* 环境变量"
        fi
    else
        bad "容器 $APP 不存在"
        note_issue "容器不存在"
    fi
fi

section "授权目录可见性"
if [ "$CONTAINER_EXISTS" -eq 1 ] && [ -n "${MOUNTS_RAW:-}" ]; then
    checked=0
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        dest=$(printf '%s' "$line" | awk '{print $3}')
        case "$dest" in
            /data | /etc/localtime) continue ;;
            /vol*) ;;
            *) continue ;;
        esac
        checked=$((checked + 1))
        if docker exec "$APP" sh -c "ls -A '$dest' >/dev/null 2>&1"; then
            ok "容器内可读：$dest"
        else
            case "$dest" in
                /vol[0-9] | /vol[0-9][0-9])
                    info "容器内不可列举：$dest（整卷挂载点，未授权时正常）"
                    ;;
                *)
                    warn "容器内不可读：$dest —— 若这是你授权的目录，请取消后重新授权，再重启应用"
                    note_issue "授权目录在容器内不可读：$dest"
                    ;;
            esac
        fi
    done <<<"$MOUNTS_RAW"
    [ "$checked" -eq 0 ] && warn "compose 里没有任何 /vol* 挂载"
else
    warn "跳过（容器不存在或不可检查）"
fi

section "端口"
compose_port=$(sed -n 's/^[[:space:]]*-[[:space:]]*"\{0,1\}\([0-9][0-9]*\):[0-9][0-9]*"\{0,1\}[[:space:]]*$/\1/p' "${COMPOSE_FILE:-/dev/null}" 2>/dev/null | head -n1)
if [ -n "${compose_port:-}" ]; then
    printf '  期望端口    : %s\n' "$compose_port"
    owner=""
    if command -v docker >/dev/null 2>&1; then
        owner=$(docker ps --filter "publish=${compose_port}" --format '{{.Names}}' 2>/dev/null | head -n1)
    fi
    if [ -n "$owner" ]; then
        printf '  占用容器    : %s\n' "$owner"
        if [ "$owner" = "$APP" ]; then
            ok "端口由本应用容器占用"
        else
            bad "端口被容器 $owner 占用（不是本应用）"
            note_issue "端口被其它容器占用：$owner"
        fi
    else
        if command -v curl >/dev/null 2>&1 && curl -fsS --max-time 3 "http://127.0.0.1:${compose_port}/api/health" >/dev/null 2>&1; then
            ok "端口 ${compose_port} 上有服务响应（但没能识别占用容器）"
        else
            warn "端口 ${compose_port} 上没有响应，容器可能没起来"
        fi
    fi
else
    warn "没能从 compose 里解析出端口"
fi

section "应用用户与 docker 组"
app_uid=$(printf '%s' "${user:-}" | awk -F: '{print $1}')
if [ -n "${app_uid:-}" ]; then
    app_name=$(getent passwd "$app_uid" 2>/dev/null | cut -d: -f1)
    if [ -n "$app_name" ]; then
        printf '  应用用户    : %s (uid=%s)\n' "$app_name" "$app_uid"
        if id -nG "$app_name" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
            ok "在 docker 组中（应用可自行重建容器）"
        else
            warn "不在 docker 组：端口/代理变更需要手动重建容器"
            note_issue "应用用户不在 docker 组"
        fi
    fi
fi

section "应用日志（末尾 15 行）"
if [ -r "$APP_LOG" ]; then
    tail -n 15 "$APP_LOG" | sed 's/^/    /'
else
    warn "读不到 $APP_LOG"
fi

section "结论"
if [ "${#ISSUES[@]}" -eq 0 ]; then
    ok "没有发现明显问题。若功能仍异常，请附上本输出、容器日志与应用日志提 Issue。"
else
    printf '  发现 %d 个需要处理的问题：\n' "${#ISSUES[@]}"
    for i in "${ISSUES[@]}"; do printf '    - %s\n' "$i"; done
    cat <<'TIP'

  常见处理办法：

  # 1) 容器不是应用创建的 / 缺少 AMANE_* 环境变量
  #    先在「Docker」应用里删掉那个手工容器（以及同名定义），再执行：
  sudo docker rm -f amane
  sudo docker compose -p amane -f /var/apps/amane/target/docker/docker-compose.yaml up -d

  # 2) 授权目录在容器内不可读
  #    到「应用设置 → 授权目录」取消后重新授权，再重启应用

  # 3) 应用用户不在 docker 组
  sudo usermod -aG docker amane && sudo systemctl restart docker  # 然后在应用中心重启应用

  详细说明见 docs/TROUBLESHOOTING.md
TIP
fi
printf '\n%s体检结束。%s\n' "$DIM" "$NC"
