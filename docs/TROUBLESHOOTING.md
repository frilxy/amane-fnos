# 排障

先跑一遍体检脚本，多数问题它会直接指出结论：

```bash
sudo bash tools/doctor.sh
```

它检查：容器是不是本应用创建的、身份与挂载、`AMANE_SAFE_DIRS`、授权目录在容器内是否可读、
端口占用、应用日志尾部。

## 应用显示「运行中」，但选路径报 `No safe directories configured.`

这句话的含义是：**正在跑的容器里没有可用的安全目录**，通常说明这个容器不是按本应用的 compose 创建的。
先分清两种情况：

```bash
sudo docker inspect amane --format '{{.Config.User}}'
sudo docker inspect amane --format 'PROJECT=[{{index .Config.Labels "com.docker.compose.project"}}] FILES=[{{index .Config.Labels "com.docker.compose.project.config_files"}}]'
sudo docker inspect amane --format '{{range .Mounts}}{{printf "%s -> %s\n" .Source .Destination}}{{end}}'
sudo docker inspect amane --format '{{range .Config.Env}}{{println .}}{{end}}' | grep AMANE
```

本应用创建的容器应该长这样：

- `user` = 应用用户:应用组（例如 `962:956`）
- `PROJECT=[amane]`、`FILES=[/vol6/@appcenter/amane/docker/docker-compose.yaml]`
- 挂载里有 `/data`、`/vol1`…`/volN`（整卷）以及你授权目录里的具体路径
- 环境变量里有 `AMANE_SAFE_DIRS`

### 情况 A：`FILES` 不是上面的路径，甚至完全没有 compose 标签

这是一个**手工创建的容器**（在「Docker」应用里用「容器 → 创建」建的：通常只挂 `/data`，
`/media` 是镜像 `VOLUME ["/data","/media"]` 自动产生的匿名卷，并带 fnOS 注入的时区挂载；
环境变量里一个 `AMANE_*` 都没有）。它占住了 `amane` 这个容器名，应用中心就无法创建自己的容器。

处理：

1. 在「Docker」应用里删除该容器（以及同名的容器定义 / 项目）。
2. 回到应用中心启动 Amane；或直接执行：

   ```bash
   sudo docker rm -f amane
   sudo docker compose -p amane -f /vol6/@appcenter/amane/docker/docker-compose.yaml up -d
   ```

### 情况 B：`FILES` 正确，但仍然报错

说明容器比 compose 旧（安全目录 / 挂载是后加的，而环境变量只在容器创建时写入）：

```bash
sudo docker rm -f amane
sudo docker compose -p amane -f /vol6/@appcenter/amane/docker/docker-compose.yaml up -d
sudo docker exec amane env | grep AMANE_SAFE_DIRS
```

## 授权了目录，但在 Amane 里选不到 / 读不到

1. 确认授权**保存成功**：应用设置里能看到该目录；应用日志里应出现
   `已授权目录：/vol5/1000/lim`。
2. 确认容器里能读：

   ```bash
   sudo docker exec amane ls -la /vol5/1000/lim | head   # 能列出 = 授权生效
   sudo docker exec amane ls /vol5 2>&1 | head -1        # 被拒 = 正常（父目录不可列举）
   ```

   `ls /vol5` 被拒**不是故障**，原因见 [AUTHORIZATION.md](AUTHORIZATION.md#为什么选择路径点不进去)。
3. 如果 `ls /vol5/1000/lim` 也报 Permission denied：在「授权目录」里取消再重新授权一次，
   然后重启应用（让容器按新配置重建）。

## 改了端口 / 代理 / 授权目录，没生效

- **授权目录**：容器整卷挂载，ACL 在宿主机侧即时生效，不需要重建。
- **端口 / 代理**：写在 compose 的 `ports` / `environment` 里，**必须重建容器**。
  本包的应用用户加入了 `docker` 组，正常情况下保存设置后日志里会出现
  `已按最新配置重建容器 amane`。若没有：

  ```bash
  # 「Docker」应用 → 项目 → amane → 重新部署；或：
  sudo docker compose -p amane -f /vol6/@appcenter/amane/docker/docker-compose.yaml up -d
  ```

- 日志里出现「当前身份无权访问 Docker」说明 `join-groups` 没生效（或应用用户不在 docker 组）：

  ```bash
  id amane                      # 应包含 docker 组
  sudo usermod -aG docker amane # 必要时手动补，然后重启应用
  ```

## 日志里出现「检测到容器 amane 由其它 Compose 项目创建」

同名容器属于别的 Compose 项目，本应用无法接管。按日志给出的命令删除后重建：

```bash
sudo docker rm -f amane
sudo docker compose -p amane -f /vol6/@appcenter/amane/docker/docker-compose.yaml up -d
```

## 应用中心显示运行中，但网页打不开

```bash
sudo docker logs --tail 200 amane      # 镜像是否拉完、数据库迁移是否失败、端口是否冲突
sudo docker exec amane env | grep AMANE_PORT
curl -s http://127.0.0.1:8000/api/health   # 期望 {"status":"ok", ...}
```

常见原因：首次拉镜像还没完成、端口被其它容器占用（安装/保存设置时日志会点名占用者）、
代理没配导致镜像拉取失败。

## 状态一直显示「未运行」

`cmd/main status` 会先试 `docker inspect`，失败时回退探测 `http://127.0.0.1:<端口>/api/health`。
两者都失败才会返回「未运行」。可以手动确认：

```bash
sudo docker inspect -f '{{.State.Running}}' amane
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8000/api/health
```

## 想彻底重来（保留数据）

```bash
# 1) 卸载应用但保留数据（卸载向导里不要勾选删除数据）
# 2) 确认残留容器已删除
sudo docker ps -a --filter name=amane
sudo docker rm -f amane
# 3) 重新安装 fpk，数据仍在 /vol*/@appshare/amane/data
```

## 收集信息反馈问题

```bash
sudo bash tools/doctor.sh 2>&1 | tee /tmp/amane-doctor.txt
sudo docker logs --tail 200 amane > /tmp/amane-container.log 2>&1
tail -100 /var/log/apps/amane.log > /tmp/amane-app.log 2>&1
```

把这三个文件附在 Issue 里（注意先自行检查是否含 Token 等敏感信息）。
