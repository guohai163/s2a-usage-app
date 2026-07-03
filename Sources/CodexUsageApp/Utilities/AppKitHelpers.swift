import AppKit

// MARK: - AppKit 外观工具

/// 菜单栏弹层的固定尺寸，集中放置以便主窗口和控制器共用。
let statusPanelSize = NSSize(width: 292, height: 386)

/// 判断当前 AppKit 外观是否更接近深色模式。
func isDarkAppearance(_ appearance: NSAppearance) -> Bool {
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
}

/// 绘制菜单栏状态图标。
///
/// 图像被设置为 template image，让系统自动按菜单栏深浅色调整前景色。
func makeCodexStatusIcon() -> NSImage {
    let size = NSSize(width: 22, height: 22)
    let image = NSImage(size: size)

    image.lockFocus()
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.isTemplate = true
        return image
    }

    context.saveGState()
    defer { context.restoreGState() }

    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: size.width / 100, y: -size.height / 100)
    context.setStrokeColor(NSColor.black.cgColor)
    context.setFillColor(NSColor.black.cgColor)
    context.setLineWidth(4)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    func stroke(_ build: (CGMutablePath) -> Void) {
        let path = CGMutablePath()
        build(path)
        context.addPath(path)
        context.strokePath()
    }

    func fill(_ build: (CGMutablePath) -> Void) {
        let path = CGMutablePath()
        build(path)
        context.addPath(path)
        context.fillPath()
    }

    stroke { path in
        path.move(to: CGPoint(x: 12, y: 24))
        path.addCurve(to: CGPoint(x: 50, y: 12), control1: CGPoint(x: 12, y: 24), control2: CGPoint(x: 50, y: 12))
        path.addCurve(to: CGPoint(x: 88, y: 24), control1: CGPoint(x: 50, y: 12), control2: CGPoint(x: 88, y: 24))
        path.addLine(to: CGPoint(x: 86, y: 55))
        path.addCurve(to: CGPoint(x: 50, y: 96), control1: CGPoint(x: 84, y: 78), control2: CGPoint(x: 50, y: 96))
        path.addCurve(to: CGPoint(x: 14, y: 55), control1: CGPoint(x: 50, y: 96), control2: CGPoint(x: 16, y: 78))
        path.closeSubpath()
    }

    stroke { path in
        path.move(to: CGPoint(x: 50, y: 8))
        path.addLine(to: CGPoint(x: 60, y: 45))
        path.addLine(to: CGPoint(x: 50, y: 85))
        path.addLine(to: CGPoint(x: 40, y: 45))
        path.closeSubpath()
    }

    fill { path in
        path.move(to: CGPoint(x: 66, y: 35))
        path.addQuadCurve(to: CGPoint(x: 48, y: 52), control: CGPoint(x: 66, y: 52))
        path.addQuadCurve(to: CGPoint(x: 66, y: 70), control: CGPoint(x: 66, y: 52))
        path.addQuadCurve(to: CGPoint(x: 84, y: 52), control: CGPoint(x: 66, y: 52))
        path.addQuadCurve(to: CGPoint(x: 66, y: 35), control: CGPoint(x: 66, y: 52))
        path.closeSubpath()
    }

    fill { path in
        path.move(to: CGPoint(x: 76, y: 18))
        path.addQuadCurve(to: CGPoint(x: 69, y: 25), control: CGPoint(x: 76, y: 25))
        path.addQuadCurve(to: CGPoint(x: 76, y: 32), control: CGPoint(x: 76, y: 25))
        path.addQuadCurve(to: CGPoint(x: 83, y: 25), control: CGPoint(x: 76, y: 25))
        path.addQuadCurve(to: CGPoint(x: 76, y: 18), control: CGPoint(x: 76, y: 25))
        path.closeSubpath()
    }

    stroke { path in
        path.move(to: CGPoint(x: 40, y: 22))
        path.addCurve(to: CGPoint(x: 22, y: 45), control1: CGPoint(x: 29, y: 22), control2: CGPoint(x: 22, y: 32))
    }

    stroke { path in
        path.move(to: CGPoint(x: 20, y: 38))
        path.addCurve(to: CGPoint(x: 40, y: 76), control1: CGPoint(x: 13, y: 54), control2: CGPoint(x: 22, y: 75))
        path.addLine(to: CGPoint(x: 48, y: 68))
    }

    stroke { path in
        path.move(to: CGPoint(x: 42, y: 35))
        path.addLine(to: CGPoint(x: 32, y: 35))
        path.addLine(to: CGPoint(x: 32, y: 48))
        path.addLine(to: CGPoint(x: 42, y: 48))
    }

    stroke { path in
        path.move(to: CGPoint(x: 32, y: 48))
        path.addLine(to: CGPoint(x: 32, y: 54))
        path.addLine(to: CGPoint(x: 42, y: 64))
    }

    image.isTemplate = true
    return image
}
