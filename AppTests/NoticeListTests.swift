import Testing
import ParlaCore
@testable import Parla

private let key = SetupIssue(item: .apiKey, fix: .enterAPIKey)
private let screen = SetupIssue(item: .screenRecording, fix: .requestScreenRecording)
private let languages = SetupIssue(item: .languages, fix: .openLanguageSettings)

@Test func losErroresDeLaSesionVanAntesQueLosPendientes() {
    let list = NoticeList(runtime: [.capture("No se pudo leer la captura.")], issues: [key])
    #expect(list.visible == [.runtime(.capture("No se pudo leer la captura.")), .setup(key)])
    #expect(list.hiddenCount == 0)
}

@Test func loQueImpideArrancarSubeArriba() {
    let list = NoticeList(runtime: [.setup("El audio del sistema se cortó.")],
                          issues: [key, screen, languages],
                          priority: [languages])
    #expect(list.visible == [.setup(languages), .runtime(.setup("El audio del sistema se cortó."))])
    #expect(list.hiddenCount == 2)
}

@Test func comoMuchoSeVenDosYElRestoSeCuenta() {
    let list = NoticeList(runtime: [.batch("b"), .capture("c")], issues: [key, screen])
    #expect(list.visible.count == 2)
    #expect(list.hiddenCount == 2)
}

@Test func sinAvisosNoHayNada() {
    let list = NoticeList(runtime: [], issues: [])
    #expect(list.visible.isEmpty)
    #expect(list.hiddenCount == 0)
}

@Test func unPendientePrioritarioNoSeRepite() {
    let list = NoticeList(runtime: [], issues: [key], priority: [key])
    #expect(list.visible == [.setup(key)])
    #expect(list.hiddenCount == 0)
}
