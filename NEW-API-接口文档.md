# new-api 二开接口文档（Dokng 桌面客户端）

Dokng 账户面板依赖两个 new-api 接口：

1. `GET /api/app/profile`：二开新增，返回账户余额、当前 API Key 信息和真实模型 Token 用量。
2. `GET /v1/models`：上游已有，返回当前 API Key 可用模型。

所有请求使用 `Authorization: Bearer sk-xxx`。后端必须由该 Key 对应的 `model.Token` 记录派生 `token_id` 和 `user_id`，不得从请求参数读取这些 ID。

---

## 先统一三个容易混淆的概念

| 概念 | new-api 上游来源 | 含义 | UI 文案 |
|---|---|---|---|
| 账户额度 | `model.User.Quota` / `User.UsedQuota` | 用户剩余额度与累计费用额度 | 可用余额、今日费用、累计费用 |
| API Key | `model.Token` 表（上游代码也称 Token） | 一条 `sk-...` 凭据及其限额 | API Key、Key 名称、额度不限 |
| 模型 Tokens | `logs.prompt_tokens + logs.completion_tokens` | 模型实际处理的输入、输出 Token 数 | 今日 Tokens、输入 / 输出 |

> **禁止把 API Key 条数叫做 Token 用量。** “2 个 Token”只能描述两条 new-api Token 记录，不能表达模型消耗。账户页统一称“2 个 Key”；“今日 Tokens 12.1K”只来自日志中的 `prompt_tokens + completion_tokens`。

---

## 通用约定

| 项 | 值 |
|---|---|
| 鉴权头 | `Authorization: Bearer sk-xxx` |
| Accept | `application/json` |
| 站点根推导 | `baseURL` 去掉末尾 `/v1`；profile 挂在站点根 `/api` 下 |
| 额度单位 | 默认 `QuotaPerUnit = 500000`，即 500000 额度 = 1 美元；客户端负责换算金额 |
| 模型 Token 单位 | 原始整数个数，不经过 `QuotaPerUnit` 换算；客户端显示为 `12.1K`、`12.4M` 等 |
| 今日范围 | 站点配置时区的本地自然日 `[今日 00:00, 明日 00:00)`，响应应保持一致 |
| 失败降级 | 非 200 / 网络异常转为中文错误；可选统计聚合失败时返回 `null` 或省略，不阻塞基础资料 |

---

## 1. `GET /api/app/profile` — 账户、当前 Key 与今日用量（新增）

### 请求

```http
GET {站点根}/api/app/profile
Authorization: Bearer sk-xxxx
Accept: application/json
```

响应可以是扁平对象，也可以包在 `data` 中；客户端兼容 `body.data ?? body`。若响应带 `success: false`，客户端读取 `message`。

### 推荐响应字段

#### 账户级字段

同一账户下不同 Key 返回值相同。

| 字段 | 类型 | 上游来源 / 算法 | UI 用途 |
|---|---|---|---|
| `username` | string | `user.Username` | 用户账号 |
| `display_name` | string | `user.DisplayName`，为空回退 `Username` | 顶部主标题 |
| `avatar` | string，可选 | 上游标准 `User` 当前没有头像字段；仅站点自行扩展时返回 | 客户端为空时显示首字母 |
| `account_remaining_quota` | number | `user.Quota` | 可用余额 |
| `account_used_quota` | number | `user.UsedQuota` | 累计费用 |
| `account_total_quota` | number | `user.Quota + user.UsedQuota` | 额度使用率分母 |
| `account_quota_used_today` | number，可选 | 今日消费日志 `SUM(logs.quota)`，限定 `user_id`、`type=2` | 今日费用 |
| `account_tokens_used_today` | number，可选 | 今日 `SUM(prompt_tokens + completion_tokens)`，限定 `user_id`、`type=2` | 今日 Tokens |
| `account_prompt_tokens_today` | number，可选 | 今日 `SUM(prompt_tokens)` | 今日输入 Tokens |
| `account_completion_tokens_today` | number，可选 | 今日 `SUM(completion_tokens)` | 今日输出 Tokens |
| `request_count_today` | number，可选 | 今日消费日志 `COUNT(*)` | 可扩展展示请求数 |

#### 当前 API Key 字段

随 Bearer Key 不同而不同。字段统一使用 `key_*`，避免与模型 Token 数混淆。

| 字段 | 类型 | 上游来源 / 算法 | UI 用途 |
|---|---|---|---|
| `key_name` | string | `token.Name` | 本地名称为空时直接展示，并一次性回填本地 label |
| `key_remaining_quota` | number | `token.RemainQuota` | Key 剩余额度 |
| `key_used_quota` | number | `token.UsedQuota` | Key 累计费用 |
| `key_quota_used_today` | number，可选 | 今日 `SUM(logs.quota)`，限定当前 `token_id`、`type=2` | Key 今日费用 |
| `key_tokens_used_today` | number，可选 | 今日 `SUM(prompt_tokens + completion_tokens)`，限定当前 `token_id`、`type=2` | Key 今日 Tokens |
| `key_prompt_tokens_today` | number，可选 | 今日 `SUM(prompt_tokens)`，限定当前 `token_id` | Key 今日输入 |
| `key_completion_tokens_today` | number，可选 | 今日 `SUM(completion_tokens)`，限定当前 `token_id` | Key 今日输出 |
| `key_unlimited_quota` | bool | `token.UnlimitedQuota` | 仅影响当前 Key 的额度条，不得影响账户余额和账户额度环 |

### 响应示例

```json
{
  "success": true,
  "data": {
    "username": "alice",
    "display_name": "Alice",
    "account_remaining_quota": 3750000,
    "account_used_quota": 1250000,
    "account_total_quota": 5000000,
    "account_quota_used_today": 85000,
    "account_tokens_used_today": 12140,
    "account_prompt_tokens_today": 10340,
    "account_completion_tokens_today": 1800,
    "request_count_today": 23,
    "key_name": "生产主 key",
    "key_remaining_quota": 0,
    "key_used_quota": 125000,
    "key_quota_used_today": 85000,
    "key_tokens_used_today": 12140,
    "key_prompt_tokens_today": 10340,
    "key_completion_tokens_today": 1800,
    "key_unlimited_quota": true
  }
}
```

该示例中当前 Key 是“额度不限”，但账户仍展示真实的 `$7.50` 可用余额与 25% 账户额度使用率。Key 的不限额标记不能让账户余额变成“不限额”。

### 后端聚合建议

new-api 上游已有可复用数据：

- `model.User`：`Username`、`DisplayName`、`Quota`、`UsedQuota`、`RequestCount`。
- `model.Token`：`Id`、`UserId`、`Name`、`RemainQuota`、`UsedQuota`、`UnlimitedQuota`、`ModelLimitsEnabled`、`ModelLimits`、`ExpiredTime`、`Group`。
- `model.Log`：`UserId`、`TokenId`、`Quota`、`PromptTokens`、`CompletionTokens`、`ModelName`、`CreatedAt`、`Type`。
- `model.QuotaData`：按小时保存 `TokenUsed`、`Count`、`Quota`，适合数据看板；账户页需要当天实时值时，优先直接聚合消费日志，避免缓存写入延迟。

统计必须使用 `token_id`，不要只按 `token_name` 聚合，因为 Key 名称可以为空或重复。消费日志条件必须带 `type = model.LogTypeConsume`。

### 旧版字段兼容

客户端暂时兼容旧二开字段，但新后端应返回明确的 `account_*` / `key_*` 字段：

| 旧字段 | 新字段 |
|---|---|
| `quota` | `account_total_quota` |
| `used_quota` | `account_used_quota` |
| `used_today` | `account_quota_used_today` |
| `token_name` | `key_name` |
| `token_remain` | `key_remaining_quota` |
| `token_used` | `key_used_quota` |
| `token_used_today` | `key_quota_used_today` |
| `unlimited` | `key_unlimited_quota` |

旧接口没有真实模型 Token 数时，`今日 Tokens` 显示 `—`，绝不能用费用额度或 Key 数量冒充。

---

## 2. `GET /v1/models` — 当前 Key 可用模型（上游已有）

new-api 上游 `GET /v1/models` 已按当前 Key 的 `model_limits` 过滤。客户端直接复用，无需新增 `/api/app/models`。

```http
GET {站点根}/v1/models
Authorization: Bearer sk-xxxxx
Accept: application/json
```

兼容 OpenAI 风格 `{ "data": [...] }` 或直接数组；元素可以是字符串 ID 或 `{ "id": "..." }`。

```json
{ "data": [{ "id": "gpt-4o" }, { "id": "claude-sonnet-5" }] }
```

客户端提取非空 ID、去重并缓存。失败返回空列表，不阻断 Key 切换。

---

## 错误与安全要求

1. `user_id`、`token_id` 只能从 Bearer Key 对应记录派生，绝不读取请求参数。
2. profile 只返回当前用户和当前 Key 的数据，不返回 Key 明文。
3. 今日统计失败时保留账户 / Key 基础字段，将统计字段省略或置 `null`。
4. 非 200：客户端显示 `请求返回 HTTP <status>`；`success: false` 使用 `message`；网络异常使用异常消息。
5. 若日志功能被站点关闭或历史日志被清理，应让 Token 统计为空，不应伪造为 0。
