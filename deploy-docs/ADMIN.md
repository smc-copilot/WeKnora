# WeKnora 管理手册（smc-weknora）

所有操作在 `http://192.168.102.104:18080` 完成（局域网内浏览器直接访问，无需隧道）。
本文只说明"去哪里拿凭据、怎么点"，**不含任何真实密码或密钥**。

## 1. 首次账号与系统管理员

### 1.1 注册第一个账号

1. 浏览器打开 `http://192.168.102.104:18080`，进入登录页，切到「注册」页签；
2. 填用户名（2–50 字符）、邮箱、密码（8–32 位，至少含字母和数字）；
3. 提交后自动创建**个人工作空间**，该账号成为这个空间的 Owner。

默认注册策略是开放注册（`self_serve`），系统没有任何预置账号或默认密码。账号密码由你设置，系统不保存明文。

### 1.2 把自己设为系统管理员

> 注册账号 ≠ 系统管理员。新用户只有个人空间的 Owner 权限，看不到全局设置。

首次管理员通过环境变量引导，只在"部署内还没有任何系统管理员"时生效：

```bash
cd /data/projects/weknora
# 1) 用你注册时的邮箱替换下面的 ADMIN_EMAIL
sudo sed -i 's|^WEKNORA_BOOTSTRAP_SYSTEM_ADMIN_EMAIL=.*|WEKNORA_BOOTSTRAP_SYSTEM_ADMIN_EMAIL=ADMIN_EMAIL|' .env
grep -q '^WEKNORA_BOOTSTRAP_SYSTEM_ADMIN_EMAIL=' .env || echo 'WEKNORA_BOOTSTRAP_SYSTEM_ADMIN_EMAIL=ADMIN_EMAIL' | sudo tee -a .env

# 2) 重启 app 生效
sudo deploy-docs/wk.sh recreate app

# 3) 确认
sudo docker logs --since 3m smc-weknora-app 2>&1 | grep -i bootstrap
```

日志出现 `promoted user ... to system admin` 表示成功；若提示 `no matching user`，说明邮箱还没注册或写错。

之后刷新页面，「设置」左侧会出现系统设置、模型目录、任务队列、平台 API Key、系统审计日志等分区。后续增删管理员在「设置 → 系统设置 → 用户管理」里操作（不能撤销自己，也不能撤销最后一位管理员）。

## 2. 用户与工作空间

| 操作 | 位置 |
| --- | --- |
| 查看全部用户、启用/停用、重置密码、授予/撤销系统管理员 | 设置 → 系统设置 → 用户管理 |
| 创建本地账号（注册关闭时） | 同页「创建用户」，随机密码只显示一次 |
| 注册策略（开放 / 邀请注册 / 禁止注册） | 设置 → 系统设置，`auth.registration_mode` |
| 空间成员与邀请 | 空间设置 → 成员 |
| 新建空间 | 空间切换器 → 新建空间（`tenant.self_service_creation_enabled` 控制普通用户能否自建） |

停用账号会立即吊销其会话；空间 Owner 与系统管理员是两套独立身份，互不自动叠加。

## 3. 模型配置

位置：**设置 → 模型**（按类型分别添加）。知识库初始化时也可以从向导里就地选模型。

### 3.1 基础知识问答的最小集合

| 类型 | 是否必需 | 用途 |
| --- | --- | --- |
| 对话模型（LLM） | **必需** | 生成回答、摘要、问题生成 |
| 向量模型（Embedding） | **必需** | 文档与问题向量化，语义检索 |
| 重排模型（Rerank） | 可选 | 召回结果精排，默认不开 |
| 视觉（VLM）/ 语音（ASR） | 可选 | 图片理解、音频转写 |

### 3.2 添加步骤

1. 「设置 → 模型 → 添加模型」，选类型（对话 / 向量）；
2. 来源选「API」（远程 OpenAI 兼容服务）或「Ollama」（本地）；
3. 选服务商；没有对应厂商时选「自定义（OpenAI 兼容接口）」；
4. 填模型名称、Base URL、API Key（以及厂商要求的额外字段）；
5. 看「实际调用方式」确认请求协议与地址；
6. 点「测试连接」通过后保存。

注意：
- 更换向量模型必须**重建索引**，新旧向量不能混用；
- API Key 在库中是 AES-256 加密存储，依赖 `.env` 里的 `SYSTEM_AES_KEY`；该密钥丢失则已存凭据无法解密；
- 容器内的 `localhost` 是容器自己，连宿主机服务要用宿主 IP 或 `host.docker.internal`。

### 3.3 模型如何被知识库使用

创建知识库后，初始化向导会要求为该库选定对话模型与向量模型（每个库独立选择）。向导里的「测试」按钮会真实调用一次模型。

## 4. 知识库

| 操作 | 位置 |
| --- | --- |
| 新建知识库 | 「知识库」→ 新建，类型选 `document`（文档库）或 `faq`（问答库） |
| 上传资料 | 进入知识库后拖入文件或粘贴网页 URL |
| 解析状态 | 文档列表的「解析状态」列：`pending → processing → finalizing → completed` |
| 失败排查 | `sudo deploy-docs/wk.sh logs docreader`，以及 `sudo deploy-docs/wk.sh logs app` |
| 检索参数 | 知识库设置里的分块大小/重叠、召回阈值 |

支持 PDF、Word、Excel、PPT、Markdown、HTML、EPUB、图片、音频等。单文件默认上限 50MB（`MAX_FILE_SIZE_MB`），解析总超时默认 2 小时。

## 5. API Key

位置：**空间设置 → API Key**（需要空间 Owner 或具备 API Key 管理权限）。

### 5.1 创建

1. 空间设置 → API Key → 新建；
2. 填名称；
3. 选择「全量访问」或勾选细粒度能力；
4. 需要限制资料范围时，指定允许访问的知识库（KB allow-list）；
5. 保存后**立即复制并妥善保存** key，页面不会再显示明文。

### 5.2 常用能力

| 能力 | 能做什么 |
| --- | --- |
| `retrieve` | 读知识库、检索（`knowledge-search`、KB 列表与详情） |
| `chat` | 建会话、`knowledge-chat` / `agent-chat` |
| `ingest` | 上传文档、改 chunk/FAQ/标签、批量移动删除 |
| `manage_kbs` | 知识库增删改与初始化配置 |
| `manage_models` | 模型与凭据管理 |
| `manage_members` | 成员与邀请 |

服务端集成建议按"最小能力"分配：只做检索问答就给 `retrieve` + `chat`，不要给全量。

### 5.3 使用

```bash
curl -s http://192.168.102.104:18080/api/v1/knowledge-bases -H "X-API-Key: <你的 key>"
```

### 5.4 撤销

在 API Key 列表里撤销/删除对应条目，立即失效（`RevokedAt` 落库，校验时直接拒绝）。定期轮换，不要跨环境复用同一把 key。

## 6. 凭据都在哪里拿

| 凭据 | 位置 |
| --- | --- |
| 网页登录账号密码 | 你自己设置，系统不显示明文；忘记由系统管理员重置 |
| API Key 明文 | 仅在创建时显示一次，之后只能撤销重建 |
| 模型 API Key | 你自己持有的上游凭据，可在「设置 → 模型」的凭据子资源里更新 |
| 数据库 / Redis / JWT / AES 密钥 | `/data/projects/weknora/.env`（权限 640，root:cowork），交付文档不记录明文 |

## 7. 权限边界

- 系统管理员：全局设置、队列、平台 API Key、跨空间审计、重置用户密码；
- 空间 Owner：本空间成员、模型、知识库、集成；
- 系统管理员身份**不会**自动获得其他空间知识库内容的访问权（跨空间数据访问由 `CanAccessAllTenants` 单独控制）。
