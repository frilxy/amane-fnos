# 安装、升级与卸载

## 安装

1. 从 [Releases](https://github.com/frilxy/amane-fnos/releases) 下载 `amane.fpk`
   （固定链接 `releases/latest/download/amane.fpk` 永远指向最新版）。
2. fnOS「**应用中心 → 手动安装**」，选择该文件。需要 Docker 运行时可用。
3. 安装向导：

   | 字段 | 默认 | 说明 |
   | --- | --- | --- |
   | Web 访问端口 | `8000` | 宿主机端口；容器内服务固定监听 8000 |
   | 出网代理（可选） | 空 | 例如 `http://host.docker.internal:7890`，留空＝容器直连。只接受 `http://` 与 `https://` |

   端口会被记录到 `${TRIM_PKGETC}/web-port`，代理记录到 `${TRIM_PKGETC}/proxy`，升级后保留。
4. 安装完成后打开应用，进入「**应用设置 → 授权目录**」把媒体文件夹授予 Amane
   —— 授权即时生效，见 [AUTHORIZATION.md](AUTHORIZATION.md)。

> 首次启动要拉取镜像（数百 MB）。应用中心显示「运行中」后可能还要几十秒服务才可用，
> 可以先 `docker logs -f amane` 看启动进度。

## 首次登录

- 浏览器访问 `http://<NAS 地址>:<端口>`。
- API Token 有三处可查：
  1. 「文件管理 → 应用文件 → amane → data → token」
  2. `docker logs amane` 的启动日志
  3. `docker exec amane cat /data/token`
- Token 只需输入一次，浏览器用 HttpOnly Cookie 保持登录。

## 数据与目录

| 内容 | 位置 |
| --- | --- |
| 数据库、Token、刮削结果、缩略图、日志 | `/vol*/@appshare/amane/data`（容器内 `/data`） |
| 应用配置目录（端口/代理/镜像覆盖等状态文件） | `/vol*/@appconf/amane/` |
| 安装目录 | `/vol*/@appcenter/amane/`（`docker/docker-compose.yaml` 与 `image`） |
| 应用日志 | `/var/log/apps/amane.log` |

备份 = 打包 `/vol*/@appshare/amane/data`；迁移 = 在新机器上先安装本包，
把该目录放回同一位置后重启应用。

## 升级

1. 下载新的 `amane.fpk`（版本号只前进：上游发版是 `0.19.0`，仅打包改动是 `0.19.0.1`）。
2. 应用中心手动安装覆盖。升级会保留：

   - 数据库与刮削结果（在 data-share 里）
   - 授权目录、端口、代理设置（fnOS 侧与会话状态文件）
   - 媒体文件（本应用从不修改挂载点以外的文件）

3. 升级后容器会按新版本镜像重建，Amane 自己完成数据库迁移；

> 第三方 fpk 不在飞牛应用商店，**不会自动升级**。订阅本仓库 Releases 可以第一时间拿到新包。

## 卸载

卸载向导里有「**同时删除 Amane 数据目录**」开关：

- 默认**保留**：`/vol*/@appshare/amane/data` 原样留下，重新安装后继续使用。
- 勾选则删除该共享目录（只删应用自己的目录，媒体文件与被授权挂载的宿主机目录不受影响）。

## 换端口 / 换镜像源 / 换代理

- **端口**：应用设置里直接改，保存后自动重建容器。
- **代理**：应用设置里的「出网代理」，留空＝沿用当前设置，填 `off` = 取消。
- **镜像**：在 `/vol*/@appconf/amane/image-override` 写一行镜像地址（例如自建代理或镜像站），
  重新生成 compose 时优先使用，升级后保留。

详细原理与排查见 [NETWORKING.md](NETWORKING.md) 与 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)。
