# WeKnora 部署说明（smc-weknora）

## 1. 结论

WeKnora 标准版已按官方 Docker Compose 部署在本机。三个业务镜像**从本地源码构建**：仓库现有版本比最近的官方发布 tag 新 154 个提交，官方没有与之对应的固定镜像，因此既没有使用浮动 `latest`，也没有混用发布版镜像。

| 项目 | 值 |
| --- | --- |
| 部署版本 | `0.8.3-dev.e1f9a616`（源码 `VERSION`=0.8.3，`git describe` = `v0.8.3-154-ge1f9a6166`） |
| 分支 / 提交 | `main` / `e1f9a6166a593a4804a2f99f1d942919c9cc8ea7` |
| 部署前工作区 | `git status` 为空（无本地修改）；未执行 pull、未切分支、未覆盖文件 |
| 源码目录 | `/data/projects/weknora` |
| Compose 项目名 | `smc-weknora` |
| 编排文件 | 官方 `docker-compose.yml`（未修改）+ 覆盖 `deploy-docs/docker-compose.smc.yml` |
| 网页入口 | **`http://192.168.102.104:18080`**（局域网可访问） |
| API Base URL | `http://192.168.102.104:18080/api/v1`（前端 Nginx 统一代理） |
| 监听地址 | 绑定网卡 `enp5s0`（192.168.102.104/24），**未绑定 0.0.0.0** |
| 时区 | Asia/Shanghai |
| 部署时间 | 2026-10-24 20:43（UTC+8） |

仓库里没有 `AGENTS.md`；本部署依据 `README.md`、`docs/`、`website-docs/`、`docker-compose.yml`、`.env.example`、`config/config.yaml`、`scripts/` 完成。

## 2. 镜像

| 服务 | 镜像 | 镜像 ID | 来源 |
| --- | --- | --- | --- |
| frontend | `wechatopenai/weknora-ui:0.8.3-dev.e1f9a616` | `sha256:95992bc6306b` | `frontend/Dockerfile` |
| app | `wechatopenai/weknora-app:0.8.3-dev.e1f9a616` | `sha256:3944258a3048` | `docker/Dockerfile.app` |
| docreader | `wechatopenai/weknora-docreader:0.8.3-dev.e1f9a616` | `sha256:81f3682566c1` | `docker/Dockerfile.docreader` |

基础设施镜像按官方固定版本拉取（非 latest）：

| 用途 | 镜像 | 镜像 ID |
| --- | --- | --- |
| 数据库 / 向量 / 全文索引 | `paradedb/paradedb:v0.25.11-pg17` | `sha256:78d65750f0f8` |
| 队列 / 流 | `redis:7.0-alpine` | `sha256:c9d92d840fd0` |

三者由同一份源码、同一次构建产出，不存在前后端与解析服务版本混用。

## 3. 服务与端口

| 服务 | 容器名 | 容器内端口 | 宿主机映射 | 说明 |
| --- | --- | --- | --- | --- |
| frontend | `smc-weknora-frontend` | 80 | **192.168.102.104:18080** | 网页 + `/api/`、`/files`、`/r/` 反向代理 |
| app | `smc-weknora-app` | 8080 | 无 | Go 后端 API（仅容器网络） |
| docreader | `smc-weknora-docreader` | 50051 (gRPC) | 无（仅 `expose`） | 文档解析 |
| postgres | `smc-weknora-postgres` | 5432 | 无 | ParadeDB / PostgreSQL 17 |
| redis | `smc-weknora-redis` | 6379 | 无 | Asynq 队列与流 |

- 只有前端绑定宿主机，且**只绑定局域网网卡地址**。没有用 `0.0.0.0`：那样会连 `docker0` 和各 `br-*` 网桥一起监听，等于对所有容器网络暴露。
- 数据库、Redis、docreader、后端 API 都不对宿主机监听。
- 未启用 `full` profile：无 Neo4j / Milvus / MinIO / Langfuse / SearXNG / Agent 沙箱；未挂载 `/var/run/docker.sock`。
- 网络：`smc-weknora-net`（bridge，显式命名）。
- 防火墙：`ufw` 处于 inactive，`iptables INPUT` 策略为 ACCEPT，本次**未修改任何防火墙规则**。

## 4. 数据卷与宿主机路径

| 卷（Docker 名） | 容器内 | 宿主机路径 | 初始大小 |
| --- | --- | --- | --- |
| `smc-weknora-postgres-data` | `/var/lib/postgresql/data` | `/var/lib/docker/volumes/smc-weknora-postgres-data/_data` | 147M |
| `smc-weknora-data-files` | `/data/files` | `/var/lib/docker/volumes/smc-weknora-data-files/_data` | 空 |
| `smc-weknora-docreader-tmp` | `/tmp/docreader` | `/var/lib/docker/volumes/smc-weknora-docreader-tmp/_data` | 空 |
| `smc-weknora-redis-data` | `/data` | `/var/lib/docker/volumes/smc-weknora-redis-data/_data` | 52K |

卷名在覆盖文件中用 `name:` 显式固定，删除/重建项目不会改名，也不会与其他 WeKnora 实例冲突。

## 5. 配置来源

- `/data/projects/weknora/.env`：实际生效配置，权限 `640 root:cowork`，已追加到 `.git/info/exclude`（不改动受版本管理的 `.gitignore`，仓库仍保持干净）。
- `config/config.yaml`：官方配置，只读挂载进 app，未修改。
- `deploy-docs/docker-compose.smc.yml`：唯一新增的编排调整。

覆盖文件做了 5 件事：

1. 前端端口强制为 `${WEKNORA_WEB_BIND}:${WEKNORA_WEB_PORT}:80`（`!override`，当前 `192.168.102.104:18080`，原 `80:80` 公开映射不再保留）；
2. 移除 app 的宿主机端口映射（`!reset`），API 只能经前端代理；
3. 容器名统一加 `smc-weknora-` 前缀；
4. 网络与数据卷显式命名；
5. Redis 增加持久化卷；5 个服务配置 json-file 日志轮转（20MB × 5）。

监听地址由 `.env` 的两个变量控制，改完执行 `wk.sh up` 即生效（改端口会重建前端容器，不是 restart）：

| 变量 | 当前值 | 说明 |
| --- | --- | --- |
| `WEKNORA_WEB_BIND` | `192.168.102.104` | 改成 `127.0.0.1` 即回到仅本机 |
| `WEKNORA_WEB_PORT` | `18080` | 宿主机端口 |

## 6. 访问方式

局域网内任意电脑：

```
http://192.168.102.104:18080
```

服务器本机也可直接用该地址。命令行自检：

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.102.104:18080/            # 200
curl -s http://192.168.102.104:18080/api/v1/auth/config                            # registration_mode
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.102.104:18080/api/v1/knowledge-bases  # 401（未登录）
sudo deploy-docs/wk.sh health
```

- 服务器换 IP 或改回仅本机：改 `.env` 的 `WEKNORA_WEB_BIND` → `sudo deploy-docs/wk.sh up`。
- 目前是纯 HTTP。若后续要域名 + HTTPS，建议在前面加反向代理（Nginx/Caddy）并申请证书，不要让 WeKnora 容器直接暴露 80/443。
- 需要更严格的来源限制时，可在网络层（交换机 ACL / 主机防火墙）限定网段，不要靠关闭认证解决。

## 7. 资源占用（空闲态实测）

| 容器 | 内存 |
| --- | --- |
| smc-weknora-app | 197 MiB |
| smc-weknora-postgres | 208 MiB |
| smc-weknora-docreader | 101 MiB |
| smc-weknora-frontend | 13 MiB |
| smc-weknora-redis | 5 MiB |
| 合计 | 约 520 MiB |

主机 16 vCPU / 31 GiB / 913 GB（可用 694 GB），余量充足。解析大文件时 docreader 与 app 会短时上涨。

## 8. 部署验证记录

| 检查项 | 结果 |
| --- | --- |
| 5 个容器 | 全部 Up，app/docreader/postgres healthy，重启次数 0 |
| 数据库迁移 | `Database migrated from version 0 to 133`，89 张表 |
| 网页（宿主本机） | `GET /` 200，`/assets/main-*.js` 200（200 KB） |
| 网页（另一台电脑，局域网） | TCP 18080 可连，`GET /` 200，`<title>WeKnora</title>`，4657 字节 |
| API 代理 | `GET /api/v1/auth/config` 200 `{"registration_mode":"self_serve"}`（本机与局域网均通过） |
| 未登录保护 | `/api/v1/knowledge-bases`、`/api/v1/tenants` 均 401 |
| 监听范围 | 只有 `192.168.102.104:18080`；`127.0.0.1:18080` 不再监听 |
| 注册/登录接口 | 空参返回 400（路由正常，未创建任何账号） |
| 受控重启 | `stop` → `start` 后健康恢复，文件与数据库标记均保留 |
| 其他业务容器 | 重启前后 `docker ps` 列表完全一致（14 个） |

## 9. 与官方编排的差异（审计用）

- 未修改 `docker-compose.yml`、`.env.example`、`config/config.yaml`，便于后续跟进上游。
- 新增文件：`.env`、`deploy-docs/`、`.git/info/exclude` 追加一行 `.env`。
- 未删除任何既有数据；未触碰其他 Compose 项目（`multica`、`ai-coding-hatchet`、`onyx`、`open-notebook`、`release-server`、`nodeskclaw-meeting`）。
- 未安装模型、未改动防火墙、未挂载 docker socket、未关闭任何认证或来源校验。

## 10. 源码与运行镜像的版本关系（2026-10-27 更新）

| 项 | 值 |
| --- | --- |
| 运行镜像 | \`0.8.3-dev.e1f9a616\`（构建自 \`e1f9a6166\`） |
| 源码工作树 | 已 rebase 到 \`internal/main\`（\`b5550eff9\`）之上，用于把文档推送到 \`smc-copilot/WeKnora\` |
| 两者差异 | 139 个提交、467 个文件；**不含新的数据库迁移**（\`migrations/\` 无变化，schema 仍为 133） |
| 影响 | 现在执行 \`wk.sh build\` 会构建出与运行中不同的版本；升级前须按 \`BACKUP-RESTORE.md\` 备份并重跑验收 |
| 回退源码 | \`git reset --hard backup/pre-rebase-20261027\`（本地引用，指向原 \`38750e27e\`） |

> 源码前移不等于已升级：容器、镜像、数据库都还是 \`e1f9a616\` 那一版。
