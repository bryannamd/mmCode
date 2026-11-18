import AppKit
import MonitorScene

// DESIGN.md의 색과 글꼴. 다른 값은 쓰지 않는다.

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
}

enum Theme {
    static let ink = NSColor(hex: 0x233e38), ink2 = NSColor(hex: 0x36534b), ink3 = NSColor(hex: 0x4f7167)
    static let paper = NSColor(hex: 0xfffbef), pink = NSColor(hex: 0xffccd0)
    static let onInkSub = NSColor(hex: 0xdae8dd), paperSub = NSColor(hex: 0x515e53), paperLine = NSColor(hex: 0xe0d9c7)
    static let postalRed = NSColor(hex: 0x8a3044), sage = NSColor(hex: 0xc8dfc6)
    static let box = NSColor(hex: 0xeab85f), box2 = NSColor(hex: 0xb9822f), boxDone = NSColor(hex: 0x93dba8), boxDone2 = NSColor(hex: 0x3f9a5f)
    static let surface = NSColor(hex: 0xfffdf8)
    static let cardNight = NSColor(hex: 0xaab3d6)

    static func jua(_ size: CGFloat) -> NSFont { NSFont(name: Fonts.jua, size: size) ?? .systemFont(ofSize: size) }
    /// 본문. 숫자는 폭이 같은 숫자로 쓴다.
    static func body(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont { .monospacedDigitSystemFont(ofSize: size, weight: weight) }
}

/// 한 줄 글자. 위가 0인 좌표계(isFlipped)에서 쓴다.
struct Line {
    let text: NSAttributedString

    init(_ s: String, _ font: NSFont, _ color: NSColor) {
        let p = NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingTail
        text = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
    }

    var width: CGFloat { ceil(text.size().width) }

    /// 글자 높이(ascender-descender)의 가운데를 cy에 맞춘다. CSS의 줄 상자 가운데 정렬과 같다.
    func draw(x: CGFloat, cy: CGFloat, maxWidth: CGFloat = .greatestFiniteMagnitude) {
        guard let f = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont else { return }
        let h = f.ascender - f.descender
        text.draw(with: CGRect(x: x, y: cy - h / 2, width: min(maxWidth, width + 1), height: h + 2), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

/// 테두리를 선 안쪽에 그린다(CSS border-box와 같음).
func fillRound(_ r: CGRect, _ radius: CGFloat, _ fill: NSColor?, stroke: NSColor? = nil, width: CGFloat = 2) {
    if let fill { fill.setFill(); NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill() }
    if let stroke {
        let i = r.insetBy(dx: width / 2, dy: width / 2), p = NSBezierPath(roundedRect: i, xRadius: max(0, radius - width / 2), yRadius: max(0, radius - width / 2))
        p.lineWidth = width; stroke.setStroke(); p.stroke()
    }
}

/// 픽셀 그림을 보간 없이 그린다. 위가 0인 좌표계에서 CGImage를 바로 세운다.
func drawPixels(_ img: CGImage, in r: CGRect) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.saveGState(); ctx.interpolationQuality = .none
    ctx.translateBy(x: r.minX, y: r.maxY); ctx.scaleBy(x: 1, y: -1)
    ctx.draw(img, in: CGRect(origin: .zero, size: r.size))
    ctx.restoreGState()
}
