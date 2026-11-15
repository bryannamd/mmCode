import CoreText
import Foundation

public enum Fonts {
    /// Jua의 PostScript 이름.
    public static let jua = "Jua-Regular"

    /// 묶음 안의 Jua를 이 프로세스에 등록한다. 이미 등록돼 있어도 성공이다.
    @discardableResult
    public static func register() -> Bool {
        guard let url = Bundle.module.url(forResource: "Jua-Regular", withExtension: "ttf") else { return false }
        var err: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &err) { return true }
        // kCTFontManagerErrorAlreadyRegistered(105)는 두 번째 호출에서 난다.
        return err.map { CFErrorGetCode($0.takeRetainedValue()) == 105 } ?? false
    }
}
