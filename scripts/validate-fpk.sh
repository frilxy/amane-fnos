#!/usr/bin/env bash
# fpk 工程静态校验：文件齐全、JSON 合法、manifest 一致、图标规格、生命周期脚本可执行，
# 并用真实渲染器生成一次 compose 交给 docker compose 做语法校验。
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
fpk="${root}/fpk"

fail() {
    echo "校验失败：$*" >&2
    exit 1
}
ok() { echo "  ✓ $*"; }

echo "== 1. 必需文件 =="
for f in \
    manifest config/privilege config/resource ICON.PNG ICON_256.PNG \
    app/docker/image app/docker/docker-compose.yaml app/ui/config app/ui/images/icon_64.png app/ui/images/icon_256.png \
    cmd/main cmd/install_init cmd/install_callback cmd/upgrade_init cmd/upgrade_callback \
    cmd/config_init cmd/config_callback cmd/uninstall_init cmd/uninstall_callback \
    cmd/lib/common.sh cmd/lib/compose.sh \
    wizard/install wizard/config wizard/upgrade wizard/uninstall; do
    [ -f "${fpk}/${f}" ] || fail "缺少 fpk/${f}"
done
ok "全部必需文件存在"

echo "== 2. JSON 文件 =="
for f in config/privilege config/resource app/ui/config wizard/install wizard/config wizard/upgrade wizard/uninstall; do
    python3 -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "${fpk}/${f}" ||
        fail "fpk/${f} 不是合法 JSON"
done
ok "JSON 全部可解析"

echo "== 3. manifest =="
python3 - "${fpk}/manifest" "${fpk}/app/ui/config" <<'PY'
import json
import re
import sys

manifest_path, ui_path = sys.argv[1], sys.argv[2]
entries = {}
for line in open(manifest_path, encoding="utf-8"):
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, _, value = line.partition("=")
    entries[key.strip()] = value.strip()

required = [
    "appname", "version", "display_name", "desc", "source", "platform",
    "maintainer", "maintainer_url", "os_min_version", "desktop_uidir",
    "desktop_applaunchname", "changelog",
]
missing = [key for key in required if not entries.get(key)]
if missing:
    raise SystemExit(f"manifest 缺少字段：{', '.join(missing)}")
if entries["appname"] != "amane":
    raise SystemExit("manifest.appname 必须是 amane")
if entries["source"] != "thirdparty":
    raise SystemExit("manifest.source 必须是 thirdparty")
if entries["platform"] not in ("x86", "arm", "all"):
    raise SystemExit(f"manifest.platform 取值不合法：{entries['platform']}")
if not re.fullmatch(r"\d+\.\d+\.\d+(\.\d+)?", entries["version"]):
    raise SystemExit(f"manifest.version 格式不合法：{entries['version']}")
if entries["desktop_uidir"] != "ui":
    raise SystemExit("manifest.desktop_uidir 必须是 ui")

ui = json.load(open(ui_path, encoding="utf-8"))
urls = ui.get(".url", {})
launch = entries["desktop_applaunchname"]
if launch not in urls:
    raise SystemExit(f"app/ui/config 中不存在入口 {launch}")
entry = urls[launch]
if entry.get("port") != "${wizard_port}":
    raise SystemExit("入口端口必须使用 ${wizard_port}，与向导字段保持一致")
print(f"  appname={entries['appname']} version={entries['version']} 入口={launch}")
PY
ok "manifest 字段与入口配置一致"

echo "== 4. 图标规格 =="
python3 - "${fpk}/ICON.PNG" "${fpk}/ICON_256.PNG" <<'PY'
import struct
import sys

for path, expect in ((sys.argv[1], 64), (sys.argv[2], 256)):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path} 不是 PNG")
    width, height = struct.unpack(">II", data[16:24])
    if (width, height) != (expect, expect):
        raise SystemExit(f"{path} 尺寸为 {width}x{height}，期望 {expect}x{expect}")
    if len(data) > 1024 * 1024:
        raise SystemExit(f"{path} 超过 1MB")
    print(f"  {path.split('/')[-1]}: {width}x{height}")
PY
ok "图标尺寸与体积符合要求"

echo "== 5. 生命周期脚本 =="
python3 - "${fpk}" <<'PY'
import os
import sys

base = sys.argv[1]
scripts = [
    "main", "install_init", "install_callback", "upgrade_init", "upgrade_callback",
    "config_init", "config_callback", "uninstall_init", "uninstall_callback",
    "lib/common.sh", "lib/compose.sh",
]
for name in scripts:
    path = os.path.join(base, "cmd", name)
    if not os.access(path, os.X_OK):
        raise SystemExit(f"cmd/{name} 没有可执行权限")
    with open(path, encoding="utf-8") as handle:
        first = handle.readline().strip()
    if not first.startswith("#!"):
        raise SystemExit(f"cmd/{name} 缺少 shebang")
print(f"  {len(scripts)} 个脚本均可执行")
PY
ok "生命周期脚本可执行且带 shebang"

echo "== 6. 渲染器 / compose 语法 =="
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "${tmp}/etc"

# 故意混入越权与非法输入，确认渲染器会拒绝
hostile='/etc/passwd:/vol1/does-not-exist:/vol6/../etc/shadow:$INJECT:/vol1/ok'
if mkdir -p /vol1/media-validate 2>/dev/null; then
    legit="/vol1/media-validate"
    hostile="${hostile}:${legit}"
else
    legit=""
fi

generated="${tmp}/docker-compose.yaml"
env -i PATH="$PATH" \
    TRIM_APPNAME=amane \
    TRIM_APPDEST="${fpk}/app" \
    TRIM_PKGETC="${tmp}/etc" \
    AMANE_IMAGE_FILE="${fpk}/app/docker/image" \
    TRIM_DATA_SHARE_PATHS=/vol1/media-validate/shares-data \
    TRIM_DATA_ACCESSIBLE_PATHS="$hostile" \
    TRIM_UID=1000 \
    TRIM_GID=1000 \
    wizard_port=9123 \
    wizard_proxy="http://host.docker.internal:7890" \
    sh -c ". ./fpk/cmd/lib/compose.sh; amane_render_compose '${generated}'" >"${tmp}/render.log" 2>&1 ||
    { cat "${tmp}/render.log"; fail "渲染器执行失败"; }
cat "${tmp}/render.log"

grep -q '9123:8000' "$generated" || fail "渲染结果未使用 wizard_port"
grep -q '"1000:1000"' "$generated" || fail "渲染结果未使用应用用户身份"
grep -q '/etc/passwd' "$generated" && fail "渲染结果挂载了未授权路径 /etc/passwd"
grep -q 'does-not-exist' "$generated" && fail "渲染结果挂载了不存在的路径"
if [ -n "$legit" ]; then
    grep -qF "${legit}:${legit}" "$generated" || fail "合法授权目录没有被挂载"
    grep -qF "AMANE_SAFE_DIRS" "$generated" || fail "AMANE_SAFE_DIRS 未写入"
fi

# 代理：设了必须整组写入，未设时不能出现代理变量
grep -q 'HTTPS_PROXY: "http://host.docker.internal:7890"' "$generated" || fail "HTTPS_PROXY 未写入"
grep -q 'HTTP_PROXY: "http://host.docker.internal:7890"' "$generated" || fail "HTTP_PROXY 未写入"
grep -q 'ALL_PROXY: "http://host.docker.internal:7890"' "$generated" || fail "ALL_PROXY 未写入"
grep -q 'NO_PROXY:' "$generated" || fail "NO_PROXY 未写入"
grep -q 'host.docker.internal:host-gateway' "$generated" || fail "缺少 host.docker.internal 映射"
[ "$(head -n 1 "${tmp}/etc/proxy")" = "http://host.docker.internal:7890" ] || fail "代理未持久化到 etc"

# 清空（留空）应沿用上次设置；off 才清除
env -i PATH="$PATH" TRIM_APPNAME=amane TRIM_APPDEST="${fpk}/app" TRIM_PKGETC="${tmp}/etc" \
    AMANE_IMAGE_FILE="${fpk}/app/docker/image" wizard_port=9123 wizard_proxy="" \
    sh -c ". ./fpk/cmd/lib/compose.sh; amane_render_compose '${tmp}/keep.yaml'" >/dev/null 2>&1
grep -q 'HTTPS_PROXY' "${tmp}/keep.yaml" || fail "留空代理后应沿用上一次的设置"

env -i PATH="$PATH" TRIM_APPNAME=amane TRIM_APPDEST="${fpk}/app" TRIM_PKGETC="${tmp}/etc" \
    AMANE_IMAGE_FILE="${fpk}/app/docker/image" wizard_port=9123 wizard_proxy="off" \
    sh -c ". ./fpk/cmd/lib/compose.sh; amane_render_compose '${tmp}/off.yaml'" >/dev/null 2>&1
grep -q 'HTTPS_PROXY' "${tmp}/off.yaml" && fail "填写 off 后应清除代理"
[ -s "${tmp}/etc/proxy" ] && fail "off 之后代理状态文件应为空"
ok "代理设置（设置/沿用/清除）渲染正确"
ok "渲染器拒绝非法输入并保留合法授权目录"

if command -v docker >/dev/null 2>&1; then
    for candidate in "$generated" "${fpk}/app/docker/docker-compose.yaml"; do
        docker compose -f "$candidate" config >"${tmp}/compose.out" 2>"${tmp}/compose.err" ||
            { cat "${tmp}/compose.err"; fail "docker compose 无法解析 ${candidate}"; }
    done
    ok "docker compose config 解析通过（含随包发布的默认文件）"
else
    python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1], encoding="utf-8"))' "$generated" 2>/dev/null &&
        ok "YAML 解析通过（未安装 docker CLI）" || echo "  ! 跳过 compose 语法校验（缺少 docker/yaml）"
fi

echo "全部校验通过。"
