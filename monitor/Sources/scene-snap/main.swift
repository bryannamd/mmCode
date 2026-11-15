import CoreGraphics
import CoreText
import Foundation
import ImageIO
import MonitorCore
import MonitorScene

// 상태별 장면을 4배(960×432) PNG로 저장한다. 시안과 눈으로 비교하는 확인 도구다.
// 이름표 글자는 실제 앱에서는 AppKit이 그린다. 비교하기 쉽게 여기서 비슷하게 얹는다.

let scale = 4
let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "scene-snap-out", isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
Fonts.register()

func color(_ hex: String) -> CGColor {
    let v = UInt32(hex.dropFirst(), radix: 16)!
    return CGColor(srgbRed: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
}

/// 위가 0인 좌표로 글자 칸을 그린다. 크기는 패널(2배) 기준 px.
func label(_ ctx: CGContext, _ text: String, x: CGFloat, top: CGFloat, size: CGFloat, box: CGRect?, fill: String, center: Bool) {
    let H = CGFloat(SceneRenderer.height * scale), k = CGFloat(scale) / 2
    let font = CTFontCreateWithName(Fonts.jua as CFString, size * k, nil)
    let attr = NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font, kCTForegroundColorAttributeName as NSAttributedString.Key: color("#232845")])
    let line = CTLineCreateWithAttributedString(attr)
    let w = CTLineGetTypographicBounds(line, nil, nil, nil)
    // 시안 .stage: 테두리 2px, 안쪽 여백 1px 6px 0, 줄 높이 15px.
    let r = box ?? CGRect(x: center ? x - (w / 2 + 8 * k) : x, y: top, width: w + 16 * k, height: 19 * k)
    ctx.setFillColor(color("#232845")); ctx.fill(CGRect(x: r.minX, y: H - r.maxY, width: r.width, height: r.height))
    ctx.setFillColor(color(fill)); ctx.fill(CGRect(x: r.minX + 2 * k, y: H - r.maxY + 2 * k, width: r.width - 4 * k, height: r.height - 4 * k))
    let tx = box == nil ? r.minX + 8 * k : r.minX + 7 * k
    ctx.textPosition = CGPoint(x: tx, y: H - r.midY - (CTFontGetAscent(font) - CTFontGetDescent(font)) / 2)
    CTLineDraw(line, ctx)
}

func save(_ name: String, _ imgs: SceneImages, _ labels: [WallLabel], night: Bool) throws {
    let W = SceneRenderer.width * scale, H = SceneRenderer.height * scale
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .none
    let full = CGRect(x: 0, y: 0, width: W, height: H)
    ctx.draw(imgs.base, in: full); ctx.draw(imgs.fx, in: full)
    let s = CGFloat(scale)
    for l in labels {
        switch l.style {
        case .stage: label(ctx, l.text, x: l.rect.minX * s, top: l.rect.minY * s, size: 12, box: nil, fill: night ? "#aab3d6" : "#fffdf4", center: true)
        case .floorName:
            let r = CGRect(x: l.rect.minX * s, y: l.rect.minY * s, width: l.rect.width * s, height: l.rect.height * s)
            // 시안의 .fname은 종이 칸(장면에 그림) 위에 글자만 얹는다.
            let H = CGFloat(H), font = CTFontCreateWithName(Fonts.jua as CFString, 13 * s / 2, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: l.text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font, kCTForegroundColorAttributeName as NSAttributedString.Key: color("#232845")]))
            ctx.textPosition = CGPoint(x: r.minX + 7 * s / 2, y: H - r.midY - (CTFontGetAscent(font) - CTFontGetDescent(font)) / 2)
            CTLineDraw(line, ctx)
        }
    }
    let url = out.appendingPathComponent(name + ".png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    print(url.path)
}

for night in [false, true] {
    let t = night ? "night" : "day"
    for d in Demo.allCases {
        for fr in 0...1 {
            if d.isOffice {
                let v = SceneBuilder.office(d.world, project: 0, night: night)
                try save("office-\(d.rawValue)-\(t)-f\(fr)", SceneRenderer.render(v.scene, frame: fr), v.scene.labels, night: night)
            }
            if d == .building || d == .otherFloorAlert {
                let v = SceneBuilder.building(d.world, night: night)
                try save("building-\(d.rawValue)-\(t)-f\(fr)", SceneRenderer.render(v.scene, frame: fr), v.scene.labels, night: night)
            }
        }
    }
}
