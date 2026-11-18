import AppKit
import MonitorScene

/// One silhouette, drawn at menu-bar scale. The envelope flap doubles as the cat's muzzle.
enum PostCat: Equatable {
    case quiet, call, paused, connecting, offline

    static func state(_ store: Store) -> Self {
        if store.hcMissing || store.hcDown { return .offline }
        if !store.loaded { return .connecting }
        let ground = SceneBuilder.buildingGround(store.world)
        if ground.turn { return .call }
        return ground.icon == .stop ? .paused : .quiet
    }

    var description: String {
        switch self {
        case .quiet: return "개입할 일이 없습니다"
        case .call: return "확인할 요청이 있습니다"
        case .paused: return "사용자 정지"
        case .connecting: return "터미널 목록을 읽는 중"
        case .offline: return "터미널 연결 확인 필요"
        }
    }

    var image: NSImage {
        let image = NSImage(size: CGSize(width: 23, height: 18), flipped: true) { _ in
            draw(at: .zero, color: .black)
            return true
        }
        image.isTemplate = true
        return image
    }

    func draw(at origin: CGPoint, color: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: origin.x, yBy: origin.y)
        transform.concat()
        color.setStroke()
        color.setFill()
        let x: CGFloat = self == .quiet ? 3 : 0
        func stroke(_ points: [CGPoint], width: CGFloat = 1.55) {
            let p = NSBezierPath()
            p.move(to: points[0])
            points.dropFirst().forEach { p.line(to: $0) }
            p.lineWidth = width
            p.lineJoinStyle = .round
            p.lineCapStyle = .round
            p.stroke()
        }
        let head = NSBezierPath()
        head.move(to: CGPoint(x: x + 1.5, y: 12))
        head.line(to: CGPoint(x: x + 2, y: 3))
        head.line(to: CGPoint(x: x + 6.4, y: 6))
        head.curve(to: CGPoint(x: x + 11, y: 6), controlPoint1: CGPoint(x: x + 8, y: 5.6), controlPoint2: CGPoint(x: x + 9.5, y: 5.6))
        head.line(to: CGPoint(x: x + 15, y: 3))
        head.line(to: CGPoint(x: x + 15.7, y: 12))
        head.curve(to: CGPoint(x: x + 1.5, y: 12), controlPoint1: CGPoint(x: x + 16, y: 18), controlPoint2: CGPoint(x: x + 1, y: 18))
        head.close()
        head.lineWidth = 1.65
        head.lineJoinStyle = .round
        head.stroke()
        for eye in [x + 5, x + 10.4] {
            NSBezierPath(roundedRect: CGRect(x: eye, y: 9, width: 1.7, height: self == .paused ? 1 : 2.4), xRadius: 0.8, yRadius: 0.8).fill()
        }
        stroke([CGPoint(x: x + 7.4, y: 12.7), CGPoint(x: x + 8.6, y: 13.5), CGPoint(x: x + 9.8, y: 12.7)], width: 1.15)
        switch self {
        case .quiet: break
        case .call:
            stroke([CGPoint(x: 19, y: 8.5), CGPoint(x: 19, y: 1.8), CGPoint(x: 22, y: 1.8)], width: 2)
            NSBezierPath(ovalIn: CGRect(x: 18, y: 11, width: 2.2, height: 2.2)).fill()
        case .paused:
            for a in [18, 21] { CGRect(x: CGFloat(a), y: 4, width: 1.6, height: 6).fill() }
        case .connecting:
            for y in [3, 6, 9] { NSBezierPath(ovalIn: CGRect(x: 19, y: CGFloat(y), width: 1.8, height: 1.8)).fill() }
        case .offline:
            stroke([CGPoint(x: 18, y: 4), CGPoint(x: 22, y: 8)])
            stroke([CGPoint(x: 22, y: 4), CGPoint(x: 18, y: 8)])
        }
    }
}
