import AppKit

// MARK: - 动态菜单弹层控制器

/// 根据受控 JSON DSL 动态渲染菜单栏弹层。
final class DynamicPopoverViewController: NSViewController {
    private var currentSpec: MenuRenderSpec?
    private var renderedContentViews: [NSView] = []

    var onAction: ((String) -> Void)?
    var onSizeChange: ((NSSize) -> Void)?

    override func loadView() {
        let panelView = GlassPanelView(frame: NSRect(origin: .zero, size: statusPanelSize))
        panelView.onAppearanceChange = { [weak self] in
            self?.rebuild()
        }
        view = panelView
    }

    func render(_ spec: MenuRenderSpec) {
        currentSpec = spec
        loadViewIfNeeded()
        rebuild()
    }

    private func rebuild() {
        renderedContentViews.forEach { $0.removeFromSuperview() }
        renderedContentViews.removeAll()

        guard let spec = currentSpec else {
            return
        }

        if let panelView = view as? GlassPanelView {
            panelView.updateChrome(cornerRadius: spec.panel.chrome?.cornerRadius)
        }

        let padding = spec.panel.padding ?? PanelPaddingSpec(top: 10, horizontal: 12, bottom: 0)
        let initialSize = initialPanelSize(from: spec.panel.size)
        view.setFrameSize(initialSize)

        let resolver = MenuBindingResolver(data: spec.data)
        let rootView = renderNode(spec.panel.root, resolver: resolver)
        rootView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootView)
        renderedContentViews.append(rootView)

        NSLayoutConstraint.activate([
            rootView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: CGFloat(padding.horizontal ?? 12)),
            rootView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -CGFloat(padding.horizontal ?? 12)),
            rootView.topAnchor.constraint(equalTo: view.topAnchor, constant: CGFloat(padding.top ?? 10)),
            rootView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -CGFloat(padding.bottom ?? 0))
        ])

        let finalSize = resolvedPanelSize(from: spec.panel.size, contentView: rootView, padding: padding)
        view.setFrameSize(finalSize)
        onSizeChange?(finalSize)
    }

    private func renderNode(_ node: RenderNode, resolver: MenuBindingResolver) -> NSView {
        switch node {
        case .stack(let node):
            return renderStack(node, resolver: resolver)
        case .text(let node):
            return renderText(node, resolver: resolver)
        case .button(let node):
            return renderButton(node, resolver: resolver)
        case .separator:
            return renderSeparator()
        case .meter(let node):
            return renderMeter(node, resolver: resolver)
        case .list(let node):
            return renderList(node, resolver: resolver)
        case .footerBar(let node):
            return renderFooterBar(node, resolver: resolver)
        case .forEach(let node):
            return renderForEach(node, resolver: resolver)
        case .unsupported(let type):
            let label = NSTextField(labelWithString: "Unsupported node: \(type)")
            applyTextStyle("error", to: label)
            return label
        }
    }

    private func renderStack(_ node: StackNode, resolver: MenuBindingResolver) -> NSView {
        let stack = NSStackView()
        stack.orientation = node.type == "hstack" ? .horizontal : .vertical
        stack.spacing = CGFloat(node.spacing ?? 0)
        stack.distribution = distribution(named: node.distribution)
        stack.alignment = alignment(named: node.alignment, orientation: stack.orientation)
        stack.translatesAutoresizingMaskIntoConstraints = false

        for child in node.children {
            stack.addArrangedSubview(renderNode(child, resolver: resolver))
        }

        return stack
    }

    private func renderText(_ node: TextNode, resolver: MenuBindingResolver) -> NSView {
        let label = NSTextField(labelWithString: resolver.resolveString(node.text))
        label.isSelectable = node.selectable ?? false
        label.lineBreakMode = node.selectable == true ? .byTruncatingMiddle : .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = !resolver.resolveBool(node.visible, default: true)
        applyTextStyle(resolver.resolveString(node.style), to: label)
        return label
    }

    private func renderButton(_ node: ButtonNode, resolver: MenuBindingResolver) -> NSView {
        let button = DynamicMenuButton()
        button.menuActionID = node.action
        button.title = ""
        button.image = NSImage(
            systemSymbolName: resolver.resolveString(node.icon),
            accessibilityDescription: resolver.resolveString(node.tooltip)
        )
        button.image?.isTemplate = true
        button.bezelStyle = .inline
        button.isBordered = false
        button.toolTip = resolver.resolveString(node.tooltip)
        button.target = self
        button.action = #selector(actionButtonPressed(_:))
        button.isEnabled = resolver.resolveBool(node.enabled, default: true)
        button.contentTintColor = secondaryColor
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 22),
            button.heightAnchor.constraint(equalToConstant: 22)
        ])
        return button
    }

    private func renderMeter(_ node: MeterNode, resolver: MenuBindingResolver) -> NSView {
        let meter = UsageMeterView(
            name: resolver.resolveString(node.title),
            symbolName: resolver.resolveString(node.icon),
            color: color(named: resolver.resolveString(node.color))
        )
        meter.update(
            progress: resolver.resolveDouble(node.progress, default: 0),
            percent: resolver.resolveString(node.percent),
            amount: resolver.resolveString(node.amount)
        )
        meter.translatesAutoresizingMaskIntoConstraints = false
        return meter
    }

    private func renderList(_ node: ListNode, resolver: MenuBindingResolver) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false

        let style = resolver.resolveString(node.style)
        let values = resolver.resolveArray(node.items).prefix(node.limit ?? Int.max)
        for (index, value) in values.enumerated() {
            let label = NSTextField(labelWithString: value.displayString)
            label.lineBreakMode = .byTruncatingMiddle
            label.maximumNumberOfLines = 1
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.translatesAutoresizingMaskIntoConstraints = false
            applyTextStyle(style, to: label, listIndex: index)
            stack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        return stack
    }

    private func renderFooterBar(_ node: FooterBarNode, resolver: MenuBindingResolver) -> NSView {
        let footer = FooterBarView()
        footer.translatesAutoresizingMaskIntoConstraints = false

        let left = NSTextField(labelWithString: resolver.resolveString(node.left.text))
        applyTextStyle(resolver.resolveString(node.left.style), to: left)
        left.lineBreakMode = .byTruncatingMiddle
        left.maximumNumberOfLines = 1

        let right = NSTextField(labelWithString: resolver.resolveString(node.right.text))
        applyTextStyle(resolver.resolveString(node.right.style), to: right)
        right.alignment = .right
        right.lineBreakMode = .byTruncatingTail
        right.maximumNumberOfLines = 1

        let row = NSStackView(views: [left, right])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .gravityAreas
        row.translatesAutoresizingMaskIntoConstraints = false

        footer.addSubview(row)
        NSLayoutConstraint.activate([
            footer.heightAnchor.constraint(equalToConstant: CGFloat(node.height ?? 32)),
            row.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            row.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
        ])

        return footer
    }

    private func renderForEach(_ node: ForEachNode, resolver: MenuBindingResolver) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false

        for item in resolver.resolveArray(node.items) {
            let itemResolver = resolver.child(item: item)
            stack.addArrangedSubview(renderNode(node.template, resolver: itemResolver))
        }

        return stack
    }

    private func renderSeparator() -> NSView {
        let view = NSBox()
        view.boxType = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    private func initialPanelSize(from size: PanelSizeSpec) -> NSSize {
        if size.mode == "fixed" {
            return NSSize(
                width: size.width ?? statusPanelSize.width,
                height: size.height ?? statusPanelSize.height
            )
        }

        return NSSize(
            width: size.minWidth ?? statusPanelSize.width,
            height: size.minHeight ?? statusPanelSize.height
        )
    }

    private func resolvedPanelSize(
        from size: PanelSizeSpec,
        contentView: NSView,
        padding: PanelPaddingSpec
    ) -> NSSize {
        guard size.mode == "auto" else {
            return initialPanelSize(from: size)
        }

        view.layoutSubtreeIfNeeded()
        let fitting = contentView.fittingSize
        let horizontal = (padding.horizontal ?? 12) * 2
        let vertical = (padding.top ?? 10) + (padding.bottom ?? 0)
        let width = clamp(
            fitting.width + horizontal,
            min: size.minWidth ?? statusPanelSize.width,
            max: size.maxWidth ?? 420
        )
        let height = clamp(
            fitting.height + vertical,
            min: size.minHeight ?? 160,
            max: size.maxHeight ?? 620
        )
        return NSSize(width: width, height: height)
    }

    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(value, max))
    }

    private func distribution(named name: String?) -> NSStackView.Distribution {
        switch name {
        case "spaceBetween":
            return .gravityAreas
        case "fillEqually":
            return .fillEqually
        case "equalSpacing":
            return .equalSpacing
        default:
            return .fill
        }
    }

    private func alignment(named name: String?, orientation: NSUserInterfaceLayoutOrientation) -> NSLayoutConstraint.Attribute {
        switch name {
        case "lastBaseline":
            return .lastBaseline
        case "leading":
            return .leading
        case "trailing":
            return .trailing
        case "width":
            return .width
        default:
            return orientation == .vertical ? .width : .centerY
        }
    }

    private func applyTextStyle(_ style: String?, to label: NSTextField, listIndex: Int? = nil) {
        switch style {
        case "title":
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.textColor = primaryColor
        case "summaryAmount":
            label.font = .monospacedDigitSystemFont(ofSize: 25, weight: .bold)
            label.textColor = .systemBlue
        case "caption":
            label.font = .systemFont(ofSize: 10, weight: .semibold)
            label.textColor = secondaryColor
            label.alignment = .right
        case "sectionTitle":
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = primaryColor
        case "monoSmall":
            label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            label.textColor = primaryColor
        case "detailLine":
            label.font = listIndex == 0
                ? .systemFont(ofSize: 10, weight: .semibold)
                : .systemFont(ofSize: 10, weight: .medium)
            label.textColor = detailColor
        case "footerText":
            label.font = .systemFont(ofSize: 10, weight: .medium)
            label.textColor = secondaryColor
        case "error":
            label.font = .systemFont(ofSize: 10, weight: .medium)
            label.textColor = .systemRed
        case "secondary":
            label.font = .systemFont(ofSize: 11)
            label.textColor = secondaryColor
        default:
            label.font = .systemFont(ofSize: 11)
            label.textColor = primaryColor
        }
    }

    private func color(named name: String) -> NSColor {
        switch name {
        case "systemIndigo":
            return .systemIndigo
        case "systemPurple":
            return .systemPurple
        case "systemGreen":
            return .systemGreen
        case "systemOrange":
            return .systemOrange
        case "systemRed":
            return .systemRed
        default:
            return .systemBlue
        }
    }

    private var primaryColor: NSColor {
        isDarkAppearance(view.effectiveAppearance)
            ? NSColor.white.withAlphaComponent(0.92)
            : .labelColor
    }

    private var secondaryColor: NSColor {
        isDarkAppearance(view.effectiveAppearance)
            ? NSColor.white.withAlphaComponent(0.68)
            : .secondaryLabelColor
    }

    private var detailColor: NSColor {
        isDarkAppearance(view.effectiveAppearance)
            ? NSColor.white.withAlphaComponent(0.58)
            : .secondaryLabelColor
    }

    @objc private func actionButtonPressed(_ sender: DynamicMenuButton) {
        onAction?(sender.menuActionID)
    }
}

private final class DynamicMenuButton: NSButton {
    var menuActionID = ""
}
