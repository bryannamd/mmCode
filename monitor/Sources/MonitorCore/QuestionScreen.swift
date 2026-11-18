import Foundation

/// Claude Code 객관식 질문(AskUserQuestion) 화면에서 읽은 질문과 선택지.
public struct ScreenQuestion: Equatable, Sendable {
    public struct Option: Equatable, Sendable {
        /// 화면의 번호. `hc keys <주소> <번호>`로 고른다.
        public var number: Int
        public var label: String
        public init(number: Int, label: String) { self.number = number; self.label = label }
    }
    public var text: String
    public var options: [Option]
    public init(text: String, options: [Option]) { self.text = text; self.options = options }
}

/// `hc read --lines 0 <주소>`의 화면 글자를 해석한다(순수 함수).
/// ponytail: 질문 탭 여러 개와 multiSelect는 따로 다루지 않는다. 숫자를 누르면 다음 화면이 뜨고 다음 갱신에서 다시 읽는다.
public enum QuestionScreen {
    /// 직접 적기와 대화 전환은 버튼으로 두지 않는다.
    static let skipped: Set<String> = ["Type something.", "Chat about this"]

    public static func parse(_ screen: String) -> ScreenQuestion? {
        let lines = screen.components(separatedBy: "\n")
        // 화면에 앞선 번호 목록이 있을 수 있다. 그래서 마지막 "1." 줄부터 읽는다.
        guard let start = lines.indices.last(where: { option(lines[$0])?.number == 1 }) else { return nil }
        var options: [ScreenQuestion.Option] = []
        var next = 1
        for line in lines[start...] {
            if isRule(line) { break }
            guard let o = option(line) else { continue }  // 선택지 아래 설명 줄
            guard o.number == next else { break }
            next += 1
            if !skipped.contains(o.label) { options.append(o) }
        }
        let text = lines[..<start].reversed().lazy.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !isRule($0) && !$0.hasPrefix("☐") && !$0.hasPrefix("☒") && !$0.hasPrefix("✔") }
        guard let text, !options.isEmpty else { return nil }
        return ScreenQuestion(text: text, options: options)
    }

    /// `❯ 1. 김밥` 또는 `  2. 라면`.
    static func option(_ line: String) -> ScreenQuestion.Option? {
        var s = Substring(line).drop { $0 == " " }
        if s.hasPrefix("❯") { s = s.dropFirst().drop { $0 == " " } }
        let digits = s.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, let n = Int(digits) else { return nil }
        let rest = s.dropFirst(digits.count)
        guard rest.hasPrefix(". ") else { return nil }
        let label = rest.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return label.isEmpty ? nil : .init(number: n, label: label)
    }

    /// 구분선(`────`).
    static func isRule(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.count >= 3 && t.allSatisfy { "─━-".contains($0) }
    }
}
