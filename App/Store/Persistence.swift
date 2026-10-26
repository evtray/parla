import Foundation
import SwiftData

/// Contenedor único de la app.
///
/// Vive aquí y no colgado de una vista: cuando `AppState.store` se asignaba
/// desde un `.task` del menú de la barra, quedaba en `nil` y `store?.save(...)`
/// se convertía en un no-op silencioso — la tarjeta se pintaba y se perdía.
enum Persistence {
    static let container: ModelContainer = {
        do {
            return try makeContainer()
        } catch {
            fatalError("No se pudo abrir la base de datos local: \(error)")
        }
    }()

    /// La única forma de abrir la base. Los tests de migración pasan por aquí
    /// para probar el mismo camino que la app.
    static func makeContainer(_ configuration: ModelConfiguration = ModelConfiguration())
        throws -> ModelContainer {
        try ModelContainer(for: StoredCard.self, configurations: configuration)
    }
}
