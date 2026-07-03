# Codex Usage macOS App

原生 macOS 桌面应用，用来读取本机 Codex 配置并展示订阅用量。

## 构建

```bash
chmod +x scripts/build_app.sh
./scripts/build_app.sh
```

构建产物：

```text
build/CodexUsage.app
```

## 运行

```bash
open build/CodexUsage.app
```

应用会读取：

- `~/.codex/auth.json` 顶层 `OPENAI_API_KEY`
- `~/.codex/config.toml` 中的 `[model_providers.OpenAI].base_url`

然后请求：

```text
${base_url}/v1/usage
```

并显示 Daily、Weekly、Monthly 的 20 格进度条、百分比、USD 用量和原始 `expires_at`。

应用也会按 `base_url` 同源请求：

```text
/api/v1/settings/public
```

从响应里的 `custom_endpoints` 提取候选节点，并对每个节点运行本机 `traceroute`。推荐逻辑会综合末端 RTT、跳数和超时跳数，在界面里显示网络更优的节点、域名、复制按钮和全部节点测试数据。

每次完成节点探测后，应用会把本次测试过的节点名和域名缓存到本机。下次如果无法连接 `/api/v1/settings/public`，会自动使用缓存域名继续进行 traceroute 测试，并在界面中以 `CACHE` 标记结果来源。

如果接口没有返回顶层 `subscription`，但返回代理用量格式（如 `daily_usage`、`usage.today`、`remaining`），应用会自动按日期聚合今天、本周、本月用量，并显示剩余额度信息。

应用会常驻 macOS 菜单栏状态区，不显示 Dock 图标。点击菜单栏里的图标，会打开半透明毛玻璃风格的用量弹层：Remaining 摘要、Daily/Weekly/Monthly 细进度条、百分比和金额，并提供：

- 刷新用量
- custom_endpoints 节点推荐
- 退出 Codex Usage
