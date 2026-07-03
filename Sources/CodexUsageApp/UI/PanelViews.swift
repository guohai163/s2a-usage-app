import AppKit

// MARK: - 面板基础视图

/// 细条形进度条，用于 Daily/Weekly/Monthly 三个用量行。
final class ThinProgressView: NSView {
    var progress: Double = 0 {
        didSet { needsDisplay = true }
    }
    var fillColor: NSColor = .controlAccentColor {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 8)
    }

    override func draw(_ dirtyRect: NSRect) {
        let trackRect = bounds.insetBy(dx: 0, dy: 2)
        let radius = trackRect.height / 2
        let trackColor = isDarkAppearance(effectiveAppearance)
            ? NSColor.white.withAlphaComponent(0.13)
            : NSColor.black.withAlphaComponent(0.075)
        trackColor.setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius).fill()

        let clamped = max(0, min(progress, 1))
        let fillWidth = clamped > 0 ? max(trackRect.height + 1, trackRect.width * clamped) : 0
        guard fillWidth > 0 else { return }

        fillColor.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: trackRect.minX, y: trackRect.minY, width: fillWidth, height: trackRect.height),
            xRadius: radius,
            yRadius: radius
        ).fill()
    }
}

/// 叠在毛玻璃背景上的轻量渐变色层。
final class GlassTintView: NSView {
    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        let gradient: NSGradient?
        if isDarkAppearance(effectiveAppearance) {
            gradient = NSGradient(colorsAndLocations:
                (NSColor(calibratedRed: 0.22, green: 0.15, blue: 0.27, alpha: 0.62), 0.0),
                (NSColor(calibratedRed: 0.13, green: 0.12, blue: 0.18, alpha: 0.48), 0.56),
                (NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.07, alpha: 0.42), 1.0)
            )
        } else {
            gradient = NSGradient(colorsAndLocations:
                (NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.97, alpha: 0.30), 0.0),
                (NSColor(calibratedRed: 0.96, green: 0.78, blue: 1.0, alpha: 0.22), 0.58),
                (NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.24), 1.0)
            )
        }
        gradient?.draw(in: bounds, angle: 135)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// 菜单栏弹层的毛玻璃容器，负责圆角、边框和深浅色材质切换。
final class GlassPanelView: NSView {
    private let effect = NSVisualEffectView()
    private let tint = GlassTintView()
    var onAppearanceChange: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.borderWidth = 1

        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.translatesAutoresizingMaskIntoConstraints = false

        tint.translatesAutoresizingMaskIntoConstraints = false

        addSubview(effect)
        addSubview(tint)
        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: trailingAnchor),
            effect.topAnchor.constraint(equalTo: topAnchor),
            effect.bottomAnchor.constraint(equalTo: bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: trailingAnchor),
            tint.topAnchor.constraint(equalTo: topAnchor),
            tint.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        applyAppearance()
    }

    func updateChrome(cornerRadius: Double?) {
        if let cornerRadius {
            layer?.cornerRadius = CGFloat(cornerRadius)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
        onAppearanceChange?()
    }

    private func applyAppearance() {
        if isDarkAppearance(effectiveAppearance) {
            effect.material = .hudWindow
            effect.appearance = NSAppearance(named: .vibrantDark)
            layer?.borderColor = NSColor.white.withAlphaComponent(0.42).cgColor
        } else {
            effect.material = .popover
            effect.appearance = NSAppearance(named: .vibrantLight)
            layer?.borderColor = NSColor.white.withAlphaComponent(0.82).cgColor
        }
        tint.needsDisplay = true
    }
}

/// 弹层底部信息栏背景，绘制浅色分隔线和半透明底色。
final class FooterBarView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let fillColor = isDarkAppearance(effectiveAppearance)
            ? NSColor.white.withAlphaComponent(0.055)
            : NSColor.white.withAlphaComponent(0.12)
        fillColor.setFill()
        bounds.fill()

        let lineColor = isDarkAppearance(effectiveAppearance)
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.05)
        lineColor.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.minX, y: bounds.maxY - 0.5))
        path.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY - 0.5))
        path.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// 可获得 key 状态的无边框面板，用于承载菜单栏弹层。
final class UsagePanelWindow: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}
