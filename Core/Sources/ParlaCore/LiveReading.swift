import Foundation

/// Una expresión que vale la pena estudiar, con cuándo se usa.
public struct LiveExpression: Codable, Sendable, Equatable {
    public let phrase: String
    public let meaning: String

    public init(phrase: String, meaning: String) {
        self.phrase = phrase
        self.meaning = meaning
    }
}

/// La traducción de una línea leída en vivo.
public struct LiveTranslation: Codable, Sendable, Equatable {
    public let spanish: String
    /// El modelo cree que la línea trae algo que estudiar y va al cuaderno.
    public let save: Bool
    public let expressions: [LiveExpression]

    public init(spanish: String, save: Bool, expressions: [LiveExpression]) {
        self.spanish = spanish
        self.save = save
        self.expressions = expressions
    }
}

/// Lo que el modelo sabe antes de traducir: de qué trata el cuaderno y lo que
/// se leyó justo antes. Sin eso, «hold it» no se puede traducir bien.
public struct NotebookContext: Sendable, Equatable {
    public static let lineLimit = 12

    public let about: String
    /// En inglés, de la más vieja a la más nueva.
    public let recentLines: [String]

    /// Se queda con las últimas `lineLimit`.
    public init(about: String, recentLines: [String]) {
        self.about = about
        self.recentLines = Array(recentLines.suffix(Self.lineLimit))
    }

    public var promptText: String {
        var blocks: [String] = []
        let about = about.trimmingCharacters(in: .whitespacesAndNewlines)
        if !about.isEmpty { blocks.append("De qué trata: \(about)") }
        if !recentLines.isEmpty {
            blocks.append("Líneas anteriores:\n" + Self.numbered(recentLines))
        }
        return blocks.joined(separator: "\n\n")
    }

    static func numbered(_ lines: [String]) -> String {
        lines.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }
}

public protocol LiveReadingTranslator: Sendable {
    /// Una entrada por línea pedida, en el mismo orden; `nil` = sin traducir.
    func translate(_ lines: [String], context: NotebookContext) async throws -> [LiveTranslation?]
    func explain(_ line: String, context: NotebookContext) async throws -> LiveTranslation?
}

/// Coincide con el esquema de `makeLiveReadingRequest`.
struct LiveReadingResponse: Decodable {
    let lines: [LiveTranslation]
}

extension LiveTranslation {
    /// Sin español no hay traducción; las expresiones a medias se descartan.
    var cleaned: LiveTranslation? {
        let spanish = spanish.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spanish.isEmpty else { return nil }
        let expressions = expressions.filter {
            !$0.phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return LiveTranslation(spanish: spanish, save: save, expressions: expressions)
    }
}
