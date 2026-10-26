import Testing
import Foundation
@testable import ParlaCore

/// Cuenta cuántas operaciones hay dentro a la vez.
private actor Occupancy {
    private var inside = 0
    private(set) var peak = 0
    func enter() { inside += 1; peak = max(peak, inside) }
    func leave() { inside -= 1 }
}

@Test func nuncaHayDosOperacionesALaVez() async throws {
    let gate = SerialGate()
    let occupancy = Occupancy()
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0 ..< 10 {
            group.addTask {
                try await gate.run {
                    await occupancy.enter()
                    try await Task.sleep(for: .milliseconds(5))
                    await occupancy.leave()
                }
            }
        }
        try await group.waitForAll()
    }
    #expect(await occupancy.peak == 1)
}

@Test func devuelveElResultadoYPropagaElError() async throws {
    struct Boom: Error {}
    let gate = SerialGate()
    #expect(try await gate.run { 42 } == 42)
    await #expect(throws: Boom.self) { try await gate.run { throw Boom() } }
    // Un error no atasca la puerta para los siguientes.
    #expect(try await gate.run { "sigue" } == "sigue")
}
