#!/usr/bin/env bash
# 把版本、镜像和更新说明写入 fpk 工程，并重新生成随包发布的默认 docker-compose.yaml。
#
# 用法：scripts/render-fpk.sh <version> <image> [changelog]
set -euo pipefail

version="${1:?用法: render-fpk.sh <version> <image> [changelog]}"
image="${2:?用法: render-fpk.sh <version> <image> [changelog]}"
changelog="${3:-同步上游 amane ${version}。}"

root="$(cd "$(dirname "$0")/.." && pwd)"
fpk="${root}/fpk"

case "$version" in
[0-9]*.[0-9]*.[0-9]*) ;;
*)
    echo "版本号格式不合法：${version}" >&2
    exit 1
    ;;
esac
case "$image" in
*/*:*) ;;
*)
    echo "镜像地址不合法：${image}" >&2
    exit 1
    ;;
esac

python3 - "$fpk/manifest" "$version" "$changelog" <<'PY'
import re
import sys

path, version, changelog = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8").read()
changelog = " ".join(changelog.split())

def set_key(text, key, value):
    pattern = re.compile(rf"^({re.escape(key)}\s*)=\s*.*$", re.MULTILINE)
    match = pattern.search(text)
    if not match:
        raise SystemExit(f"manifest 中缺少字段 {key}")
    prefix = match.group(1)
    return pattern.sub(lambda _m: f"{prefix}= {value}", text, count=1)

text = set_key(text, "version", version)
text = set_key(text, "changelog", changelog)
open(path, "w", encoding="utf-8").write(text)
print(f"manifest: version={version}")
PY

printf '%s\n' "$image" >"${fpk}/app/docker/image"

# 用包内同一份渲染器生成默认 compose，保证仓库里的默认文件与运行时逻辑一致
(
    cd "$root"
    env -i PATH="$PATH" \
        TRIM_APPNAME=amane \
        TRIM_APPDEST="${fpk}/app" \
        TRIM_DATA_SHARE_PATHS=/var/apps/amane/shares/data \
        TRIM_UID=1000 \
        TRIM_GID=1000 \
        AMANE_COMPOSE_OMIT_TIMESTAMP=1 \
        wizard_port=8000 \
        sh -c '. ./fpk/cmd/lib/compose.sh; amane_render_compose'
)

echo "镜像：${image}"
echo "默认 compose：${fpk}/app/docker/docker-compose.yaml"
