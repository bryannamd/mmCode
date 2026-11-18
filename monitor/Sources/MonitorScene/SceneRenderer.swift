import CoreGraphics

// 장면 그리기. 시안의 room, shelf, drawOffice, bell, drawFx, drawBuilding, icon을 값 그대로 옮긴다.
// 장면(base)과 주의 표시(fx)를 따로 그린다. 분홍은 fx에서만 쓴다.

public struct SceneImages {
    public var base: CGImage
    /// 물음표, 느낌표, 분홍 벨. 투명 바탕.
    public var fx: CGImage
}

public enum SceneRenderer {
    public static let width = 240, height = 108

    public static func render(_ s: OfficeScene, frame: Int) -> SceneImages {
        let fr = frame & 1  // 프레임은 두 장이다. 좌표에 그대로 더하므로 0과 1만 쓴다.
        let P = Palette.of(night: s.night)
        var c = PixelCanvas(width: width, height: height), f = PixelCanvas(width: width, height: height)
        let bounds = drawOffice(&c, s, P, fr)
        drawOfficeFx(&f, s, P, fr, bounds)
        return SceneImages(base: c.image(), fx: f.image())
    }

    public static func render(_ s: BuildingScene, frame: Int) -> SceneImages {
        let fr = frame & 1
        let P = Palette.of(night: s.night)
        var c = PixelCanvas(width: width, height: height), f = PixelCanvas(width: width, height: height)
        drawBuilding(&c, s, P, fr)
        for (i, fl) in s.floors.enumerated() {
            guard let a = fl.alert else { continue }
            let y = BuildingLayout.floorY + i * BuildingLayout.floorH, up = fr   // 깜박임 대신 1픽셀 들썩인다
            f.R(220, y + 8, 4, 2, P.ink); f.B(224, y + 2 - up, 11, 13, P.pink, P.ink); f.text(a == .error ? "!" : "?", 228, y + 6 - up, P.ink)
        }
        return SceneImages(base: c.image(), fx: f.image())
    }

    // MARK: 사무실

    static func room(_ c: inout PixelCanvas, _ P: Palette, _ night: Bool) {
        let W = width, H = height
        c.R(0, 0, W, H, P.wall)
        for y in stride(from: 8, to: 48, by: 8) { for x in stride(from: y % 16 != 0 ? 10 : 4, to: W, by: 12) { c.R(x, y, 1, 1, P.dot) } }
        c.R(0, 50, W, 20, P.wall2); for x in stride(from: 5, to: W, by: 10) { c.R(x, 52, 1, 16, P.wall) }
        c.R(0, 70, W, 2, P.base); c.R(0, 72, W, 32, P.floor)
        for y in stride(from: 80, to: 104, by: 8) {
            c.R(0, y, W, 1, P.plank)
            for x in stride(from: y % 16 != 0 ? 14 : 44, to: W, by: 60) { c.R(x, y - 8, 1, 8, P.plank) }
        }
        c.R(0, 0, W, 3, P.slab); c.R(0, 104, W, 4, P.slab); c.R(0, 0, 3, H, P.slab); c.R(237, 0, 3, H, P.slab)
        for x in stride(from: 6, to: W - 6, by: 7) { c.R(x, 105, 2, 1, P.hatch); c.R(x + 1, 106, 2, 1, P.hatch); c.R(x, 1, 2, 1, P.hatch) }
        // 창(낮에는 해, 밤에는 달과 별), 시계, 액자(생선)
        c.B(57, 7, 26, 17, P.sky, P.ink); c.R(69, 8, 1, 15, P.ink); c.R(58, 15, 24, 1, P.ink); c.R(55, 24, 30, 2, P.ink)
        if night { c.R(74, 10, 4, 4, P.sun); c.R(76, 10, 2, 2, P.sky); c.R(61, 11, 1, 1, P.star); c.R(65, 19, 1, 1, P.star); c.R(78, 20, 1, 1, P.star) }
        else { c.R(61, 10, 4, 4, P.sun); c.R(73, 18, 6, 2, P.cloud); c.R(75, 17, 3, 1, P.cloud) }
        c.B(150, 8, 11, 11, P.card, P.ink); c.R(155, 10, 1, 4, P.ink); c.R(155, 13, 3, 1, P.ink)
        c.B(178, 9, 15, 10, P.card, P.ink); c.R(182, 12, 6, 4, P.code); c.R(188, 11, 2, 1, P.code); c.R(188, 16, 2, 1, P.code); c.R(189, 12, 1, 4, P.code); c.R(183, 13, 1, 1, P.ink)
    }

    static func shelf(_ c: inout PixelCanvas, _ P: Palette, _ x: Int, _ done: Bool) {
        c.B(x, 40, 26, 32, P.wood2, P.ink); c.R(x + 1, 41, 24, 30, P.back); c.R(x + 1, 55, 24, 2, P.wood); c.R(x + 1, 56, 24, 1, P.wood2)
        if done { c.R(x + 11, 34, 1, 6, P.ink); c.B(x + 12, 33, 8, 6, P.green, P.ink) }
    }

    static func bell(_ c: inout PixelCanvas, _ P: Palette, _ x: Int, _ col: RGBA, _ ring: Int) {
        c.B(x, 95, 14, 9, P.wood, P.ink); c.R(x + 1, 101, 12, 2, P.wood2)
        c.B(x + 3 + ring, 88, 8, 7, col, P.ink); c.R(x + 6 + ring, 86, 2, 2, P.ink); c.R(x + 2, 94, 10, 1, P.ink)
    }

    /// 캐릭터마다 그린 영역을 돌려준다. 주의 표시 자리에 쓴다.
    static func drawOffice(_ c: inout PixelCanvas, _ st: OfficeScene, _ P: Palette, _ fr: Int) -> [String: SpriteBounds] {
        room(&c, P, st.night)
        // 문. 걷는 동작이 없으므로 늘 닫혀 있다.
        c.B(8, 36, 16, 36, P.door, P.ink)
        c.R(9, 68, 14, 3, P.door2); c.B(12, 41, 8, 8, P.sky, P.ink); c.R(20, 56, 2, 2, P.amber)
        shelf(&c, P, 31, false); shelf(&c, P, 211, true)
        for dx in OfficeLayout.desks {
            let on = st.actors.contains { $0.pose == .work && $0.spot.point.x == dx && $0.spot.point.y == 84 }
            c.R(dx, 3, 1, 7, P.ink); c.B(dx - 3, 10, 7, 4, on ? P.lampOn : P.lampOff, P.ink)
            if on { for i in 0..<6 { c.R(dx - 4 - i * 2, 14 + i * 8, 9 + i * 4, 8, P.cone) } }
            c.R(dx - 11, 62, 2, 10, P.ink); c.R(dx + 9, 62, 2, 10, P.ink); c.B(dx - 12, 59, 24, 4, P.wood, P.ink); c.B(dx - 12, 62, 9, 6, P.wood2, P.ink)
            c.R(dx - 6, 56, 2, 3, P.ink); c.B(dx - 10, 46, 11, 10, on ? P.on : P.off, P.screen)
            if on { c.R(dx - 8, 48 + fr, 5, 1, P.code); c.R(dx - 8, 51 - fr, 3, 1, P.code); c.R(dx - 8, 53, 6, 1, P.off) }
        }
        // 시험대와 3색 신호등
        c.R(155, 62, 2, 10, P.ink); c.R(177, 62, 2, 10, P.ink); c.B(154, 59, 26, 4, P.metal, P.ink); c.R(155, 61, 24, 1, P.metal2)
        c.B(171, 35, 8, 24, P.tower, P.ink)
        let lit: [Bool] = switch st.lamp { case .run: [false, fr == 1, false]; case .ok: [false, false, true]; case .fail: [true, false, false]; case .off: [false, false, false] }
        for (i, col) in [P.red, P.amber, P.green].enumerated() { c.R(173, 38 + i * 7, 4, 4, lit[i] ? col : P.off) }
        // 검수 화면
        c.B(186, 38, 23, 17, P.off, P.screen); c.R(196, 55, 3, 3, P.ink); c.R(192, 58, 11, 1, P.ink)
        if st.boxes.contains(where: { $0.place == .ui }) {
            c.R(187, 39, 21, 15, P.on); c.R(188, 40, 19, 2, P.code); c.R(188, 44, 8, 9, P.amber); c.R(198, 44, 9, 4, P.boxD); c.R(198, 50, 9, 3, P.metal)
        }
        c.R(191, 62, 2, 10, P.ink); c.R(202, 62, 2, 10, P.ink); c.B(189, 59, 16, 4, P.wood, P.ink)
        // 화분
        c.B(223, 94, 9, 9, P.pot, P.ink); c.R(225, 86, 5, 8, P.leaf); c.R(222, 89, 4, 4, P.leaf); c.R(229, 88, 4, 5, P.leaf2); c.R(227, 83, 2, 4, P.leaf2)
        // 상자 번호는 그리지 않는다. 패널을 0.5배로 보이면 숫자가 화면 5pt라 읽히지 않는다. 번호는 상자를 고르면 지반 제목에 나온다.
        for b in st.boxes { let p = b.place.point; c.box(P, p.x, p.y, number: nil, done: b.phase == .done) }
        if st.stopSign { c.R(28, 62, 1, 10, P.ink); c.B(25, 55, 7, 7, P.red, P.ink); c.R(26, 58, 5, 1, P.white) }
        // 앞뒤 순서: 발 y가 작은 것부터. 같으면 넣은 순서(시안의 안정 정렬).
        enum Item { case actor(SceneActor), sofa, bell }
        var items: [(y: Int, i: Int, item: Item)] = st.actors.enumerated().map { ($0.element.spot.point.y, $0.offset, .actor($0.element)) }
        items.append((90, items.count, .sofa)); items.append((103, items.count, .bell))
        var bounds: [String: SpriteBounds] = [:]
        for it in items.sorted(by: { ($0.y, $0.i) < ($1.y, $1.i) }) {
            switch it.item {
            case .actor(let a):
                let p = a.spot.point
                bounds[a.id] = c.sprite(P, x: p.x, y: p.y, coat: a.coat, pose: a.pose, carry: a.carry, fr: fr)
            case .sofa:
                c.B(9, 84, 36, 10, P.sofa2, P.ink); c.B(9, 92, 36, 9, P.sofa, P.ink); c.B(6, 88, 6, 14, P.sofa2, P.ink); c.B(42, 88, 6, 14, P.sofa2, P.ink)
                c.R(10, 101, 2, 2, P.ink); c.R(42, 101, 2, 2, P.ink)
            case .bell: bell(&c, P, OfficeLayout.bellX, P.amber, 0)
            }
        }
        return bounds
    }

    static func drawOfficeFx(_ c: inout PixelCanvas, _ st: OfficeScene, _ P: Palette, _ fr: Int, _ bounds: [String: SpriteBounds]) {
        let bx = OfficeLayout.bellX
        if st.bell {
            c.B(bx + 3 + fr, 88, 8, 7, P.pink, P.ink); c.R(bx + 6 + fr, 86, 2, 2, P.ink)
            if fr == 1 { c.R(bx - 1, 87, 1, 3, P.pink); c.R(bx + 14, 87, 1, 3, P.pink); c.R(bx - 3, 85, 1, 2, P.pink); c.R(bx + 16, 85, 1, 2, P.pink) }
        }
        // 단위 막힘: 상자에 느낌표
        for b in st.boxes where b.blocked {
            let p = b.place.point, x = p.x + 7, y = p.y - 7 - fr
            c.B(x, y, 7, 9, P.pink, P.ink); c.text("!", x + 2, y + 2, P.ink)
        }
        for a in st.actors where (a.pose == .ask || a.pose == .error) && a.carry == nil {
            guard let s = bounds[a.id] else { continue }
            let x = s.bx + 1, y = s.top - fr
            c.B(x, y, 11, 9, P.pink, P.ink); c.R(x + 4, y + 9, 2, 1, P.ink); c.R(x + 4, y + 8, 1, 1, P.pink); c.text(a.pose == .ask ? "?" : "!", x + 4, y + 2, P.ink)
        }
        // 환경·한도: 시안에 사무실 쪽 그림이 없어 건물 층 등과 같은 모양을 문 위에 단다.
        if st.officeError {
            let y = 22 - fr
            c.B(10, y, 11, 13, P.pink, P.ink); c.text("!", 14, y + 4, P.ink)
        }
    }

    // MARK: 건물

    static func drawBuilding(_ c: inout PixelCanvas, _ st: BuildingScene, _ P: Palette, _ fr: Int) {
        let W = width, H = height
        c.R(0, 0, W, H, P.sky)
        if st.night { c.R(5, 14, 5, 5, P.sun); c.R(7, 14, 3, 3, P.sky); for p in [(11, 36), (4, 58), (9, 82), (229, 40), (233, 90)] { c.R(p.0, p.1, 1, 1, P.star) } }
        else { c.R(5, 14, 6, 6, P.sun); c.R(2, 44, 10, 2, P.cloud); c.R(4, 42, 5, 2, P.cloud); c.R(228, 60, 9, 2, P.cloud) }
        c.R(0, 102, W, 6, P.grass); c.R(0, 102, W, 1, P.ink)
        c.R(14, 4, 208, 4, P.bldg); c.R(18, 8, 200, 94, P.bldg)
        for x in stride(from: 18, to: 218, by: 7) { c.R(x, 5, 2, 1, P.hatch) }
        for (i, f) in st.floors.enumerated() {
            let y = BuildingLayout.floorY + i * BuildingLayout.floorH, n = f.agents.count
            c.R(20, y, 196, 21, P.walls[f.index % P.walls.count])
            for x in stride(from: 94, to: 212, by: 10) { c.R(x, y + 14, 1, 7, RGBA(35, 40, 69, 0.08)) }
            c.B(22, y + 2, 62, 11, P.card, P.ink)
            for k in 0..<min(f.total, BuildingLayout.cellsPerFloor) {   // 사무실의 상자와 같은 그림: 호박색은 대기·진행, 초록은 완료
                let dn = k < f.done
                c.B(23 + k * 6, y + 15, 5, 5, dn ? P.boxD : P.box, P.ink); c.R(24 + k * 6, y + 18, 3, 1, dn ? P.boxD2 : P.box2)
            }
            if n == 0 || (st.night && f.agents.allSatisfy { $0.pose == .sleep }) { c.R(20, y, 196, 21, P.dim) }
            for (k, a) in f.agents.prefix(BuildingLayout.agentsPerFloor).enumerated() {
                c.sprite(P, x: 104 + k * 22, y: y + 20, coat: a.coat, pose: a.pose, fr: fr, bare: true)
            }
        }
        // 시안에 없는 추가: 위나 아래에 층이 더 있으면 작은 화살표. 눈에 띄지 않게 해치 색으로 그린다.
        if st.moreAbove { c.R(118, 1, 1, 1, P.hatch); c.R(117, 2, 3, 1, P.hatch); c.R(116, 3, 5, 1, P.hatch) }
        if st.moreBelow { c.R(116, 104, 5, 1, P.ink); c.R(117, 105, 3, 1, P.ink); c.R(118, 106, 1, 1, P.ink) }
    }

    // MARK: 지반 아이콘

    /// 지반 왼쪽 동그란 칸과 목록에 넣는 16×16 그림. 낮 팔레트만 쓴다(시안과 같음).
    public static func icon(_ kind: GroundIcon) -> CGImage {
        let P = Palette.day
        var c = PixelCanvas(width: 16, height: 16)
        switch kind {
        case .face(let coat, let pose):
            let p: Pose = pose == .sleep ? .stopped : pose == .work ? .wait : pose
            c.sprite(P, x: 8, y: 21, coat: coat, pose: p, fr: 0, bare: true)
        case .bell:
            c.B(3, 4, 10, 8, P.amber, P.ink); c.R(7, 2, 2, 2, P.ink); c.R(2, 11, 12, 1, P.ink); c.R(7, 12, 2, 2, P.ink)
        case .stop:
            c.R(7, 11, 2, 4, P.ink); c.B(2, 1, 12, 11, P.red, P.ink); c.R(4, 6, 8, 1, P.white)
        case .box(let n, let d):
            c.B(2, 3, 12, 10, d ? P.boxD : P.box, P.ink); c.R(3, 11, 10, 1, d ? P.boxD2 : P.box2); c.digit(n, 6, 5, P.ink)
        case .building:
            c.B(3, 1, 10, 14, P.wall2, P.ink)
            for y in stride(from: 3, to: 11, by: 4) { c.R(5, y, 2, 2, P.ink); c.R(9, y, 2, 2, P.ink) }
            c.R(7, 11, 2, 3, P.ink)
        }
        return c.image()
    }
}
