import Testing
@testable import Parla

@Test @MainActor func estudioAbreEnElHistorial() {
    #expect(StudioRouter().section == .history)
}

@Test @MainActor func abrirEnAjustesCambiaLaSeccion() {
    let router = StudioRouter()
    router.open(.settings)
    #expect(router.section == .settings)
}

@Test @MainActor func reabrirSinSeccionNoTeMueve() {
    let router = StudioRouter()
    router.open(.settings)
    router.open(nil)
    #expect(router.section == .settings)
}

@Test @MainActor func abrirCuadernosCambiaLaSeccion() {
    let router = StudioRouter()
    router.open(.notebooks)
    #expect(router.section == .notebooks)
    #expect(StudioSection.notebooks.title == "Cuadernos")
    #expect(StudioSection.notebooks.symbol == "books.vertical")
}
