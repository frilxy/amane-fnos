# 更新日志

版本号 = 上游版本；只有打包工程变动时追加序号。产物见 [Releases](https://github.com/frilxy/amane-fnos/releases)。

## 0.19.0.1
发布时自动带上上游更新记录：Release 正文会附上该版本的上游 `CHANGELOG.md` 条目，
fpk 的 `changelog` 字段也写入压缩版摘要（应用中心的更新说明里能直接看到改了什么）。

## 0.19.0
定时任务自动同步上游 `v0.19.0`，只替换镜像 tag，覆盖安装即可。

## 0.18.0.5
`AMANE_SAFE_DIRS` 默认 = 授权目录 + 数据目录（选择器直接落在授权目录里）；
容器无法重建时自动退回 `ALLOW_ALL`；文档补充「选择路径用不了但手输可以」。

## 0.18.0.4
授权改为宿主机 ACL 即时生效：整卷挂载 `/vol1…/volN` + 授权目录精确挂载，授权变更不再依赖重建容器。

## 0.18.0.3
`join-groups: ["docker"]`：应用可自行重建容器，端口/代理/授权改动保存即生效；新增端口冲突检测与冲突提示。

## 0.18.0.2
随包默认 compose 改用 `${TRIM_UID}` / `${TRIM_DATA_SHARE_PATHS}` 占位；无法重建容器时日志给出结论与命令。

## 0.18.0.1
支持 ARM（`platform = all`，未实机验证）；新增「出网代理」向导项与 `host.docker.internal` 映射。

## 0.18.0
首个版本：官方镜像打包为 fnOS `docker-project` + `data-share` 应用包，
按端口与授权目录渲染 compose，数据落在应用共享目录，每天自动检查上游。
