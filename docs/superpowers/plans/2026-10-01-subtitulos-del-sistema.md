# Subtítulos del sistema — plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un tercer modo de Parla. Escucha el audio del sistema (videos en inglés), lo transcribe y lo traduce al español en el Mac, y lo muestra como subtítulos sobre cualquier app, guardando cada frase en el historial.

**Architecture:** La lógica de qué se traduce y qué se muestra es una máquina de estados pura en Core, `SubtitleState`, con un envoltorio asíncrono, `SubtitlePipeline`, que solo ejecuta traducciones. En App:
- el motor de voz deja de estar atado al micrófono: recibe una `AudioSource` y una lista de idiomas;
- `SystemAudioCapture` entrega el audio del sistema con ScreenCaptureKit;
- `LiveTranslator` traduce con `TranslationSession` en `.lowLatency`;
- `SubtitleOverlay` es la banda.

Nada sale del Mac.

**Tech Stack:** Swift 6 (concurrencia estricta), swift-testing, SPM + XcodeGen, Speech (`SpeechAnalyzer`), Translation, ScreenCaptureKit, AVFAudio, SwiftData, AppKit/SwiftUI, KeyboardShortcuts.

**Spec:** `docs/superpowers/specs/2026-10-01-subtitulos-del-sistema-design.md`

## Global Constraints

- **La app pasa a macOS 26.4 mínimo** (Task 6). Core se queda en `.macOS(.v26)`.
- **`Core` solo importa Foundation.** Translation, ScreenCaptureKit y AVFAudio viven en App.
- **Ninguna dependencia nueva.**
- **En este modo no se manda nada a Anthropic.** El audio no sale del Mac.
- **El texto de los subtítulos no va al log del sistema:** el motor se crea con `logsText: false` para la fuente del sistema.
- Ritmo: el parcial se traduce como mucho cada **250 ms**; la banda se oculta tras **4 s** de silencio.
- Banda: centrada, a un **8 %** del borde inferior, **70 %** del ancho de la pantalla; texto de **28 pt** semibold, blanco, sobre negro al **60 %**; la frase anterior al **55 %** de opacidad.
- Atajo **⌃⌥S**. Origen en el historial: `"system"`. Etiqueta: «🎧 Subtítulos».
- La voz y la captura no cambian de comportamiento. Sus tests siguen en verde sin tocarlos, salvo donde una tarea lo dice.
- Textos de interfaz en español.
- Después de crear archivos en `App/` o `AppTests/`, `make test-app` y `make build` regeneran el proyecto solos.
- **Cada `make install` es una app nueva para macOS** y pierde el permiso de Grabación de pantalla. Tras instalar, pide a Edwin que lo conceda y relanza la app.
- Rama `feat/subtitulos`, creada desde `feat/captura`.

## Review Focus

1. **Encender los subtítulos con la escucha del micrófono activa.** La escucha se apaga y el icono pasa a los subtítulos, sin dos analizadores a la vez. → Paso manual en la Task 9.
2. **Pausar el video a mitad de frase.** A los 4 s la banda se oculta aunque la frase no se haya cerrado. → Test `pausarAMitadDeFraseTambienOculta` (Task 2).
3. **Reanudar tras una pausa larga.** La frase de hace minutos no reaparece arriba como «anterior». → Test `cuatroSegundosDeSilencioOcultanLaBanda` (Task 2).
4. **Apagar los subtítulos con una traducción en vuelo.** No aparece nada después de apagar y la app no se cuelga. → Paso manual en la Task 9 (⌃⌥S en plena frase).
5. **El audio del sistema se corta** (reposo, cambio de pantalla). Un reintento y, si no vuelve, se apaga con aviso, sin dejar la banda colgada. → `recover(from:)` en la Task 5 y paso manual en la Task 9.

---

## Estructura de archivos

```
Core/Sources/ParlaCore/
  Subtitles.swift              # NUEVO: SubtitleFrame, SubtitleLine, SubtitleOutput, Translator
  SubtitleState.swift          # NUEVO: máquina de estados pura
  SubtitlePipeline.swift       # NUEVO: envoltorio asíncrono
Core/Tests/ParlaCoreTests/
  SubtitleStateTests.swift     # NUEVO
  SubtitlePipelineTests.swift  # NUEVO
App/
  Audio/AudioSource.swift      # NUEVO: protocolo AudioSource + AudioConversion
  Audio/AudioCapture.swift     # conforme a AudioSource; usa AudioConversion
  Audio/SystemAudioCapture.swift  # NUEVO
  Speech/SpeechTranscriberEngine.swift  # recibe fuente, idiomas y logsText
  Subtitles/LiveTranslator.swift        # NUEVO
  Subtitles/SubtitleOverlay.swift       # NUEVO: SubtitleLayout, SubtitleModel, panel, vista
  Store/StoredCard.swift       # + init(subtitle:)
  Store/CardStore.swift        # + save(subtitle:)
  UI/HistoryWindow.swift       # filtro por origen
  UI/PanelView.swift           # aviso de idiomas de traducción
  UI/SettingsView.swift        # atajo ⌃⌥S
  AppState.swift               # modo subtítulos
  ParlaApp.swift               # atajo, menú, icono, autostart
AppTests/
  AudioSourceTests.swift       # NUEVO
  SystemAudioCaptureTests.swift  # NUEVO
  LiveTranslatorTests.swift    # NUEVO
  SubtitleLayoutTests.swift    # NUEVO
  HistoryFilterTests.swift     # NUEVO
project.yml                    # macOS 26.4
README.md
```

---

### Task 1: Sonda — audio del sistema y traducción en el sandbox

Es una prueba para responder una pregunta. La sonda se revierte al final; el
resultado queda escrito en el spec.

**Files:**
- Modify (temporal, se revierte): `App/DebugHooks.swift`
- Modify: `docs/superpowers/specs/2026-10-01-subtitulos-del-sistema-design.md` (§ 4.3, § 6, § 10)

**Interfaces:**
- Consumes: nada.
- Produces:
  - si ScreenCaptureKit entrega audio del sistema;
  - el estado de los idiomas inglés → español;
  - la latencia media de `.lowLatency` frente a `.highFidelity`;
  - si `prepareTranslation()` puede pedir la descarga.

- [ ] **Step 1: Añadir la sonda**

En `App/DebugHooks.swift`, añade `import ScreenCaptureKit`, `import Translation`,
`import AVFoundation` y `import CoreMedia` debajo de `import AppKit`. En
`install()`, después de la línea de `PARLA_PROBE_AUDIO`:

```swift
        if environment["PARLA_PROBE_SUBTITLES"] == "1" { Task { await probeSubtitles() } }
```

Y al final del archivo, fuera del enum:

```swift
// SONDA TEMPORAL (Task 1 del plan de subtítulos). Se borra al terminar.
extension DebugHooks {
    static func probeSubtitles() async {
        // 1. Audio del sistema durante 10 s.
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                Log.pipeline.error("sonda: sin pantallas"); return
            }
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48_000
            config.channelCount = 1
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            let counter = ProbeAudioCounter()
            let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []),
                                  configuration: config, delegate: nil)
            try stream.addStreamOutput(counter, type: .audio, sampleHandlerQueue: counter.queue)
            try await stream.startCapture()
            Log.pipeline.info("sonda: audio del sistema escuchando 10 s")
            try await Task.sleep(for: .seconds(10))
            try await stream.stopCapture()
            Log.pipeline.info("sonda: audio del sistema → \(counter.summary)")
        } catch {
            Log.pipeline.error("sonda: audio del sistema falló: \(error)")
        }

        // 2. Idiomas de traducción.
        let english = Locale.Language(identifier: "en")
        let spanish = Locale.Language(identifier: "es")
        let status = await LanguageAvailability().status(from: english, to: spanish)
        Log.pipeline.info("sonda: idiomas en→es = \(String(describing: status))")
        guard status == .installed else {
            let session = TranslationSession(installedSource: english, target: spanish)
            Log.pipeline.info("sonda: canRequestDownloads = \(session.canRequestDownloads)")
            do {
                try await session.prepareTranslation()
                Log.pipeline.info("sonda: prepareTranslation terminó sin error")
            } catch {
                Log.pipeline.error("sonda: prepareTranslation falló: \(error)")
            }
            return
        }

        // 3. Latencia y calidad de las dos estrategias.
        let sentences = [
            "Welcome back to the channel, today we're going to dive into something really cool.",
            "If you haven't subscribed yet, make sure to hit that button.",
            "Let's get started with the basics before we move on to the advanced stuff.",
            "This is where most people get stuck, so pay close attention.",
            "I'll leave a link in the description below.",
            "At the end of the day, it all comes down to practice.",
            "We ran out of time, so we'll pick this up next week.",
            "That's a great question, and honestly, it depends.",
            "Don't worry if it doesn't make sense right away.",
            "The company went belly up after the deal fell through.",
            "She's been working on this project for over three years.",
            "You can't have your cake and eat it too.",
            "Make sure you back up your files before updating.",
            "He was over the moon when he found out.",
            "Let me walk you through the whole process step by step.",
            "It's not rocket science, but it takes some getting used to.",
            "We need to figure out what went wrong.",
            "The meeting has been pushed back to Thursday.",
            "I'm going to break it down into three simple steps.",
            "Thanks for watching, and I'll see you in the next one.",
        ]
        for (name, strategy) in [("lowLatency", TranslationSession.Strategy.lowLatency),
                                 ("highFidelity", TranslationSession.Strategy.highFidelity)] {
            let session = TranslationSession(installedSource: english, target: spanish,
                                             preferredStrategy: strategy)
            var total = Duration.zero
            for (index, sentence) in sentences.enumerated() {
                let start = ContinuousClock.now
                do {
                    let response = try await session.translate(sentence)
                    total += start.duration(to: .now)
                    if index < 5 { Log.pipeline.info("sonda: [\(name)] \(response.targetText)") }
                } catch {
                    Log.pipeline.error("sonda: [\(name)] falló: \(error)")
                }
            }
            Log.pipeline.info("sonda: [\(name)] media \(total / sentences.count)")
        }
    }
}

/// Cuenta buffers del audio del sistema y su pico, sin guardarlos.
final class ProbeAudioCounter: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "sonda.audio")
    private var buffers = 0
    private var peak: Float = 0
    private var format = "?"

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio,
              let description = CMSampleBufferGetFormatDescription(sampleBuffer)
        else { return }
        let audioFormat = AVAudioFormat(cmAudioFormatDescription: description)
        format = "\(audioFormat.sampleRate) Hz \(audioFormat.channelCount)ch"
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let pcm = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frames) else { return }
        pcm.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList)
        guard status == noErr, let channel = pcm.floatChannelData?[0] else { return }
        buffers += 1
        for index in 0 ..< Int(frames) { peak = max(peak, abs(channel[index])) }
    }

    var summary: String { "\(buffers) buffers, \(format), pico \(peak)" }
}
```

- [ ] **Step 2: Instalar y asegurar el permiso**

Run: `make install`
Expected: `Parla instalada en /Applications.`

Pide a Edwin que vuelva a conceder Grabación de pantalla a Parla, porque cada
instalación lo pierde.

- [ ] **Step 3: Correr la sonda con voz de prueba**

```bash
SONDA=/private/tmp/claude-501/-Users-edwinsandoval-Work-Free/6fcb88aa-8ba8-40a7-aba7-4479d2b39660/scratchpad/sonda-subtitulos.log
pkill -f 'Parla.app/Contents/MacOS/Parla'; rm -f "$SONDA"
open -n --env PARLA_PROBE_SUBTITLES=1 --env PARLA_STDERR_LOG=1 --stderr "$SONDA" /Applications/Parla.app
sleep 3; say -v Samantha "Welcome back to the channel. Today we are going to learn how to set up the project from scratch."
sleep 12; grep sonda "$SONDA"
```

Expected:
- `audio del sistema → N buffers, 48000.0 Hz 1ch, pico P`, con N > 50 y P > 0.01;
- `idiomas en→es = installed`;
- y, si están instalados, cinco traducciones por estrategia y su `media`.

Si los idiomas salen `supported`, anota `canRequestDownloads` y qué pasó con
`prepareTranslation`. Pide a Edwin que mire si apareció un diálogo de descarga.
Si no, que los instale en Ajustes del Sistema › General › Idioma y región ›
Idiomas de traducción, y repite el Step 3.

- [ ] **Step 4: Decidir**

| Resultado | Decisión |
|---|---|
| N > 50, P > 0.01 e idiomas `installed` | Seguir con el plan tal cual |
| `.lowLatency` más de 2× peor en calidad que `.highFidelity` (a juicio sobre las 5 frases) | Ruling: `.highFidelity` para los finales; `.lowLatency` solo para parciales (Task 6) |
| N = 0 o P = 0 con audio sonando | **Parar.** ScreenCaptureKit no sirve en el sandbox: es un cambio de spec (process taps de Core Audio). Hablarlo con Edwin |
| `prepareTranslation` pide la descarga | En la Task 9, `.needsLanguages` llama a `prepareTranslation()` en lugar de solo avisar |

- [ ] **Step 5: Revertir y escribir el resultado**

```bash
git checkout App/DebugHooks.swift
pkill -f 'Parla.app/Contents/MacOS/Parla'
```

En el spec, al final de § 4.3, añade «**Resultado de la sonda (fecha):**» con N,
P, el estado de los idiomas, las dos medias y la decisión. En § 10, primera
fila, cambia la mitigación por «Confirmado en la sonda».

```bash
git add docs/superpowers/specs/2026-10-01-subtitulos-del-sistema-design.md
git commit -m "docs: resultado de la sonda de subtítulos en el sandbox"
```

---

### Task 2: `SubtitleState` — qué se traduce y qué se ve

**Files:**
- Create: `Core/Sources/ParlaCore/Subtitles.swift`
- Create: `Core/Sources/ParlaCore/SubtitleState.swift`
- Test: `Core/Tests/ParlaCoreTests/SubtitleStateTests.swift`

**Interfaces:**
- Consumes: `TranscriptEvent` (ya existe).
- Produces:
  - `public struct SubtitleFrame: Sendable, Equatable { previous: String?; current: String; currentIsFinal: Bool; currentIsOriginal: Bool }` (init público memberwise)
  - `public struct SubtitleLine: Sendable, Equatable { english: String; spanish: String; spokenAt: Date }`. `spanish` va vacío si la traducción falló.
  - `public enum SubtitleOutput: Sendable, Equatable { case show(SubtitleFrame), hide, line(SubtitleLine) }`
  - `public protocol Translator: Sendable { func translate(_ text: String) async throws -> String }`
  - `public struct SubtitleState: Sendable`, con:
    - `Config(partialInterval: TimeInterval = 0.25, silenceTimeout: TimeInterval = 4)`
    - `Request { id: Int; line: Int; text: String; isFinal: Bool }`
    - `enum Action { case translate(Request), output(SubtitleOutput) }`
    - `mutating func ingest(_ event: TranscriptEvent, at time: Date) -> [Action]`
    - `mutating func tick(at time: Date) -> [Action]`
    - `mutating func receive(_ request: Request, translation: String?) -> [Action]`

`SubtitleLine` no lleva `id`, aunque el spec lo pone. El `UUID` lo crea
`StoredCard` al guardarla (Task 8). Así la línea es determinista y se compara en
los tests.

- [ ] **Step 1: Escribir los tests que fallan**

`Core/Tests/ParlaCoreTests/SubtitleStateTests.swift`:

```swift
import Testing
import Foundation
@testable import ParlaCore

private let t0 = Date(timeIntervalSince1970: 1000)
private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

/// Las traducciones que pidió una lista de acciones.
private func requests(_ actions: [SubtitleState.Action]) -> [SubtitleState.Request] {
    actions.compactMap { if case .translate(let request) = $0 { request } else { nil } }
}

private func outputs(_ actions: [SubtitleState.Action]) -> [SubtitleOutput] {
    actions.compactMap { if case .output(let output) = $0 { output } else { nil } }
}

private func frame(_ actions: [SubtitleState.Action]) -> SubtitleFrame? {
    outputs(actions).compactMap { if case .show(let frame) = $0 { frame } else { nil } }.last
}

@Test func elPrimerParcialSeTraduceAlMomento() {
    var state = SubtitleState()
    let sent = requests(state.ingest(.partial("hello"), at: at(0)))
    #expect(sent == [.init(id: 0, line: 0, text: "hello", isFinal: false)])
}

@Test func dosParcialesSeguidosDanUnaSolaTraduccionLaDelUltimo() {
    var state = SubtitleState()
    _ = state.ingest(.partial("hello"), at: at(0))
    #expect(requests(state.ingest(.partial("hello there"), at: at(0.1))).isEmpty)
    #expect(requests(state.tick(at: at(0.2))).isEmpty)
    let sent = requests(state.tick(at: at(0.26)))
    #expect(sent.map(\.text) == ["hello there"])
    // Ya enviado: el siguiente latido no lo repite.
    #expect(requests(state.tick(at: at(0.6))).isEmpty)
}

@Test func unParcialALos300msSeTraduceDirecto() {
    var state = SubtitleState()
    _ = state.ingest(.partial("hello"), at: at(0))
    #expect(requests(state.ingest(.partial("hello there"), at: at(0.3))).map(\.text)
            == ["hello there"])
}

@Test func elFinalSeTraduceAunqueAcabeDeTraducirseUnParcial() {
    var state = SubtitleState()
    _ = state.ingest(.partial("hello"), at: at(0))
    let sent = requests(state.ingest(.final("hello world"), at: at(0.01)))
    #expect(sent == [.init(id: 1, line: 0, text: "hello world", isFinal: true)])
}

@Test func elFinalReemplazaAlParcialYLuegoPasaArriba() {
    var state = SubtitleState()
    let partial = requests(state.ingest(.partial("hello"), at: at(0)))[0]
    #expect(frame(state.receive(partial, translation: "hola"))
            == SubtitleFrame(previous: nil, current: "hola",
                             currentIsFinal: false, currentIsOriginal: false))

    let final = requests(state.ingest(.final("hello world"), at: at(1)))[0]
    let afterFinal = state.receive(final, translation: "hola mundo")
    #expect(outputs(afterFinal).contains(.line(SubtitleLine(
        english: "hello world", spanish: "hola mundo", spokenAt: at(0)))))
    #expect(frame(afterFinal)?.current == "hola mundo")
    #expect(frame(afterFinal)?.currentIsFinal == true)

    let next = requests(state.ingest(.partial("and you"), at: at(2)))[0]
    #expect(next.line == 1)
    #expect(frame(state.receive(next, translation: "y tú"))
            == SubtitleFrame(previous: "hola mundo", current: "y tú",
                             currentIsFinal: false, currentIsOriginal: false))
}

@Test func cadaFinalSeGuardaUnaSolaVez() {
    var state = SubtitleState()
    let final = requests(state.ingest(.final("hello"), at: at(0)))[0]
    let first = outputs(state.receive(final, translation: "hola"))
    let second = outputs(state.receive(final, translation: "hola"))
    #expect(first.filter { if case .line = $0 { true } else { false } }.count == 1)
    #expect(!second.contains { if case .line = $0 { true } else { false } })
}

@Test func unaTraduccionTardiaNoPisaAUnaMasNueva() {
    var state = SubtitleState()
    let old = requests(state.ingest(.partial("hel"), at: at(0)))[0]
    let new = requests(state.ingest(.partial("hello there"), at: at(0.3)))[0]
    #expect(frame(state.receive(new, translation: "hola, tú"))?.current == "hola, tú")
    #expect(frame(state.receive(old, translation: "hol")) == nil)
}

@Test func siLaTraduccionFallaSeVeElIngles() {
    var state = SubtitleState()
    let final = requests(state.ingest(.final("break a leg"), at: at(0)))[0]
    let actions = state.receive(final, translation: nil)
    #expect(outputs(actions).contains(.line(SubtitleLine(
        english: "break a leg", spanish: "", spokenAt: at(0)))))
    #expect(frame(actions) == SubtitleFrame(previous: nil, current: "break a leg",
                                            currentIsFinal: true, currentIsOriginal: true))
}

@Test func cuatroSegundosDeSilencioOcultanLaBanda() {
    var state = SubtitleState()
    let final = requests(state.ingest(.final("hello"), at: at(0)))[0]
    _ = state.receive(final, translation: "hola")
    #expect(outputs(state.tick(at: at(3.9))).isEmpty)
    #expect(outputs(state.tick(at: at(4))) == [.hide])
    #expect(outputs(state.tick(at: at(5))).isEmpty)   // una sola vez

    // Al volver, la frase de antes de la pausa no reaparece arriba.
    let next = requests(state.ingest(.partial("welcome back"), at: at(60)))[0]
    #expect(frame(state.receive(next, translation: "bienvenidos de nuevo"))?.previous == nil)
}

@Test func pausarAMitadDeFraseTambienOculta() {
    var state = SubtitleState()
    let partial = requests(state.ingest(.partial("so the next"), at: at(0)))[0]
    _ = state.receive(partial, translation: "así que el siguiente")
    #expect(outputs(state.tick(at: at(4.1))) == [.hide])
}

@Test func unFinalVacioSeIgnora() {
    var state = SubtitleState()
    #expect(state.ingest(.final("   "), at: at(0)).isEmpty)
}

@Test func elFinalDeLaFraseAnteriorLlegaTardeYSubeArriba() {
    var state = SubtitleState()
    let first = requests(state.ingest(.final("first one"), at: at(0)))[0]
    let second = requests(state.ingest(.partial("second"), at: at(0.5)))[0]
    #expect(frame(state.receive(second, translation: "segunda"))?.previous == nil)

    let late = state.receive(first, translation: "la primera")
    #expect(outputs(late).contains(.line(SubtitleLine(
        english: "first one", spanish: "la primera", spokenAt: at(0)))))
    #expect(frame(late) == SubtitleFrame(previous: "la primera", current: "segunda",
                                         currentIsFinal: false, currentIsOriginal: false))
}
```

- [ ] **Step 2: Ver que fallan**

Run: `make test`
Expected: FAIL de compilación: `cannot find 'SubtitleState' in scope`.

- [ ] **Step 3: Los tipos**

`Core/Sources/ParlaCore/Subtitles.swift`:

```swift
import Foundation

/// Lo que se ve en la banda en un momento dado.
public struct SubtitleFrame: Sendable, Equatable {
    /// La frase anterior, ya cerrada. Va atenuada encima.
    public let previous: String?
    /// La que se está diciendo.
    public let current: String
    public let currentIsFinal: Bool
    /// `true` si es el inglés porque la traducción falló.
    public let currentIsOriginal: Bool

    public init(previous: String?, current: String,
                currentIsFinal: Bool, currentIsOriginal: Bool) {
        self.previous = previous
        self.current = current
        self.currentIsFinal = currentIsFinal
        self.currentIsOriginal = currentIsOriginal
    }
}

/// Una frase cerrada, para el historial.
public struct SubtitleLine: Sendable, Equatable {
    public let english: String
    /// Vacío si la traducción falló.
    public let spanish: String
    /// Cuándo empezó a decirse.
    public let spokenAt: Date

    public init(english: String, spanish: String, spokenAt: Date) {
        self.english = english
        self.spanish = spanish
        self.spokenAt = spokenAt
    }
}

public enum SubtitleOutput: Sendable, Equatable {
    case show(SubtitleFrame)
    case hide
    case line(SubtitleLine)
}

/// Del inglés al español. Separado para que el pipeline se pruebe sin el
/// framework de traducción, que vive en App.
public protocol Translator: Sendable {
    func translate(_ text: String) async throws -> String
}
```

- [ ] **Step 4: La máquina de estados**

`Core/Sources/ParlaCore/SubtitleState.swift`:

```swift
import Foundation

/// Decide qué se traduce y qué se ve en la banda.
///
/// Pura, como `UtteranceSegmenter`: no tiene reloj ni traduce. Quien la usa le
/// entrega eventos, latidos y traducciones, y ejecuta las acciones que devuelve.
public struct SubtitleState: Sendable {

    public struct Config: Sendable {
        /// Como mucho una traducción de parcial cada tanto: más rápido no se
        /// lee y hace parpadear el texto.
        public var partialInterval: TimeInterval
        /// Silencio tras el que la banda se oculta.
        public var silenceTimeout: TimeInterval

        public init(partialInterval: TimeInterval = 0.25, silenceTimeout: TimeInterval = 4) {
            self.partialInterval = partialInterval
            self.silenceTimeout = silenceTimeout
        }
    }

    /// Una traducción pedida. `id` crece con cada petición y ordena las
    /// respuestas, que llegan desordenadas; `line` dice de qué frase es.
    public struct Request: Sendable, Equatable {
        public let id: Int
        public let line: Int
        public let text: String
        public let isFinal: Bool

        public init(id: Int, line: Int, text: String, isFinal: Bool) {
            self.id = id
            self.line = line
            self.text = text
            self.isFinal = isFinal
        }
    }

    public enum Action: Sendable, Equatable {
        case translate(Request)
        case output(SubtitleOutput)
    }

    private struct Shown {
        var text: String
        var isFinal: Bool
        var isOriginal: Bool
    }

    private let config: Config
    private var nextID = 0
    /// La frase que se está diciendo.
    private var line = 0
    /// La frase actual ya recibió su final: el próximo evento abre otra.
    private var lineClosed = false
    private var lineStartedAt: Date?
    private var lastActivityAt: Date?
    private var lastPartialRequestAt: Date?
    /// El último parcial, esperando a que pase el intervalo.
    private var waitingPartial: String?
    /// La respuesta más nueva mostrada para la frase actual.
    private var shownID = -1
    private var current: Shown?
    private var previous: String?
    /// Finales pedidos y aún sin respuesta: se guardan una sola vez.
    private var pendingFinals: [Int: (english: String, startedAt: Date)] = [:]
    private var visible = false

    public init(config: Config = Config()) {
        self.config = config
    }

    public mutating func ingest(_ event: TranscriptEvent, at time: Date) -> [Action] {
        switch event {
        case .partial(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            openLineIfNeeded(at: time)
            lastActivityAt = time
            waitingPartial = trimmed
            return flushPartial(at: time)

        case .final(let text):
            // El motor emite un final vacío al cerrarse el stream: no es una frase.
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            openLineIfNeeded(at: time)
            lastActivityAt = time
            waitingPartial = nil
            let request = makeRequest(trimmed, isFinal: true)
            pendingFinals[request.id] = (trimmed, lineStartedAt ?? time)
            lineClosed = true
            return [.translate(request)]
        }
    }

    public mutating func tick(at time: Date) -> [Action] {
        var actions = flushPartial(at: time)
        if visible, let last = lastActivityAt,
           time.timeIntervalSince(last) >= config.silenceTimeout {
            visible = false
            // Tras una pausa, lo de antes no vuelve a aparecer arriba.
            previous = nil
            if lineClosed { current = nil }
            actions.append(.output(.hide))
        }
        return actions
    }

    /// `translation == nil` si la traducción falló.
    public mutating func receive(_ request: Request, translation: String?) -> [Action] {
        var actions: [Action] = []
        if request.isFinal, let final = pendingFinals.removeValue(forKey: request.id) {
            actions.append(.output(.line(SubtitleLine(
                english: final.english, spanish: translation ?? "", spokenAt: final.startedAt))))
        }

        let shown = Shown(text: translation ?? request.text,
                          isFinal: request.isFinal,
                          isOriginal: translation == nil)
        if request.line == line {
            // Una respuesta vieja no pisa a una más nueva de la misma frase.
            guard request.id > shownID else { return actions }
            shownID = request.id
            current = shown
        } else if request.line == line - 1, request.isFinal {
            // El final de la frase anterior llegó cuando ya empezó otra.
            previous = shown.text
            guard current != nil else { return actions }
        } else {
            return actions
        }

        guard let current else { return actions }
        visible = true
        actions.append(.output(.show(SubtitleFrame(
            previous: previous, current: current.text,
            currentIsFinal: current.isFinal, currentIsOriginal: current.isOriginal))))
        return actions
    }

    private mutating func openLineIfNeeded(at time: Date) {
        guard lineClosed else {
            if lineStartedAt == nil { lineStartedAt = time }
            return
        }
        // La frase anterior sube con lo último que se vio de ella.
        previous = current?.text ?? previous
        current = nil
        shownID = -1
        line += 1
        lineClosed = false
        lineStartedAt = time
        // El primer parcial de una frase nueva no espera al intervalo.
        lastPartialRequestAt = nil
    }

    private mutating func flushPartial(at time: Date) -> [Action] {
        guard let text = waitingPartial else { return [] }
        if let last = lastPartialRequestAt,
           time.timeIntervalSince(last) < config.partialInterval { return [] }
        waitingPartial = nil
        lastPartialRequestAt = time
        return [.translate(makeRequest(text, isFinal: false))]
    }

    private mutating func makeRequest(_ text: String, isFinal: Bool) -> Request {
        defer { nextID += 1 }
        return Request(id: nextID, line: line, text: text, isFinal: isFinal)
    }
}
```

- [ ] **Step 5: Ver que pasan**

Run: `make test`
Expected: PASS, 89 tests: los 77 de antes y 12 nuevos.

- [ ] **Step 6: Commit**

```bash
git add Core/Sources/ParlaCore/Subtitles.swift Core/Sources/ParlaCore/SubtitleState.swift Core/Tests/ParlaCoreTests/SubtitleStateTests.swift
git commit -m "feat(core): la máquina de estados de los subtítulos"
```

---

### Task 3: `SubtitlePipeline`

**Files:**
- Create: `Core/Sources/ParlaCore/SubtitlePipeline.swift`
- Test: `Core/Tests/ParlaCoreTests/SubtitlePipelineTests.swift`

**Interfaces:**
- Consumes: `SubtitleState`, `Translator`, `SubtitleOutput` (Task 2); `Transcriber`; `FakeTranscriber` (de `Fakes.swift`).
- Produces: `public struct SubtitlePipeline: Sendable`, con `init(transcriber: any Transcriber, translator: any Translator, config: SubtitleState.Config = .init(), tickInterval: Duration? = .milliseconds(50))` y `var outputs: AsyncStream<SubtitleOutput>`.

- [ ] **Step 1: Escribir los tests que fallan**

`Core/Tests/ParlaCoreTests/SubtitlePipelineTests.swift`:

```swift
import Testing
import Foundation
@testable import ParlaCore

private struct PrefixTranslator: Translator {
    func translate(_ text: String) async throws -> String { "ES:" + text }
}

private struct FailingTranslator: Translator {
    struct Down: Error {}
    func translate(_ text: String) async throws -> String { throw Down() }
}

private let t0 = Date(timeIntervalSince1970: 1000)

private func collect(_ pipeline: SubtitlePipeline) async -> [SubtitleOutput] {
    var all: [SubtitleOutput] = []
    for await output in pipeline.outputs { all.append(output) }
    return all
}

@Test func traduceYGuardaLaFraseCerrada() async {
    let transcriber = FakeTranscriber(script: [
        (.partial("hello"), t0),
        (.final("hello world"), t0.addingTimeInterval(1)),
    ])
    let outputs = await collect(SubtitlePipeline(transcriber: transcriber,
                                                 translator: PrefixTranslator(),
                                                 tickInterval: nil))
    #expect(outputs.contains(.line(SubtitleLine(english: "hello world",
                                                spanish: "ES:hello world", spokenAt: t0))))
    let lastShown = outputs.compactMap { if case .show(let frame) = $0 { frame } else { nil } }.last
    #expect(lastShown?.current == "ES:hello world")
}

@Test func conElTraductorCaidoGuardaLaFraseSinTraducir() async {
    let transcriber = FakeTranscriber(script: [(.final("break a leg"), t0)])
    let outputs = await collect(SubtitlePipeline(transcriber: transcriber,
                                                 translator: FailingTranslator(),
                                                 tickInterval: nil))
    #expect(outputs.contains(.line(SubtitleLine(english: "break a leg",
                                                spanish: "", spokenAt: t0))))
}
```

- [ ] **Step 2: Ver que fallan**

Run: `make test`
Expected: FAIL de compilación: `cannot find 'SubtitlePipeline' in scope`.

- [ ] **Step 3: Implementar**

`Core/Sources/ParlaCore/SubtitlePipeline.swift`:

```swift
import Foundation

/// Une la transcripción con la traducción y emite lo que la banda tiene que
/// mostrar. Las decisiones son de `SubtitleState`; aquí solo se ejecutan.
public struct SubtitlePipeline: Sendable {

    private enum Beat: Sendable {
        case event(TranscriptEvent, Date)
        case tick(Date)
        case translated(SubtitleState.Request, String?)
        /// El transcriptor terminó: se espera a las traducciones en vuelo.
        case ended
    }

    private let transcriber: any Transcriber
    private let translator: any Translator
    private let config: SubtitleState.Config
    /// Cada cuánto se comprueban el intervalo de los parciales y el silencio.
    /// `nil` lo apaga, para los tests con horas fijas.
    private let tickInterval: Duration?

    public init(transcriber: any Transcriber,
                translator: any Translator,
                config: SubtitleState.Config = .init(),
                tickInterval: Duration? = .milliseconds(50)) {
        self.transcriber = transcriber
        self.translator = translator
        self.config = config
        self.tickInterval = tickInterval
    }

    public var outputs: AsyncStream<SubtitleOutput> {
        AsyncStream { continuation in
            let task = Task {
                var state = SubtitleState(config: config)
                let (beats, feed) = AsyncStream<Beat>.makeStream()
                let translator = self.translator

                let forwarding = Task {
                    for await (event, time) in transcriber.events {
                        feed.yield(.event(event, time))
                    }
                    feed.yield(.ended)
                }
                let ticking = Task {
                    guard let interval = tickInterval else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: interval)
                        feed.yield(.tick(Date()))
                    }
                }

                var inFlight = 0
                var ended = false
                func run(_ actions: [SubtitleState.Action]) {
                    for action in actions {
                        switch action {
                        case .output(let output):
                            continuation.yield(output)
                        case .translate(let request):
                            inFlight += 1
                            Task {
                                let text = try? await translator.translate(request.text)
                                feed.yield(.translated(request, text))
                            }
                        }
                    }
                }

                for await beat in beats {
                    switch beat {
                    case .event(let event, let time):
                        run(state.ingest(event, at: time))
                    case .tick(let time):
                        run(state.tick(at: time))
                    case .translated(let request, let text):
                        inFlight -= 1
                        run(state.receive(request, translation: text))
                    case .ended:
                        ended = true
                    }
                    if ended && inFlight == 0 { break }
                }
                forwarding.cancel()
                ticking.cancel()
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

- [ ] **Step 4: Ver que pasan**

Run: `make test`
Expected: PASS, 91 tests.

- [ ] **Step 5: Commit**

```bash
git add Core/Sources/ParlaCore/SubtitlePipeline.swift Core/Tests/ParlaCoreTests/SubtitlePipelineTests.swift
git commit -m "feat(core): pipeline de subtítulos sobre la máquina de estados"
```

---

### Task 4: `AudioSource` — el motor deja de estar atado al micrófono

**Files:**
- Create: `App/Audio/AudioSource.swift`
- Modify: `App/Audio/AudioCapture.swift`, `App/Speech/SpeechTranscriberEngine.swift`, `App/AppState.swift`
- Test: `AppTests/AudioSourceTests.swift`

**Interfaces:**
- Consumes: `AudioChunk` (ya existe en `AudioCapture.swift`).
- Produces:
  - `@MainActor protocol AudioSource: AnyObject { var displayName: String { get }; var isReceivingAudio: Bool { get }; func requestAccess() async throws; func start(outputFormat: AVAudioFormat) async throws -> AsyncStream<AudioChunk>; func stop() }`
  - `enum AudioConversion { nonisolated static func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat, using converter: AVAudioConverter?) -> AVAudioPCMBuffer?; nonisolated static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? }`
  - `TranscriberSetupError.screenRecordingDenied`
  - `SpeechTranscriberEngine.init(source: any AudioSource, locales: [Locale], logsText: Bool = true)`

- [ ] **Step 1: Escribir los tests que fallan**

`AppTests/AudioSourceTests.swift`:

```swift
import Testing
import AVFoundation
@testable import Parla

@Test func convierteDe48kA16kHz() throws {
    let source = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                            channels: 1, interleaved: false))
    let target = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                            channels: 1, interleaved: false))
    let input = try #require(AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 4800))
    input.frameLength = 4800
    for index in 0 ..< 4800 { input.floatChannelData![0][index] = sin(Float(index) * 0.05) }

    let output = try #require(AudioConversion.convert(
        input, to: target, using: AVAudioConverter(from: source, to: target)))
    #expect(output.format.sampleRate == 16_000)
    // Un tercio de los frames, menos lo que el conversor retiene al empezar.
    #expect(output.frameLength > 1400 && output.frameLength <= 1700)
}

@Test @MainActor func elMicrofonoEsUnaFuenteDeAudio() {
    let source: any AudioSource = AudioCapture()
    #expect(!source.displayName.isEmpty)
    #expect(!source.isReceivingAudio)
}
```

- [ ] **Step 2: Ver que fallan**

Run: `make test-app`
Expected: FAIL de compilación: `cannot find 'AudioConversion' in scope`.

- [ ] **Step 3: El protocolo y la conversión**

`App/Audio/AudioSource.swift`:

```swift
import AVFoundation
import CoreMedia

/// De dónde llega el audio que se transcribe: el micrófono o el sistema.
@MainActor
protocol AudioSource: AnyObject {
    /// Para los avisos: «No llega audio desde …».
    var displayName: String { get }
    var isReceivingAudio: Bool { get }
    /// Lanza el `TranscriberSetupError` que toque si falta el permiso.
    func requestAccess() async throws
    func start(outputFormat: AVAudioFormat) async throws -> AsyncStream<AudioChunk>
    func stop()
}

/// Conversiones de audio compartidas por las dos fuentes. Puras: corren en el
/// hilo de audio, nunca en el principal.
enum AudioConversion {

    nonisolated static func convert(_ buffer: AVAudioPCMBuffer,
                                    to format: AVAudioFormat,
                                    using converter: AVAudioConverter?) -> AVAudioPCMBuffer? {
        guard let converter else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }

    /// Lo que entrega ScreenCaptureKit, como buffer de AVFAudio.
    nonisolated static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }
}
```

- [ ] **Step 4: `AudioCapture` usa la conversión compartida y se vuelve fuente**

En `App/Audio/AudioCapture.swift`:
- borra el método `private nonisolated static func convert(...)` entero;
- en el bloque del tap, cambia `Self.convert(buffer, to: outputFormat, using: converter)`
  por `AudioConversion.convert(buffer, to: outputFormat, using: converter)`;
- añade al final del archivo:

```swift
extension AudioCapture: AudioSource {
    var displayName: String { inputDeviceName }

    /// Se pide explícitamente para distinguir "denegado" de "no hay audio" y
    /// ofrecer el botón a Ajustes del Sistema.
    func requestAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .audio) { return }
        default:
            break
        }
        throw TranscriberSetupError.microphoneDenied
    }
}
```

- [ ] **Step 5: El motor recibe la fuente, los idiomas y si registra el texto**

En `App/Speech/SpeechTranscriberEngine.swift`:

1. En `TranscriberSetupError`, añade `case screenRecordingDenied` después de
   `microphoneDenied`.
2. Sustituye las propiedades `requestedLocale`, `inputDeviceUID` y
   `audio: AudioCapture?` por:

```swift
    private let source: any AudioSource
    /// En orden de preferencia: el primero que el sistema soporte.
    private let locales: [Locale]
    /// `false` para el audio del sistema: el texto de lo que suena no va al log.
    private let logsText: Bool
```

3. Sustituye `isReceivingAudio`, `inputDeviceName` y el `init` por:

```swift
    var isReceivingAudio: Bool { source.isReceivingAudio }
    var inputDeviceName: String { source.displayName }

    init(source: any AudioSource, locales: [Locale], logsText: Bool = true) {
        self.source = source
        self.locales = locales
        self.logsText = logsText
        (self.events, self.relay) = AsyncStream.makeStream()
    }
```

4. En `start()`, sustituye el `guard await Self.microphoneGranted() else { … }` por:

```swift
        do {
            try await source.requestAccess()
        } catch {
            phase = .failed("permiso denegado")
            throw error
        }
```

   Sustituye las dos líneas
   `let capture = AudioCapture(preferredInputUID: inputDeviceUID)` y
   `let chunks = try capture.start(outputFormat: format)` por
   `let chunks = try await source.start(outputFormat: format)`, y borra
   `self.audio = capture`.

   En el bucle de resultados, sustituye la línea `Log.speech.info("resultado …: \(text)")` por:

```swift
                    if self.logsText {
                        Log.speech.info("resultado \(result.isFinal ? "final" : "parcial"): \(text)")
                    } else {
                        Log.speech.info("resultado \(result.isFinal ? "final" : "parcial"): "
                            + "\(text.count) caracteres")
                    }
```

5. Borra `private static func microphoneGranted()`. Ahora vive en
   `AudioCapture.requestAccess()`.
6. En `stop()`, sustituye `audio?.stop()` y `audio = nil` por `source.stop()`.
7. Sustituye `resolvedLocale()` por:

```swift
    /// El primer idioma de la lista que el sistema soporte, en su variante
    /// equivalente (`es-419` puede resolverse a otra).
    private func resolvedLocale() async throws -> Locale {
        for locale in locales {
            if let match = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
                return match
            }
        }
        throw TranscriberSetupError.localeUnsupported
    }
```

8. Cambia el comentario de `ensureAssets` («Descarga el modelo de español…») por
   «Descarga el modelo del idioma si no está instalado.», y el de
   `TranscriberPhase.downloadingModel` («…del modelo de español») por «…del
   modelo de voz».

- [ ] **Step 6: La voz sigue igual**

En `App/AppState.swift`, en `start()`, sustituye
`let engine = SpeechTranscriberEngine(inputDeviceUID: inputDeviceUID)` por:

```swift
        let engine = SpeechTranscriberEngine(
            source: AudioCapture(preferredInputUID: inputDeviceUID),
            locales: [Locale(identifier: "es-419"), Locale(identifier: "es-ES")])
```

- [ ] **Step 7: Ver que pasan**

Run: `make test-app`
Expected: `** TEST SUCCEEDED **`, 43 tests. Los 4 de `AudioDeviceTests` siguen en
verde.

- [ ] **Step 8: Comprobar que la voz no cambió**

Run: `make install`, y luego, con `open` para que macOS atribuya el permiso del
micrófono a Parla y no a la Terminal:

```bash
L=/private/tmp/claude-501/-Users-edwinsandoval-Work-Free/6fcb88aa-8ba8-40a7-aba7-4479d2b39660/scratchpad/voz.log
pkill -f 'Parla.app/Contents/MacOS/Parla'; rm -f "$L"
open -n --env PARLA_AUTOSTART=1 --env PARLA_STDERR_LOG=1 --stderr "$L" /Applications/Parla.app
sleep 8; grep -E "locale resuelto|analizador arrancado|permiso" "$L"
pkill -f 'Parla.app/Contents/MacOS/Parla'
```

Expected: `locale resuelto: es…` y `analizador arrancado`. Si sale `permiso
denegado`, pide a Edwin que vuelva a dar el micrófono a Parla, porque la
instalación lo pierde, y repite.

- [ ] **Step 9: Commit**

```bash
git add App/Audio App/Speech App/AppState.swift AppTests/AudioSourceTests.swift
git commit -m "refactor: el motor de voz recibe la fuente de audio y los idiomas"
```

---

### Task 5: `SystemAudioCapture`

**Files:**
- Create: `App/Audio/SystemAudioCapture.swift`
- Test: `AppTests/SystemAudioCaptureTests.swift`

**Interfaces:**
- Consumes: `AudioSource`, `AudioConversion`, `TranscriberSetupError.screenRecordingDenied` (Task 4); `AudioChunk`.
- Produces: `@MainActor final class SystemAudioCapture: NSObject, AudioSource` con `nonisolated static func configuration() -> SCStreamConfiguration`.

- [ ] **Step 1: Escribir el test que falla**

`AppTests/SystemAudioCaptureTests.swift`:

```swift
import Testing
import ScreenCaptureKit
@testable import Parla

@Test func pideSoloAudioYSinElDeParla() {
    let configuration = SystemAudioCapture.configuration()
    #expect(configuration.capturesAudio)
    #expect(configuration.excludesCurrentProcessAudio)
    #expect(configuration.sampleRate == 48_000)
    #expect(configuration.channelCount == 1)
    // El vídeo es obligatorio en ScreenCaptureKit: se pide el mínimo.
    #expect(configuration.width == 2 && configuration.height == 2)
}
```

- [ ] **Step 2: Ver que falla**

Run: `make test-app`
Expected: FAIL de compilación: `cannot find 'SystemAudioCapture' in scope`.

- [ ] **Step 3: Implementar**

`App/Audio/SystemAudioCapture.swift`:

```swift
import AVFoundation
import CoreGraphics
import CoreMedia
@preconcurrency import ScreenCaptureKit

/// Todo el audio del sistema, menos el de la propia Parla, vía ScreenCaptureKit.
/// Usa el permiso de Grabación de pantalla que Parla ya tiene para las capturas.
@MainActor
final class SystemAudioCapture: NSObject, AudioSource {

    let displayName = "el audio del sistema"

    private var stream: SCStream?
    private var output: SystemAudioOutput?
    /// Un solo reintento cuando el stream se corta (reposo, cambio de pantalla).
    private var retried = false

    var isReceivingAudio: Bool { output?.receivedRecently ?? false }

    func requestAccess() async throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw TranscriberSetupError.screenRecordingDenied
        }
    }

    nonisolated static func configuration() -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 1
        // ScreenCaptureKit exige vídeo: el mínimo, y sin salida que lo reciba.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        return configuration
    }

    func start(outputFormat: AVAudioFormat) async throws -> AsyncStream<AudioChunk> {
        stop()
        let (chunks, continuation) = AsyncStream<AudioChunk>.makeStream()
        let output = SystemAudioOutput(outputFormat: outputFormat, continuation: continuation)
        self.output = output
        retried = false
        try await startStream(with: output)
        return chunks
    }

    func stop() {
        let stream = self.stream
        self.stream = nil
        Task { try? await stream?.stopCapture() }
        output?.finish()
        output = nil
    }

    private func startStream(with output: SystemAudioOutput) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw TranscriberSetupError.assetUnavailable
        }
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []),
                              configuration: Self.configuration(),
                              delegate: self)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.queue)
        try await stream.startCapture()
        self.stream = stream
        Log.audio.info("audio del sistema: capturando")
    }

    /// Un reintento; si vuelve a fallar se cierra el stream de audio, el motor
    /// termina y `AppState` apaga los subtítulos con un aviso.
    fileprivate func recover(from error: any Error) {
        Log.audio.error("el audio del sistema se cortó: \(error.localizedDescription)")
        guard !retried, let output else {
            output?.finish()
            return
        }
        retried = true
        Task {
            do {
                try await startStream(with: output)
            } catch {
                output.finish()
            }
        }
    }
}

extension SystemAudioCapture: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in self.recover(from: error) }
    }
}

/// Recibe los buffers en la cola de ScreenCaptureKit y los entrega ya en el
/// formato del analizador.
final class SystemAudioOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "app.schoolaid.Parla.audio-del-sistema")
    private let outputFormat: AVAudioFormat
    private let continuation: AsyncStream<AudioChunk>.Continuation
    /// Solo se toca desde `queue`.
    private var converter: AVAudioConverter?
    private let lock = NSLock()
    private var lastBufferAt: Date?

    init(outputFormat: AVAudioFormat, continuation: AsyncStream<AudioChunk>.Continuation) {
        self.outputFormat = outputFormat
        self.continuation = continuation
    }

    var receivedRecently: Bool {
        lock.withLock { lastBufferAt.map { Date().timeIntervalSince($0) < 3 } ?? false }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio, let pcm = AudioConversion.pcmBuffer(from: sampleBuffer) else { return }
        if converter == nil || converter?.inputFormat != pcm.format {
            converter = AVAudioConverter(from: pcm.format, to: outputFormat)
        }
        if let converted = AudioConversion.convert(pcm, to: outputFormat, using: converter) {
            continuation.yield(AudioChunk(buffer: converted))
        }
        lock.withLock { lastBufferAt = Date() }
    }

    func finish() { continuation.finish() }
}
```

- [ ] **Step 4: Ver que pasa**

Run: `make test-app`
Expected: `** TEST SUCCEEDED **`, 44 tests.

- [ ] **Step 5: Commit**

```bash
git add App/Audio/SystemAudioCapture.swift AppTests/SystemAudioCaptureTests.swift
git commit -m "feat: capturar el audio del sistema con ScreenCaptureKit"
```

---

### Task 6: `LiveTranslator` y macOS 26.4

**Files:**
- Create: `App/Subtitles/LiveTranslator.swift`
- Modify: `project.yml`
- Test: `AppTests/LiveTranslatorTests.swift`

**Interfaces:**
- Consumes: `Translator` (Task 2).
- Produces:
  - `actor LiveTranslator: Translator` con `init()`
  - `enum LiveTranslator.Readiness { case ready, needsLanguages, unsupported }`
  - `static func readiness() async -> Readiness`
  - `nonisolated static func notice(for readiness: Readiness) -> String?`

Si la Task 1 decidió `.highFidelity` para los finales, `LiveTranslator` tiene dos
sesiones y `translate` no sabe si es final. En ese caso, ruling: `Translator`
gana `func translate(_ text: String, isFinal: Bool)` y `SubtitlePipeline` pasa
`request.isFinal`. Si no, se queda como está.

- [ ] **Step 1: Escribir el test que falla**

`AppTests/LiveTranslatorTests.swift`:

```swift
import Testing
@testable import Parla

@Test func avisaSoloCuandoFaltaAlgo() {
    #expect(LiveTranslator.notice(for: .ready) == nil)
    #expect(LiveTranslator.notice(for: .needsLanguages)?.contains("Idiomas de traducción") == true)
    #expect(LiveTranslator.notice(for: .unsupported) != nil)
}
```

- [ ] **Step 2: Ver que falla**

Run: `make test-app`
Expected: FAIL de compilación: `cannot find 'LiveTranslator' in scope`.

- [ ] **Step 3: Implementar**

`App/Subtitles/LiveTranslator.swift`:

```swift
import Foundation
import ParlaCore
import Translation

/// Inglés → español con la traducción de Apple, en el Mac y sin coste.
/// `.lowLatency` prioriza la velocidad: el subtítulo tiene que llegar mientras
/// se habla.
actor LiveTranslator: Translator {

    enum Readiness: Equatable, Sendable {
        case ready
        /// Soportados pero sin descargar.
        case needsLanguages
        case unsupported
    }

    private static let english = Locale.Language(identifier: "en")
    private static let spanish = Locale.Language(identifier: "es")

    private let session = TranslationSession(installedSource: LiveTranslator.english,
                                             target: LiveTranslator.spanish,
                                             preferredStrategy: .lowLatency)

    func translate(_ text: String) async throws -> String {
        try await session.translate(text).targetText
    }

    static func readiness() async -> Readiness {
        switch await LanguageAvailability().status(from: english, to: spanish) {
        case .installed: .ready
        case .supported: .needsLanguages
        case .unsupported: .unsupported
        @unknown default: .unsupported
        }
    }

    nonisolated static func notice(for readiness: Readiness) -> String? {
        switch readiness {
        case .ready:
            nil
        case .needsLanguages:
            "Faltan el inglés y el español en Ajustes del Sistema › General › "
                + "Idioma y región › Idiomas de traducción."
        case .unsupported:
            "Este Mac no puede traducir del inglés al español."
        }
    }
}
```

- [ ] **Step 4: Ver el error de disponibilidad**

Run: `make test-app`
Expected: FAIL de compilación en `preferredStrategy: .lowLatency`:
`'lowLatency' is only available in macOS 26.4 or newer`. Ese es el motivo del
paso siguiente.

- [ ] **Step 5: Subir la app a macOS 26.4**

En `project.yml`, cambia `macOS: "26.0"` por `macOS: "26.4"`, en
`options.deploymentTarget`, y `LSMinimumSystemVersion: "26.0"` por
`LSMinimumSystemVersion: "26.4"`. `Core/Package.swift` no se toca.

- [ ] **Step 6: Ver que pasa**

Run: `make test-app`
Expected: `** TEST SUCCEEDED **`, 45 tests.

Si `TranslationSession` da errores de concurrencia (`sending … risks causing data
races`) dentro del actor, ruling: cambia `actor` por
`final class LiveTranslator: Translator, @unchecked Sendable`. La sesión solo se
toca desde `translate`, que el pipeline llama de una en una por petición.

- [ ] **Step 7: Commit**

```bash
git add App/Subtitles/LiveTranslator.swift AppTests/LiveTranslatorTests.swift project.yml
git commit -m "feat: traducir en el Mac con baja latencia; la app pasa a macOS 26.4"
```

---

### Task 7: La banda

**Files:**
- Create: `App/Subtitles/SubtitleOverlay.swift`
- Test: `AppTests/SubtitleLayoutTests.swift`

**Interfaces:**
- Consumes: `SubtitleFrame` (Task 2).
- Produces:
  - `enum SubtitleLayout { static let height: CGFloat = 200; static func frame(in screen: CGRect) -> CGRect }`
  - `@MainActor @Observable final class SubtitleModel { var frame: SubtitleFrame?; var notice: String?; var isVisible: Bool }`
  - `final class SubtitleOverlay: NSPanel`, con `init(model: SubtitleModel, screen: NSScreen)`

- [ ] **Step 1: Escribir los tests que fallan**

`AppTests/SubtitleLayoutTests.swift`:

```swift
import Testing
import CoreGraphics
@testable import Parla

@Test func vaCentradaYAbajo() {
    let frame = SubtitleLayout.frame(in: CGRect(x: 0, y: 0, width: 1000, height: 800))
    #expect(frame.width == 700)
    #expect(frame.midX == 500)
    #expect(frame.minY == 64)   // un 8 % de 800
}

@Test func respetaElOrigenDeUnaSegundaPantalla() {
    let frame = SubtitleLayout.frame(in: CGRect(x: 1440, y: -200, width: 1920, height: 1080))
    #expect(frame.midX == 1440 + 960)
    #expect(frame.minY == (-200 + 1080 * 0.08).rounded())
}

@Test func tieneAltoParaDosBloquesDeDosLineas() {
    #expect(SubtitleLayout.frame(in: CGRect(x: 0, y: 0, width: 1000, height: 800)).height
            == SubtitleLayout.height)
}

@Test func enUnaPantallaPequenaNoSeSale() {
    let screen = CGRect(x: 0, y: 0, width: 800, height: 220)
    #expect(screen.contains(SubtitleLayout.frame(in: screen)))
}
```

- [ ] **Step 2: Ver que fallan**

Run: `make test-app`
Expected: FAIL de compilación: `cannot find 'SubtitleLayout' in scope`.

- [ ] **Step 3: Implementar**

`App/Subtitles/SubtitleOverlay.swift`:

```swift
import AppKit
import ParlaCore
import SwiftUI

/// Dónde va la banda. La ventana es fija y transparente; el fondo oscuro solo
/// rodea al texto, así que su tamaño real lo pone el contenido.
enum SubtitleLayout {
    /// Dos bloques de hasta dos líneas a 28 pt, con márgenes.
    static let height: CGFloat = 200
    static let widthFraction: CGFloat = 0.7
    static let bottomFraction: CGFloat = 0.08

    static func frame(in screen: CGRect) -> CGRect {
        let width = (screen.width * widthFraction).rounded()
        let height = min(Self.height, screen.height - screen.height * bottomFraction)
        return CGRect(x: (screen.midX - width / 2).rounded(),
                      y: (screen.minY + screen.height * bottomFraction).rounded(),
                      width: width,
                      height: height)
    }
}

@MainActor
@Observable
final class SubtitleModel {
    var frame: SubtitleFrame?
    /// Un aviso (descarga del modelo, idiomas que faltan) en lugar del subtítulo.
    var notice: String?
    var isVisible = false
}

/// Flota sobre todo, también sobre un video a pantalla completa, y deja pasar
/// los clics: no tapa los controles del video ni roba el foco.
final class SubtitleOverlay: NSPanel {

    init(model: SubtitleModel, screen: NSScreen) {
        super.init(contentRect: SubtitleLayout.frame(in: screen.frame),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: SubtitleView(model: model))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct SubtitleView: View {
    let model: SubtitleModel

    var body: some View {
        VStack {
            if let notice = model.notice {
                Text(notice)
                    .font(.system(size: 20, weight: .medium))
                    .modifier(Banded())
            } else if model.isVisible, let frame = model.frame {
                VStack(spacing: 4) {
                    if let previous = frame.previous {
                        Text(previous)
                            .opacity(0.55)
                            .lineLimit(2)
                            .truncationMode(.head)
                    }
                    // Si no cabe, se ve el final: es lo que se acaba de decir.
                    Text(frame.current)
                        .italic(frame.currentIsOriginal)
                        .opacity(frame.currentIsOriginal ? 0.7 : 1)
                        .lineLimit(2)
                        .truncationMode(.head)
                }
                .font(.system(size: 28, weight: .semibold))
                .modifier(Banded())
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.easeOut(duration: 0.3), value: model.isVisible)
    }
}

/// Texto blanco centrado sobre el fondo oscuro de la banda.
private struct Banded: ViewModifier {
    func body(content: Content) -> some View {
        content
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }
}
```

- [ ] **Step 4: Ver que pasan**

Run: `make test-app`
Expected: `** TEST SUCCEEDED **`, 49 tests.

- [ ] **Step 5: Commit**

```bash
git add App/Subtitles/SubtitleOverlay.swift AppTests/SubtitleLayoutTests.swift
git commit -m "feat: la banda de subtítulos"
```

---

### Task 8: Historial — guardar las frases y filtrar por origen

**Files:**
- Modify: `App/Store/StoredCard.swift`, `App/Store/CardStore.swift`, `App/UI/HistoryWindow.swift`
- Test: `AppTests/HistoryFilterTests.swift`

**Interfaces:**
- Consumes: `SubtitleLine` (Task 2).
- Produces:
  - `StoredCard.init(subtitle: SubtitleLine)` (convenience; `origin = "system"`)
  - `CardStore.save(subtitle: SubtitleLine)`
  - `enum HistoryFilter: String, CaseIterable, Identifiable { case all, voice, screen, system }`, con `label` y `func includes(origin: String) -> Bool`

- [ ] **Step 1: Escribir los tests que fallan**

`AppTests/HistoryFilterTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
import ParlaCore
@testable import Parla

@Test func cadaFiltroDejaPasarSuOrigen() {
    #expect(HistoryFilter.all.includes(origin: "system"))
    #expect(HistoryFilter.voice.includes(origin: "voice"))
    #expect(!HistoryFilter.voice.includes(origin: "screen"))
    #expect(HistoryFilter.screen.includes(origin: "screen"))
    #expect(HistoryFilter.system.includes(origin: "system"))
    #expect(!HistoryFilter.system.includes(origin: "voice"))
}

@Test func losFiltrosSeLlamanComoEnLaInterfaz() {
    #expect(HistoryFilter.allCases.map(\.label) == ["Todo", "Voz", "Capturas", "Subtítulos"])
}

@Test func guardaUnaFraseDeSubtitulos() async throws {
    let container = try ModelContainer(
        for: StoredCard.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let store = CardStore(modelContainer: container)
    await store.save(subtitle: SubtitleLine(english: "Welcome back", spanish: "Bienvenidos",
                                            spokenAt: Date(timeIntervalSince1970: 5)))

    let stored = try ModelContext(container).fetch(FetchDescriptor<StoredCard>())
    #expect(stored.count == 1)
    #expect(stored.first?.origin == "system")
    #expect(stored.first?.source == "Welcome back")
    #expect(stored.first?.result == "Bienvenidos")
    #expect(stored.first?.why.isEmpty == true)
    #expect(stored.first?.createdAt == Date(timeIntervalSince1970: 5))
}
```

- [ ] **Step 2: Ver que fallan**

Run: `make test-app`
Expected: FAIL de compilación: `cannot find 'HistoryFilter' in scope`.

- [ ] **Step 3: Guardar**

`App/Store/StoredCard.swift`, dentro de `StoredCard`, debajo de `init(capture:card:)`:

```swift
    convenience init(subtitle: SubtitleLine) {
        self.init(id: UUID(),
                  source: subtitle.english,
                  result: subtitle.spanish,
                  why: [],
                  createdAt: subtitle.spokenAt,
                  origin: "system",
                  vocab: [])
    }
```

`App/Store/CardStore.swift`, dentro del actor:

```swift
    func save(subtitle: SubtitleLine) {
        modelContext.insert(StoredCard(subtitle: subtitle))
        try? modelContext.save()
    }
```

- [ ] **Step 4: El filtro y la vista**

En `App/UI/HistoryWindow.swift`, añade al final del archivo:

```swift
/// Una hora de video son cientos de frases: sin filtro taparían las tarjetas
/// de voz y de captura.
enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, voice, screen, system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:    "Todo"
        case .voice:  "Voz"
        case .screen: "Capturas"
        case .system: "Subtítulos"
        }
    }

    /// Los valores de `StoredCard.origin` coinciden con los `rawValue`.
    func includes(origin: String) -> Bool {
        self == .all || rawValue == origin
    }
}
```

En `HistoryView`:
- añade `@State private var filter: HistoryFilter = .all` debajo de `search`;
- sustituye `filtered` por:

```swift
    private var filtered: [StoredCard] {
        let byOrigin = cards.filter { filter.includes(origin: $0.origin) }
        guard !search.isEmpty else { return byOrigin }
        return byOrigin.filter {
            $0.source.localizedStandardContains(search)
                || $0.result.localizedStandardContains(search)
        }
    }
```

- en la fila, sustituye la etiqueta de captura y el resultado:

```swift
                if card.origin == "system" {
                    Text("🎧 Subtítulos").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                } else if let kind = card.kind.flatMap(CaptureKind.init(rawValue:)) {
                    Text(kind.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text("«\(card.source)»").font(.caption).foregroundStyle(.secondary)
                Text(card.result.isEmpty ? "(sin traducción)" : card.result).font(.headline)
```

- después de `.searchable(…)`, añade:

```swift
        .toolbar {
            Picker("Mostrar", selection: $filter) {
                ForEach(HistoryFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
```

- [ ] **Step 5: Ver que pasan**

Run: `make test-app`
Expected: `** TEST SUCCEEDED **`, 52 tests.

- [ ] **Step 6: Commit**

```bash
git add App/Store App/UI/HistoryWindow.swift AppTests/HistoryFilterTests.swift
git commit -m "feat: las frases de los subtítulos van al historial, con filtro por origen"
```

---

### Task 9: Cablear el modo

**Files:**
- Modify: `App/AppState.swift`, `App/ParlaApp.swift`, `App/UI/SettingsView.swift`, `App/UI/PanelView.swift`

**Interfaces:**
- Consumes:
  - `SubtitlePipeline` (Task 3);
  - `SpeechTranscriberEngine(source:locales:logsText:)`, `TranscriberSetupError.screenRecordingDenied` (Task 4);
  - `SystemAudioCapture` (Task 5);
  - `LiveTranslator`, `readiness()`, `notice(for:)` (Task 6);
  - `SubtitleModel`, `SubtitleOverlay` (Task 7);
  - `CardStore.save(subtitle:)` (Task 8).
- Produces:
  - `AppState.isSubtitling`, `toggleSubtitles()`, `stopSubtitles()`, `needsTranslationLanguages`, `subtitleModel`;
  - `KeyboardShortcuts.Name.toggleSubtitles` (⌃⌥S);
  - `PARLA_SUBTITLES_AUTOSTART`.

No hay tests unitarios: `AppState` depende de las ventanas, el audio y el
sistema. Se verifica con los Steps 6 a 8.

- [ ] **Step 1: El modo en `AppState`**

En `App/AppState.swift`, añade al principio de `start()` (la escucha), antes del
`guard let apiKey`:

```swift
        // Los dos modos usan el reconocimiento de voz: uno apaga al otro.
        if isSubtitling { stopSubtitles() }
```

Debajo de `captureError`:

```swift
    private(set) var isSubtitling = false
    /// Los idiomas de traducción no están descargados: el panel ofrece el
    /// botón a Ajustes, porque la banda no se puede pulsar.
    private(set) var needsTranslationLanguages = false
    @ObservationIgnored let subtitleModel = SubtitleModel()
    @ObservationIgnored private var subtitleOverlay: SubtitleOverlay?
    @ObservationIgnored private var subtitleTask: Task<Void, Never>?
    @ObservationIgnored private var subtitleEngine: SpeechTranscriberEngine?
```

Debajo de `openScreenRecordingSettings()`:

```swift
    /// Ajustes del Sistema › General › Idioma y región.
    static func openLanguageSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!
        NSWorkspace.shared.open(url)
    }
```

Una sección nueva antes de `// MARK: - Captura de pantalla`:

```swift
    // MARK: - Subtítulos del sistema

    func toggleSubtitles() {
        isSubtitling ? stopSubtitles() : startSubtitles()
    }

    private func startSubtitles() {
        if isListening { stop() }
        isSubtitling = true
        needsTranslationLanguages = false
        subtitleModel.notice = nil
        subtitleModel.frame = nil
        subtitleModel.isVisible = false
        showSubtitleOverlay()

        subtitleTask = Task {
            let readiness = await LiveTranslator.readiness()
            if let notice = LiveTranslator.notice(for: readiness) {
                subtitleModel.notice = notice
                needsTranslationLanguages = readiness == .needsLanguages
                setupError = notice
                showPanel()
                try? await Task.sleep(for: .seconds(6))
                stopSubtitles()
                return
            }

            let engine = SpeechTranscriberEngine(
                source: SystemAudioCapture(),
                locales: [Locale(identifier: "en-US"), Locale(identifier: "en-GB")],
                logsText: false)
            subtitleEngine = engine
            let downloadWatcher = Task { [weak self] in
                while !Task.isCancelled {
                    if case .downloadingModel(let fraction) = engine.phase {
                        self?.subtitleModel.notice =
                            "Descargando el modelo de inglés… \(Int(fraction * 100)) %"
                    } else if self?.subtitleModel.notice?.hasPrefix("Descargando") == true {
                        self?.subtitleModel.notice = nil
                    }
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
            defer { downloadWatcher.cancel() }

            do {
                try await engine.start()
            } catch TranscriberSetupError.screenRecordingDenied {
                needsScreenRecordingAccess = true
                showPanel()
                stopSubtitles()
                return
            } catch {
                setupError = "No se pudieron encender los subtítulos (\(error))."
                showPanel()
                stopSubtitles()
                return
            }
            Log.pipeline.info("subtítulos encendidos")

            let pipeline = SubtitlePipeline(transcriber: engine, translator: LiveTranslator())
            for await output in pipeline.outputs {
                guard isSubtitling else { break }
                switch output {
                case .show(let frame):
                    subtitleModel.notice = nil
                    subtitleModel.frame = frame
                    subtitleModel.isVisible = true
                case .hide:
                    subtitleModel.isVisible = false
                case .line(let line):
                    Log.pipeline.info("subtítulos: frase guardada")
                    await store.save(subtitle: line)
                }
            }
            // El stream terminó sin que nadie apagara: el audio se cortó y no volvió.
            if isSubtitling {
                setupError = "El audio del sistema se cortó y se apagaron los subtítulos."
                showPanel()
                stopSubtitles()
            }
        }
    }

    func stopSubtitles() {
        guard isSubtitling else { return }
        isSubtitling = false
        subtitleTask?.cancel()
        subtitleTask = nil
        let engine = subtitleEngine
        subtitleEngine = nil
        Task { await engine?.stop() }
        subtitleOverlay?.orderOut(nil)
        subtitleOverlay = nil
        subtitleModel.frame = nil
        subtitleModel.isVisible = false
        Log.pipeline.info("subtítulos apagados")
    }

    /// En la pantalla donde está el ratón al encenderlos.
    private func showSubtitleOverlay() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main
        else { return }
        let overlay = SubtitleOverlay(model: subtitleModel, screen: screen)
        overlay.orderFrontRegardless()
        subtitleOverlay = overlay
    }
```

- [ ] **Step 2: Atajo, menú, icono y arranque automático**

`App/UI/SettingsView.swift`, en la extensión de `KeyboardShortcuts.Name`:

```swift
    static let toggleSubtitles = Self("toggleSubtitles",
                                      initial: .init(.s, modifiers: [.control, .option]))
```

En `Section("Atajo")`, debajo del de capturar:

```swift
                KeyboardShortcuts.Recorder("Mostrar u ocultar subtítulos:", name: .toggleSubtitles)
```

`App/ParlaApp.swift`, en `init()`, debajo del `onKeyUp` de `.captureScreen`:

```swift
        KeyboardShortcuts.onKeyUp(for: .toggleSubtitles) {
            Task { @MainActor in state.toggleSubtitles() }
        }
        if ProcessInfo.processInfo.environment["PARLA_SUBTITLES_AUTOSTART"] == "1" {
            Task { @MainActor in state.toggleSubtitles() }
        }
```

El icono del `MenuBarExtra`:

```swift
            Image(systemName: state.isSubtitling ? "captions.bubble.fill"
                  : state.isListening ? "mic.fill" : "mic")
```

En `MenuBarView.body`, debajo de «Capturar pantalla»:

```swift
        Button(state.isSubtitling ? "Ocultar subtítulos" : "Mostrar subtítulos") {
            state.toggleSubtitles()
        }
```

- [ ] **Step 3: El botón de idiomas en el panel**

`App/UI/PanelView.swift`, debajo del bloque `if state.needsScreenRecordingAccess { … }`:

```swift
                if state.needsTranslationLanguages {
                    Button("Abrir Idioma y región") { AppState.openLanguageSettings() }
                        .controlSize(.small)
                }
```

- [ ] **Step 4: Compilar y tests**

Run: `make test && make test-app`
Expected: Core con 91 tests en verde y `** TEST SUCCEEDED **` en la app.

- [ ] **Step 5: Instalar y permiso**

Run: `make install`. Pide a Edwin que vuelva a conceder Grabación de pantalla.

- [ ] **Step 6: De punta a punta con voz de prueba**

```bash
L=/private/tmp/claude-501/-Users-edwinsandoval-Work-Free/6fcb88aa-8ba8-40a7-aba7-4479d2b39660/scratchpad/subtitulos.log
pkill -f 'Parla.app/Contents/MacOS/Parla'; rm -f "$L"
open -n --env PARLA_SUBTITLES_AUTOSTART=1 --env PARLA_STDERR_LOG=1 --stderr "$L" /Applications/Parla.app
sleep 8
say -v Samantha "Welcome back to the channel. Today we are going to learn how to set up the project."
sleep 6
grep -E "subtítulos|audio del sistema|resultado (final|parcial)" "$L" | tail -8
sqlite3 ~/Library/Containers/app.schoolaid.Parla/Data/Library/Application\ Support/default.store \
  "select ZSOURCE, ZRESULT from ZSTOREDCARD where ZORIGIN='system' order by ZCREATEDAT desc limit 3;"
```

Expected:
- `subtítulos encendidos`;
- `audio del sistema: capturando`;
- `resultado parcial: N caracteres`, sin el texto;
- `subtítulos: frase guardada`;
- y en la base, filas con el inglés dicho y su traducción al español.

Si el modelo de inglés no estaba, primero aparece la descarga: repite el bloque.

Con la herramienta de capturas de computer-use, confirma que la banda se vio
abajo y centrada mientras sonaba `say`.

- [ ] **Step 7: Exclusión y apagado en plena frase**

Con la app del paso anterior abierta:
1. Pulsa el ítem «Empezar a escuchar» con `PARLA_CLICK_MENU`, o pide a Edwin
   ⌃⌥Espacio. En el log debe aparecer `subtítulos apagados` antes de que
   arranque la escucha, y el icono debe cambiar al micrófono.
2. Vuelve a encender los subtítulos. Lanza un `say` largo y, a mitad de frase,
   apaga con ⌃⌥S, o pide a Edwin que lo haga. La banda desaparece, no reaparece
   nada y la app sigue respondiendo (Review Focus 4).

- [ ] **Step 8: Con un video real (Edwin al teclado)**

Pide a Edwin:
1. Un video de YouTube en inglés, en ventana: subtítulos en español mientras
   hablan.
2. El mismo video a pantalla completa: la banda encima.
3. Hacer clic en los controles del video a través de la banda: funcionan.
4. Pausar 5 s: la banda desaparece. Reanudar: vuelve sin la frase vieja arriba.
5. Historial › «Subtítulos»: las frases con su inglés.
6. Monitor de Actividad durante 2 minutos: la CPU de Parla, para el informe.

Anota lo que no se cumpla y arréglalo antes del commit.

- [ ] **Step 9: Commit**

```bash
git add App/AppState.swift App/ParlaApp.swift App/UI/SettingsView.swift App/UI/PanelView.swift
git commit -m "feat: subtítulos del sistema con ⌃⌥S"
```

---

### Task 10: README y verificación final

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: la documentación y la rama lista para revisión.

- [ ] **Step 1: «Cómo funciona» y privacidad**

En la tabla de «Cómo funciona», debajo de «Lectura de capturas»:

```markdown
| Subtítulos del sistema | **En tu Mac.** `SpeechAnalyzer` en inglés y la traducción de Apple, sin conexión |
```

Debajo del párrafo de «Las capturas sí salen»:

```markdown
**Los subtítulos no salen:** el audio del sistema se transcribe y se traduce en
tu Mac. En ese modo no se manda nada a la API.
```

- [ ] **Step 2: Sección de uso**

Debajo de «### Capturar la pantalla»:

```markdown
### Subtítulos de lo que suena

Pulsa **⌃⌥S** (o «Mostrar subtítulos» en el menú de la barra) mientras ves un
video en inglés. Abajo de la pantalla aparece la traducción al español mientras
hablan, encima de cualquier app y también a pantalla completa. Los clics la
atraviesan. Se oculta en los silencios.

Todo pasa en tu Mac: no hay coste ni hace falta conexión. Cada frase queda en el
Historial con su inglés original; el filtro «Subtítulos» las separa de lo demás.

Usa el mismo permiso de Grabación de pantalla que las capturas. Si faltan los
idiomas de traducción, Parla te lleva a Ajustes del Sistema › General › Idioma y
región › Idiomas de traducción. Encender los subtítulos apaga la escucha del
micrófono, y al revés.
```

En «## Requisitos», cambia «macOS 26 o posterior» por «macOS 26.4 o
posterior».

En «## Depuración», en la lista de variables:

```markdown
- `PARLA_SUBTITLES_AUTOSTART=1` enciende los subtítulos al arrancar. Con
  `say -v Samantha "…"` se prueban sin abrir un video.
```

- [ ] **Step 3: Recuentos**

En «## Compilar», cambia los recuentos por los reales de `make test` y
`make test-app`.

- [ ] **Step 4: Verificación final**

Run: `make test && make test-app`
Expected: los dos en verde. Copia las líneas de resumen en el informe.

Recorre la checklist «A mano» del spec (§ 9) y confirma cada punto con lo
observado en la Task 9.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: subtítulos del sistema en el README"
```

---

## Notas para quien ejecute el plan

- **Orden:** 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10. Las Tasks 2 y 3 solo tocan
  Core; de la 4 a la 8 solo App y sin cablear, así que la app sigue funcionando
  igual hasta la 9.
- **La sonda puede parar el plan:** si ScreenCaptureKit no entrega audio en el
  sandbox, es un cambio de spec. No sigas con la Task 5 sin hablarlo.
- **Pasos con Edwin:** conceder el permiso tras cada `make install` (Tasks 1, 4,
  9) y el video real (Task 9, Step 8). Lo demás se hace solo, con `say` como
  audio de prueba.
- **Si `feat/captura` recibe arreglos** de las pruebas a mano, tráelos a esta
  rama antes de la Task 9 (`git merge feat/captura`). Los recuentos de tests
  pueden subir.
- **Si un recuento no coincide,** no lo ajustes a mano: busca qué test falta o
  sobra.
