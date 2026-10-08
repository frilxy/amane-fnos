# amane-fnos

把上游 [sqzw-x/amane](https://github.com/sqzw-x/amane)（AI 时代的私人影库）的官方 Docker 镜像
打包成飞牛 fnOS 可以直接安装的 `.fpk` 应用包，并且**每天北京时间 06:00 自动检查上游更新**，
有新版就自动出包、发 Release。

- 镜像来源：`ghcr.io/sqzw-x/amane:<上游标签>`（上游官方多架构镜像，x86_64 由本包声明支持）
- 应用包名：`amane`
- 包管理器：fnOS 官方 `fnpack`
- 本仓库只包含打包工程与 CI，不包含上游源码

## 下载安装

| 方式 | 链接 |
| --- | --- |
| 最新版本（固定文件名，推荐） | `https://github.com/frilxy/amane-fnos/releases/latest/download/amane.fpk` |
| 全部版本 | [Releases](https://github.com/frilxy/amane-fnos/releases) |

安装步骤：

1. 打开 fnOS「应用中心 → 手动安装」，选择下载好的 `amane.fpk`（需要 Docker 运行时可用）。
2. 安装向导里填写 **Web 访问端口**（默认 `8000`，容器内服务固定监听 8000）和可选的
   **出网代理**（例如 `http://host.docker.internal:7890`，留空＝容器直连，详见下面的「网络与代理」）。
3. 安装完成后打开应用，进入「**应用设置 → 授权目录**」，把存放影视的文件夹（例如 `/vol1/media`）
   授予 Amane 并保存，然后**重启一次应用**。授权目录会在启动时被自动挂载进容器，
   同时写入容器的 `AMANE_SAFE_DIRS`；未授权的目录容器内看不到。
4. 首次登录：浏览器访问 `http://<NAS 地址>:<端口>`，API Token 见
   「文件管理 → 应用文件 → amane → data → token」，或执行 `docker logs amane` 从启动日志里取。

> 端口、代理、授权目录等改动都会由生命周期脚本重新生成 `docker-compose.yaml`，无需手工编辑任何文件。

## 自动更新机制

`.github/workflows/release.yml`：

- **定时**：`cron: 0 22 * * *` = 北京时间每天 **06:00**（GitHub cron 使用 UTC）。
- **检查内容**：
  1. 上游仓库最新的 `vX.Y.Z` 标签（`git ls-remote`，不受 API 限流影响）；
  2. 该标签镜像在 GHCR 上的 manifest digest（匿名 token 读取）。
- **出包判定**（任一命中即重新出包）：
  - 上游版本变化 → fpk 版本 = 上游版本，例如 `0.18.0`
  - 同一上游版本但镜像 digest 变了（上游重推同名 tag） → fpk 版本 = `0.18.0.1`
  - 本仓库的打包工程（`fpk/**`、`scripts/**`）有改动 → fpk 版本顺延 `0.18.0.2`
  - 手动触发并勾选 `force`
- **无事发生**：直接跳过，不产生新 Release。

手动触发：Actions → 「构建并发布 fpk」 → Run workflow，可填 `upstream_version` 指定版本、
勾选 `force` 强制重建。

只在推送 `v*` tag 时上游才会更新 GHCR 镜像，所以本包的更新节奏与上游发版一致。
如果希望跟到上游 `main` 分支的未发布提交，需要改成由 CI 自行 `docker build` 并推送到自己的
GHCR 命名空间（当前实现没有这么做，以保持包体积和构建时间可控）。

## 工作原理

```text
.
├── fpk/                          # fnOS 应用包工程（fnpack 的输入）
│   ├── manifest                  # 应用元信息；version/changelog 由 CI 注入
│   ├── ICON.PNG / ICON_256.PNG   # 64 / 256 图标（取自上游 assets/app.ico）
│   ├── config/
│   │   ├── privilege             # run-as=package，应用用户 amane
│   │   └── resource              # docker-project + data-share(amane/data)
│   ├── app/
│   │   ├── docker/
│   │   │   ├── image             # 固定镜像地址（CI 注入）
│   │   │   └── docker-compose.yaml   # 随包默认文件，运行时会被重新生成
│   │   └── ui/                   # 桌面入口 ui/config 与图标
│   ├── cmd/                      # 安装/升级/配置/卸载/启停生命周期脚本
│   │   └── lib/
│   │       ├── common.sh         # 渲染、状态探测、容器重建等公共函数
│   │       └── compose.sh        # 由「端口 + 授权目录」生成 docker-compose.yaml
│   └── wizard/                   # install / config / upgrade / uninstall 向导
├── scripts/
│   ├── resolve-upstream.sh       # 解析上游版本与镜像 digest
│   ├── render-fpk.sh             # 注入版本、镜像、changelog，重算默认 compose
│   ├── validate-fpk.sh           # 静态校验 + 渲染器/Compose 语法校验
│   └── build-fpk.sh              # 下载官方 fnpack、打包、产物校验
└── .github/workflows/            # build.yml（校验构建）/ release.yml（定时发布）
```

关键行为：

- `cmd/lib/compose.sh` 是唯一的 Compose 生成器：**运行时**由生命周期脚本调用，
  **CI 里**用同一份脚本生成随包默认文件，避免两份逻辑漂移。
- 授权目录只挂载管理员确实授权过的路径（逐个校验必须是 `/vol*` 下的真实目录，
  解析符号链接后再校验一次），不整卷挂载；`/etc/localtime` 以只读方式挂载保证容器时区正确。
- 容器以应用用户身份运行（`user: "<TRIM_UID>:<TRIM_GID>"`），这样 fnOS 给应用用户的
  授权目录 ACL 才能在容器内生效；数据目录使用 `data-share` 声明的
  `/vol*/@appshare/amane/data`，在「应用文件」里可见可备份。
- `cmd/main status` 优先 `docker inspect`，docker 不可用时回退探测
  `http://127.0.0.1:<端口>/api/health`，避免误报未运行。
- 端口会记录到 `${TRIM_PKGETC}/web-port`，代理会记录到 `${TRIM_PKGETC}/proxy`，
  升级或仅授权目录变化时不会丢失用户设置。
- 容器固定加上 `host.docker.internal:host-gateway` 映射：填代理地址时用
  `http://host.docker.internal:7890` 即可指向 NAS 宿主，NAS 换 IP 也不会失效。

## 网络与代理（容器为什么连不上）

容器里的 Amane 用的是 Docker 自己的网络，它**不会自动走 NAS 上的透明代理**。以 OpenSurge / mihomo
这类方案为例：

- 它们的 TUN 只接管「把网关/DNS 指向 NAS 的局域网设备」发来的转发流量；NAS 自身发起的流量由
  `local_system_proxy` 控制，而 fnOS 上该项不可用（OpenSurge 预设里是关闭的）。
- 容器的 DNS 继承宿主机 `/etc/resolv.conf`（通常是路由器），不做 fake-IP，也没有被 nftables 重定向，
  所以容器是**直连**出网：能通的站点很快，被墙或被限速的站点（TMDB、GitHub、图床等）就会超时/卡住。
- Docker 守护进程默认也没有配代理（`dockermgr.conf` 里 `proxies` 为空），`registry-mirrors`
  只对 Docker Hub 生效，对 `ghcr.io` 无效 —— 这也是**拉镜像**慢/失败的原因。

三处可以分别配置，建议至少配置前两项：

1. **应用内代理（推荐，热生效）**：Amane 界面里「设置 → 网络 → 代理」填
   `http://host.docker.internal:7890`（或 `http://<NAS IP>:7890`）。
   mihomo/OpenSurge 的 mixed 端口同时支持 HTTP 与 SOCKS，填 `http://` 最稳。
   对应的配置文件是 `/vol*/@appshare/amane/data/config.toml` 里的 `[network] proxy`。
2. **容器级代理（安装/应用设置里的「出网代理」）**：填同一个地址，会写进容器的
   `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY`（附 `NO_PROXY`），保存即重建容器；
   留空＝沿用当前设置，填 `off`＝取消代理。适合插件、外链下载等所有容器内出网流量。
3. **镜像拉取代理**：在 fnOS 的 Docker 设置里给守护进程配 HTTP(S) 代理；或者用上面的
   `image-override` 把镜像换成可直连的镜像地址。

排查用的几条命令（在 NAS 的 SSH 里执行）：

```bash
# 容器能不能访问宿主上的代理端口
docker exec amane python -c "import socket;s=socket.create_connection(('host.docker.internal',7890),5);print('proxy ok')"

# 直连 vs 走代理（走代理返回 200 说明代理可用、直连不通）
docker exec amane python -c "import urllib.request;print(urllib.request.urlopen('https://www.google.com',timeout=8).status)"
docker exec -e HTTPS_PROXY=http://host.docker.internal:7890 amane \
  python -c "import urllib.request;print(urllib.request.urlopen('https://www.google.com',timeout=8).status)"

# DNS 是否被污染（返回 198.18.x.x 或明显异常地址即为污染）
docker exec amane python -c "import socket;print(socket.gethostbyname('www.google.com'))"
```

## 更新与升级

- **`.fpk` 只有几十 KB，是正常的**：包里只有 manifest、图标、向导 JSON、生命周期脚本和一份
  `docker-compose.yaml`；几百 MB 的容器镜像不在包里，是安装后由 NAS 的 Docker 从
  `ghcr.io/sqzw-x/amane:<版本>` 拉取的。（好处：出包只要几秒，仓库也不会膨胀。）
- **后续更新怎么做**：下载新的 `amane.fpk`，在应用中心手动安装覆盖即可（走升级流程）。
  数据库、Token、刮削结果、缩略图都在 `data-share`（`/vol*/@appshare/amane/data`）里，
  授权目录、端口、代理设置也都保留；新包只是把 compose 里的镜像 tag 换成新版本，
  启动时 Docker 拉新镜像，Amane 自己完成数据库迁移。
- 第三方 fpk 不在飞牛应用商店里，**不会自动升级**；想省事就订阅本仓库的 Releases（Watch → Custom → Releases）。
- 版本号只会前进：上游发版 → `0.19.0`；只改了打包工程 → `0.19.0.1`。重复安装同一版本没有意义。

## 本地构建

Linux x86_64，需要 `bash`、`curl`、`python3`、`tar`，可选 `docker`（用于 Compose 语法校验）：

```bash
bash scripts/resolve-upstream.sh                       # 看看上游最新版本
bash scripts/render-fpk.sh 0.18.0 ghcr.io/sqzw-x/amane:0.18.0
bash scripts/validate-fpk.sh                           # 静态校验
bash scripts/build-fpk.sh                              # 下载 fnpack 并打包
ls dist/                                               # dist/amane-0.18.0.fpk、dist/amane.fpk
```

`fnpack` 版本与下载地址可用 `FN_PACK_VERSION` / `FN_PACK_URL` 覆盖。
本地打包产物可以用 `appcenter-cli install-fpk dist/amane.fpk` 在 fnOS 设备上安装测试。

## 高级用法

- **换镜像源**：在应用配置目录（`/vol*/@appconf/amane/`）放一个 `image-override` 文件，
  内容是一行镜像地址（例如私有代理 `https://ghcr.nju.edu.cn/...` 对应的镜像名），
  重新生成时优先使用它，且升级后依然保留。
- **改端口**：应用设置里直接修改，入口与端口映射会一起更新。
- **改代理**：应用设置里的「出网代理」修改/留空（沿用）/填 `off`（取消）；也可以只在 Amane
  界面里设 `network.proxy`，两者互不冲突。
- **卸载保留数据**：卸载向导默认保留数据；勾选「同时删除 Amane 数据目录」才会删除
  `/vol*/@appshare/amane/data`（只删应用自己的共享目录，媒体文件不受影响）。

## 已知限制

- **架构**：`platform = all`，x86_64 与 ARM 都可安装（上游镜像是 `amd64/arm64` 多架构的，
  已确认索引里两个架构都存在）。**ARM 设备未做实机验证**：包本身只含配置与脚本、
  不含任何架构相关二进制，理论上直接可用；如果在 ARM 上装出问题，请带 `docker logs amane` 提 issue。
- 容器名固定为 `amane`、默认端口 `8000`。如果你之前用 `docker compose` 手工跑过 amane，
  请先 `docker compose down` 再安装本包，否则容器名/端口会冲突。
- 拉取 `ghcr.io` 依赖网络环境；无法直连时可以配置 Docker 镜像代理或使用上面的 `image-override`。
- 首次启动需要拉取镜像（数百 MB），应用状态为“运行中”后仍可能再等几十秒服务才可用。
- GitHub 会在仓库连续 60 天没有提交活动后停用定时工作流（会提前发邮件提醒）；
  长期不更新仓库时，往 `main` 推一次提交或用 `workflow_dispatch` 手动跑一次即可恢复。
- 「打包指纹」只统计 `fpk/**` 与 `scripts/**`：改这两个目录会在下一次定时运行时自动重新出包，
  只改 README 或工作流本身不会产生新版本（需要时可手动 `force`）。

## 说明

- 本仓库为社区打包工程，与 amane 上游作者无关；应用功能、镜像内容与缺陷归属上游
  [sqzw-x/amane](https://github.com/sqzw-x/amane)。
- 图标取自上游 `assets/app.ico`；上游项目采用 GPLv3。
