# 更新日志

本仓库的版本号 = 上游版本（例如 `0.18.0`）；只有打包工程变动时追加序号（`0.18.0.1`、`0.18.0.2`…）。
完整产物与说明见 [Releases](https://github.com/frilxy/amane-fnos/releases)。

## 0.19.0

- 定时任务自动同步上游 `v0.19.0`：仅替换 compose 中的镜像 tag，
  打包工程未改动，安装覆盖即可，数据与授权设置全部保留。

## 0.18.0.5

- **选择器与授权落地对齐**：`AMANE_SAFE_DIRS` 改为「已授权目录 + 数据目录」（精确模式），
  文件选择器默认落在第一个授权目录里，打开即可选中，不必逐级点击。
- **回退保护**：容器无法自动重建时（无 docker 权限 / 撞名 / `up -d` 失败）自动退回
  `ALLOW_ALL` 宽松模式，避免新授权的目录被旧列表挡住。
- 三种取值来源：`etc/safe-dirs` 文件 > permissive > precise。
- 文档新增「选择路径用不了但手输可以」的实测说明。

## 0.18.0.4

- **授权改为宿主机 ACL 即时生效**：容器按卷挂载 `/vol1`…`/volN`，并把授权目录再精确挂载一次；
  授权变更不再依赖重建容器。跳过 `vol0*` 系统卷。
- `AMANE_SAFE_DIRS` 默认 `ALLOW_ALL`，amane 自身边界交给 fnOS 授权目录的 ACL。
- README 明确三层边界（授权列表 / Compose 挂载 / 容器身份）与严格模式做法。

## 0.18.0.3

- `config/privilege` 增加 `join-groups: ["docker"]`：生命周期脚本可以自己
  `docker compose up -d` 重建容器，端口 / 代理 / 授权变更保存即生效（真机验证通过）。
- 新增端口冲突检测：安装 / 保存设置时若端口被别的容器占用，日志直接点名占用者。
- 检测到容器属于其它 Compose 项目时，日志给出可复制的修复命令。

## 0.18.0.2

- 随包默认 compose 改用 `${TRIM_UID}` / `${TRIM_DATA_SHARE_PATHS}` 占位：
  即使应用中心在 `install_callback` 之前创建容器，身份与数据目录也正确。
- 无法自动重建容器时不再静默跳过，日志给出结论与命令。
- README 新增排障章节（区分「手工容器」与「容器旧于 compose」）。

## 0.18.0.1

- **ARM 支持**：`platform` 改为 `all`（上游镜像是 `amd64/arm64` 多架构），
  应用详情页与文档注明「ARM 未实机验证」。
- **出网代理**：安装 / 应用设置新增「出网代理」向导项，写入容器
  `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` / `NO_PROXY`；留空沿用，填 `off` 取消。
- compose 固定加 `host.docker.internal:host-gateway`，代理地址不受 NAS 换 IP 影响。
- README 新增「网络与代理」「更新与升级」两节。

## 0.18.0

首个版本：

- 把上游官方镜像 `ghcr.io/sqzw-x/amane:<版本>` 打包成 fnOS `.fpk`
  （`docker-project` + `data-share`，`run-as=package`）。
- 生命周期脚本按「访问端口 + 授权目录」渲染 `docker-compose.yaml`；
  只挂载 `/vol*` 下真实存在、且解析符号链接后仍在卷内的目录，并同步 `AMANE_SAFE_DIRS`。
- 容器以 fnOS 应用用户身份运行，授权目录 ACL 才能在容器内生效；
  数据落在应用共享目录 `/vol*/@appshare/amane/data`。
- `status` 优先 `docker inspect`，docker 不可用时回退探测 `/api/health`。
- 端口 / 代理持久化在应用配置目录，升级不丢。
- GitHub Actions：`build.yml` 校验 + 打包，`release.yml` 每天北京时间 06:00
  检查上游标签与 GHCR 镜像 digest，有变化才出包并发布 Release。
