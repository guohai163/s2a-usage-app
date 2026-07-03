# 菜单渲染 JSON v1

默认渲染 JSON 在 `Resources/default-menu-render.json`。构建时会复制到 `CodexUsage.app/Contents/Resources/default-menu-render.json`，运行时由 `MenuRenderSpecFactory` 加载。

## 根结构

```json
{
  "schema": "codex.menu.render.v1",
  "statusItem": {},
  "panel": {},
  "data": {},
  "actions": {}
}
```

- `schema`：当前固定为 `codex.menu.render.v1`。
- `statusItem`：菜单栏图标、文字、tooltip。
- `panel`：弹出层尺寸、外观、padding 和布局树。
- `data`：运行时展示数据。当前默认模板会由 Swift 填充，不需要在模板里写死真实用量。
- `actions`：按钮动作白名单声明。

## 绑定语法

使用 `{{path.to.value}}` 读取 `data` 中的值。

- `{{summary.value}}` 读取 `data.summary.value`。
- `{{endpoint.host}}` 读取 `data.endpoint.host`。
- `forEach` 循环内用 `{{item.title}}` 读取当前 item。
- 只支持取值和字符串替换，不支持表达式、脚本或 AppKit 类名。

缺失绑定会显示 `-` 或按控件默认值降级，避免渲染崩溃。

## statusItem

```json
{
  "icon": { "type": "builtin", "name": "codexTemplate" },
  "title": { "text": "{{statusItem.title}}", "font": "mono12Semibold" },
  "tooltip": "Codex Usage"
}
```

- `icon.type = builtin` 且 `name = codexTemplate`：使用应用内绘制的 Codex 模板图标。
- `icon.type = system`：`name` 使用 SF Symbols 名称。
- `title.text` 支持绑定。
- `title.font` 当前支持 `mono12Semibold`。

## panel

```json
{
  "size": { "mode": "fixed", "width": 292, "height": 386 },
  "chrome": { "type": "glass", "cornerRadius": 14 },
  "padding": { "top": 10, "horizontal": 12, "bottom": 0 },
  "root": {}
}
```

- `size.mode = fixed`：使用 `width` 和 `height`。
- `size.mode = auto`：根据内容自适应，可配 `minWidth`、`minHeight`、`maxWidth`、`maxHeight`。
- `chrome.type = glass`：使用当前毛玻璃背景。
- `padding.horizontal` 同时控制左右内边距。

## 布局节点

### vstack / hstack

```json
{
  "type": "vstack",
  "spacing": 7,
  "children": []
}
```

- `type`：`vstack` 垂直排列，`hstack` 水平排列。
- `spacing`：子节点间距。
- `distribution`：支持 `spaceBetween`、`fillEqually`、`equalSpacing`。
- `alignment`：支持 `lastBaseline`、`leading`、`trailing`、`width`。

### text

```json
{
  "type": "text",
  "text": "{{summary.value}}",
  "style": "summaryAmount",
  "visible": "{{status.visible}}",
  "selectable": true
}
```

- `text`：文本或绑定。
- `style`：样式 token。
- `visible`：布尔值或绑定，默认 `true`。
- `selectable`：是否允许复制文本。

### button

```json
{
  "type": "button",
  "icon": "arrow.clockwise",
  "tooltip": "刷新用量",
  "enabled": "{{controls.canRefresh}}",
  "action": "refresh"
}
```

- `icon`：SF Symbols 名称。
- `enabled`：布尔值或绑定，默认 `true`。
- `action`：引用 `actions` 中的 key。

### meter

```json
{
  "type": "meter",
  "title": "{{item.title}}",
  "icon": "{{item.icon}}",
  "progress": "{{item.progress}}",
  "percent": "{{item.percent}}",
  "amount": "{{item.amount}}",
  "color": "{{item.color}}"
}
```

- `progress`：0 到 1。
- `percent` 和 `amount` 是已格式化文本。
- `color` 支持 `systemBlue`、`systemIndigo`、`systemPurple`、`systemGreen`、`systemOrange`、`systemRed`。

### list

```json
{
  "type": "list",
  "items": "{{endpoint.lines}}",
  "limit": 5,
  "style": "{{endpoint.lineStyle}}"
}
```

- `items` 必须绑定到数组。
- `limit` 限制最多渲染几行。
- 当前用于 traceroute 明细和错误信息。

### forEach

```json
{
  "type": "forEach",
  "items": "{{usageRows}}",
  "template": {}
}
```

- `items` 必须绑定到数组。
- `template` 会对每个 item 渲染一次。
- 模板内用 `{{item.xxx}}` 访问当前数据。

### footerBar

```json
{
  "type": "footerBar",
  "height": 32,
  "left": { "text": "{{footer.left}}", "style": "footerText" },
  "right": { "text": "{{footer.right}}", "style": "footerText" }
}
```

用于底部固定信息栏，当前显示过期时间和 schema 来源。

## 样式 token

当前支持：

- `title`
- `summaryAmount`
- `caption`
- `sectionTitle`
- `monoSmall`
- `detailLine`
- `footerText`
- `error`
- `secondary`

样式由 `DynamicPopoverViewController` 映射到 AppKit 字体、颜色、对齐方式。v1 不支持 CSS。

## actions

只允许白名单动作：

```json
{
  "refresh": { "type": "app.refresh" },
  "copyEndpoint": {
    "type": "clipboard.copy",
    "value": "{{endpoint.host}}",
    "feedback": "已复制域名 {{endpoint.host}}"
  },
  "quit": { "type": "app.quit" },
  "openBrowser": {
    "type": "system.openURL",
    "url": "https://example.com"
  },
  "openUsagePage": {
    "type": "app.openPage",
    "page": "usage.detail",
    "params": { "tab": "endpoints" }
  }
}
```

- `app.refresh`：触发用量和节点刷新。
- `clipboard.copy`：复制 `value` 到剪贴板，可显示 `feedback`。
- `system.openURL`：用系统默认浏览器打开 URL。
- `app.openPage`：打开主窗口指定页面。当前 `usage.detail` 会拉起主窗口。
- `app.quit`：退出应用。

## 运行时 data 形状

默认模板期望 Swift 填充以下数据：

```json
{
  "statusItem": { "title": " 83%" },
  "controls": { "canRefresh": true },
  "summary": { "value": "$128.40", "caption": "REMAINING" },
  "usageRows": [
    {
      "title": "Daily",
      "icon": "clock",
      "progress": 0.17,
      "percent": "17.0%",
      "amount": "$17 / $100",
      "color": "systemBlue"
    }
  ],
  "endpoint": {
    "title": "推荐 Singapore",
    "source": "NETWORK",
    "host": "sg.example.com",
    "hostText": "sg.example.com",
    "canCopy": true,
    "lineStyle": "detailLine",
    "lines": ["全部节点 traceroute"]
  },
  "footer": { "left": "Expires: Never", "right": "代理用量格式" },
  "status": { "visible": false, "text": "", "style": "secondary" }
}
```

业务计算仍在 Swift 服务层完成；JSON 只描述如何展示和交互。
