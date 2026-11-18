// 작은 명단 사진에서도 종, 눈, 표정이 읽히도록 장면 스프라이트와 별도로 그린 정면 초상.
// 털색은 사무실과 같은 COATS 표를 사용한다.
import CoreGraphics

extension SceneRenderer {
    public static func portrait(_ coat: Coat, pose: Pose) -> CGImage {
        let fur = COATS[coat]!
        let ink = RGBA("#303c36")
        let cream = RGBA("#fff8e8")
        let blush = RGBA("#eea58e")
        let body = fur.col["b"] ?? cream
        let dog = coat == .beagle || coat == .dogSpot
        let frog = coat == .frog || coat == .frogSpot
        var c = PixelCanvas(width: 26, height: 22)
        let catHead = [
            "....##............##....",
            "...#bb##........##bb#...",
            "...#bppb########bppb#...",
            "...#bppbbbbbbbbbbppb#...",
            "...#bbbbbbbbbbbbbbbb#...",
            "..#bbbbbbbbbbbbbbbbbb#..",
            ".#bbbbbbbbbbbbbbbbbbbb#.",
            ".#bbbbbbbbbbbbbbbbbbbb#.",
            ".#bbbbbbbbbbbbbbbbbbbb#.",
            ".#bbbbbbbbbbbbbbbbbbbb#.",
            ".#bbbbbbbbbbbbbbbbbbbb#.",
            ".#bbbbbbbbbbbbbbbbbbbb#.",
            "..#bbbbbbbbbbbbbbbbbb#..",
            "...#bbbbbbbbbbbbbbbb#...",
            "....##bbbbbbbbbbbb##....",
            "......############......"
        ]
        let dogHead = [
            "......############......",
            "....##ebbbbbbbbbbe##....",
            "...#eeebbbbbbbbbbeee#...",
            "..#eeebbbbbbbbbbbbeee#..",
            ".#eeeebbbbbbbbbbbbeeee#.",
            "#eeee#bbbbbbbbbbbb#eeee#",
            "#eeee#bbbbbbbbbbbb#eeee#",
            "#eeee#bbbbbbbbbbbb#eeee#",
            "#eeee#bbbbbbbbbbbb#eeee#",
            "#eeee#bbbbbbbbbbbb#eeee#",
            ".#eee#bbbbbbbbbbbb#eee#.",
            "..###bbbbbbbbbbbbbb###..",
            "....#bbbbbbbbbbbbbb#....",
            ".....##bbbbbbbbbb##.....",
            ".......##########......."
        ]
        let frogHead = [
            "....####........####....",
            "...#wwww#......#wwww#...",
            "..#wwwwww######wwwwww#..",
            "..#wwwwwwbbbbbbwwwwww#..",
            "..#wwwwwwbbbbbbwwwwww#..",
            "..#bbbbbbbbbbbbbbbbbb#..",
            ".#bbbbbbbbbbbbbbbbbbbb#.",
            ".#bbbbbbbbbbbbbbbbbbbb#.",
            "#bbbbbbbbbbbbbbbbbbbbbb#",
            "#bbbbbbbbbbbbbbbbbbbbbb#",
            ".#bbbbbbbbbbbbbbbbbbbb#.",
            "..#bbbbbbbbbbbbbbbbbb#..",
            "...##bbbbbbbbbbbbbb##...",
            ".....##############....."
        ]
        let y = frog ? 4 : dog ? 3 : 2
        let colors: [Character: RGBA] = ["#": ink, "b": body, "p": blush, "w": cream, "e": fur.col["e"] ?? ink]
        c.map(frog ? frogHead : dog ? dogHead : catHead, 1, y, colors)
        if coat == .tabby {
            for (x, h) in [(9, 2), (12, 3), (15, 2)] { c.R(x, y + 3, 2, h, fur.col["s"]!) }
        } else if coat == .calico || coat == .dogSpot {
            let patch = fur.col["a"] ?? fur.col["s"]!
            c.R(7, y + 3, 5, 3, patch)
            c.R(7, y + 6, 3, 2, patch)
        } else if coat == .frogSpot {
            c.R(11, y + 5, 4, 2, fur.col["s"]!)
        }
        if !frog {
            c.R(10, y + 10, 6, 4, cream)
            c.R(8, y + 11, 10, 2, cream)
            c.R(12, y + 10, 2, 1, ink)
            c.R(13, y + 11, 1, 1, ink)
        } else {
            c.R(9, y + 10, 8, 1, ink)
            c.R(8, y + 9, 1, 1, ink)
            c.R(17, y + 9, 1, 1, ink)
        }
        let eyeY = y + (frog ? 2 : 7)
        let eyeColor = coat == .tuxedo ? RGBA("#fce08b") : ink
        for eye in (frog ? [6, 18] : [8, 16]) {
            if pose == .sleep || pose == .stopped {
                c.R(eye - 1, eyeY + 1, 3, 1, eyeColor)
            } else {
                c.R(eye - 1, eyeY, 3, 3, eyeColor)
                c.R(eye - 1, eyeY, 1, 1, cream)
            }
        }
        let cheekY = y + (frog ? 8 : 10)
        c.R(dog ? 7 : 4, cheekY, 2, 1, blush)
        c.R(dog ? 17 : 20, cheekY, 2, 1, blush)
        return c.image()
    }
}
