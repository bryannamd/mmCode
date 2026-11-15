// 캐릭터 그림. 시안의 CAT, DOG, FROG, put, COAT, sprite, glyph, box, digit, text를 값 그대로 옮긴다.
// 머리 그림 글자: o 외곽선, b 털, s 줄무늬와 점, a·k 얼룩, e 늘어진 귀, w 흰 털, p 귀 안쪽과 볼, n 코와 입

struct CoatStyle {
    var head: [String]
    var col: [Character: RGBA]
    var torso, arm, leg: RGBA
    var eye: RGBA?
    var eyeRow: Int?
    var eyeX: (Int, Int)?
}

private func put(_ rows: [String], _ edits: [(Int, Int, Character)]) -> [String] {
    var g = rows.map { Array($0) }
    for e in edits { g[e.0][e.1] = e.2 }
    return g.map { String($0) }
}

private let CAT = ["oo........oo", "obo......obo", "obboooooobbo", "obbbbbbbbbbo", "obbbbbbbbbbo", "obbbbbbbbbbo", "obbbbbbbbbbo", "obbbbbbbbbbo", "obpbbwwbbpbo", ".obbbwwbbbo.", "..oooooooo.."]
private let DOG = ["..oooooooo..", ".oebbbbbbeo.", "oeebbbbbbeeo", "oeebbbbbbeeo", "oeebbbbbbeeo", "oeebbbbbbeeo", "oeebbbbbbeeo", "oeebwwwwbeeo", "oeeownnwoeeo", ".oo.owwo.oo.", "....oooo...."]
private let FROG = [".ooo....ooo.", "owwwo..owwwo", "owwwoooowwwo", "obbbbbbbbbbo", "obbbbbbbbbbo", "obnbbbbbbnbo", "obbnnnnnnbbo", "obbbbbbbbbbo", ".obbbbbbbbo.", "..oooooooo.."]
private let EARS: [(Int, Int, Character)] = [(1, 1, "p"), (1, 10, "p")]
private let catPink = RGBA("#ff9db0")

let COATS: [Coat: CoatStyle] = [
    .tuxedo: CoatStyle(head: put(CAT, EARS + [(5, 5, "w"), (5, 6, "w"), (6, 5, "w"), (6, 6, "w"), (7, 4, "w"), (7, 5, "w"), (7, 6, "w"), (7, 7, "w"), (8, 2, "b"), (8, 9, "b"), (8, 3, "w"), (8, 4, "w"), (8, 7, "w"), (8, 8, "w"), (9, 3, "w"), (9, 4, "w"), (9, 7, "w"), (9, 8, "w")]),
                       col: ["b": RGBA("#454a6e"), "w": RGBA("#ffffff"), "p": catPink], torso: RGBA("#ffffff"), arm: RGBA("#ffffff"), leg: RGBA("#ffffff"), eye: RGBA("#ffe27a")),
    .calico: CoatStyle(head: put(CAT, [(1, 1, "a"), (2, 1, "a"), (2, 2, "a"), (3, 1, "a"), (3, 2, "a"), (3, 3, "a"), (3, 4, "a"), (4, 1, "a"), (4, 2, "a"), (4, 3, "a"), (5, 1, "a"), (5, 2, "a"), (1, 10, "k"), (2, 9, "k"), (2, 10, "k"), (3, 7, "k"), (3, 8, "k"), (3, 9, "k"), (3, 10, "k"), (4, 8, "k"), (4, 9, "k"), (4, 10, "k"), (5, 9, "k"), (5, 10, "k"), (6, 10, "k")]),
                       col: ["b": RGBA("#fffaf0"), "a": RGBA("#f79a3e"), "k": RGBA("#454a6e"), "w": RGBA("#ffffff"), "p": catPink], torso: RGBA("#fffaf0"), arm: RGBA("#f79a3e"), leg: RGBA("#454a6e")),
    .tabby: CoatStyle(head: put(CAT, EARS + [(3, 3, "s"), (3, 5, "s"), (3, 6, "s"), (3, 8, "s"), (4, 5, "s"), (4, 6, "s"), (6, 1, "s"), (6, 10, "s")]),
                      col: ["b": RGBA("#f79a3e"), "s": RGBA("#c9661a"), "w": RGBA("#ffffff"), "p": catPink], torso: RGBA("#f79a3e"), arm: RGBA("#f79a3e"), leg: RGBA("#cf6f1c")),
    .white: CoatStyle(head: put(CAT, EARS), col: ["b": RGBA("#ffffff"), "w": RGBA("#ffffff"), "p": catPink], torso: RGBA("#ffffff"), arm: RGBA("#ffffff"), leg: RGBA("#d9dbe6")),
    .catGray: CoatStyle(head: put(CAT, EARS), col: ["b": RGBA("#9aa3bd"), "w": RGBA("#ffffff"), "p": catPink], torso: RGBA("#9aa3bd"), arm: RGBA("#9aa3bd"), leg: RGBA("#7a84a3")),
    .beagle: CoatStyle(head: put(DOG, [(1, 5, "w"), (1, 6, "w"), (2, 5, "w"), (2, 6, "w"), (3, 5, "w"), (3, 6, "w"), (4, 5, "w"), (4, 6, "w"), (5, 5, "w"), (5, 6, "w"), (6, 5, "w"), (6, 6, "w"), (6, 4, "w"), (6, 7, "w")]),
                       col: ["b": RGBA("#c08552"), "e": RGBA("#7a4a26"), "w": RGBA("#ffffff")], torso: RGBA("#ffffff"), arm: RGBA("#c08552"), leg: RGBA("#ffffff"), eyeRow: 4, eyeX: (4, 7)),
    .dogSpot: CoatStyle(head: put(DOG, [(3, 3, "s"), (3, 4, "s"), (3, 5, "s"), (4, 3, "s"), (4, 4, "s"), (4, 5, "s"), (5, 3, "s"), (5, 4, "s"), (5, 5, "s"), (6, 3, "s"), (6, 4, "s"), (6, 5, "s")]),
                        col: ["b": RGBA("#ffffff"), "e": RGBA("#59618a"), "s": RGBA("#8089ad"), "w": RGBA("#ffffff")], torso: RGBA("#ffffff"), arm: RGBA("#ffffff"), leg: RGBA("#d9dbe6"), eyeRow: 4, eyeX: (4, 7)),
    // 개구리의 초록은 완료 초록(#3fc46f)과 겹치지 않게 짙은 청록으로 쓴다.
    .frog: CoatStyle(head: FROG, col: ["b": RGBA("#1f8a7a"), "w": RGBA("#ffffff")], torso: RGBA("#cdeee0"), arm: RGBA("#1f8a7a"), leg: RGBA("#176b60"), eyeRow: 1, eyeX: (2, 9)),
    .frogSpot: CoatStyle(head: put(FROG, [(3, 4, "s"), (4, 7, "s"), (4, 8, "s"), (7, 3, "s"), (7, 7, "s"), (3, 9, "s")]),
                         col: ["b": RGBA("#1f8a7a"), "s": RGBA("#0b3d36"), "w": RGBA("#ffffff")], torso: RGBA("#cdeee0"), arm: RGBA("#1f8a7a"), leg: RGBA("#176b60"), eyeRow: 1, eyeX: (2, 9)),
]

private let DIGIT: [[String]] = [
    ["01110", "10001", "10001", "10001", "01110"], ["00100", "01100", "00100", "00100", "01110"], ["11110", "00001", "01110", "10000", "11111"], ["11110", "00001", "01110", "00001", "11110"],
    ["10010", "10010", "11111", "00010", "00010"], ["11111", "10000", "11110", "00001", "11110"], ["01111", "10000", "11110", "10001", "01110"], ["11111", "00001", "00010", "00100", "00100"],
    ["01110", "10001", "01110", "10001", "01110"], ["01110", "10001", "01111", "00001", "11110"],
]
private let FONT: [Character: [String]] = ["?": ["110", "001", "010", "000", "010"], "!": ["010", "010", "010", "000", "010"]]

/// 캐릭터가 차지한 영역. 클릭 영역과 주의 표시 자리에 쓴다.
public struct SpriteBounds: Equatable, Sendable {
    public var bx, by, bh, top: Int
}

extension PixelCanvas {
    /// 시안과 같이 마지막 숫자 하나만 그린다. 단위가 10개를 넘으면 상자를 넓혀야 한다.
    mutating func digit(_ n: Int?, _ x: Int, _ y: Int, _ col: RGBA) {
        guard let n else { return }
        let g = DIGIT[abs(n) % 10]
        for r in 0..<5 { for (k, ch) in g[r].enumerated() where ch == "1" { R(x + k, y + r, 1, 1, col) } }
    }

    mutating func text(_ s: String, _ x0: Int, _ y: Int, _ col: RGBA) {
        var x = x0
        for ch in s {
            if let g = FONT[ch] { for r in 0..<5 { for (k, b) in g[r].enumerated() where b == "1" { R(x + k, y + r, 1, 1, col) } } }
            x += 4
        }
    }

    mutating func box(_ P: Palette, _ x: Int, _ y: Int, number: Int?, done d: Bool) {
        B(x, y - 1, 11, 9, d ? P.boxD : P.box, P.ink); R(x + 1, y + 6, 9, 1, d ? P.boxD2 : P.box2)
        digit(number, x + 3, y + 1, P.ink)   // 숫자만 그린다. 외곽선과 위 1px, 좌우 2px 을 띄운다
    }

    /// 머리 위 작은 상태 표시. 주의 표시(ask, error)는 여기서 그리지 않는다. 위층에서 그린다.
    mutating func glyph(_ P: Palette, _ kind: Pose, _ x: Int, _ y: Int, _ fr: Int) {
        if kind == .sleep {
            let o = fr
            R(x + 2, y + 3 - o, 4, 1, P.paper); R(x + 4, y + 4 - o, 1, 1, P.paper); R(x + 3, y + 5 - o, 1, 1, P.paper); R(x + 2, y + 6 - o, 4, 1, P.paper)
            R(x + 7, y - o, 3, 1, P.paper); R(x + 8, y + 1 - o, 1, 1, P.paper); R(x + 7, y + 2 - o, 3, 1, P.paper)
            return
        }
        B(x, y, 9, 8, P.paper, P.ink); R(x + 3, y + 8, 2, 1, P.ink); R(x + 3, y + 7, 1, 1, P.paper)
        if kind == .stopped { R(x + 3, y + 2, 1, 4, P.ink); R(x + 5, y + 2, 1, 4, P.ink) }
        else if kind == .done { R(x + 2, y + 4, 1, 1, P.boxD2); R(x + 3, y + 5, 1, 1, P.boxD2); R(x + 4, y + 4, 1, 1, P.boxD2); R(x + 5, y + 3, 1, 1, P.boxD2); R(x + 6, y + 2, 1, 1, P.boxD2) }
    }

    /// 발 가운데가 (ax, ay)다. bare면 머리 위 표시와 그림자를 뺀다.
    @discardableResult
    mutating func sprite(_ P: Palette, x ax: Int, y ay: Int, coat: Coat, pose st: Pose, carry: SceneBox? = nil, fr: Int, bare: Bool = false) -> SpriteBounds {
        let s = COATS[coat]!, hd = s.head, x = ax - 6
        let bob = st == .work && fr == 1 ? 1 : 0, sit = st == .sleep ? 2 : 0
        let feet = ay, tt = feet - 5 + sit, ht = tt - hd.count + bob
        if sit == 0 && !bare { R(x + 1, feet, 10, 1, P.shadow) }
        var col = s.col; col["o"] = col["o"] ?? P.ink; col["n"] = col["n"] ?? P.ink
        let eye = s.eye ?? P.ink
        if sit == 0 { B(x + 2, feet - 3, 4, 3, s.leg, P.ink); B(x + 6, feet - 3, 4, 3, s.leg, P.ink) }
        B(x + 2, tt, 8, 4, s.torso, P.ink)
        func arm(_ side: Int, _ top: Int, _ len: Int) { B(side == 1 ? x + 9 : x, top, 3, len + 1, s.arm, P.ink) }
        let raised = carry == nil && (st == .ask || st == .error)
        if carry != nil { arm(0, tt - 3, 5); arm(1, tt - 3, 5) }
        else if raised { arm(1, tt, 3) }   // 손든 왼팔은 머리를 그린 뒤에 그린다
        else if st == .work { arm(0, tt + (fr == 1 ? 0 : 1), 2); arm(1, tt + (fr == 1 ? 1 : 0), 2) }
        else { arm(0, tt, 3); arm(1, tt, 3) }
        map(hd, x, ht, col)
        // 손든 팔: 벨의 반대쪽(왼쪽) 볼 옆에 짧은 앞발을 올린다. 2프레임으로 흔든다.
        if raised { let up = fr == 1 ? 5 : 4; B(x - 2, tt - up, 4, up + 3, s.arm, P.ink) }
        let er = ht + (s.eyeRow ?? hd.count - 5), eL = x + (s.eyeX?.0 ?? 3), eR = x + (s.eyeX?.1 ?? 8)
        switch st {
        case .sleep, .stopped: R(eL - 1, er + 1, 2, 1, eye); R(eR, er + 1, 2, 1, eye)
        case .done:
            R(eL - 1, er + 1, 1, 1, eye); R(eL, er, 1, 1, eye); R(eL + 1, er + 1, 1, 1, eye)
            R(eR - 1, er + 1, 1, 1, eye); R(eR, er, 1, 1, eye); R(eR + 1, er + 1, 1, 1, eye)
        case .error:
            R(eL - 1, er, 1, 1, eye); R(eL, er + 1, 1, 1, eye); R(eL - 1, er + 2, 1, 1, eye)
            R(eR + 1, er, 1, 1, eye); R(eR, er + 1, 1, 1, eye); R(eR + 1, er + 2, 1, 1, eye)
        default: R(eL, er, 1, 2, eye); R(eR, er, 1, 2, eye)
        }
        var b = SpriteBounds(bx: x, by: ht, bh: feet - ht + 1, top: ht - 10)
        if let c = carry {
            box(P, x, ht - 9, number: c.number, done: c.phase == .done); b.by = ht - 10; b.bh = feet - ht + 11
        } else if !bare, [.sleep, .stopped, .done].contains(st) {
            glyph(P, st, x + (st == .sleep ? 6 : 2), ht - 10, fr)
        }
        return b
    }
}

/// 그리지 않고 영역만 계산한다. SceneBuilder가 클릭 영역을 만들 때 쓴다(프레임 0 기준).
public func spriteBounds(x: Int, y: Int, coat: Coat, pose: Pose, carrying: Bool = false) -> SpriteBounds {
    let hd = COATS[coat]!.head.count, x0 = x - 6, sit = pose == .sleep ? 2 : 0
    let tt = y - 5 + sit, ht = tt - hd
    return carrying ? SpriteBounds(bx: x0, by: ht - 10, bh: y - ht + 11, top: ht - 10)
                    : SpriteBounds(bx: x0, by: ht, bh: y - ht + 1, top: ht - 10)
}
