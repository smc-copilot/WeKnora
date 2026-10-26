# API 验收记录（2026-10-26，服务器本机执行）

所有请求均设置 10–20s 超时、不跟随重定向；未记录任何 token、密码或 Key 明文。
"来源"列：**本机** = 在 192.168.102.104 上通过 `http://192.168.102.104:18080` 调用；**待 Octop** = 需在 Octop 主机验证。

## 1. 配置与注册

| # | 场景 | 请求 | 结果 | 响应形状 | 来源 |
| --- | --- | --- | --- | --- | --- |
| 1 | 注册已关闭 | `POST /api/v1/auth/register` 合法格式 | **403** | `{"error":{"code":1002,"message":"Public registration is disabled"}}` | 本机 |
| 2 | 既有账号仍可登录 | `POST /api/v1/auth/login` | **200** | keys: `active_tenant, memberships, message, refresh_token, success, token, user` | 本机 |
| 3 | 管理员开户 | `POST /api/v1/system/admin/users/create` | **201 / 200** | 见第 5 节 | 本机 |
| 4 | 开户接口无凭据 | 同上，无认证 | **401** | `{"error":"Unauthorized: missing authentication"}` | 本机 |
| 5 | 开户接口租户 Owner JWT | 同上，smc-copilot JWT | **403** | `{"error":"Forbidden: system administrator required"}` | 本机 |
| 6 | 开户接口 API Key | 同上，无效 `X-API-Key` | **401** | 认证失败（非 403，说明 API Key 不参与该路由） | 本机 |
| 7 | 租户 Owner 读全局设置 | `GET /system/admin/settings` | **403** | `{"error":"Forbidden: system administrator required"}` | 本机 |

## 2. 角色与跨空间

| # | 场景 | 请求 | 结果 | 说明 | 来源 |
| --- | --- | --- | --- | --- | --- |
| 8 | 跨空间访问被拒 | `GET /knowledge-bases` + `X-Tenant-ID: 10000`（调用者属 10001） | **403** | `Forbidden: insufficient permissions to access target workspace`；RBAC 强制且跨空间关闭 | 本机 |
| 9 | 不存在的空间 | `X-Tenant-ID: 99999` | **403** | 同上（不泄漏存在性） | 本机 |

## 3. 新空间不自动发 Key

| # | 场景 | 请求 | 结果 | 响应形状 | 来源 |
| --- | --- | --- | --- | --- | --- |
| 10 | 建空间 | `POST /tenants {"name":"octop-probe-autokey"}` | **201** | keys: `data, success`；**无** `api_key`、**无** `token` | 本机 |
| 11 | 清理 | `DELETE /tenants/10002` + `X-Tenant-ID: 10002` | **200** | `{"message":"Workspace deleted successfully","success":true}`（软删） | 本机 |

> 注意：删除空间必须显式带 `X-Tenant-ID`，否则返回 403 "URL workspace does not match the active workspace"。

## 4. 限定 Key 的权限链（临时探针，已清理）

| # | 场景 | 请求 | 结果 | 响应形状 | 来源 |
| --- | --- | --- | --- | --- | --- |
| 12 | 建知识库 | `POST /knowledge-bases`（owner JWT） | **201** | `{"data":{"id","name","type":"document","tenant":10001}}` | 本机 |
| 13 | 列表归属 | `GET /knowledge-bases` | **200** | 数组元素含 `id, name, tenant_id, creator_id` | 本机 |
| 14 | 建限定 Key | `POST /tenants/10001/api-keys` `{full_access:false, knowledge_base_ids:[kb], capabilities:["retrieve"]}` | **201** | `{"data":{"id","name","full_access":null,"capabilities":["retrieve"],"knowledge_base_ids":[kb]}}` | 本机 |
| 15 | Key 列库（白名单） | `GET /knowledge-bases` + `X-API-Key` + `X-Tenant-ID: 10001` | **200** | **只返回被授权的 1 个 KB** | 本机 |
| 16 | Key 越权管理 | `GET /tenants/10001/api-keys` + 同一 Key | **403** | 能力不含管理动作 | 本机 |
| 17 | 检索（空库） | `POST /knowledge-search?resource_urls=handle` + Key + Tenant | **200** | `{"data":[],"meta":{"rerank":{"applied":false,"outcome":"no_candidates","threshold":0.2,"candidate_count":0,...}},"success":true}` | 本机 |
| 18 | 清理 | 撤销 Key / 删除 KB | **200 / 200** | 软删与撤销，API 列表不再可见 | 本机 |

探针资源：租户 10002、KB `b0534ae6-52cb-4982-b27f-a343e7780331`、Key id=2。均为临时对象，已软删/撤销，不参与后续验收。

## 4b. 企业共享库（本轮新增）

| # | 场景 | 请求 | 结果 | 响应形状 | 来源 |
| --- | --- | --- | --- | --- | --- |
| 26 | 建企业 retrieve Key | `POST /tenants/10001/api-keys` `{name:"octop-enterprise-shared-retrieve", full_access:false, knowledge_base_ids:["805b7515-..."], capabilities:["retrieve"]}` | **201** | `{"data":{"id":3,"capabilities":["retrieve"],"knowledge_base_ids":["805b7515-..."]}}` | 本机 |
| 27 | 企业 Key LIST | `GET /knowledge-bases` + Key + `X-Tenant-ID: 10001` | **200** | `[{"id":"805b7515-...","name":"工作流程","tenant_id":10001}]`（仅白名单库） | 本机 |
| 28 | 企业 Key SEARCH | `POST /knowledge-search?resource_urls=handle` `{query:"工作流程", knowledge_base_ids:["805b7515-..."], match_count:8}` | **200** | `{"success":true,"data":[],"meta":{"rerank":{"outcome":"no_candidates","candidate_count":0,...}}}` —— 该库 0 文档 | 本机 |
| 29 | 企业 Key 越权 | 同一 Key：管理接口 / `X-Tenant-ID: 10000` | **403 / 403** | 能力与租户边界均生效 | 本机 |

企业库 `805b7515-6cff-4db4-978a-cad5b762a9fd`（"工作流程"）属于租户 **10001**，当前 **0 篇文档**。要验证"命中固定文档"，需要先入库内容，而入库依赖 Embedding 模型——按约定该模型由 Octop 侧创建。

## 5. 开户与个人空间链路（已执行，2026-10-27 00:02）

执行前提：`smc-copilot` 已被 `loudon` 授予系统管理员，`/system/admin/*` 返回 200。

| # | 场景 | 请求 | 结果 | 响应形状 | 来源 |
| --- | --- | --- | --- | --- | --- |
| 19 | 建用户 A | `POST /system/admin/users/create` `{username,email,password}` | **201** | `{"user":{"id":"a157311f-...","username":"octop-accept-a","email":"...","tenant_id":10003,"is_system_admin":false}}`，**无** `generated_password`（显式传了密码） | 本机 |
| 20 | 重复同一身份 | 同上再发一次 | **200** | 同一个 `user.id`，未改密码 | 本机 |
| 21 | 身份冲突 | 同 username + 不同 email | **409** | `{"error":"email and username refer to conflicting existing identities"}` | 本机 |
| 22 | 建用户 B | 同上 | **201** | `{"user":{...,"tenant_id":10004}}` | 本机 |
| 23 | A 登录身份 | `POST /auth/login` | **200** | `memberships=[{"tenant_id":10003,"role":"owner"}]`，`is_system_admin=false` | 本机 |
| 24 | B 登录身份 | 同上 | **200** | `memberships=[{"tenant_id":10004,"role":"owner"}]` | 本机 |
| 25 | 个人库 A | `POST /knowledge-bases` | **201** | `{"data":{"id":"8fe88491-...","name":"octop-accept-kb-a","tenant":10003,"creator_id":"a157311f-..."}}` | 本机 |
| 26 | 个人库 B | 同上 | **201** | `{"id":"5c4819e0-...","tenant":10004}` | 本机 |
| 27 | 单库 retrieve Key A | `POST /tenants/10003/api-keys` | **201** | `{"id":4,"capabilities":["retrieve"],"knowledge_base_ids":["8fe88491-..."]}` | 本机 |
| 28 | 单库 retrieve Key B | `POST /tenants/10004/api-keys` | **201** | `{"id":5,"capabilities":["retrieve"],"knowledge_base_ids":["5c4819e0-..."]}` | 本机 |
| 29 | Key LIST 白名单 | `GET /knowledge-bases` + Key + 本租户 | **200** | A 只见 `["octop-accept-kb-a"]`；B 只见 `["octop-accept-kb-b"]` | 本机 |
| 30 | A Key 篡改租户 | `X-Tenant-ID: 10004` | **403** | 租户不匹配被拒 | 本机 |
| 31 | A Key 读 B 的库 | `GET /knowledge-bases/<B KB>` | **403** | `{"error":{"code":1002,"message":"API key scope does not allow one or more knowledge bases"}}` | 本机 |
| 32 | A Key 检索 B 的库 | `knowledge-search` 带 B 的 `knowledge_base_ids` | **403** | 同上（批量任一越界整体拒绝） | 本机 |
| 33 | 检索 Key 越权管理 | `GET /tenants/10003/api-keys` | **403** | 能力不含管理 | 本机 |
| 34 | 本人库检索 | `knowledge-search` 带自己的库 | **200** | `{"success":true,"data":[]}`（库内 0 文档，无 Embedding 模型） | 本机 |

结论：**用户 → 个人空间 → 个人库 → 单库 Key** 的授权链与隔离全部成立；新租户未自动获得 Key（表中只有显式创建的 4/5）。

## 5b. 仍未执行（阻塞）

| # | 场景 | 阻塞原因 |
| --- | --- | --- |
| 35 | 非空文档上传、解析、索引、命中 | 个人租户无 Embedding 模型（按约定由 Octop 侧创建），入库会失败 |
| 36 | 文档 READ / chunks / preview / 分页 | 同上，库内无文档 |
| 37 | 企业共享库命中真实文档 | Key 与白名单已验证，库内 0 文档 |
| 38 | Octop 主机可达性、插件连接、员工授权 | 需 Octop 主机 |

## 6. 入口与代理

| 检查 | 结果 | 来源 |
| --- | --- | --- |
| `GET http://192.168.102.104:18080/api/v1/auth/config` | 200 `application/json; charset=utf-8`，无重定向 | 本机 |
| `GET http://sncon.k9.luyouxia.net:44813/api/v1/auth/config` | 200 `application/json`，内容与上面一致 | 本机（经公网回环） |
| 前端→后端 | nginx `proxy_pass http://app:8080`，后端 8080 未发布到宿主机 | 本机 |
| `Authorization` 透传 | 错误 token → 401 JSON（未落到 SPA HTML） | 本机 |
| `X-Tenant-ID` 透传 | 生效（403 语义来自后端） | 本机 |
| Octop 主机可达性 | **待 Octop 主机验证** | 待 Octop |

## 7. 与 v0.8.3 文档的差异（本机版本）

1. 本机是 `v0.8.3-154-ge1f9a6166`，比 tag 新 154 个提交，含 14 个新迁移；官方 v0.8.3 的行为描述需按本机源码复核。
2. `/system/admin/users/create` 在本机仍**只接受 SystemAdmin JWT**，不接受 platform API Key（与该版本说明一致，实测 401）。
3. `RequireSystemAdmin` 中间件对 platform API Key 有放行分支，但仅对显式声明了 `apiKeyPlatform(...)` 策略的路由生效（`/settings`、`/runtime/*`、`/audit-log`、`/tenants/apply-default-storage-quota`）；用户管理路由未声明策略，默认拒绝。