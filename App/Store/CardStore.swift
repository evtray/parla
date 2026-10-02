import Foundation
import SwiftData
import ParlaCore

/// Escribe fuera del hilo principal para que guardar no congele el panel.
@ModelActor
actor CardStore {
    func save(utterance: Utterance, card: Card) {
        modelContext.insert(StoredCard(utterance: utterance, card: card))
        try? modelContext.save()
    }

    /// Reemplaza si ya hay una fila con ese `id`: es lo que hace «¿No era
    /// eso?». Un `skip` no se guarda, porque no hay nada que repasar.
    func save(capture: Capture, card: CaptureCard) {
        guard card.kind != .skip else { return }
        let id = capture.id
        let existing = (try? modelContext.fetch(
            FetchDescriptor<StoredCard>(predicate: #Predicate { $0.id == id }))) ?? []
        for old in existing { modelContext.delete(old) }
        modelContext.insert(StoredCard(capture: capture, card: card))
        try? modelContext.save()
    }

    func save(subtitle: SubtitleLine) {
        modelContext.insert(StoredCard(subtitle: subtitle))
        try? modelContext.save()
    }
}
