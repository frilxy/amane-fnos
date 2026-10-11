# 排障

先跑体检脚本，多数问题它会直接给结论和修复命令：

```bash
sudo bash tools/doctor.sh
```

## 报 `No safe directories configured.` / 应用功能不对

说明跑着的容器不是本应用的 compose 创建的（常见于手工建的同名容器占了容器名）：

```bash
sudo docker inspect amane --format 'PROJECT=[{{index .Config.Labels "com.docker.compose.project"}}] FILES=[{{index .Config.Labels "com.docker.compose.project.config_files"}}]'
```

- `FILES` 不是 `/vol6/@appcenter/amane/docker/docker-compose.yaml`（或没有标签）→
  在「Docker」应用里删掉那个容器（连同同名定义），然后：
  ```bash
  sudo docker rm -f amane
  sudo docker compose -p amane -f /vol6/@appcenter/amane/docker/docker-compose.yaml up -d
  ```
- `FILES` 正确但仍报错 → 容器比 compose 旧，用上面同样两条命令重建一次。

## 授权了目录但读不到

```bash
sudo docker exec amane ls -la /vol5/1000/lim | head   # 能列出 = 正常
sudo docker exec amane ls /vol5 2>&1 | head -1        # 被拒 = 正常（父目录不可列举）
```

两条都失败时：到「应用设置 → 授权目录」取消后重新授权，再重启应用。

## 改了端口 / 代理没生效

这两个写在 compose 里，必须重建容器。正常会自动重建（日志出现 `已按最新配置重建容器 amane`），否则：

```bash
sudo docker compose -p amane -f /vol6/@appcenter/amane/docker/docker-compose.yaml up -d
```

日志出现「当前身份无权访问 Docker」时补一下用户组再重启应用：

```bash
id amane                       # 应包含 docker
sudo usermod -aG docker amane
```

## 网页打不开

```bash
sudo docker logs --tail 200 amane                          # 拉镜像 / 迁移 / 端口冲突
curl -s http://127.0.0.1:8000/api/health                   # 期望 {"status":"ok",...}
```

首次启动要拉几百 MB 镜像；端口被占用时安装/保存设置的日志会点名占用容器。

## 反馈问题

```bash
sudo bash tools/doctor.sh 2>&1 | tee /tmp/amane-doctor.txt
sudo docker logs --tail 200 amane > /tmp/amane-container.log 2>&1
```

把这两个文件附在 Issue 里（先确认不含 Token 等敏感信息）。
应用本身的功能 / 刮削问题请提到[上游](https://github.com/sqzw-x/amane/issues)。
