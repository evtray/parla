import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    private(set) var isListening = false

    func toggleListening() {
        isListening.toggle()
    }
}
