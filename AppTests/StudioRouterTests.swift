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
