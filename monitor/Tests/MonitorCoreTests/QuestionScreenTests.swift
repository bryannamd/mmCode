import Foundation
import Testing
@testable import MonitorCore

@Test func parsesQuestionScreen() throws {
    let url = try #require(Bundle.module.url(forResource: "question-screen", withExtension: "txt", subdirectory: "Fixtures"))
    let q = try #require(QuestionScreen.parse(try String(contentsOf: url, encoding: .utf8)))
    #expect(q.text == "점심 메뉴는?")
    #expect(q.options.map(\.number) == [1, 2, 3])  // Type something.·Chat about this는 뺀다
    #expect(q.options.map(\.label) == ["김밥", "라면", "국수"])
}

@Test func plainScreenHasNoQuestion() {
    #expect(QuestionScreen.parse("$ ls\nREADME.md\n") == nil)
    #expect(QuestionScreen.parse("질문\n  1. Type something.\n") == nil)
}
