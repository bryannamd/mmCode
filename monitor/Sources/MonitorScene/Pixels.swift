import CoreGraphics
import Foundation

// 픽셀 그리기의 바탕: 색, 팔레트, RGBA 버퍼. 시안(monitor-office-mock.html)의 R, B, map을 옮긴다.

public struct RGBA: Equatable, Sendable {
    public var r, g, b: UInt8
    public var a: Double

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }

    /// "#rrggbb" 형식.
    public init(_ hex: String) {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        self.init(UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff))
    }
}

/// 시안의 PAL.day / PAL.night 값 그대로.
public struct Palette: Sendable {
    public let ink, slab, hatch, wall, dot, wall2, base, floor, plank, wood, wood2, back, metal, metal2, tower,
        screen, on, code, off, box, box2, boxD, boxD2, door, door2, sofa, sofa2, paper, pink, red, amber,
        green, leaf, leaf2, pot, sky, cloud, sun, star, lampOn, lampOff, cone, shadow, grass, dim, white, bldg, card: RGBA
    /// 건물 층의 벽색(시안 WALLS). 층 순서대로 돌려 쓴다.
    public let walls: [RGBA]

    public static let day = Palette(
        ink: RGBA("#232845"), slab: RGBA("#232845"), hatch: RGBA("#4a548c"), wall: RGBA("#c8eee0"), dot: RGBA("#b2e3d2"), wall2: RGBA("#8fd6c2"), base: RGBA("#5aa896"),
        floor: RGBA("#f4bd6c"), plank: RGBA("#dd9c47"), wood: RGBA("#cf7c3c"), wood2: RGBA("#a35a26"), back: RGBA("#f1d3a2"), metal: RGBA("#a9bbd8"), metal2: RGBA("#6f83a8"), tower: RGBA("#39406b"),
        screen: RGBA("#232845"), on: RGBA("#eafcff"), code: RGBA("#2f8fe8"), off: RGBA("#55608a"), box: RGBA("#eab85f"), box2: RGBA("#b9822f"), boxD: RGBA("#93dba8"), boxD2: RGBA("#3f9a5f"),
        door: RGBA("#e9a55c"), door2: RGBA("#cf7c3c"), sofa: RGBA("#5aa896"), sofa2: RGBA("#3f8576"), paper: RGBA("#fffdf4"), pink: RGBA("#ff4f9a"), red: RGBA("#ef4b4b"), amber: RGBA("#ffc23d"),
        green: RGBA("#3fc46f"), leaf: RGBA("#3fae6a"), leaf2: RGBA("#2b8a52"), pot: RGBA("#d9683a"), sky: RGBA("#8fd0ff"), cloud: RGBA("#ffffff"), sun: RGBA("#ffd84d"), star: RGBA("#8fd0ff"), lampOn: RGBA("#ffe27a"),
        lampOff: RGBA("#e7a04a"), cone: RGBA(255, 226, 122, 0), shadow: RGBA(35, 40, 69, 0.2), grass: RGBA("#5fbf6b"), dim: RGBA(35, 40, 69, 0.38), white: RGBA("#ffffff"), bldg: RGBA("#232845"), card: RGBA("#fffdf4"),
        walls: [RGBA("#c8eee0"), RGBA("#ffd9c2"), RGBA("#d9d2ff"), RGBA("#fff0b8")])

    public static let night = Palette(
        ink: RGBA("#141833"), slab: RGBA("#141833"), hatch: RGBA("#2a3266"), wall: RGBA("#2f3b76"), dot: RGBA("#384588"), wall2: RGBA("#253066"), base: RGBA("#1b2452"),
        floor: RGBA("#8a6248"), plank: RGBA("#6f4a34"), wood: RGBA("#a9683a"), wood2: RGBA("#7a4424"), back: RGBA("#5a4a68"), metal: RGBA("#7f8fb8"), metal2: RGBA("#4f5d86"), tower: RGBA("#1d2248"),
        screen: RGBA("#141833"), on: RGBA("#d9fbff"), code: RGBA("#2f8fe8"), off: RGBA("#3a446f"), box: RGBA("#dfaa55"), box2: RGBA("#9c6b22"), boxD: RGBA("#84cf9a"), boxD2: RGBA("#2f7f4c"),
        door: RGBA("#a9683a"), door2: RGBA("#7a4424"), sofa: RGBA("#3f8576"), sofa2: RGBA("#2c6558"), paper: RGBA("#fffdf4"), pink: RGBA("#ff4f9a"), red: RGBA("#ef4b4b"), amber: RGBA("#ffc23d"),
        green: RGBA("#3fc46f"), leaf: RGBA("#2f9358"), leaf2: RGBA("#1f6d40"), pot: RGBA("#b9552e"), sky: RGBA("#141a3c"), cloud: RGBA("#2a3266"), sun: RGBA("#f4f1d0"), star: RGBA("#f4f1d0"), lampOn: RGBA("#ffe27a"),
        lampOff: RGBA("#6b5a3a"), cone: RGBA(255, 226, 122, 0.12), shadow: RGBA(0, 0, 0, 0.3), grass: RGBA("#2f6a4a"), dim: RGBA(8, 10, 28, 0.55), white: RGBA("#ffffff"), bldg: RGBA("#141833"), card: RGBA("#aab3d6"),
        walls: [RGBA("#2f3b76"), RGBA("#5a3f55"), RGBA("#3d3a78"), RGBA("#5a5236")])

    public static func of(night: Bool) -> Palette { night ? .night : .day }
}

/// 투명으로 시작하는 RGBA 버퍼. canvas fillRect와 같은 source-over 합성을 한다.
public struct PixelCanvas {
    public let width, height: Int
    public private(set) var px: [UInt8]

    public init(width: Int, height: Int) {
        self.width = width; self.height = height
        px = [UInt8](repeating: 0, count: width * height * 4)
    }

    /// 시안의 R. x, y는 반올림한다.
    public mutating func R(_ x: Double, _ y: Double, _ w: Int, _ h: Int, _ c: RGBA) {
        guard c.a > 0 else { return }
        // JS Math.round와 같게 .5는 위로 올린다.
        let rx = Int((x + 0.5).rounded(.down)), ry = Int((y + 0.5).rounded(.down))
        let x0 = max(0, rx), y0 = max(0, ry), x1 = min(width, rx + w), y1 = min(height, ry + h)
        guard x0 < x1, y0 < y1 else { return }
        for yy in y0..<y1 { for xx in x0..<x1 { blend((yy * width + xx) * 4, c) } }
    }

    public mutating func R(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: RGBA) { R(Double(x), Double(y), w, h, c) }

    /// 시안의 B: 외곽선 1px 상자.
    public mutating func B(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ fill: RGBA, _ ink: RGBA) {
        R(x, y, w, h, ink); R(x + 1, y + 1, w - 2, h - 2, fill)
    }

    /// 시안의 map: 글자 그림의 각 칸을 색표로 칠한다. '.'와 표에 없는 글자는 건너뛴다.
    public mutating func map(_ rows: [String], _ x: Int, _ y: Int, _ col: [Character: RGBA]) {
        for (r, row) in rows.enumerated() {
            for (i, ch) in row.enumerated() where ch != "." { if let c = col[ch] { R(x + i, y + r, 1, 1, c) } }
        }
    }

    public func pixel(_ x: Int, _ y: Int) -> RGBA {
        let i = (y * width + x) * 4
        return RGBA(px[i], px[i + 1], px[i + 2], Double(px[i + 3]) / 255)
    }

    private mutating func blend(_ i: Int, _ c: RGBA) {
        if c.a >= 1 { px[i] = c.r; px[i + 1] = c.g; px[i + 2] = c.b; px[i + 3] = 255; return }
        let da = Double(px[i + 3]) / 255, oa = c.a + da * (1 - c.a)
        func mix(_ s: UInt8, _ d: UInt8) -> UInt8 { UInt8(((Double(s) * c.a + Double(d) * da * (1 - c.a)) / oa).rounded()) }
        px[i] = mix(c.r, px[i]); px[i + 1] = mix(c.g, px[i + 1]); px[i + 2] = mix(c.b, px[i + 2])
        px[i + 3] = UInt8((oa * 255).rounded())
    }

    public func image() -> CGImage {
        let data = CFDataCreate(nil, px, px.count)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}
