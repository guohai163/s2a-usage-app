import AppKit

// MARK: - 菜单栏弹层控制器

/// 菜单栏点击后出现的紧凑弹层。
///
/// 只负责构建和刷新弹层 UI，实际数据加载由 AppDelegate 触发。
final class StatusPopoverViewController: NSViewController {
    private let titleLabel = NSTextField(labelWithString: "Codex Usage")
    private let summaryLabel = NSTextField(labelWithString: "Remaining -")
    private let remainingCaption = NSTextField(labelWithString: "REMAINING")
    private let dailyRow = UsageMeterView(name: "Daily", symbolName: "clock", color: .systemBlue)
    private let weeklyRow = UsageMeterView(name: "Weekly", symbolName: "calendar", color: .systemIndigo)
    private let monthlyRow = UsageMeterView(name: "Monthly", symbolName: "chart.bar", color: .systemPurple)
    private let expiresLabel = NSTextField(labelWithString: "Expires: -")
    private let schemaLabel = NSTextField(labelWithString: "等待刷新")
    private let endpointLabel = NSTextField(labelWithString: "节点推荐 -")
    private let endpointCaption = NSTextField(labelWithString: "NETWORK")
    private let endpointDomainLabel = NSTextField(labelWithString: "域名 -")
    private let endpointResultsStack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let refreshButton = NSButton()
    private let copyEndpointButton = NSButton()
    private let quitButton = NSButton()
    private var currentEndpointHost: String?
    private var endpointResultsUseErrorColor = false

    var onRefresh: (() -> Void)?
    var onQuit: (() -> Void)?

    override func loadView() {
        let panelView = GlassPanelView(frame: NSRect(origin: .zero, size: statusPanelSize))
        panelView.onAppearanceChange = { [weak self] in
            self?.applyAppearance()
        }
        view = panelView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        summaryLabel.font = .monospacedDigitSystemFont(ofSize: 25, weight: .bold)
        remainingCaption.font = .systemFont(ofSize: 10, weight: .semibold)
        remainingCaption.alignment = .right

        expiresLabel.font = .systemFont(ofSize: 10, weight: .medium)
        expiresLabel.lineBreakMode = .byTruncatingMiddle
        expiresLabel.maximumNumberOfLines = 1
        expiresLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        schemaLabel.font = .systemFont(ofSize: 10, weight: .medium)
        schemaLabel.alignment = .right
        schemaLabel.lineBreakMode = .byTruncatingTail
        schemaLabel.maximumNumberOfLines = 1
        schemaLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        endpointLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        endpointLabel.lineBreakMode = .byTruncatingMiddle
        endpointLabel.maximumNumberOfLines = 1
        endpointLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        endpointCaption.font = .systemFont(ofSize: 10, weight: .semibold)
        endpointCaption.alignment = .right
        endpointDomainLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        endpointDomainLabel.lineBreakMode = .byTruncatingMiddle
        endpointDomainLabel.maximumNumberOfLines = 1
        endpointDomainLabel.isSelectable = true
        endpointDomainLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        endpointResultsStack.orientation = .vertical
        endpointResultsStack.alignment = .width
        endpointResultsStack.spacing = 3
        endpointResultsStack.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.isHidden = true

        configureIconButton(refreshButton, symbolName: "arrow.clockwise", accessibility: "刷新用量")
        refreshButton.target = self
        refreshButton.action = #selector(refreshPressed)

        configureIconButton(copyEndpointButton, symbolName: "doc.on.doc", accessibility: "复制推荐域名")
        copyEndpointButton.target = self
        copyEndpointButton.action = #selector(copyEndpointHostPressed)
        copyEndpointButton.isEnabled = false

        configureIconButton(quitButton, symbolName: "rectangle.portrait.and.arrow.right", accessibility: "退出")
        quitButton.target = self
        quitButton.action = #selector(quitPressed)

        let buttonStack = NSStackView(views: [refreshButton, quitButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 2

        let header = NSStackView(views: [titleLabel, buttonStack])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .gravityAreas
        header.translatesAutoresizingMaskIntoConstraints = false

        let summaryRow = NSStackView(views: [summaryLabel, remainingCaption])
        summaryRow.orientation = .horizontal
        summaryRow.alignment = .lastBaseline
        summaryRow.distribution = .gravityAreas
        summaryRow.translatesAutoresizingMaskIntoConstraints = false

        let rows = NSStackView(views: [dailyRow, weeklyRow, monthlyRow])
        rows.orientation = .vertical
        rows.alignment = .width
        rows.spacing = 7
        rows.translatesAutoresizingMaskIntoConstraints = false

        let endpointHeader = NSStackView(views: [endpointLabel, endpointCaption])
        endpointHeader.orientation = .horizontal
        endpointHeader.alignment = .centerY
        endpointHeader.distribution = .gravityAreas
        endpointHeader.translatesAutoresizingMaskIntoConstraints = false

        let endpointDomainRow = NSStackView(views: [endpointDomainLabel, copyEndpointButton])
        endpointDomainRow.orientation = .horizontal
        endpointDomainRow.alignment = .centerY
        endpointDomainRow.distribution = .fill
        endpointDomainRow.spacing = 6
        endpointDomainRow.translatesAutoresizingMaskIntoConstraints = false

        setEndpointResultLines(["等待探测"])

        let endpointStack = NSStackView(views: [endpointHeader, endpointDomainRow, endpointResultsStack])
        endpointStack.orientation = .vertical
        endpointStack.alignment = .width
        endpointStack.spacing = 3
        endpointStack.translatesAutoresizingMaskIntoConstraints = false

        let footer = NSStackView(views: [expiresLabel, schemaLabel])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.distribution = .gravityAreas
        footer.translatesAutoresizingMaskIntoConstraints = false

        let footerBar = FooterBarView()
        footerBar.translatesAutoresizingMaskIntoConstraints = false
        footerBar.addSubview(footer)

        let stack = NSStackView(views: [header, separator(), summaryRow, rows, endpointStack, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        view.addSubview(footerBar)
        NSLayoutConstraint.activate([
            refreshButton.widthAnchor.constraint(equalToConstant: 22),
            refreshButton.heightAnchor.constraint(equalToConstant: 22),
            copyEndpointButton.widthAnchor.constraint(equalToConstant: 20),
            copyEndpointButton.heightAnchor.constraint(equalToConstant: 20),
            quitButton.widthAnchor.constraint(equalToConstant: 22),
            quitButton.heightAnchor.constraint(equalToConstant: 22),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            summaryRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            rows.widthAnchor.constraint(equalTo: stack.widthAnchor),
            endpointStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            endpointHeader.widthAnchor.constraint(equalTo: endpointStack.widthAnchor),
            endpointDomainRow.widthAnchor.constraint(equalTo: endpointStack.widthAnchor),
            endpointResultsStack.widthAnchor.constraint(equalTo: endpointStack.widthAnchor),
            dailyRow.widthAnchor.constraint(equalTo: rows.widthAnchor),
            weeklyRow.widthAnchor.constraint(equalTo: rows.widthAnchor),
            monthlyRow.widthAnchor.constraint(equalTo: rows.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: footerBar.topAnchor, constant: -8),
            footerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footerBar.heightAnchor.constraint(equalToConstant: 32),
            footer.leadingAnchor.constraint(equalTo: footerBar.leadingAnchor, constant: 12),
            footer.trailingAnchor.constraint(equalTo: footerBar.trailingAnchor, constant: -12),
            footer.centerYAnchor.constraint(equalTo: footerBar.centerYAnchor)
        ])
        applyAppearance()
    }

    /// 进入用量刷新中的 UI 状态。
    func setLoading() {
        refreshButton.isEnabled = false
        statusLabel.isHidden = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "正在刷新..."
    }

    /// 展示用量加载失败信息。
    func setError(_ error: Error) {
        statusLabel.isHidden = false
        statusLabel.textColor = .systemRed
        statusLabel.stringValue = "错误: \(error.localizedDescription)"
    }

    /// 用最新用量快照刷新弹层。
    func update(_ snapshot: UsageSnapshot) {
        dailyRow.update(usage: snapshot.dailyUsage, limit: snapshot.dailyLimit)
        weeklyRow.update(usage: snapshot.weeklyUsage, limit: snapshot.weeklyLimit)
        monthlyRow.update(usage: snapshot.monthlyUsage, limit: snapshot.monthlyLimit)
        expiresLabel.stringValue = "Expires: \(snapshot.expiresAt == "-" ? "Never" : snapshot.expiresAt)"
        summaryLabel.attributedStringValue = Self.remainingString(snapshot.remaining)
        schemaLabel.stringValue = snapshot.schemaLabel
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
    }

    /// 进入节点探测中的 UI 状态。
    func setEndpointChecking() {
        currentEndpointHost = nil
        endpointLabel.stringValue = "节点推荐 探测中"
        endpointCaption.stringValue = "NETWORK"
        endpointDomainLabel.stringValue = "域名 -"
        setEndpointResultLines(["正在读取公共设置并运行 traceroute"])
        copyEndpointButton.isEnabled = false
    }

    /// 展示节点推荐加载失败信息。
    func setEndpointError(_ error: Error) {
        currentEndpointHost = nil
        endpointLabel.stringValue = "节点推荐 暂不可用"
        endpointCaption.stringValue = "NETWORK"
        endpointDomainLabel.stringValue = "域名 -"
        setEndpointResultLines([error.localizedDescription], isError: true)
        copyEndpointButton.isEnabled = false
    }

    /// 用节点推荐结果刷新弹层。
    func update(_ recommendation: EndpointRecommendation) {
        currentEndpointHost = recommendation.recommendedHost
        endpointLabel.stringValue = recommendation.headline
        endpointCaption.stringValue = recommendation.sourceLabel
        endpointDomainLabel.stringValue = recommendation.recommendedHost ?? "域名 -"
        setEndpointResultLines(recommendation.detailLines)
        copyEndpointButton.isEnabled = recommendation.recommendedHost != nil
    }

    func setRefreshEnabled(_ enabled: Bool) {
        refreshButton.isEnabled = enabled
    }

    private func setEndpointResultLines(_ lines: [String], isError: Bool = false) {
        endpointResultsUseErrorColor = isError
        endpointResultsStack.arrangedSubviews.forEach { view in
            endpointResultsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for (index, line) in lines.prefix(5).enumerated() {
            let label = NSTextField(labelWithString: line)
            label.font = index == 0
                ? .systemFont(ofSize: 10, weight: .semibold)
                : .systemFont(ofSize: 10, weight: .medium)
            label.alignment = .left
            label.lineBreakMode = .byTruncatingMiddle
            label.maximumNumberOfLines = 1
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.translatesAutoresizingMaskIntoConstraints = false
            endpointResultsStack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: endpointResultsStack.widthAnchor).isActive = true
        }
        applyEndpointResultAppearance()
    }

    private func applyEndpointResultAppearance() {
        let color: NSColor
        if endpointResultsUseErrorColor {
            color = .systemRed
        } else if isDarkAppearance(view.effectiveAppearance) {
            color = NSColor.white.withAlphaComponent(0.58)
        } else {
            color = .secondaryLabelColor
        }

        for case let label as NSTextField in endpointResultsStack.arrangedSubviews {
            label.textColor = color
        }
    }

    private func configureIconButton(_ button: NSButton, symbolName: String, accessibility: String) {
        button.title = ""
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibility)
        button.image?.isTemplate = true
        button.bezelStyle = .inline
        button.isBordered = false
    }

    private func applyAppearance() {
        if isDarkAppearance(view.effectiveAppearance) {
            let primary = NSColor.white.withAlphaComponent(0.92)
            let secondary = NSColor.white.withAlphaComponent(0.68)
            let tertiary = NSColor.white.withAlphaComponent(0.56)
            titleLabel.textColor = primary
            summaryLabel.textColor = .systemBlue
            remainingCaption.textColor = secondary
            expiresLabel.textColor = secondary
            schemaLabel.textColor = secondary
            endpointLabel.textColor = primary
            endpointCaption.textColor = secondary
            endpointDomainLabel.textColor = primary
            applyEndpointResultAppearance()
            statusLabel.textColor = tertiary
            refreshButton.contentTintColor = secondary
            copyEndpointButton.contentTintColor = secondary
            quitButton.contentTintColor = secondary
        } else {
            titleLabel.textColor = .labelColor
            summaryLabel.textColor = .systemBlue
            remainingCaption.textColor = .secondaryLabelColor
            expiresLabel.textColor = .secondaryLabelColor
            schemaLabel.textColor = .secondaryLabelColor
            endpointLabel.textColor = .labelColor
            endpointCaption.textColor = .secondaryLabelColor
            endpointDomainLabel.textColor = .labelColor
            applyEndpointResultAppearance()
            statusLabel.textColor = .secondaryLabelColor
            refreshButton.contentTintColor = .secondaryLabelColor
            copyEndpointButton.contentTintColor = .secondaryLabelColor
            quitButton.contentTintColor = .secondaryLabelColor
        }
    }

    private func separator() -> NSView {
        let view = NSBox()
        view.boxType = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    @objc private func refreshPressed() {
        onRefresh?()
    }

    @objc private func copyEndpointHostPressed() {
        guard let host = currentEndpointHost else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(host, forType: .string)
        setEndpointResultLines(["已复制域名 \(host)"])
    }

    @objc private func quitPressed() {
        onQuit?()
    }

    private static func remainingString(_ value: Double?) -> NSAttributedString {
        guard let value else {
            return NSAttributedString(string: "-")
        }
        let text = "$\(amount(value))"
        let result = NSMutableAttributedString(string: text)
        if let dotRange = text.range(of: ".") {
            let nsRange = NSRange(dotRange.lowerBound..<text.endIndex, in: text)
            result.addAttributes([
                .font: NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ], range: nsRange)
        }
        return result
    }

    private static func amount(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}
