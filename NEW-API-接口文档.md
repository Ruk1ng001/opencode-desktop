# new-api 二开接口文档（Dokng 桌面客户端）

Dokng 客户端账户面板依赖 **两个** new-api 侧接口：一个是**二开新增**的用户 profile 接口，一个是**上游已有、二开确认可直接复用**的模型列表接口。所有请求都用 `Bearer sk-<token>` 鉴权，由 token 记录反查归属，**绝不从入参读取 user_id**。

---

## 通用约定

| 项 | 值 |
|---|---|
| 鉴权头 | `Authorization: Bearer sk-xxx` |
| Accept | `application/json` |
| 站点根推导 | 从渠道 `baseURL`（如 `https://host/v1`）**去掉尾部 `/v1`** 得到站点根 `https://host`；用户接口挂在站点根 `/api` 下，不是 `/v1` 渠道端点 |
| 额度单位 | `QUOTA_PER_UNIT = 500000`，即 **500000 额度 = 1 美元**。所有 `quota` / `*_used` / `*_remain` 字段都是这个整数单位，金额换算在客户端做 |
| 失败降级 | 客户端对任何非 200 / 网络异常都转中文提示，不崩溃、不阻塞主程序 |

---

## 1. `GET /api/app/profile` — 用户与 token 概览（⭐ 二开新增）

这是 new-api 仓库需要**新增实现**的端点（非 opencode 补丁层）。走 token 鉴权中间件：由请求头里的 `sk-` 定位到对应 token 记录，`user_id` 只从该 token 记录派生，**不读任何入参**，返回本人 profile。

### 请求

```
GET {站点根}/api/app/profile
Authorization: Bearer sk-xxxx
Accept: application/json
```

### 响应字段

响应支持两种形态：**扁平**对象，或包在 `data` 里（客户端 `body.data ?? body` 两者都兼容）。若带 `success: false` 则视为失败，读 `message` 作错误提示。

字段分两组——**账户级**（同一账户下所有 token 返回值一致）与 **token 级**（随 `sk-` 不同而不同）：

| 字段 | 层级 | 类型 | 含义 | 缺失默认 |
|---|---|---|---|---|
| `username` | 账户 | string | 用户名 | `""` |
| `avatar` | 账户 | string | 头像 URL | `""`（客户端显示首字母占位） |
| `quota` | 账户 | number | **账户总授予额度** = `user.quota + user.used_quota` | `0` |
| `used_quota` | 账户 | number | 账户累计消耗 | `0` |
| `used_today` | 账户 | number **可选** | 账户今日消耗；后端聚合失败时**可省略** | 省略→客户端显示「—」 |
| `token_name` | token | string | 当前 token 的名称（`token.Name`） | `""` |
| `token_remain` | token | number | 当前 token 剩余额度 | `0` |
| `token_used` | token | number | 当前 token 累计消耗 | `0` |
| `token_used_today` | token | number | 当前 token 今日消耗 | `0` |
| `unlimited` | token | bool | 当前 token 是否不限额 | `false` |

> `token_name` 的用途：客户端新增 key 时若用户未填名称，会用它一次性回填本地 label（之后不再与远端同步）。

### 响应示例

```json
{
  "username": "alice",
  "avatar": "https://host/avatars/1.png",
  "quota": 5000000,
  "used_quota": 1250000,
  "used_today": 85000,
  "token_name": "生产主 key",
  "token_remain": 3750000,
  "token_used": 125000,
  "token_used_today": 85000,
  "unlimited": false
}
```

客户端据此渲染：账户余额 = `(quota - used_quota) / 500000` 美元；账户今日/累计消耗；当前 token 的剩余/今日/累计与使用率。

### 错误处理

- 非 200 → `请求返回 HTTP <status>`
- `success: false` → 用响应 `message`，否则「接口返回失败」
- 网络异常 → `error.message` 或「网络请求失败」

---

## 2. `GET /v1/models` — 当前 token 可用模型（上游已有，无需二开）

经查 new-api 源码确认：`GET /v1/models` 已按 token 的 `model_limits` 过滤——`TokenAuth` 注入 `model_limits` → `ListModels` 据此过滤，返回**该 key 可用的模型**。因此客户端切换 key 时直接用 `/v1/models`，**无需新增 `/api/app/models`**。

### 请求

```
GET {站点根}/v1/models       # 若 baseURL 已含 /v1 则直接 {baseURL}/models
Authorization: Bearer sk-xxxxx
Accept: application/json
```

### 响应

兼容 OpenAI 风格（`{ "data": [...] }`）或直接数组；元素可为字符串 id 或 `{ id }` 对象。客户端提取所有非空 `id` 去重返回。

```json
{ "data": [{ "id": "gpt-4o" }, { "id": "claude-sonnet-5" }] }
```

切换激活 key 后，拉到的模型列表落盘缓存，供 provider 作为可选模型注入内核。失败返回空数组，不阻断切换。

---

## 安全要点（二开实现方须遵守）

1. **`user_id` / `token_id` 只从 `sk-` token 记录派生，永不读入参**——防止越权查他人 profile。
2. `/api/app/profile` 走的是**用户接口**（站点根 `/api`），鉴权中间件与 `/v1` 渠道端点不同。
3. `used_today` 允许聚合失败时省略，不要为它阻塞整个响应。
