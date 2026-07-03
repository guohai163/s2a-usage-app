import AppKit

// MARK: - 应用协调器

/// 应用的协调层。
///
/// 这里连接菜单栏入口、弹层、主窗口和 UsageService，避免视图层直接持有业务逻辑。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let service = UsageService()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusPopoverController = StatusPopoverViewController()
    private let statusPanel = UsagePanelWindow(
        contentRect: NSRect(origin: .zero, size: statusPanelSize),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 720, height: 430),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )

    private let titleLabel = NSTextField(labelWithString: "Codex Usage")
    private let subtitleLabel = NSTextField(labelWithString: "Reads ~/.codex/auth.json and ~/.codex/config.toml")
    private let refreshButton = NSButton(title: "刷新用量", target: nil, action: nil)
    private let dailyRow = UsageMeterView(name: "Daily", symbolName: "clock", color: .systemBlue)
    private let weeklyRow = UsageMeterView(name: "Weekly", symbolName: "calendar", color: .systemIndigo)
    private let monthlyRow = UsageMeterView(name: "Monthly", symbolName: "chart.bar", color: .systemPurple)
    private let expiresLabel = NSTextField(labelWithString: "Expires  -")
    private let endpointTitleLabel = NSTextField(labelWithString: "节点推荐  -")
    private let endpointHostLabel = NSTextField(labelWithString: "域名  -")
    private let endpointDetailLabel = NSTextField(labelWithString: "等待 traceroute")
    private let copyEndpointButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private var isRefreshing = false
    private var refreshSerial = 0
    private var pendingRefreshTasks = 0
    private var currentEndpointHost: String?

    /// 应用启动后配置菜单栏和主窗口，并立即刷新一次数据。
    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureWindow()
        refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// 创建菜单栏状态项和对应的浮动弹层。
    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = makeCodexStatusIcon()
            button.imagePosition = .imageLeft
            button.title = " --"
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            button.toolTip = "Codex Usage"
            button.target = self
            button.action = #selector(toggleUsagePanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        statusPopoverController.loadViewIfNeeded()
        statusPanel.contentView = statusPopoverController.view
        statusPanel.isOpaque = false
        statusPanel.backgroundColor = .clear
        statusPanel.hasShadow = true
        statusPanel.level = .statusBar
        statusPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        statusPanel.hidesOnDeactivate = true
        statusPanel.isReleasedWhenClosed = false

        statusPopoverController.onRefresh = { [weak self] in
            self?.refresh()
        }
        statusPopoverController.onQuit = {
            NSApp.terminate(nil)
        }
    }

    /// 保留一个可扩展的主窗口，用于展示更完整的用量和节点详情。
    private func configureWindow() {
        window.title = "Codex Usage"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = content

        titleLabel.font = .systemFont(ofSize: 26, weight: .semibold)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.font = .systemFont(ofSize: 13)

        refreshButton.target = self
        refreshButton.action = #selector(refreshButtonPressed)
        refreshButton.bezelStyle = .rounded

        expiresLabel.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        endpointTitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        endpointTitleLabel.lineBreakMode = .byTruncatingMiddle
        endpointHostLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        endpointHostLabel.textColor = .labelColor
        endpointHostLabel.lineBreakMode = .byTruncatingMiddle
        endpointHostLabel.isSelectable = true
        endpointDetailLabel.font = .systemFont(ofSize: 13)
        endpointDetailLabel.alignment = .left
        endpointDetailLabel.textColor = .secondaryLabelColor
        endpointDetailLabel.maximumNumberOfLines = 5
        endpointDetailLabel.lineBreakMode = .byWordWrapping
        endpointDetailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        configureIconButton(copyEndpointButton, symbolName: "doc.on.doc", accessibility: "复制推荐域名")
        copyEndpointButton.target = self
        copyEndpointButton.action = #selector(copyEndpointHostPressed)
        copyEndpointButton.isEnabled = false
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 3
        statusLabel.lineBreakMode = .byWordWrapping

        let headerText = NSStackView(views: [titleLabel, subtitleLabel])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 4

        let header = NSStackView(views: [headerText, refreshButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .gravityAreas

        let rows = NSStackView(views: [dailyRow, weeklyRow, monthlyRow])
        rows.orientation = .vertical
        rows.alignment = .width
        rows.spacing = 10

        let endpointHeader = NSStackView(views: [endpointTitleLabel, copyEndpointButton])
        endpointHeader.orientation = .horizontal
        endpointHeader.alignment = .centerY
        endpointHeader.distribution = .gravityAreas
        endpointHeader.spacing = 8

        let endpointStack = NSStackView(views: [endpointHeader, endpointHostLabel, endpointDetailLabel])
        endpointStack.orientation = .vertical
        endpointStack.alignment = .leading
        endpointStack.spacing = 5

        let mainStack = NSStackView(views: [header, separator(), rows, expiresLabel, endpointStack, statusLabel])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 22
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            mainStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            mainStack.topAnchor.constraint(equalTo: content.topAnchor, constant: 30),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -28),
            header.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            rows.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            endpointStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            endpointHeader.widthAnchor.constraint(equalTo: endpointStack.widthAnchor),
            endpointHostLabel.widthAnchor.constraint(equalTo: endpointStack.widthAnchor),
            endpointDetailLabel.widthAnchor.constraint(equalTo: endpointStack.widthAnchor),
            copyEndpointButton.widthAnchor.constraint(equalToConstant: 24),
            copyEndpointButton.heightAnchor.constraint(equalToConstant: 24)
        ])

        window.orderOut(nil)
    }

    @objc private func toggleUsagePanel() {
        guard let button = statusItem.button else {
            return
        }

        if statusPanel.isVisible {
            statusPanel.orderOut(nil)
        } else {
            positionStatusPanel(relativeTo: button)
            statusPanel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            refresh()
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        statusPanel.orderOut(nil)
    }

    private func positionStatusPanel(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else {
            return
        }

        let buttonFrame = buttonWindow.convertToScreen(button.frame)
        let panelSize = statusPanel.frame.size
        let screenFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let idealX = buttonFrame.midX - panelSize.width / 2
        let clampedX = min(max(idealX, screenFrame.minX + 8), screenFrame.maxX - panelSize.width - 8)
        let idealY = buttonFrame.minY - panelSize.height - 6
        let clampedY = max(idealY, screenFrame.minY + 8)

        statusPanel.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
    }

    private func separator() -> NSView {
        let view = NSBox()
        view.boxType = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    private func configureIconButton(_ button: NSButton, symbolName: String, accessibility: String) {
        button.title = ""
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibility)
        button.image?.isTemplate = true
        button.bezelStyle = .rounded
    }

    @objc private func refreshButtonPressed() {
        refresh()
    }

    /// 同时刷新用量和节点推荐；两个异步任务都结束后才恢复刷新按钮。
    private func refresh() {
        guard !isRefreshing else {
            return
        }
        refreshSerial += 1
        let serial = refreshSerial
        isRefreshing = true
        pendingRefreshTasks = 2
        setRefreshEnabled(false)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "正在读取本地配置并查询用量..."
        statusPopoverController.setLoading()
        setEndpointChecking()
        statusPopoverController.setEndpointChecking()

        service.loadUsage { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                guard self.refreshSerial == serial else {
                    return
                }
                defer {
                    self.finishRefreshTask(serial: serial)
                }

                switch result {
                case .success(let snapshot):
                    self.update(snapshot)
                    self.statusPopoverController.update(snapshot)
                    self.updateStatusItem(with: snapshot)
                    self.statusLabel.textColor = .secondaryLabelColor
                    self.statusLabel.stringValue = snapshot.note ?? "已更新。"
                case .failure(let error):
                    self.statusPopoverController.setError(error)
                    self.statusLabel.textColor = .systemRed
                    self.statusLabel.stringValue = "错误: \(error.localizedDescription)"
                }
            }
        }

        service.loadEndpointRecommendation { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                guard self.refreshSerial == serial else {
                    return
                }
                defer {
                    self.finishRefreshTask(serial: serial)
                }

                switch result {
                case .success(let recommendation):
                    self.update(recommendation)
                    self.statusPopoverController.update(recommendation)
                case .failure(let error):
                    self.setEndpointError(error)
                    self.statusPopoverController.setEndpointError(error)
                }
            }
        }
    }

    private func update(_ snapshot: UsageSnapshot) {
        dailyRow.update(usage: snapshot.dailyUsage, limit: snapshot.dailyLimit)
        weeklyRow.update(usage: snapshot.weeklyUsage, limit: snapshot.weeklyLimit)
        monthlyRow.update(usage: snapshot.monthlyUsage, limit: snapshot.monthlyLimit)
        expiresLabel.stringValue = "Expires  \(snapshot.expiresAt)"
    }

    private func setEndpointChecking() {
        currentEndpointHost = nil
        endpointTitleLabel.stringValue = "节点推荐  探测中"
        endpointTitleLabel.textColor = .labelColor
        endpointHostLabel.stringValue = "域名  -"
        copyEndpointButton.isEnabled = false
        endpointDetailLabel.textColor = .secondaryLabelColor
        endpointDetailLabel.stringValue = "正在读取 /api/v1/settings/public 并运行 traceroute..."
    }

    private func setEndpointError(_ error: Error) {
        currentEndpointHost = nil
        endpointTitleLabel.stringValue = "节点推荐  暂不可用"
        endpointTitleLabel.textColor = .labelColor
        endpointHostLabel.stringValue = "域名  -"
        copyEndpointButton.isEnabled = false
        endpointDetailLabel.textColor = .systemRed
        endpointDetailLabel.stringValue = error.localizedDescription
    }

    private func update(_ recommendation: EndpointRecommendation) {
        currentEndpointHost = recommendation.recommendedHost
        endpointTitleLabel.stringValue = recommendation.headline
        endpointTitleLabel.textColor = .labelColor
        endpointHostLabel.stringValue = "域名  \(recommendation.recommendedHost ?? "-")"
        endpointDetailLabel.textColor = .secondaryLabelColor
        endpointDetailLabel.stringValue = recommendation.detail
        copyEndpointButton.isEnabled = recommendation.recommendedHost != nil
    }

    private func finishRefreshTask(serial: Int) {
        guard refreshSerial == serial else {
            return
        }
        pendingRefreshTasks = max(0, pendingRefreshTasks - 1)
        if pendingRefreshTasks == 0 {
            isRefreshing = false
            setRefreshEnabled(true)
        }
    }

    private func setRefreshEnabled(_ enabled: Bool) {
        refreshButton.isEnabled = enabled
        statusPopoverController.setRefreshEnabled(enabled)
    }

    @objc private func copyEndpointHostPressed() {
        guard let host = currentEndpointHost else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(host, forType: .string)
        endpointDetailLabel.textColor = .secondaryLabelColor
        endpointDetailLabel.stringValue = "已复制域名 \(host)"
    }

    private func updateStatusItem(with snapshot: UsageSnapshot) {
        let remaining = snapshot.dailyLimit > 0
            ? max(0, min(100, 100 - snapshot.dailyUsage / snapshot.dailyLimit * 100))
            : 0
        statusItem.button?.title = " \(Int(remaining.rounded()))%"
    }
}
