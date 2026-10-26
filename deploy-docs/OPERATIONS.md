# 日常运维（smc-weknora）

## 0. 固定约定

所有命令都必须在 `/data/projects/weknora` 下、并显式带上**两个**编排文件和**项目名**，否则可能作用到其他服务：

```bash
cd /data/projects/weknora
CF="-p smc-weknora -f docker-compose.yml -f deploy-docs/docker-compose.smc.yml"
```

下文统一用 `sudo deploy-docs/wk.sh <子命令>` 封装（脚本内部已固定上述参数）。不使用封装时，把 `wk.sh <子命令>` 换成上面对应的 `docker compose $CF ...`。

> 这台主机上还跑着 multica / ai-coding-hatchet / onyx / open-notebook / release-server / nodeskclaw-meeting。**不要**执行不带 `-p` 和 `-f` 的 `docker compose down`，**不要**执行 `docker system prune`、`docker compose down -v`，也**不要**动其他项目。

## 1. 状态检查

```bash
sudo deploy-docs/wk.sh ps          # 5 个容器的状态与健康
sudo deploy-docs/wk.sh health      # 逐个容器健康状态 + 网页/API 探活
sudo deploy-docs/wk.sh version     # 当前运行的镜像与源码版本
```

等价的原生命令：

```bash
docker compose $CF ps
docker inspect --format '{{.Name}} {{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' \
  smc-weknora-frontend smc-weknora-app smc-weknora-docreader smc-weknora-postgres smc-weknora-redis
docker compose $CF exec -T app curl -s http://localhost:8080/health
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.102.104:18080/
# 监听地址取自 .env 的 WEKNORA_WEB_BIND / WEKNORA_WEB_PORT，改完执行 wk.sh up 生效
```

> 网页入口探活是唯一需要暴露端口的检查（当前绑定 192.168.102.104:18080）；`/health` 在 app 容器内，不要用宿主机 8080 去试（8080 属于其他服务）。

## 2. 日志

```bash
sudo deploy-docs/wk.sh logs            # 全部服务，最近 200 行
sudo deploy-docs/wk.sh logs app        # 单个服务
sudo deploy-docs/wk.sh logs app 1000   # 指定行数
sudo deploy-docs/wk.sh logs-f app      # 实时跟随（Ctrl+C 退出）
```

日志轮转已配置：单文件 20MB、保留 5 个。

解析卡住时优先看 `docreader`：

```bash
sudo deploy-docs/wk.sh logs docreader | tail -100
docker exec smc-weknora-docreader ls -l /tmp/docreader | tail
```

## 3. 启动 / 停止

```bash
sudo deploy-docs/wk.sh up         # 启动（必要时创建容器）
sudo deploy-docs/wk.sh stop       # 停止（保留容器与数据）
sudo deploy-docs/wk.sh start      # 启动已停止的容器
sudo deploy-docs/wk.sh restart    # 重启全部
sudo deploy-docs/wk.sh restart app
sudo deploy-docs/wk.sh down       # 删除容器与网络，数据卷保留
```

**禁止** `down -v` / `down --volumes`：会删掉数据库与上传文件。

## 4. 重建（改配置、换镜像）

```bash
sudo deploy-docs/wk.sh recreate app      # 按当前镜像重建单个容器
sudo deploy-docs/wk.sh up                # 应用 .env / 覆盖文件的变更
```

改 `.env` 后必须重建对应容器，仅 `restart` 不会重新读取环境变量：

```bash
sudo deploy-docs/wk.sh recreate app
```

> 环境变量优先级：`docker-compose.yml` 的 `environment:` 显式列出的变量会覆盖 `env_file` 里的同名值（两者的值都来自 `.env` 插值，实际一致）。只写进 `.env`、没在 `environment:` 里列出的变量，靠 `env_file` 传给容器。

## 5. 升级（源码版本）

**升级前先备份**（见 `BACKUP-RESTORE.md`），然后在仓库里更新代码并重建：

```bash
cd /data/projects/weknora
sudo deploy-docs/wk.sh backup            # 备份数据库 + 文件 + 配置

# 更新源码（本次部署未执行，由你按需决定）
sudo -u cowork git fetch --tags && sudo -u cowork git checkout <目标 tag 或 commit>

# 版本号、镜像标签同步修改
sudo sed -i 's|^WEKNORA_VERSION=.*|WEKNORA_VERSION=<新版本>|' .env

sudo deploy-docs/wk.sh build             # 重新构建三个镜像
sudo deploy-docs/wk.sh up                # 滚动启动；app 启动时自动执行数据库迁移
sudo deploy-docs/wk.sh health
```

- `AUTO_MIGRATE=true`，app 启动时会跑 `migrations/`；**只前进不回退**。
- 回滚不能只把镜像标签换回旧版：数据库已被迁移过，旧二进制可能读不了新 schema。正确做法是用升级前的备份恢复数据库（见 `BACKUP-RESTORE.md` 第 5 节）。
- 升级后若前端仍是旧页面，强制刷新（Ctrl+Shift+R）。

## 6. 常见故障

| 现象 | 排查 |
| --- | --- |
| 网页 502 / 空白 | `wk.sh ps` 看 app / frontend 是否健康；`wk.sh logs app` 看启动报错 |
| app 反复重启 | 多半是 `.env` 里 DB 凭据与已有数据卷不匹配（改过 `DB_PASSWORD` 但没改库）；看 `logs postgres` 与 `logs app` |
| 上传后一直 processing | `wk.sh logs docreader`；确认 `MAX_FILE_SIZE_MB` 与解析超时 |
| 模型测试失败 | 容器内出网正常吗：`docker exec smc-weknora-app curl -sS -m 8 -o /dev/null -w '%{http_code}' <模型地址>` |
| 登录后又跳回登录页 | 检查 `JWT_SECRET` 是否被改动（改动后所有已签发 token 失效） |
| 磁盘涨得快 | `docker system df`；日志已轮转，主要是镜像层与 `data-files` |

## 7. 资源占用

5 个容器常驻。实测内存占用见 `DEPLOYMENT.md`；主机 16C/31G，剩余充足。不要给 app 设过小的内存限制（文档解析与 OCR 峰值较高）。

## 8. 禁止项

- `docker system prune` / `docker volume prune` / `docker compose down -v`
- 删除 `smc-weknora-postgres-data` 卷"重装"
- 修改其他项目的 compose 文件或容器
- 把 `ports` 改成 `0.0.0.0` 或关闭认证来"解决"访问问题
- 把 `.env`、密钥贴进聊天、日志、README 或 git
