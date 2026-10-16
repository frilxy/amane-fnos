#!/usr/bin/env bash
# 提取上游仓库某个版本的更新记录（优先读 CHANGELOG.md，失败再退回 GitHub Release）。
#
# 用法：
#   scripts/fetch-upstream-notes.sh 0.19.0             # 输出 markdown（用于 Release 正文）
#   scripts/fetch-upstream-notes.sh 0.19.0 --manifest  # 输出单行（用于 fpk manifest 的 changelog）
#
# 找不到记录时输出为空并返回 0，不阻断发布流程。
set -euo pipefail

version="${1:?用法: fetch-upstream-notes.sh <version> [--manifest]}"
mode="${2:-}"
upstream_repo="${UPSTREAM_REPO:-sqzw-x/amane}"
tag="v${version}"

raw=""
for ref in "$tag" "main"; do
    if raw=$(curl -fsSL --retry 2 --max-time 30 \
        "https://raw.githubusercontent.com/${upstream_repo}/${ref}/CHANGELOG.md" 2>/dev/null); then
        [ -n "$raw" ] && break
    fi
    raw=""
done

printf '%s' "$raw" | python3 -c '
import re
import sys

version, mode = sys.argv[1], sys.argv[2]
text = sys.stdin.read()

section = ""
pattern = re.compile(rf"^##\s*v?{re.escape(version)}\s*$", re.MULTILINE)
match = pattern.search(text)
if match:
    rest = text[match.end():]
    nxt = re.search(r"^##\s", rest, re.MULTILINE)
    section = (rest[: nxt.start()] if nxt else rest).strip()

if not section:
    sys.exit(0)


def clean(line: str) -> str:
    line = line.strip()
    line = re.sub(r"^#+\s*", "", line)
    line = line.replace("**", "").replace("`", "")
    line = re.sub(r"^\s*[-*]\s*", "", line)
    return line.strip()


if mode == "--manifest":
    # 压成一行：标题用「标题：」，条目用「；」分隔，供应用中心显示
    parts, current = [], ""
    for raw_line in section.splitlines():
        line = raw_line.rstrip()
        if not line.strip():
            continue
        if line.lstrip().startswith("#"):
            if current:
                parts.append(current)
                current = ""
            parts.append(f"{clean(line)}：")
        elif re.match(r"^\s*[-*]\s+", line):
            item = clean(line)
            current = f"{current}{item}；" if current else f"{item}；"
        else:
            current = f"{current}{clean(line)} " if current else f"{clean(line)} "
    if current:
        parts.append(current)
    text_out = f"上游 v{version}：" + "".join(parts)
    text_out = re.sub(r"；+", "；", text_out).rstrip("；")
    text_out = re.sub(r"\s+", " ", text_out).strip()
    if len(text_out) > 700:
        text_out = text_out[:700].rstrip("；，, ") + "…（详见 Release 页面）"
    print(text_out)
else:
    print(f"### 上游 v{version} 更新记录\n")
    print(section)
' "$version" "$mode"
