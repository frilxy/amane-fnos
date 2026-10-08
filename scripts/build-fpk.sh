#!/usr/bin/env bash
# 打包 fpk：下载官方 fnpack，校验工程结构后打包，并对产物做内容校验。
#
# 产物：
#   dist/amane-<version>.fpk   带版本号的构建产物
#   dist/amane.fpk             固定文件名，方便 releases/latest/download 直接引用
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
fn_pack_version="${FN_PACK_VERSION:-1.2.3}"
fn_pack_url="${FN_PACK_URL:-https://static2.fnnas.com/fnpack/fnpack-${fn_pack_version}-linux-amd64}"
cache_dir="${CACHE_DIR:-${root}/.cache}"

die() {
    echo "错误：$*" >&2
    exit 1
}

mkdir -p "$cache_dir"
fn_pack="${cache_dir}/fnpack-${fn_pack_version}"
if [ ! -x "$fn_pack" ]; then
    echo "下载 fnpack ${fn_pack_version}：${fn_pack_url}"
    curl -fsSL --retry 3 --retry-delay 3 -o "${fn_pack}.part" "$fn_pack_url"
    chmod +x "${fn_pack}.part"
    mv "${fn_pack}.part" "$fn_pack"
fi

bash "${root}/scripts/validate-fpk.sh"

version=$(sed -n 's/^version[[:space:]]*=[[:space:]]*//p' "${root}/fpk/manifest" | head -n 1 | tr -d ' \r')
[ -n "$version" ] || die "fpk/manifest 中没有 version 字段"
image=$(head -n 1 "${root}/fpk/app/docker/image" | tr -d ' \t\r\n')
[ -n "$image" ] || die "fpk/app/docker/image 为空"

rm -f "${root}/amane.fpk"
(cd "$root" && "$fn_pack" build --directory fpk)
built="${root}/amane.fpk"
[ -f "$built" ] || die "fnpack 未生成 ${built}"

# --- 产物校验 ---------------------------------------------------------------
listing=$(tar -tzf "$built")
for entry in \
    manifest config/privilege config/resource ICON.PNG ICON_256.PNG app.tgz \
    cmd/main cmd/install_init cmd/install_callback cmd/upgrade_init cmd/upgrade_callback \
    cmd/config_init cmd/config_callback cmd/uninstall_init cmd/uninstall_callback \
    cmd/lib/common.sh cmd/lib/compose.sh \
    wizard/install wizard/config wizard/upgrade wizard/uninstall; do
    grep -qx -- "$entry" <<<"$listing" || die "fpk 中缺少 ${entry}"
done

packed_version=$(tar -xzOf "$built" manifest | sed -n 's/^version[[:space:]]*=[[:space:]]*//p' | head -n 1 | tr -d ' \r')
[ "$packed_version" = "$version" ] || die "包内版本(${packed_version})与期望(${version})不一致"

packed_compose=$(tar -xzOf "$built" app.tgz | tar -xzOf - docker/docker-compose.yaml)
grep -qF "$image" <<<"$packed_compose" || die "包内 docker-compose.yaml 未使用镜像 ${image}"
grep -q "container_name: amane" <<<"$packed_compose" || die "包内 docker-compose.yaml 缺少 container_name"

packed_ui=$(tar -xzOf "$built" app.tgz | tar -xzOf - ui/config)
grep -q '"amane.main"' <<<"$packed_ui" || die "包内 ui/config 缺少 amane.main 入口"

mkdir -p "${root}/dist"
cp -f "$built" "${root}/dist/amane-${version}.fpk"
cp -f "$built" "${root}/dist/amane.fpk"
rm -f "$built"

sha=$(sha256sum "${root}/dist/amane-${version}.fpk" | awk '{ print $1 }')
size=$(stat -c '%s' "${root}/dist/amane-${version}.fpk")

echo "version=${version}"
echo "image=${image}"
echo "fpk=dist/amane-${version}.fpk"
echo "sha256=${sha}"
echo "size=${size}"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        printf 'version=%s\n' "$version"
        printf 'image=%s\n' "$image"
        printf 'fpk=dist/amane-%s.fpk\n' "$version"
        printf 'sha256=%s\n' "$sha"
        printf 'size=%s\n' "$size"
    } >>"$GITHUB_OUTPUT"
fi
