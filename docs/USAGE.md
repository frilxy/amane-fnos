# 使用说明

## 安装向导

| 字段 | 默认 | 说明 |
| --- | --- | --- |
| Web 访问端口 | `8000` | 宿主机端口，容器内固定 8000 |
| 出网代理（可选） | 空 | 如 `http://host.docker.internal:7890`；留空＝容器直连，只接受 `http/https` |

端口与代理会记到 `/vol*/@appconf/amane/`，升级后保留。

## 首次登录

浏览器打开 `http://<NAS 地址>:<端口>`，API Token 三处可查：
「文件管理 → 应用文件 → amane → data → token」、`docker logs amane`、`docker exec amane cat /data/token`。

## 数据与目录

| 内容 | 位置 |
| --- | --- |
| 数据库 / Token / 刮削结果 / 缩略图 / 日志 | `/vol*/@appshare/amane/data`（容器内 `/data`） |
| 应用配置（端口、代理、镜像覆盖） | `/vol*/@appconf/amane/` |
| 安装目录（compose、镜像地址） | `/vol*/@appcenter/amane/docker/` |
| 应用日志 | `/var/log/apps/amane.log` |

备份 = 拷贝 data 目录；迁移 = 新机器装好后把该目录放回同一位置再重启应用。

## 升级 / 卸载

- **升级**：下载新版本的 `amane-<版本>.fpk` 在应用中心覆盖安装。数据库、授权、端口、代理都保留；
  新包只换 compose 里的镜像 tag，启动时拉新镜像，Amane 自己做数据库迁移。
- **卸载**：向导里「同时删除数据目录」默认关闭；打开只删 `/vol*/@appshare/amane/data`，
  媒体文件不受影响。

## 授权与权限边界

| 层面 | 落地位置 | 作用 |
| --- | --- | --- |
| fnOS 授权目录 | 应用设置授权，写入 `TRIM_DATA_ACCESSIBLE_PATHS` | 给应用用户哪些目录的 ACL |
| Compose 挂载 | 整卷 `/vol1…/volN` + 授权目录精确挂载 | 容器里能看到哪些路径 |
| 容器身份 | `user: "<应用用户>:<应用组>"` | **真正的读写边界**（内核按它判 ACL） |

- 容器进程就是 fnOS 应用用户，**未授权目录即使挂着也读不到**。
- 授权目录**即时生效**，不需要重启；`AMANE_SAFE_DIRS` 默认 = 授权目录 + 数据目录
  （容器无法重建时自动退回 `ALLOW_ALL`）。
- 想自定义边界：在 `/vol*/@appconf/amane/safe-dirs` 写一行逗号分隔路径。

### 为什么「选择路径」点不进目录

fnOS 只给**授权目录本身** `r` 权限，**父目录只给穿越 `x` 不给列举 `r`**（实测：`ls /vol1/1000/download` 可以，
`ls /vol1`、`ls /vol1/1000` 被拒）。所以选择器从 `/` 逐级点击会在卷一级失败，而**手输完整路径只需要穿越权限**。

用法：直接手输绝对路径，或用选择器自带的路径输入框粘贴路径；默认配置下选择器会直接落在第一个授权目录里。

### 验证

```bash
sudo docker inspect amane --format '{{.Config.User}}'                                     # 应用用户
sudo docker inspect amane --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'
sudo docker exec amane env | grep AMANE_SAFE_DIRS
sudo docker exec amane ls -la /vol5/1000/lim | head     # 能列出 = 授权生效
sudo docker exec amane ls /vol5 2>&1 | head -1          # 被拒 = 正常
```

## 网络与代理

容器**不会**自动走 NAS 上的透明代理（OpenSurge / mihomo 的 TUN 只接管「网关指向 NAS 的局域网设备」的转发流量；
宿主与容器流量不在其中），Docker 守护进程默认也没有代理，所以 `ghcr.io` 拉取同样是直连。

三处可分别配置：

1. **应用内**（推荐，热生效）：Amane「设置 → 网络 → 代理」填 `http://host.docker.internal:7890`。
2. **容器级**：应用设置里的「出网代理」→ 写入 `HTTP_PROXY/HTTPS_PROXY/ALL_PROXY`。留空沿用，填 `off` 取消。
3. **镜像拉取**：给 Docker 守护进程配代理，或用 `image-override`（见下）。

compose 固定加了 `host.docker.internal:host-gateway`，所以用 `host.docker.internal` 不受 NAS 换 IP 影响。

```bash
docker exec amane python -c "import socket;socket.create_connection(('host.docker.internal',7890),5);print('proxy ok')"
docker exec -e HTTPS_PROXY=http://host.docker.internal:7890 amane \
  python -c "import urllib.request;print(urllib.request.urlopen('https://www.google.com',timeout=8).status)"
```

## 常用改动

- **端口**：应用设置里改，保存后自动重建容器。
- **代理**：同上；留空＝沿用，`off`＝取消。
- **镜像源**：`/vol*/@appconf/amane/image-override` 写一行可直连的镜像地址，升级后保留。
