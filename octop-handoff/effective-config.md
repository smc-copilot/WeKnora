# 生效配置核对（smc-weknora）

版本：`0.8.3-dev.e1f9a616` / commit `e1f9a6166a593a4804a2f99f1d942919c9cc8ea7`

## 1. 五项配置

| 配置 | 期望值 | 实际值 | 来源 | 运行时覆盖（DB） | 验证方式 |
| --- | --- | --- | --- | --- | --- |
| `WEKNORA_AUTH_DEFAULT_TENANT_MODE` | create_personal | `create_personal` | `.env` → compose `environment` 第 131 行 → 容器 | 无 | 容器 `printenv`；`system_settings` 0 行 |
| `WEKNORA_TENANT_ENABLE_RBAC` | true | `true` | `.env` → compose 第 364 行 → 容器 | **无此运行时键**（只能由环境变量控制） | 容器 `printenv` + 跨空间负例实测 |
| `WEKNORA_TENANT_ENABLE_CROSS_TENANT_ACCESS` | false | `false` | `.env` → compose 第 135 行 → 容器 | 无 | 容器 `printenv` + 跨空间负例实测 |
| `WEKNORA_TENANT_AUTO_CREATE_API_KEY` | false | `false` | `.env` → compose 第 366 行 → 容器 | 无 | 建空间响应无 `api_key` |
| `DISABLE_REGISTRATION` | true | `true` | `.env` → compose 第 127 行 → 容器 | `auth.registration_mode` 存在 DB 键但表为空 | `/auth/config` 返回 `invite_only` + 注册 403 |

### 运行时设置键说明

`internal/application/service/system_setting.go` 的注册表里有：

- `auth.registration_mode`（默认 self_serve；本部署经 `DISABLE_REGISTRATION=true` 在 `internal/config/config.go:913` 被强制为 `invite_only`）
- `auth.default_tenant_mode`（默认 create_personal）
- `tenant.auto_create_api_key`（默认 false）
- 另有 `tenant.self_service_creation_enabled`、`tenant.max_owned_per_user` 等

**没有** `tenant.enable_rbac` / `tenant.cross_tenant_access` 这类运行时键：RBAC 与跨空间访问只能通过环境变量控制，符合"不要假设两者都有同名设置 API"。

`system_settings` 表当前 **0 行**，即全部取值来自环境变量，没有被数据库值覆盖。因此本轮无需调用设置写接口（也没有权限调用）。

## 2. 有效配置取证（脱敏）

```text
容器内环境：
DISABLE_REGISTRATION=true
WEKNORA_AUTH_DEFAULT_TENANT_MODE=create_personal
WEKNORA_TENANT_AUTO_CREATE_API_KEY=false
WEKNORA_TENANT_ENABLE_CROSS_TENANT_ACCESS=false
WEKNORA_TENANT_ENABLE_RBAC=true

GET /api/v1/auth/config  ->  200
{"complex_password_enabled":false,"registration_mode":"invite_only","success":true}
```

## 3. 管理员开户接口

| 项 | 结论 |
| --- | --- |
| 路由 | `POST /api/v1/system/admin/users/create`（`internal/router/routes_auth_tenant.go:311`） |
| 鉴权 | 路由组 `r.Group("/system/admin", g.SystemAdmin())`，**只接受 SystemAdmin 的登录 JWT** |
| Platform API Key | **不接受**。该路由用普通 `adminRoutes.POST` 登记，没有 `apiKeyRoute` 策略；API Key 网关对未声明策略的路由默认拒绝（源码注释明确写明 "API keys remain default-denied"） |
| 实测 | 无凭据 401；租户 Owner JWT 403；`X-API-Key: invalid` 401；获得 SystemAdmin 后 201 / 200 / 409 全部按契约返回 |
| 请求体 | `{"username","email","password"}` |
| 响应 | `{"user": {...}}`，服务端生成密码时附加 `generated_password`；**没有** `success/data` 外层 |
| 状态码 | 201 新建；200 身份已存在（返回既有用户，不改密码） |

> 与你们本地冻结合同的差异确认：官方契约就是 `{user, generated_password?}` 顶层结构，不是"原始 user 字段"。本机源码 `internal/handler/system.go:1714-1802` 与此一致。

## 4. 认证方式与有效期

| 方式 | 头 | 用途 | 有效期 |
| --- | --- | --- | --- |
| 登录 JWT | `Authorization: Bearer <token>` | 浏览器 / 管理员开户 | **24 小时**（实测 iat 2026-10-26 23:38:19 → exp 2026-10-27 23:38:19） |
| 刷新令牌 | `refresh_token`（登录响应返回） | 续期 | `POST /api/v1/auth/refresh` |
| 空间 API Key | `X-API-Key: <key>` | 服务端检索/问答 | 长期有效，可撤销，带能力与 KB 白名单 |
| 指定空间 | `X-Tenant-ID: <id>` | 多空间用户切换 | — |

- JWT 不能伪造，`JWT_SECRET` 不能当 access token 用。
- 过期后必须重新登录；不要假设保存一次可永久开户。
- 管理员凭据请保存在服务器受限文件或秘密管理系统，不要写进仓库、聊天或交接文件。

## 5. 密钥与持久化

| 项 | 状态 |
| --- | --- |
| `JWT_SECRET` | 已配置（64 hex） |
| `SYSTEM_AES_KEY` | 已配置（32 字符） |
| `SYSTEM_SIGNING_KEY` | 已配置（64 hex） |
| 数据库/文件/Redis 卷 | 4 个命名卷，重启后数据保留（此前已验证 stop→start 数据完整） |

本轮未重新生成任何密钥。
## 6. 运行期复核（2026-10-27 00:02，SystemAdmin 就绪后）

`GET /api/v1/system/admin/settings` → 200，实际取值：

```json
[{"key":"auth.default_tenant_mode","value":"create_personal"},
 {"key":"auth.registration_mode","value":"invite_only"},
 {"key":"tenant.auto_create_api_key","value":false},
 {"key":"tenant.self_service_creation_enabled","value":true}]
```

即：五项配置的最终行为与目标一致，且 `system_settings` 表仍为空（这些值由环境变量派生，没有数据库覆盖）。

开户接口实测：新建 201、重复 200（不改密码）、username/email 指向不同身份 409。
