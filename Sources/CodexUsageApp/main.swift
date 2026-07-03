import AppKit

// 创建唯一的 AppKit 应用实例。
let app = NSApplication.shared

// AppDelegate 持有菜单栏状态项、窗口和刷新流程，必须在 app.run() 期间保持强引用。
let delegate = AppDelegate()
app.delegate = delegate

// 以辅助应用运行：常驻菜单栏，不在 Dock 中显示图标。
app.setActivationPolicy(.accessory)

// 启动主事件循环。
app.run()
