# new-api `/api/app/profile` 接口契约（App 端只读 profile）

> 状态：**后端后续实现**。本文件是 App 端与 new-api 二开之间的**接口契约**，
> 定义 App 需要的只读接口形态；new-api 侧按此实现，App 端按此对接。
> 契约以「只读、只返回该 token 本人信息、绝不接受任意 `user_id` 入参」为不可违背的安全底线
> （见根方案 `brand/TODO.md` 第三节「凭据模型」）。

---

## 1. 背景与用途

App 只持有 API Token（`sk-…`），不持有 passkey / 系统访问令牌（见 TODO 第三节）。
App 需要凭 `sk-` 展示「该 key 的用户名 / 头像 / 额度 / 用量」，用于 key 卡片列表
（TODO 第六节「key 卡片展示」）。

现状隐患：余额面板早期用 `sk-` 调 new-api 原生 `/api/user/self`，该端点走**用户会话/系统令牌**
鉴权，`sk-` API Token 大概率鉴权失败（TODO 第七节风险 #3）。**本接口即为解决此问题**——
新增一个走 **token 鉴权中间件**、由 `sk-` 定位 token 的只读聚合端点，App 端统一改调它。

---

## 2. 接口定义

```
GET /api/app/profile
```

| 项 | 值 |
|---|---|
| 方法 | `GET` |
| 路径 | `/api/app/profile` |
| 鉴权 | `Authorization: Bearer sk-…`，走 **token 鉴权中间件**（同 `/v1/*` 那套） |
| 入参 | **无**（不接受任何 query / body 参数，尤其不接受 `user_id`） |
| 幂等 | 是（纯只读，无副作用） |
| Content-Type | `application/json` |

### 鉴权与定位逻辑（后端实现要点）

1. 从 `Authorization: Bearer <sk>` 取出 API Token 明文。
2. 走 new-api 既有的 **token 鉴权中间件**校验 token（验证存在 / 未禁用 / 未过期 / 额度）。
3. 由 token 记录拿到其绑定的 `user_id`，再查 user 表。
4. **`user_id` 只能来自 token 记录本身**，绝不从请求参数读取——这是安全底线。

---

## 3. 返回字段

成功 `200 OK`：

```jsonc
{
  "username":         "alice",              // 用户名（user 表 username，可回退 display_name）
  "avatar":           "https://…/a.png",    // 头像 URL；无头像时为空串 ""
  "quota":            5000000,              // 账户总额度（user.quota + user.used_quota，见下）
  "used_quota":       1200000,              // 账户已用（user.used_quota）
  "used_today":       86000,                // 账户今日消耗（该账户全部 token 当天日志之和；可选，见下）
  "token_remain":     380000,               // 该 key 自己的剩余额度（token.remain_quota）
  "token_used":       120000,               // 该 key 自己的已用（token.used_quota）
  "token_used_today": 4200,                 // 该 key 今日消耗（按 token_id 聚合当天日志）
  "unlimited":        false                 // 该 key 是否不限额（token.unlimited_quota）
}
```

### 字段语义与来源映射（new-api 数据模型）

| 字段 | 类型 | 语义 | 来源建议 |
|---|---|---|---|
| `username` | string | 用户名 | `user.username`；空则回退 `user.display_name` |
| `avatar` | string | 头像 URL | 头像字段（如 `user.avatar`）；无则返回 `""`，App 端用占位 |
| `quota` | number | **账户总额度**（原始 quota 单位，非美元） | `user.quota + user.used_quota`（当前可用 + 已用 = 历史总额）。若产品定义为「当前授予的总额」，则取 `user.quota + user.used_quota` 或按 new-api 语义调整，**以本契约「账户总额度」为准**，后端确认后固化 |
| `used_quota` | number | **账户已用**（原始 quota 单位） | `user.used_quota` |
| `used_today` | number | **账户今日消耗**（原始 quota 单位）；**可选字段** | 按 `user_id` 聚合当天该账户全部 token 的日志 quota：`SELECT COALESCE(SUM(quota),0) FROM logs WHERE user_id = ? AND created_at >= <当日 0 点> AND type = <消费类型>`。时区须与 `token_used_today` 一致。**后端未实现时可省略该字段**，App 端会显示「—」而非 0，不影响其他数据 |
| `token_remain` | number | **该 key 剩余额度**（原始 quota 单位） | `token.remain_quota`（`unlimited` 为真时该值无意义，见下） |
| `token_used` | number | **该 key 已用**（原始 quota 单位） | `token.used_quota` |
| `token_used_today` | number | **该 key 今日消耗**（原始 quota 单位） | 按 `token_id` 聚合当天（用户本地/服务器时区取其一，需固定）日志表 quota：`SELECT COALESCE(SUM(quota),0) FROM logs WHERE token_id = ? AND created_at >= <当日 0 点> AND type = <消费类型>` |
| `unlimited` | bool | 该 key 是否不限额 | `token.unlimited_quota` |

> **额度单位约定**：所有 `*quota*` 字段返回 new-api **原始 quota 整数**（不在后端换算成美元/人民币）。
> 单位换算（除以 `QuotaPerUnit`，默认 500000 → 1 美元额度）由 **App 端**负责显示，避免后端与前端各算一套。
>
> **`unlimited` 与额度字段的关系**：当 `unlimited = true` 时，`token_remain` 无实际意义
> （App 端应显示「不限额」而非具体数字）；`token_used` / `token_used_today` 仍有效，表示实际消耗。

---

## 4. 错误返回

沿用 new-api 既有错误响应风格（token 鉴权中间件会先行拦截无效 token）：

| 场景 | HTTP | 说明 |
|---|---|---|
| 缺失 / 格式错误的 `Authorization` | `401` | 无 `Bearer sk-…` |
| token 无效 / 被禁用 / 已过期 | `401` | 由 token 鉴权中间件返回 |
| token 有效但关联 user 缺失（异常态） | `500` | 数据不一致，记录服务端日志 |
| 成功 | `200` | 见第 3 节 |

错误体沿用 new-api 现有约定（如 `{ "success": false, "message": "…" }` 或 OpenAI 风格 `{ "error": {...} }`），
以 new-api 现网实际格式为准；App 端按 HTTP status 分支即可，不强依赖错误体结构。

---

## 5. 安全约束（不可违背）

1. **只返回该 token 本人信息**：`user_id` 只能由 `sk-` 定位的 token 记录派生，**接口不接受任何 `user_id` 入参**
   （query / body / header 一律不读）。杜绝越权查看他人 profile。
2. **只读**：本接口不修改任何数据，无副作用。
3. **最小暴露**：只返回第 3 节列出的字段，不透传 token 明文、passkey、系统令牌、内部 id、邮箱/手机号等敏感信息。
4. **鉴权复用**：必须走 new-api 既有 **token 鉴权中间件**（与 `/v1/*` 同源），不自建弱鉴权。
5. **日志**：服务端日志**不得记录** `sk-` 明文（与 App 端「key 不进日志」策略一致）。

---

## 6. 模型列表 `/v1/models`（按 key 返回可用模型）

App 切换 key 时需要「该 key 可用模型」以更新可选模型（TODO 第六节「切换 key 联动」）。

### 现状与约定

- **优先复用 OpenAI 兼容端点** `GET /v1/models`（带 `Authorization: Bearer sk-…`），无需新增接口。
- new-api 的 token 支持**模型限制**（`model_limits_enabled` + `model_limits`）：token 开启限制时只能访问白名单模型。

### 需 new-api 侧确认的行为

**`/v1/models` 是否按 key（token 的 `model_limits`）返回该 key 可用模型，而非全站模型？**

- **若 `/v1/models` 已按 token 的 `model_limits` 过滤**（开启限制时只返回白名单模型，未开启时返回该用户/渠道全部可用模型）：
  App 端**直接用 `/v1/models`**，无需新增接口。这是首选。
- **若 `/v1/models` 不区分 key（对任意 token 都返回全站/全渠道模型）**：
  则 new-api 二开**追加一个按 key 返回绑定模型的接口**，契约如下。

### 追加接口契约（仅当 `/v1/models` 不按 key 区分时实现）

```
GET /api/app/models
  鉴权：Authorization: Bearer sk-…    （同 token 鉴权中间件）
  入参：无（不接受 user_id / token id 入参）
  逻辑：由 sk- 定位 token → 取该 token 的可用模型集合
        （token.model_limits_enabled 为真时取 model_limits 白名单；
         否则取该 token 绑定分组/渠道的可用模型集合）
  返回（OpenAI /v1/models 兼容形态，便于 App 端复用同一解析）：
  {
    "object": "list",
    "data": [
      { "id": "gpt-5-codex", "object": "model", "owned_by": "newapi" }
      // …该 key 可用的模型
    ]
  }
  安全：只返回该 token 可用模型，不接受任意 user_id / token 入参
```

> **落地建议**：new-api 侧先自查 `/v1/models` 是否已按 token `model_limits` 过滤。
> 若已过滤 → 无需 `/api/app/models`，App 直接用 `/v1/models`；
> 若未过滤 → 实现 `/api/app/models`，返回上述 OpenAI 兼容形态。
> 无论哪种，**App 端解析逻辑一致**（都消费 `{ object:"list", data:[{id,…}] }`）。

---

## 7. App 端对接约定

- key 卡片展示：调 `GET /api/app/profile` 拿 `username` / `avatar` / 账户额度 / 该 key 用量。
- 切换 key 联动模型：调 `GET /v1/models`（或 `GET /api/app/models`，视上节确认结果）拿该 key 可用模型。
- 单位换算：`*quota*` 原始整数 ÷ `QuotaPerUnit`（默认 500000）在 **App 端**换算显示。
- 充值：见 TODO 第六节「充值入口」（`NEWAPI_TOPUP_URL`），与本 profile 接口无关。

---

## 8. 变更记录

| 日期 | Story | 变更 |
|---|---|---|
| 2026-07-09 | US-005 | 首版契约：定义 `GET /api/app/profile`（含 `token_used_today`）、安全约束、`/v1/models` 按 key 说明及 `/api/app/models` 备用接口 |
| 2026-07-10 | 面板重设计 | 新增账户级 `used_today`（可选）字段，供左侧账户卡展示「账户今日消耗」；后端未实现时可省略，App 端显示「—」 |
