# 网络与代理（容器为什么连不上）

容器里的 Amane 用的是 Docker 自己的网络，**不会自动走 NAS 上的透明代理**。
以 OpenSurge / mihomo 这类方案为例，实测原因如下：

- 它们的 TUN 只接管「把网关 / DNS 指向 NAS 的局域网设备」发来的转发流量；
  NAS 自身发起的流量由 `local_system_proxy` 控制，而 fnOS 上该项不可用（OpenSurge 预设里是关闭的）。
- 容器的 DNS 继承宿主机 `/etc/resolv.conf`（通常是路由器），不做 fake-IP，也没有被 nftables 重定向，
  所以容器是**直连**出网：能通的站点很快，被墙或被限速的站点（TMDB、GitHub、图床等）就会超时 / 卡住。
- Docker 守护进程默认也没有配代理（`dockermgr.conf` 里 `proxies` 为空），`registry-mirrors`
  只对 Docker Hub 生效，对 `ghcr.io` 无效 —— 这也是**拉镜像**慢 / 失败的原因。

## 三处可以分别配置（建议至少前两项）

1. **应用内代理（推荐，热生效）**：Amane 界面「设置 → 网络 → 代理」填
   `http://host.docker.internal:7890`（或 `http://<NAS IP>:7890`）。
   mihomo / OpenSurge 的 mixed 端口同时支持 HTTP 与 SOCKS，填 `http://` 最稳。
   对应配置文件是 `/vol*/@appshare/amane/data/config.toml` 的 `[network] proxy`。
2. **容器级代理**：应用设置里的「出网代理」，会写进容器的
   `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY`（附 `NO_PROXY`），保存即重建容器；
   留空＝沿用，填 `off`＝取消。适合插件、外链下载等所有容器内出网流量。
3. **镜像拉取代理**：在 fnOS 的 Docker 设置里给守护进程配 HTTP(S) 代理；
   或用 `/vol*/@appconf/amane/image-override` 把镜像换成能直连的地址。

> 本包的 compose 固定加了 `host.docker.internal:host-gateway` 映射，
> 所以代理地址填 `http://host.docker.internal:7890` 不会因为 NAS 换 IP 而失效。

## 排查命令（NAS 的 SSH 里执行）

```bash
# 容器能不能访问宿主上的代理端口
docker exec amane python -c "import socket;socket.create_connection(('host.docker.internal',7890),5);print('proxy ok')"

# 直连 vs 走代理（走代理返回 200 说明代理可用、直连不通）
docker exec amane python -c "import urllib.request;print(urllib.request.urlopen('https://www.google.com',timeout=8).status)"
docker exec -e HTTPS_PROXY=http://host.docker.internal:7890 amane \
  python -c "import urllib.request;print(urllib.request.urlopen('https://www.google.com',timeout=8).status)"

# DNS 是否被污染（返回 198.18.x.x 或明显异常地址即为污染）
docker exec amane python -c "import socket;print(socket.gethostbyname('www.google.com'))"

# 镜像拉取是否正常
docker image ls ghcr.io/sqzw-x/amane
docker pull ghcr.io/sqzw-x/amane:0.18.0
```

## 判断 NAS 上的透明代理是否覆盖容器

```bash
ip route | head -3                 # 默认路由是否指向 TUN / 路由器
ip -br link | grep -iE 'tun|utun'  # TUN 是否存在
ss -ltn | grep -E ':(7890|1080|53)' # 代理端口是否监听、是否绑定在 0.0.0.0
```

经验：如果代理端口监听在 `*:7890`（而不是 `127.0.0.1:7890`），容器就能通过
`host.docker.internal` 访问到它；如果只监听回环，容器访问不到，需要改成监听全部地址。

## 结果

配好代理后建议重启一次应用，然后在 Amane 里跑一次「扫描」，观察
「任务队列 / 结构化日志」里的网络错误是否消失。仍有问题请看
[TROUBLESHOOTING.md](TROUBLESHOOTING.md)。
