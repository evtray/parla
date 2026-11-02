import Foundation
import SwiftData

/// Un cuaderno de la lectura en vivo: un juego, un curso, una serie. Su «De
/// qué trata» y sus líneas son el contexto con el que se traduce.
@Model
final class Notebook {
    var id: UUID
    var name: String
    var about: String = ""
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \NotebookLine.notebook)
    var lines: [NotebookLine] = []

    init(id: UUID = UUID(), name: String, about: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.about = about
        self.createdAt = createdAt
    }
}

/// Cada línea leída se guarda, traducida o no: sirve de contexto y de
/// «antes» y «después» de las que se guardan para estudiar.
@Model
final class NotebookLine {
    var id: UUID
    var english: String
    /// `nil` = sin traducir.
    var spanish: String?
    var sessionID: UUID
    var readAt: Date
    /// `nil` = «Sin cuaderno».
    var notebook: Notebook?
    /// Va a la lista de estudio del cuaderno.
    var isSaved: Bool = false
    @Relationship(deleteRule: .cascade) var expressions: [StoredExpression] = []

    init(id: UUID, english: String, sessionID: UUID, readAt: Date, notebook: Notebook?) {
        self.id = id
        self.english = english
        self.sessionID = sessionID
        self.readAt = readAt
        self.notebook = notebook
    }
}

@Model
final class StoredExpression {
    var phrase: String
    var meaning: String

    init(phrase: String, meaning: String) {
        self.phrase = phrase
        self.meaning = meaning
    }
}
