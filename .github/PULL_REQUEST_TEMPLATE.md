## 改了什么

<!-- 简要说明；若是修复，请写清现象与根因 -->

## 类型

- [ ] 修复（bug fix）
- [ ] 新能力（feature）
- [ ] 文档
- [ ] CI / 构建
- [ ] 其它

## 自检

- [ ] `make check` 通过（`scripts/validate-fpk.sh`）
- [ ] 改了 `fpk/**` 或 `scripts/**`（会触发下一次定时发布重新出包）
- [ ] 涉及挂载 / 环境变量时，已确认 `docker compose config` 能解析生成的 compose
- [ ] 涉及权限、路径、用户输入时，已说明安全影响
- [ ] 文档已同步（README / `docs/` / `CHANGELOG.md`）

## 真机验证（可选，改行为时建议填）

- 设备架构与 fnOS 版本：
- 验证步骤与结果：

## 关联 Issue

<!-- 例如 Closes #12 -->
