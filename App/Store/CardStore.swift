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
}
