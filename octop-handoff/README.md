# Octop × WeKnora 服务器侧交接

生成时间：2026-10-26 23:50 (UTC+8)

## 1. 实际运行版本

| 项 | 值 |
| --- | --- |
| 源码版本 | `0.8.3-dev.e1f9a616` |
| git describe | `v0.8.3-154-ge1f9a6166`（比官方 tag `v0.8.3` 多 154 个提交，**不是** v0.8.3 release） |
| commit | `e1f9a6166a593a4804a2f99f1d942919c9cc8ea7` |
| 镜像 | `wechatopenai/weknora-app:0.8.3-dev.e1f9a616` = `sha256:3944258a304861984ce0e94f7a33bdca33c485c6280e0e24944084d6976368cc` |
|  | `wechatopenai/weknora-ui:0.8.3-dev.e1f9a616` = `sha256:95992bc6306b475b4fa581f2922b273f76b04f8764aa953e2d9c91bb1fd512b3` |
|  | `wechatopenai/weknora-docreader:0.8.3-dev.e1f9a616` = `sha256:81f3682566c14a9c50221a8b42d5d002b9bf1917cd336b585827e59f470f400a` |
| 基础设施 | `paradedb/paradedb:v0.25.11-pg17` = `sha256:78d65750f0f8...`；`redis:7.0-alpine` = `sha256:c9d92d840fd0...` |

镜像由本机源码构建（本地打 tag），不是 Docker Hub 上的发布版，因此没有仓库 digest，上面的 `sha256` 是本地镜像 ID。

> 由于版本领先于 v0.8.3，官方 v0.8.3 文档里的行为不一定成立；本目录所有结论以本机实测和本地源码为准。

## 2. 部署方式

- Compose 项目名：`smc-weknora`
- 编排：`/data/projects/weknora/docker-compose.yml`（官方，未改）+ `deploy-docs/docker-compose.smc.yml`（覆盖）
- 服务：frontend / app / docreader / postgres / redis（无 full profile 组件）
- 数据卷：`smc-weknora-postgres-data`、`smc-weknora-data-files`、`smc-weknora-docreader-tmp`、`smc-weknora-redis-data`
- 入口：`http://192.168.102.104:18080`（绑定网卡 IP，非 0.0.0.0）；外部映射入口 `http://sncon.k9.luyouxia.net:44813`，两者返回同一份 JSON

## 3. 本轮变更

| 变更 | 内容 | 验证 |
| --- | --- | --- |
| 五项配置写入 `.env` 并重建 app | 见 `effective-config.md` | 容器内 `printenv`、`/auth/config`、DB 无运行时覆盖 |
| 备份 | `/data/backups/weknora/20261026-233818` | 含 dump/.env/compose，`SHA256SUMS` |
| 探针资源（已清理） | 临时租户 10002（软删）、临时 KB `b0534ae6-...`（软删）、临时 Key id=2（已撤销） | API 列表不可见 |

未执行：版本升级、迁移变更、`down -v`、删除卷、改动其他项目容器、修改数据库业务表造身份。

## 4. 备份与回滚

- 备份：`sudo /data/projects/weknora/deploy-docs/wk.sh backup`
- 恢复：见 `/data/projects/weknora/deploy-docs/BACKUP-RESTORE.md`
- 本轮回滚（撤销五项配置）：把 `.env` 里 `DISABLE_REGISTRATION` 改回 `false`、删除新增的四行，然后 `wk.sh recreate app`；数据库未变更，无需回库。

## 5. 已通过（有实测证据）

1. 五项配置生效：容器内 5 个变量正确，`/api/v1/auth/config` 返回 `registration_mode=invite_only`，`system_settings` 表 0 行（无覆盖）。
2. 注册关闭：合法格式的注册请求返回 **403 / code 1002 "Public registration is disabled"**。
3. 既有账号仍可登录：`/auth/login` 200。
4. RBAC 强制 + 跨空间关闭：租户 10001 的 Owner 用 `X-Tenant-ID: 10000` 访问知识库列表返回 **403 "insufficient permissions to access target workspace"**。
5. 开户接口鉴权边界：无凭据 **401**；租户 Owner JWT **403**；`X-API-Key`（无效）**401**。
6. 新空间不自动发 Key：`POST /tenants` 201，响应**无** `api_key`/`token`（探针租户已软删）。
7. 限定 Key 链路：创建 `capabilities=[retrieve]` + 单库白名单的 Key（201）→ 用该 Key LIST 只返回被授权的 1 个知识库；该 Key 调 `GET /tenants/10001/api-keys` 返回 403；`knowledge-search` 返回 200 `{"data":[],"meta":{...}}`。
8. 入口：局域网与外部映射两个 origin 的 `/api/v1/auth/config` 均为 200 `application/json`，无 30x 跳转，`Authorization` 透传正常（错误 token 得到 401，不是 HTML）。
9. 企业共享库 retrieve Key（id=3，租户 10001，白名单仅 `805b7515-…`，能力仅 `retrieve`）：LIST 只返回该库；SEARCH 200；管理接口 403；跨租户 403。Key 明文存 `/root/.octop-secrets/weknora-enterprise-retrieve.key`（600），交接文件只记位置不记值。
10. 开户 API（`smc-copilot` 获得 SystemAdmin 后）：201 新建 / 200 已存在且不改密码 / 409 身份冲突。响应顶层只有 `user`；显式传密码时**没有** `generated_password`。
11. A/B 合成用户：租户 10003 / 10004，各自 `owner`，互不可见；各自建 document 库与单库 `retrieve` Key（id 4 / 5）。
12. 隔离实测：A 的 Key 带 B 的 `X-Tenant-ID` → 403；读/检索 B 的库 → 403 `API key scope does not allow one or more knowledge bases`；管理接口 → 403；本人库检索 → 200 空结果。
13. 新租户未自动发 Key：`tenant_api_keys` 中只有显式创建的 4/5，A/B 租户没有全权 Key。

## 6. 未通过 / 阻塞

| 项 | 原因 |
| --- | --- |
| 非空文档上传、解析、索引、命中 | 个人租户没有 Embedding 模型（按约定由 Octop 侧创建）；库内 0 文档，检索只验证到"200 空结果" |
| 文档 READ / chunks / preview / 分页 | 同上，库内无文档 |
| 企业共享库命中真实文档 | Key 与白名单已验证，`工作流程` 库内 0 文档 |
| Octop 主机网络可达性、插件连接、员工授权 | 需 Octop 主机 |

### 模型缺口（重要）

模型按租户隔离，新租户默认**没有任何模型**：

| 租户 | KnowledgeQA | Embedding | Rerank | VLLM | ASR |
| --- | --- | --- | --- | --- | --- |
| 10000 loudon | ✓ | **✓ text-embedding-v4** | ✓ | ✓ | ✓ |
| 10001 admin | ✓ | **✗** | ✓ | ✓ | ✗ |

新建的个人租户不会继承 10000 的模型与凭据。要让"个人知识库"能建索引并检索，必须给每个新租户准备可用的 Embedding 模型与凭据（我不会复制其他租户的密钥）。

## 7. 待补充输入

1. **Embedding 模型**：按约定由 Octop 侧为新租户创建；在完成之前，任何"命中真实文档"的验收都无法进行。
2. **企业共享库内容**：`工作流程`（10001）当前 0 文档，入库依赖 Embedding。
3. **Octop 主机**：入口选择、HTTP 精确 origin（如用内网 HTTP）、企业 Key 与管理员 JWT 的安全录入。

服务器侧开户链路已完成并留证，不再依赖任何人工提升操作。