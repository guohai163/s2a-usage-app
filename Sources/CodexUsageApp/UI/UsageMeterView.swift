import AppKit

// MARK: - 用量进度视图

/// 单个用量周期的展示行，包含图标、百分比、进度条和金额。
final class UsageMeterView: NSView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "0.0%")
    private let progress = ThinProgressView()
    private let amountLabel = NSTextField(labelWithString: "$0 / $1")
    private let rowName: String

    init(name: String, symbolName: String, color: NSColor) {
        rowName = name
        super.init(frame: .zero)
        progress.fillColor = color

        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: name)
        iconView.image?.isTemplate = true
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = name
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        percentLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        percentLabel.alignment = .right

        amountLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        amountLabel.alignment = .right

        let labelStack = NSStackView(views: [iconView, titleLabel])
        labelStack.orientation = .horizontal
        labelStack.alignment = .centerY
        labelStack.spacing = 5
        labelStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let top = NSStackView(views: [labelStack, percentLabel])
        top.orientation = .horizontal
        top.alignment = .centerY
        top.distribution = .fill
        top.spacing = 8
        top.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [top, progress, amountLabel])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            progress.heightAnchor.constraint(equalToConstant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 43)
        ])

        applyAppearance()
        update(usage: 0, limit: 1)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 用最新用量刷新进度条和文字。
    func update(usage: Double, limit: Double) {
        let percentage = limit > 0 ? usage / limit * 100 : 0
        progress.progress = max(0, min(percentage / 100, 1))
        percentLabel.stringValue = String(format: "%.1f%%", percentage)
        amountLabel.stringValue = "$\(Self.amount(usage)) / $\(Self.amount(limit))"
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    private func applyAppearance() {
        if isDarkAppearance(effectiveAppearance) {
            let primary = NSColor.white.withAlphaComponent(0.90)
            let secondary = NSColor.white.withAlphaComponent(0.72)
            iconView.contentTintColor = secondary
            titleLabel.textColor = secondary
            percentLabel.textColor = primary
            amountLabel.textColor = secondary
        } else {
            iconView.contentTintColor = .secondaryLabelColor
            titleLabel.textColor = .secondaryLabelColor
            percentLabel.textColor = .labelColor
            amountLabel.textColor = .secondaryLabelColor
        }
    }

    private static func amount(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}
