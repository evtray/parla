import Testing
import Foundation
@testable import ParlaCore

@Test func decodesTheShapeClaudeReturns() throws {
    let json = """
    {"english":"I need you to let me know when you get in.",
     "why":["\\"avisar\\" aquí es \\"let me know\\", no \\"advise\\".",
            "Tras \\"when\\" el inglés usa presente, no futuro."],
     "vocab":[{"term":"let me know","meaning":"avisar, hacer saber"}],
     "skip":false}
    """
    let card = try JSONDecoder().decode(Card.self, from: Data(json.utf8))

    #expect(card.english == "I need you to let me know when you get in.")
    #expect(card.why.count == 2)
    #expect(card.vocab.first?.term == "let me know")
    #expect(card.skip == false)
}

@Test func decodesASkippedCard() throws {
    let json = #"{"english":"","why":[],"vocab":[],"skip":true}"#
    let card = try JSONDecoder().decode(Card.self, from: Data(json.utf8))
    #expect(card.skip == true)
}
