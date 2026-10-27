import Foundation
import SwiftData
import ParlaCore

/// Los cuadernos y sus líneas, fuera del hilo principal.
@ModelActor
actor NotebookStore {

    func createNotebook(name: String, about: String) -> UUID {
        let notebook = Notebook(name: name, about: about)
        modelContext.insert(notebook)
        try? modelContext.save()
        return notebook.id
    }

    func updateNotebook(_ id: UUID, name: String, about: String) {
        guard let notebook = notebook(id) else { return }
        notebook.name = name
        notebook.about = about
        try? modelContext.save()
    }

    /// Sus líneas se van con él (`deleteRule: .cascade`).
    func deleteNotebook(_ id: UUID) {
        guard let notebook = notebook(id) else { return }
        modelContext.delete(notebook)
        try? modelContext.save()
    }

    func insertLine(id: UUID, english: String, sessionID: UUID, notebookID: UUID?, readAt: Date) {
        let line = NotebookLine(id: id, english: english, sessionID: sessionID, readAt: readAt,
                                notebook: notebookID.flatMap(notebook))
        modelContext.insert(line)
        try? modelContext.save()
    }

    /// `nil` deja la línea sin traducir. Guarda si `translation.save`.
    func apply(_ translation: LiveTranslation?, toLine id: UUID) {
        guard let line = line(id) else { return }
        guard let translation else {
            line.spanish = nil
            try? modelContext.save()
            return
        }
        fill(line, with: translation)
        line.isSaved = translation.save
        try? modelContext.save()
    }

    /// «Guardar» a mano: guarda aunque el modelo no la hubiera marcado.
    func save(line id: UUID, with translation: LiveTranslation) {
        guard let line = line(id) else { return }
        fill(line, with: translation)
        line.isSaved = true
        try? modelContext.save()
    }

    func unsave(line id: UUID) {
        guard let line = line(id) else { return }
        line.isSaved = false
        try? modelContext.save()
    }

    /// Con cuaderno, sus últimas 12 en cualquier sesión; sin él, las de la sesión.
    func context(notebookID: UUID?, sessionID: UUID) -> NotebookContext {
        var descriptor: FetchDescriptor<NotebookLine>
        if let notebookID {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.notebook?.id == notebookID },
                                         sortBy: [SortDescriptor(\.readAt, order: .reverse)])
        } else {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.sessionID == sessionID },
                                         sortBy: [SortDescriptor(\.readAt, order: .reverse)])
        }
        descriptor.fetchLimit = NotebookContext.lineLimit
        let recent = (try? modelContext.fetch(descriptor)) ?? []
        return NotebookContext(about: notebookID.flatMap(notebook)?.about ?? "",
                               recentLines: recent.reversed().map(\.english))
    }

    /// La línea de antes y la de después en la misma sesión.
    func neighbors(ofLine id: UUID) -> (before: String?, after: String?) {
        guard let line = line(id) else { return (nil, nil) }
        let sessionID = line.sessionID
        let session = (try? modelContext.fetch(FetchDescriptor<NotebookLine>(
            predicate: #Predicate { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.readAt)]))) ?? []
        guard let index = session.firstIndex(where: { $0.id == id }) else { return (nil, nil) }
        return (index > 0 ? session[index - 1].english : nil,
                index + 1 < session.count ? session[index + 1].english : nil)
    }

    // MARK: - Ayudantes

    private func fill(_ line: NotebookLine, with translation: LiveTranslation) {
        line.spanish = translation.spanish
        for old in line.expressions { modelContext.delete(old) }
        line.expressions = translation.expressions.map {
            StoredExpression(phrase: $0.phrase, meaning: $0.meaning)
        }
    }

    private func notebook(_ id: UUID) -> Notebook? {
        try? modelContext.fetch(FetchDescriptor<Notebook>(predicate: #Predicate { $0.id == id }))
            .first
    }

    private func line(_ id: UUID) -> NotebookLine? {
        try? modelContext.fetch(FetchDescriptor<NotebookLine>(predicate: #Predicate { $0.id == id }))
            .first
    }
}
