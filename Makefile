# amane-fnos 本地构建入口
#
#   make check   静态校验 + 渲染器/Compose 校验（不改动产物）
#   make fpk     校验并打包到 dist/
#   make clean   清理 dist/ 与 .cache/
#
# 依赖：bash、curl、python3、tar；可选 docker（用于 compose 语法校验）

SHELL := /bin/bash

.PHONY: help check fpk clean upstream

help:
	@grep -E '^#   make' -A0 Makefile | sed 's/^#   //'

check:
	bash scripts/validate-fpk.sh

fpk:
	bash scripts/build-fpk.sh

upstream:
	bash scripts/resolve-upstream.sh

clean:
	rm -rf dist .cache amane.fpk
