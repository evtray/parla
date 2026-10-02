import Foundation

/// Ejecuta operaciones asíncronas de una en una, en el orden en que llegan.
///
/// Un `actor` solo no basta: es reentrante, y mientras una operación espera
/// otra puede empezar. Aquí cada operación espera a que termine la anterior.
public actor SerialGate {
    private var tail: Task<Void, Never>?

    public init() {}

    public func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T)
        async throws -> T {
        let previous = tail
        let task = Task { () async throws -> T in
            _ = await previous?.value
            return try await operation()
        }
        // La cola sigue aunque esta operación falle.
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
}
