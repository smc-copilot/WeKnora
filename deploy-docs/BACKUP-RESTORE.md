# 备份与恢复（smc-weknora）

## 1. 要备份什么

| 对象 | 位置 | 丢失后果 |
| --- | --- | --- |
| 数据库 | 卷 `smc-weknora-postgres-data` | 知识库、文档记录、用户、空间、模型配置全部丢失 |
| 上传文件与解析产物 | 卷 `smc-weknora-data-files` | 记录还在但原文与图片打不开 |
| 配置 | `/data/projects/weknora/.env` | 数据库口令、Redis 口令、JWT、AES 密钥丢失 |
| 编排文件 | `docker-compose.yml` + `deploy-docs/docker-compose.smc.yml` | 无法还原一致的部署形态 |
| 源码版本 | git 提交 `e1f9a6166a593a4804a2f99f1d942919c9cc8ea7` | 只能用新版重建，schema 可能不匹配 |

**`SYSTEM_AES_KEY` 是全库密文的主密钥**：数据库里的模型 API Key、平台凭据都用它加密。备份必须同时包含 `.env`，且两者分开保管没有意义——只有数据库没有密钥，恢复出来的凭据全是解不开的密文。

## 2. 一键备份（推荐）

```bash
cd /data/projects/weknora
sudo deploy-docs/wk.sh backup
```

产物在 `/data/backups/weknora/<YYYYmmdd-HHMMSS>/`：

| 文件 | 内容 |
| --- | --- |
| `weknora.dump` | `pg_dump -Fc` 自定义格式，事务一致快照 |
| `data-files.tar.gz` | 上传文件卷的 tar |
| `.env` | 实际配置（含密钥，权限 600） |
| `docker-compose.yml`、`docker-compose.smc.yml`、`config.yaml` | 编排与官方配置 |
| `GIT_COMMIT`、`VERSION` | 源码提交与镜像版本 |
| `SHA256SUMS` | 校验和 |

默认保留最近 14 份，只清理 `/data/backups/weknora/` 下的旧目录。

> 文件备份是在业务运行中打包的，正在上传的单个文件可能不完整。需要严格一致（升级前、迁移前）时：`sudo deploy-docs/wk.sh stop` → 备份 → `start`。

## 3. 手动分项备份

```bash
TS=$(date +%Y%m%d-%H%M%S); D=/data/backups/weknora/$TS; mkdir -p "$D"

# 数据库（一致快照）
docker exec smc-weknora-postgres sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$D/weknora.dump"

# 文件
tar -C /var/lib/docker/volumes/smc-weknora-data-files/_data -czf "$D/data-files.tar.gz" .

# 配置
install -m 600 /data/projects/weknora/.env "$D/.env"
```

只备份元数据不要文件时，用 `pg_dump` 的 `--schema-only`；但知识库没有文件就无法回答。

## 4. 恢复

### 4.1 完整恢复（同一台机器，卷还在）

```bash
cd /data/projects/weknora
BK=/data/backups/weknora/<时间戳>

sudo deploy-docs/wk.sh stop          # 停止写入，不要用 down -v

# 1) 数据库：重建空库后灌入
sudo docker exec smc-weknora-postgres psql -U weknora -d postgres -c 'DROP DATABASE IF EXISTS weknora;'
sudo docker exec smc-weknora-postgres psql -U weknora -d postgres -c 'CREATE DATABASE weknora;'
sudo docker exec -i smc-weknora-postgres sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --role="$POSTGRES_USER"' < "$BK/weknora.dump"

# 2) 文件
sudo rm -rf /var/lib/docker/volumes/smc-weknora-data-files/_data/*
sudo tar -C /var/lib/docker/volumes/smc-weknora-data-files/_data -xzf "$BK/data-files.tar.gz"
sudo chown -R 1000:1000 /var/lib/docker/volumes/smc-weknora-data-files/_data

# 3) 配置（仅当 .env 丢失或被改坏）
sudo install -m 640 -g cowork "$BK/.env" /data/projects/weknora/.env

sudo deploy-docs/wk.sh start
sudo deploy-docs/wk.sh health
```

恢复后 `docker logs smc-weknora-app | grep migration` 应显示已是备份时的版本，不再前进。

### 4.2 完整恢复（换机器 / 卷已删）

1. 装好 Docker 与 Compose（本机已具备）；
2. 任意方式取得源码到 `/data/projects/weknora`，并 `git checkout e1f9a6166a593a4804a2f99f1d942919c9cc8ea7`；
3. 把备份里的 `docker-compose.smc.yml` 放回 `deploy-docs/`，`.env` 放回仓库根目录（`chmod 640`）；
4. 重建镜像：`sudo deploy-docs/wk.sh build`；
5. 创建空卷并起库：`sudo deploy-docs/wk.sh up`（首次会自动建表），然后立刻 `stop`；
6. 按 4.1 的第 1、2 步灌入数据；
7. `sudo deploy-docs/wk.sh start`，核对知识库条数、文档条数、登录是否正常。

### 4.3 只恢复单个知识库的文件

文件按 `/data/files/<tenant>/<kb>/...` 组织，可只解包子目录；但数据库记录必须同时存在，否则列表里看不到。

## 5. 升级与回滚

**升级前必须备份**：

```bash
sudo deploy-docs/wk.sh backup
sudo deploy-docs/wk.sh build       # 新版本重建
sudo deploy-docs/wk.sh up
```

**回滚不能只回退镜像。** app 启动时会执行 `AUTO_MIGRATE`，把 schema 推进到新版本（本次从 0 前进到 133）；旧二进制面对新 schema 通常无法工作，数据库扩展升级也可能是单向的。正确回滚：

1. `wk.sh stop`；
2. 把镜像标签改回旧版本（或 `git checkout` 旧提交后 `build`）；
3. **用升级前的备份恢复数据库**（4.1 第 1 步），并恢复对应的 `.env`；
4. 恢复文件（若升级期间有新上传，选择"回滚点"一致的备份）；
5. 启动并验证。

因此备份要包含 `GIT_COMMIT` 与 `VERSION`，保证"代码 + schema + 数据"三者对得上。

## 6. 恢复演练

不要在生产库上试。可用一次性容器验证 dump 可读：

```bash
docker run --rm -v /data/backups/weknora:/b:ro postgres:17-alpine \
  sh -c 'pg_restore --list /b/<时间戳>/weknora.dump | head -20'
```

能看到表清单即说明 dump 结构完好。

## 7. 保管要求

- 备份目录默认 `700`，内含 `.env`（AES/JWT 密钥），按密钥级别保管；
- 异地/离线留一份，至少覆盖"最近一次升级前"的版本；
- 不要放进 git 仓库，不要贴到聊天或工单里；
- 定期抽查：`sha256sum -c SHA256SUMS`。
