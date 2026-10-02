# Captura de pantalla — plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un atajo global abre la selección de una región de la pantalla. Parla manda esa imagen a Claude, que decide si hay que traducir, corregir o explicar, y muestra la tarjeta en el panel flotante.

**Architecture:** Lo que tiene lógica de verdad vive en `Core`, que solo importa Foundation y se prueba sin Xcode: los tipos de captura, la petición con imagen, el prompt y la decodificación. `App` pone el resto: la selección de región (`screencapture -i`, o ScreenCaptureKit si el sandbox no lo deja), la reducción de la imagen, la persistencia y la tarjeta. La frontera entre ambos es el protocolo `CaptureExplainer` y el tipo `CaptureCard`.

**Tech Stack:** Swift 6 (concurrencia estricta), swift-testing, SPM + XcodeGen, SwiftData, AppKit/SwiftUI, ImageIO, ScreenCaptureKit (solo en el plan B), KeyboardShortcuts 3.0.1, API de Anthropic vía URLSession.

**Spec:** `docs/superpowers/specs/2026-10-01-captura-de-pantalla-design.md`

## Global Constraints

- Deployment target **macOS 26.0**. `SWIFT_STRICT_CONCURRENCY: complete`.
- **Una sola dependencia externa:** `sindresorhus/KeyboardShortcuts`. No añadir ninguna.
- **`Core` solo importa Foundation.** Nada de SwiftData, AppKit, SwiftUI, Speech, ImageIO ni CoreGraphics en `Core/Sources/ParlaCore`.
- **La API key, solo en el Llavero o en `PARLA_API_KEY`.** Nunca en un archivo del repositorio ni en un test: los tests usan `"sk-test"` o `"k"`.
- Cabeceras: `anthropic-version: 2023-06-01`, `anthropic-beta: server-side-fallback-2026-07-01`, y en el cuerpo `"fallbacks": "default"`.
- **Límites de imagen:** 2576 px de lado largo, **4784 tokens visuales** (`⌈ancho/28⌉ × ⌈alto/28⌉`), **10 MB en base64**.
- Petición de captura: `max_tokens` 16000, `effort: "low"`, system prompt de captura con `cache_control: ephemeral`, imagen antes que el texto.
- **Las peticiones de voz no cambian ni un byte.** Su prefijo está cacheado.
- **La imagen nunca se guarda en disco.** Solo existe el temporal de `screencapture`, que se borra en el acto.
- Textos de interfaz y explicaciones en español. Las traducciones al inglés, en inglés.
- Después de crear un archivo en `App/` o `AppTests/`, `make test-app` y `make build` regeneran el proyecto solos (`xcodegen`). No edites `Parla.xcodeproj`.
- Trabajo en la rama `feat/captura`, creada desde `feat/lote`.

## Review Focus

1. **El atajo se pulsa dos veces con la selección ya abierta.** Se espera una sola cruz y el segundo atajo ignorado. → Paso manual en la Task 10.
2. **El permiso de Grabación de pantalla se concede con Parla abierta.** macOS no lo aplica hasta reabrir la app, así que el aviso tiene que decirlo y no parecer roto. → Texto del aviso y paso manual en la Task 10.
3. **Texto en un tercer idioma (francés).** Se espera `understand` con la traducción al español, no `skip`. → Regla 8 del prompt (Task 2) y la muestra `understand-08-frances` (Task 5).
4. **Una región diminuta** (un clic sin arrastrar, unos pocos píxeles). No debe ampliarse ni romper nada. → Test `unaRegionDiminutaPasaIntacta` (Task 6).
5. **«¿No era eso?» varias veces sobre la misma tarjeta.** El historial debe quedar con una sola fila, con el último caso. → Test `reclasificarVariasVecesDejaUnaSolaFila` (Task 7).

---

## Estructura de archivos

```
Core/
  Package.swift                                   # + executableTarget parla-eval
  Sources/ParlaCore/
    Capture.swift                                 # NUEVO: Capture, CaptureKind, CaptureCard, CaptureExplainer
    CaptureSystemPrompt.swift                     # NUEVO: el prompt de captura
    ClaudeRequestBuilder.swift                    # + makeCaptureRequest, captureInstruction
    ClaudeExplainer.swift                         # + conformidad a CaptureExplainer
  Sources/parla-eval/main.swift                   # NUEVO: make eval-capture
  Fixtures/capturas/
    render.sh                                     # NUEVO: HTML → PNG con Chrome headless
    fuentes/*.html                                # NUEVO: 8 páginas de muestra
    *.png                                         # NUEVO: 8 capturas generadas
  Tests/ParlaCoreTests/
    CaptureTests.swift                            # NUEVO: tipos y prompt
    CaptureRequestTests.swift                     # NUEVO: la petición
    CaptureExplainerTests.swift                   # NUEVO: explainCapture
App/
  CaptureKind+UI.swift                            # NUEVO: etiquetas de los casos
  CardPresentation.swift                          # origen voz | captura
  AppState.swift                                  # captureScreen, reclassify, permiso
  ParlaApp.swift                                  # atajo e ítem de menú
  Capture/ImageDownscaler.swift                   # NUEVO
  Capture/ScreenCapturer.swift                    # NUEVO
  Capture/SelectionOverlay.swift                  # NUEVO solo en el plan B
  Store/StoredCard.swift                          # source/result/origin/kind
  Store/CardStore.swift                           # + save(capture:card:)
  Store/Persistence.swift                         # + makeContainer(_:)
  UI/CardParts.swift                              # NUEVO: esqueleto, viñetas, chips, FlowLayout
  UI/CardView.swift                               # usa CardParts
  UI/CaptureCardView.swift                        # NUEVO
  UI/PanelView.swift                              # aviso de permiso, despacho por origen
  UI/HistoryWindow.swift                          # etiqueta del caso
  UI/SettingsView.swift                           # segundo atajo
AppTests/
  ImageDownscalerTests.swift                      # NUEVO
  ScreenCapturerTests.swift                       # NUEVO
  StoredCardMigrationTests.swift                  # NUEVO
  FlowLayoutTests.swift                           # NUEVO
  CardStoreTests.swift                            # campos renombrados + capturas
  CardOrderingTests.swift                         # voz y capturas mezcladas
Makefile                                          # + eval-capture
README.md                                         # privacidad, uso, depuración
```

---

### Task 1: Sonda — ¿funciona `screencapture` dentro del sandbox?

Es una prueba para responder una pregunta. El código de la sonda se descarta al
final. Lo único que queda es el resultado, escrito en el spec.

**Files:**
- Modify (temporal, se revierte): `App/DebugHooks.swift`
- Modify: `docs/superpowers/specs/2026-10-01-captura-de-pantalla-design.md` (§ 4.1 y § 10)

**Interfaces:**
- Consumes: nada.
- Produces: la decisión **plan A** (Task 8) o **plan B** (Task 8B), y el valor de `ScreenCapturer.cancelStatuses` para el plan A.

- [ ] **Step 1: Crear la rama**

```bash
cd /Users/edwinsandoval/Work/Free/translate
git checkout feat/lote && git checkout -b feat/captura
```

- [ ] **Step 2: Añadir la sonda a `DebugHooks`**

En `App/DebugHooks.swift`, añade `import ScreenCaptureKit` debajo de `import AppKit`. En `install()`, justo después de la línea `if environment["PARLA_PROBE_AUDIO"] == "1" { probeAudio() }`, añade:

```swift
        if let mode = environment["PARLA_PROBE_CAPTURE"] { probeCapture(mode: mode) }
```

Y al final del enum, antes de la llave de cierre:

```swift
    /// SONDA TEMPORAL (Task 1 del plan de captura). Se borra al terminar.
    /// `region`: captura fija sin interacción. `interactive`: la cruz de ⌘⇧4.
    /// `sck`: ScreenCaptureKit, por si hace falta el plan B.
    private static func probeCapture(mode: String) {
        Log.pipeline.info("sonda: permiso de pantalla = \(CGPreflightScreenCaptureAccess())")
        if mode == "sck" {
            Task {
                do {
                    let image = try await SCScreenshotManager.captureImage(
                        in: CGRect(x: 0, y: 0, width: 600, height: 300))
                    Log.pipeline.info("sonda: SCK devolvió \(image.width)×\(image.height)")
                } catch {
                    Log.pipeline.error("sonda: SCK falló: \(error)")
                }
            }
            return
        }
        let file = FileManager.default.temporaryDirectory.appending(path: "sonda.png")
        try? FileManager.default.removeItem(at: file)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = (mode == "interactive" ? ["-i"] : ["-R", "0,0,600,300"])
            + ["-x", "-t", "png", file.path]
        process.terminationHandler = { finished in
            let bytes = (try? Data(contentsOf: file))?.count ?? -1
            Log.pipeline.info("sonda: salida=\(finished.terminationStatus) "
                + "bytes=\(bytes) archivo=\(file.path)")
        }
        do {
            try process.run()
            Log.pipeline.info("sonda: screencapture arrancó")
        } catch {
            Log.pipeline.error("sonda: no arranca: \(error)")
        }
    }
```

- [ ] **Step 3: Instalar**

Run: `make install`
Expected: `Parla instalada en /Applications.`

- [ ] **Step 4: Sonda sin interacción**

Hay que lanzar con `open`, no ejecutando el binario. Si se ejecuta el binario
desde la terminal, macOS atribuye el permiso de pantalla a la Terminal y la
sonda mide lo que no es.

```bash
SONDA=/private/tmp/claude-501/-Users-edwinsandoval-Work-Free/6fcb88aa-8ba8-40a7-aba7-4479d2b39660/scratchpad/sonda.log
pkill -f 'Parla.app/Contents/MacOS/Parla'; rm -f "$SONDA"
open -n --env PARLA_PROBE_CAPTURE=region --env PARLA_STDERR_LOG=1 --stderr "$SONDA" /Applications/Parla.app
sleep 5; cat "$SONDA" | grep sonda
```

Expected: tres líneas `sonda:`. Anota `permiso`, `salida` y `bytes`.

- Si macOS muestra el diálogo de Grabación de pantalla, pide a Edwin que lo
  conceda en Ajustes del Sistema › Privacidad y seguridad › Grabación de
  pantalla. Después, repite este paso.
- Mira la imagen con la herramienta Read en
  `~/Library/Containers/app.schoolaid.Parla/Data/tmp/sonda.png`. Tiene que
  verse el contenido real de la esquina superior izquierda, no solo el fondo de
  escritorio con las ventanas en blanco.

- [ ] **Step 5: Sonda interactiva**

```bash
pkill -f 'Parla.app/Contents/MacOS/Parla'; rm -f "$SONDA"
open -n --env PARLA_PROBE_CAPTURE=interactive --env PARLA_STDERR_LOG=1 --stderr "$SONDA" /Applications/Parla.app
```

Pide a Edwin: «Debería aparecer la cruz de ⌘⇧4. Arrastra un rectángulo sobre
cualquier texto». Luego `cat "$SONDA" | grep sonda` y mira la imagen con Read,
como en el Step 4.

Repite el bloque y esta vez pide a Edwin que **pulse Esc**. Anota la `salida`
de la cancelación y confirma `bytes=-1`.

- [ ] **Step 6: Sonda de ScreenCaptureKit (para el plan B)**

```bash
pkill -f 'Parla.app/Contents/MacOS/Parla'; rm -f "$SONDA"
open -n --env PARLA_PROBE_CAPTURE=sck --env PARLA_STDERR_LOG=1 --stderr "$SONDA" /Applications/Parla.app
sleep 5; cat "$SONDA" | grep sonda
```

Expected: `sonda: SCK devolvió 1200×600` (o el doble de puntos que corresponda en
Retina), o el error que dé.

- [ ] **Step 7: Decidir**

| Resultado | Decisión |
|---|---|
| La cruz aparece, arrastrar deja un PNG con contenido real y Esc no deja archivo | **Plan A** → Task 8. `cancelStatuses` = `[0, <salida de Esc>]` |
| La cruz no aparece, el proceso no arranca, o la imagen sale con ventanas en blanco teniendo el permiso | **Plan B** → Task 8B, en lugar de la Task 8 |

- [ ] **Step 8: Revertir la sonda y escribir el resultado en el spec**

```bash
git checkout App/DebugHooks.swift
pkill -f 'Parla.app/Contents/MacOS/Parla'
```

En el spec, al final de § 4.1, añade un párrafo con la fecha, los valores
anotados y la decisión, por ejemplo:

```markdown
**Resultado de la sonda (2026-10-0X):** desde el sandbox, `screencapture -R`
devolvió un PNG con contenido real (salida 0); `-i` mostró la cruz; Esc
terminó con salida 1 y sin archivo. ScreenCaptureKit también funciona.
**Se usa el plan A.**
```

En § 10, cambia la mitigación de la primera fila por «Resuelto en la sonda:
plan A» (o B).

- [ ] **Step 9: Commit**

```bash
git add docs/superpowers/specs/2026-10-01-captura-de-pantalla-design.md
git commit -m "docs: resultado de la sonda de captura en el sandbox"
```

---

### Task 2: Tipos de captura y system prompt

**Files:**
- Create: `Core/Sources/ParlaCore/Capture.swift`
- Create: `Core/Sources/ParlaCore/CaptureSystemPrompt.swift`
- Test: `Core/Tests/ParlaCoreTests/CaptureTests.swift`

**Interfaces:**
- Consumes: `VocabTerm` (de `Card.swift`), `ExplainerError` (de `Explainer.swift`).
- Produces:
  - `public struct Capture: Sendable, Equatable, Identifiable { id: UUID; imageData: Data; mediaType: String; capturedAt: Date; init(id: UUID = UUID(), imageData:mediaType:capturedAt:) }`
  - `public enum CaptureKind: String, Sendable, Codable, CaseIterable { case understand, correct, translate, skip }`
  - `public struct CaptureCard: Sendable, Equatable, Codable { kind: CaptureKind; source: String; result: String; why: [String]; vocab: [VocabTerm]; init(kind:source:result:why:vocab:) }`
  - `public protocol CaptureExplainer: Sendable { func explainCapture(_ capture: Capture, forcing kind: CaptureKind?) async throws -> CaptureCard }`
  - `public enum CaptureSystemPrompt { public static let text: String }`

- [ ] **Step 1: Escribir los tests que fallan**

`Core/Tests/ParlaCoreTests/CaptureTests.swift`:

```swift
import Testing
import Foundation
@testable import ParlaCore

@Test func laTarjetaDeCapturaSeDecodificaDelEsquema() throws {
    let json = #"{"kind":"understand","source":"Heads up","result":"Ojo","#
        + #""why":["x"],"vocab":[{"term":"heads up","meaning":"ojo"}]}"#
    let card = try JSONDecoder().decode(CaptureCard.self, from: Data(json.utf8))
    #expect(card.kind == .understand)
    #expect(card.result == "Ojo")
    #expect(card.vocab.first?.term == "heads up")
}

@Test func unCasoDesconocidoNoSeDecodifica() {
    // Si el modelo inventara un caso, la tarjeta no puede pintarse: mejor fallar
    // aquí que mostrar algo sin etiqueta.
    let json = #"{"kind":"summarize","source":"","result":"","why":[],"vocab":[]}"#
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(CaptureCard.self, from: Data(json.utf8))
    }
}

@Test func losCasosVanEnElOrdenDelEsquema() {
    #expect(CaptureKind.allCases.map(\.rawValue)
            == ["understand", "correct", "translate", "skip"])
}

@Test func elPromptDeCapturaEsLoBastanteLargoParaCachearse() {
    // Mismo margen que el de la voz: muy por encima del mínimo cacheable.
    #expect(CaptureSystemPrompt.text.count > 4000)
}

@Test func elPromptDeCapturaNombraLosCuatroCasos() {
    for kind in CaptureKind.allCases {
        #expect(CaptureSystemPrompt.text.contains(kind.rawValue))
    }
}
```

- [ ] **Step 2: Ver que fallan**

Run: `make test`
Expected: FAIL de compilación: `cannot find 'CaptureCard' in scope`.

- [ ] **Step 3: Escribir `Capture.swift`**

`Core/Sources/ParlaCore/Capture.swift`:

```swift
import Foundation

/// Una región de la pantalla, ya reducida a lo que el modelo aprovecha.
public struct Capture: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let imageData: Data
    /// `"image/png"` casi siempre; `"image/jpeg"` si el PNG no cabía.
    public let mediaType: String
    /// Ordena la tarjeta en el panel junto a las de voz.
    public let capturedAt: Date

    public init(id: UUID = UUID(), imageData: Data, mediaType: String, capturedAt: Date) {
        self.id = id
        self.imageData = imageData
        self.mediaType = mediaType
        self.capturedAt = capturedAt
    }
}

/// Qué hace la tarjeta con el texto de la captura. El orden es el del `enum`
/// del esquema de salida.
public enum CaptureKind: String, Sendable, Codable, CaseIterable {
    /// Inglés de otra persona: qué significa y qué tiene de no evidente.
    case understand
    /// Inglés escrito por el usuario: la versión corregida y por qué.
    case correct
    /// Español: cómo se dice en inglés y por qué, como la voz.
    case translate
    /// No había texto que procesar.
    case skip
}

/// Lo que Claude devuelve para una captura. La forma coincide con el
/// `json_schema` de `makeCaptureRequest`, así que se decodifica directo.
public struct CaptureCard: Sendable, Equatable, Codable {
    public let kind: CaptureKind
    /// El texto leído en la imagen, sin la interfaz que lo rodea.
    public let source: String
    /// La traducción, la corrección o el inglés. Siempre completo.
    public let result: String
    public let why: [String]
    public let vocab: [VocabTerm]

    public init(kind: CaptureKind, source: String, result: String,
                why: [String], vocab: [VocabTerm]) {
        self.kind = kind
        self.source = source
        self.result = result
        self.why = why
        self.vocab = vocab
    }
}

/// Separado de `Explainer` para que los dobles del pipeline de voz no tengan
/// que implementar algo que no usan.
public protocol CaptureExplainer: Sendable {
    /// Con `forcing == nil` el modelo decide el caso. Nunca devuelve `nil`: un
    /// `skip` vuelve como tarjeta, porque capturar es un gesto explícito y
    /// merece respuesta.
    func explainCapture(_ capture: Capture,
                        forcing kind: CaptureKind?) async throws -> CaptureCard
}
```

- [ ] **Step 4: Escribir `CaptureSystemPrompt.swift`**

`Core/Sources/ParlaCore/CaptureSystemPrompt.swift`. Ningún ejemplo de este prompt
puede repetirse en las muestras de la Task 5.

```swift
public enum CaptureSystemPrompt {
    public static let text = """
    Eres un profesor de inglés para un hispanohablante que está aprendiendo.
    Recibes una captura de una región de su pantalla. Lees el texto que
    contiene, decides qué necesita la persona y devuelves una tarjeta que
    enseña, no que solo traduce.

    QUÉ CASO ES

    Elige kind según lo que ves:

    - translate: el texto está en español. La persona quiere saber cómo se
      dice en inglés. result es el inglés.
    - correct: el texto está en inglés y lo escribió la persona. result es su
      texto corregido. Señales de que lo escribió ella: está en una caja de
      redacción o en un campo con cursor; en un chat, sus burbujas van a la
      derecha o llevan "You" o "Tú"; en un correo, es el borrador que está
      redactando o ella figura como remitente.
    - understand: el texto está en inglés y lo escribió otra persona. result
      es la traducción al español. Es el caso por defecto cuando no hay
      señales de que lo escribiera ella: artículos, páginas web,
      documentación, subtítulos, mensajes recibidos.
    - skip: no hay texto legible, o solo hay cosas que no son lenguaje:
      números sueltos, código, iconos. Un texto corto pero real, como
      "Sounds good", no es skip.

    Si conviven un mensaje de otra persona y un borrador de la persona, el
    caso es correct: corriges el borrador y usas el otro mensaje solo como
    contexto, por ejemplo para ver si la respuesta encaja con lo que le
    preguntaron.

    Si el texto no está ni en español ni en inglés, el caso es understand:
    result es la traducción al español y why puede quedar vacío.

    Si el mensaje del usuario fija el caso, obedécelo aunque las señales
    digan otra cosa.

    REGLAS

    1. source es el texto que lees, tal cual, sin la interfaz que lo rodea:
       nada de menús, nombres de canal, horas ni botones. Si hay varios
       bloques, solo los que importan para el caso elegido. Si una línea está
       cortada por el borde de la captura, transcríbela como se ve.
    2. result va siempre completo: la traducción entera, el texto corregido
       entero o el inglés entero. Nunca un resumen ni puntos suspensivos.
    3. En translate y correct, el inglés es el que escribiría un nativo en esa
       situación, no el literal. Respeta el registro: un mensaje de chat sigue
       siendo informal y un correo de trabajo sigue siendo cortés. En correct
       cambia solo lo que está mal o le suena extraño a un nativo; no
       reescribas el estilo de la persona.
    4. Las explicaciones de why van en español, máximo dos líneas cada una.
       Cada una cubre UNA diferencia concreta y cita el fragmento al que se
       refiere.
    5. Cantidad: si el texto tiene una o dos frases, why tiene entre una y
       tres explicaciones y vocab hasta tres términos. Si es más largo, why
       tiene como mucho cinco y vocab como mucho cinco. Elige lo que más
       enseña, nunca una explicación por frase. Si un error se repite,
       agrúpalo en una sola explicación con su recuento.
    6. Prohibido el metalenguaje vacío. Nunca escribas "suena más natural" o
       "es más común" sin decir a continuación exactamente por qué. Nada de
       elogios.
    7. En correct, si no hay nada que corregir, result es igual a source y why
       va vacío.
    8. En understand, why explica lo que un hispanohablante no deduciría
       palabra por palabra: modismos, phrasal verbs, falsos amigos,
       construcciones que no existen en español, el registro. Lo transparente
       no se explica.
    9. En translate, prioriza el error que un hispanohablante cometería:
       falsos amigos, preposición regida, tiempo verbal, orden de palabras,
       artículos, el subjuntivo que en inglés no existe.
    10. vocab son términos en inglés que vale la pena recordar, con su
        significado breve en español. Si no hay ninguno, lista vacía.
    11. En skip, source y result van vacíos y las listas también.

    EJEMPLOS

    Cada ejemplo describe lo que se ve en la captura y la tarjeta esperada.

    Captura: un chat. En la caja de redacción, con el cursor al final:
    "I am agree with you, we can discuss it in the next meeting"
    kind: correct
    source: I am agree with you, we can discuss it in the next meeting
    result: I agree with you, we can discuss it at the next meeting.
    why:
      - "Agree" ya es un verbo: "I agree". "I am agree" calca "estoy de
        acuerdo".
      - Las reuniones van con "at": "at the next meeting", no "in".
    vocab: vacío

    Captura: un mensaje recibido, a la izquierda, de "Sarah":
    "Heads up — the client pushed the deadline back, so we're off the hook
    until Friday."
    kind: understand
    source: Heads up — the client pushed the deadline back, so we're off the
    hook until Friday.
    result: Aviso: el cliente retrasó la fecha de entrega, así que estamos
    libres hasta el viernes.
    why:
      - "Heads up" abre un aviso: equivale a "para que lo sepas" u "ojo".
      - "Push back" una fecha es retrasarla; adelantarla es "move up".
      - "Off the hook" es quedar libre de una obligación, no "fuera del
        gancho".
    vocab: heads up = aviso, ojo | push back = retrasar | off the hook =
    libre de una obligación

    Captura: arriba, un mensaje recibido: "Can you send me the report before
    the meeting?". Debajo, en la caja de redacción: "Sure, I will send you
    after lunch, I have to finish some things before."
    kind: correct
    source: Sure, I will send you after lunch, I have to finish some things
    before.
    result: Sure, I'll send it to you after lunch. I have to finish a few
    things first.
    why:
      - "Send" necesita decir qué se manda: "send it to you", no "send you" a
        secas.
      - "Before" al final de la frase no funciona como el "antes" español: se
        dice "first".
    vocab: first = antes, primero

    Captura: una nota con el texto "Quedamos mañana a las diez para revisar
    la propuesta, ¿te parece bien?"
    kind: translate
    source: Quedamos mañana a las diez para revisar la propuesta, ¿te parece
    bien?
    result: Let's meet tomorrow at ten to go over the proposal. Does that
    work for you?
    why:
      - "Quedar" con alguien es "meet" o "meet up", nunca "stay".
      - "¿Te parece bien?" es "Does that work for you?": "Does it seem good
        to you?" no se usa.
      - Revisar algo juntos es "go over", no "review", que suena a evaluación
        formal.
    vocab: go over = repasar, revisar | does that work for you? = ¿te viene
    bien?

    Captura: un correo propio en redacción: "Hi John, I write you because I
    have a doubt about the invoice. Yesterday I have received it but the
    amount is not correct. Can you check it? I stay attentive."
    kind: correct
    source: Hi John, I write you because I have a doubt about the invoice.
    Yesterday I have received it but the amount is not correct. Can you check
    it? I stay attentive.
    result: Hi John, I'm writing because I have a question about the invoice.
    I received it yesterday, but the amount isn't right. Could you check it?
    I look forward to hearing from you.
    why:
      - "Duda" es "question": "doubt" expresa desconfianza, no una pregunta.
      - Con un momento terminado ("yesterday") va pasado simple: "I
        received", no "I have received".
      - "Le escribo" es "I'm writing": "I write you" calca el español.
      - "Quedo atento" no se traduce: la fórmula de cierre es "I look forward
        to hearing from you".
    vocab: look forward to = esperar con interés

    Captura: un párrafo de una página web: "Let's circle back on this once
    the dust settles."
    kind: understand
    source: Let's circle back on this once the dust settles.
    result: Retomemos esto cuando las cosas se calmen.
    why:
      - "Circle back" es volver a un tema más adelante; muy común en el
        trabajo.
      - "Once the dust settles" es "cuando pase el revuelo". "Once" aquí es
        "en cuanto", no "una vez".
    vocab: circle back = retomar un tema | once = en cuanto

    Captura: un gráfico de barras sin etiquetas.
    kind: skip, source y result vacíos, listas vacías.
    """
}
```

- [ ] **Step 5: Ver que pasan**

Run: `make test`
Expected: PASS. Son 56 tests: 51 de antes y 5 nuevos.

- [ ] **Step 6: Commit**

```bash
git add Core/Sources/ParlaCore/Capture.swift Core/Sources/ParlaCore/CaptureSystemPrompt.swift Core/Tests/ParlaCoreTests/CaptureTests.swift
git commit -m "feat(core): tipos de captura y su system prompt"
```

---

### Task 3: La petición de captura

**Files:**
- Modify: `Core/Sources/ParlaCore/ClaudeRequestBuilder.swift`
- Test: `Core/Tests/ParlaCoreTests/CaptureRequestTests.swift`

**Interfaces:**
- Consumes: `Capture`, `CaptureKind`, `CaptureSystemPrompt` (Task 2).
- Produces:
  - `ClaudeRequestBuilder.init(model: String = "claude-opus-5-5", maxTokens: Int = 4000, batchMaxTokens: Int = 24000, captureMaxTokens: Int = 16000)`
  - `public let captureMaxTokens: Int`
  - `public static func captureInstruction(forcing kind: CaptureKind?) -> String`
  - `public func makeCaptureRequest(for capture: Capture, forcing kind: CaptureKind?, apiKey: String) throws -> URLRequest`

- [ ] **Step 1: Escribir los tests que fallan**

`Core/Tests/ParlaCoreTests/CaptureRequestTests.swift`:

```swift
import Testing
import Foundation
@testable import ParlaCore

private func body(of request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}

private func content(of json: [String: Any]) throws -> [[String: Any]] {
    let messages = try #require(json["messages"] as? [[String: Any]])
    #expect(messages.count == 1)
    return try #require(messages.first?["content"] as? [[String: Any]])
}

/// Los cuatro primeros bytes de un PNG: "iVBORw==" en base64.
private let capture = Capture(imageData: Data([0x89, 0x50, 0x4E, 0x47]),
                              mediaType: "image/png",
                              capturedAt: Date(timeIntervalSince1970: 0))

private func captureRequest(forcing kind: CaptureKind? = nil) throws -> URLRequest {
    try ClaudeRequestBuilder().makeCaptureRequest(for: capture, forcing: kind, apiKey: "k")
}

@Test func laImagenVaPrimeroYEnBase64() throws {
    let blocks = try content(of: body(of: captureRequest()))
    #expect(blocks.count == 2)
    #expect(blocks[0]["type"] as? String == "image")
    let source = try #require(blocks[0]["source"] as? [String: Any])
    #expect(source["type"] as? String == "base64")
    #expect(source["media_type"] as? String == "image/png")
    #expect(source["data"] as? String == "iVBORw==")
    #expect(blocks[1]["type"] as? String == "text")
}

@Test func sinForzarDejaQueDecidaElModelo() throws {
    let blocks = try content(of: body(of: captureRequest()))
    #expect(blocks[1]["text"] as? String == "Decide tú el caso.")
}

@Test func forzarUnCasoLoDiceEnElTexto() throws {
    let blocks = try content(of: body(of: captureRequest(forcing: .correct)))
    let text = try #require(blocks[1]["text"] as? String)
    #expect(text.contains("El caso es correct."))
}

@Test func forzarSkipEsComoNoForzar() {
    #expect(ClaudeRequestBuilder.captureInstruction(forcing: .skip)
            == ClaudeRequestBuilder.captureInstruction(forcing: nil))
}

@Test func usaElPromptDeCapturaCacheado() throws {
    let system = try #require(body(of: captureRequest())["system"] as? [[String: Any]])
    #expect(system[0]["text"] as? String == CaptureSystemPrompt.text)
    let cache = try #require(system[0]["cache_control"] as? [String: Any])
    #expect(cache["type"] as? String == "ephemeral")
}

@Test func elEsquemaDeCapturaTieneLosCuatroCasos() throws {
    let json = try body(of: captureRequest())
    let output = try #require(json["output_config"] as? [String: Any])
    let format = try #require(output["format"] as? [String: Any])
    let schema = try #require(format["schema"] as? [String: Any])
    let required = try #require(schema["required"] as? [String])
    #expect(Set(required) == ["kind", "source", "result", "why", "vocab"])
    #expect(schema["additionalProperties"] as? Bool == false)
    let properties = try #require(schema["properties"] as? [String: Any])
    let kind = try #require(properties["kind"] as? [String: Any])
    #expect(kind["enum"] as? [String] == ["understand", "correct", "translate", "skip"])
}

@Test func laCapturaTieneMasPresupuestoYElMismoEsfuerzo() throws {
    let request = try captureRequest()
    let json = try body(of: request)
    #expect(json["max_tokens"] as? Int == 16000)
    #expect(json["model"] as? String == "claude-opus-5-5")
    #expect(json["stream"] as? Bool == true)
    #expect(json["fallbacks"] as? String == "default")
    let output = try #require(json["output_config"] as? [String: Any])
    #expect(output["effort"] as? String == "low")
    #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
}

@Test func laCapturaNoUsaPalabrasClaveQueLaAPIRechaza() throws {
    let raw = String(data: try #require(captureRequest().httpBody), encoding: .utf8) ?? ""
    #expect(!raw.contains("maxItems"))
    #expect(!raw.contains("minItems"))
}

@Test func laCapturaExigeApiKey() {
    #expect(throws: ExplainerError.missingAPIKey) {
        try ClaudeRequestBuilder().makeCaptureRequest(for: capture, forcing: nil, apiKey: "")
    }
}
```

- [ ] **Step 2: Ver que fallan**

Run: `make test`
Expected: FAIL de compilación: `value of type 'ClaudeRequestBuilder' has no member 'makeCaptureRequest'`.

- [ ] **Step 3: Implementar**

En `Core/Sources/ParlaCore/ClaudeRequestBuilder.swift`:

1. Añade la propiedad y el parámetro del `init`:

```swift
    /// Un correo largo corregido, con su explicación y el razonamiento, no cabe
    /// en el presupuesto de una frase.
    public let captureMaxTokens: Int

    public init(model: String = "claude-opus-5-5",
                maxTokens: Int = 4000,
                batchMaxTokens: Int = 24000,
                captureMaxTokens: Int = 16000) {
        self.model = model
        self.maxTokens = maxTokens
        self.batchMaxTokens = batchMaxTokens
        self.captureMaxTokens = captureMaxTokens
    }
```

2. Sustituye `cardProperties` para que `why` y `vocab` salgan de un solo sitio, y
   añade el esquema de captura debajo de `batchSchema`:

```swift
    /// `why` y `vocab` son iguales en la voz y en la captura: si divergieran, la
    /// UI tendría que pintar dos formas de lo mismo.
    private static var whySchema: [String: Any] {
        ["type": "array", "items": ["type": "string"]]
    }

    private static var vocabSchema: [String: Any] {
        [
            "type": "array",
            "items": [
                "type": "object",
                "properties": [
                    "term": ["type": "string"],
                    "meaning": ["type": "string"],
                ],
                "required": ["term", "meaning"],
                "additionalProperties": false,
            ],
        ]
    }

    /// Los campos de una tarjeta, compartidos por los dos esquemas para que no
    /// puedan divergir.
    private var cardProperties: [String: Any] {
        [
            "english": ["type": "string"],
            "why": Self.whySchema,
            "vocab": Self.vocabSchema,
            "skip": ["type": "boolean"],
        ]
    }
```

```swift
    /// El esquema de una captura. Coincide con `CaptureCard`.
    private var captureSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "kind": ["type": "string", "enum": CaptureKind.allCases.map(\.rawValue)],
                "source": ["type": "string"],
                "result": ["type": "string"],
                "why": Self.whySchema,
                "vocab": Self.vocabSchema,
            ],
            "required": ["kind", "source", "result", "why", "vocab"],
            "additionalProperties": false,
        ]
    }
```

3. Generaliza `payload` sin cambiar lo que mandan la voz y el lote:

```swift
    private func payload(system: String = SystemPrompt.text,
                         content: Any,
                         schema: [String: Any],
                         maxTokens: Int) -> [String: Any] {
        [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            // Si un clasificador declina la frase, la API reintenta sola.
            "fallbacks": "default",
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": schema],
            ],
            "system": [[
                "type": "text",
                "text": system,
                "cache_control": ["type": "ephemeral"],
            ]],
            "messages": [["role": "user", "content": content]],
        ]
    }
```

   (El comentario de `payload` sobre el bloque `system` compartido por los dos
   modos se queda como está, porque sigue siendo cierto para la voz.)

4. Al final del struct, después de `makeBatchRequest`:

```swift
    /// El texto que acompaña a la imagen. Forzar `.skip` no tiene sentido y la
    /// UI no lo ofrece: si llega, decide el modelo, igual que con `nil`.
    public static func captureInstruction(forcing kind: CaptureKind?) -> String {
        switch kind {
        case .correct?:
            "El usuario indica que este texto lo escribió él. El caso es correct."
        case .understand?:
            "El usuario indica que este texto no lo escribió él y quiere entenderlo. "
                + "El caso es understand."
        case .translate?:
            "El usuario quiere saber cómo se dice este texto en inglés. El caso es translate."
        case .skip?, nil:
            "Decide tú el caso."
        }
    }

    /// La imagen va antes que el texto, que es el orden que la documentación de
    /// visión recomienda. El system prompt es el de captura y tiene su propia
    /// caché: no comparte prefijo con el de la voz.
    public func makeCaptureRequest(for capture: Capture,
                                   forcing kind: CaptureKind?,
                                   apiKey: String) throws -> URLRequest {
        let content: [[String: Any]] = [
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": capture.mediaType,
                    "data": capture.imageData.base64EncodedString(),
                ],
            ],
            ["type": "text", "text": Self.captureInstruction(forcing: kind)],
        ]
        return try request(payload(system: CaptureSystemPrompt.text,
                                   content: content,
                                   schema: captureSchema,
                                   maxTokens: captureMaxTokens),
                           apiKey: apiKey)
    }
```

- [ ] **Step 4: Ver que pasan, también los de la voz**

Run: `make test`
Expected: PASS, 65 tests. Los 8 de `ClaudeRequestBuilderTests` siguen en verde,
lo que confirma que la petición de voz no cambió.

- [ ] **Step 5: Commit**

```bash
git add Core/Sources/ParlaCore/ClaudeRequestBuilder.swift Core/Tests/ParlaCoreTests/CaptureRequestTests.swift
git commit -m "feat(core): petición de captura con imagen y caso forzado"
```

---

### Task 4: `explainCapture`

**Files:**
- Modify: `Core/Sources/ParlaCore/ClaudeExplainer.swift`
- Test: `Core/Tests/ParlaCoreTests/CaptureExplainerTests.swift`

**Interfaces:**
- Consumes: `makeCaptureRequest(for:forcing:apiKey:)` (Task 3), `CaptureExplainer`, `CaptureCard` (Task 2), `FakeStreamer`, `ScriptedStreamer` y `sseLines(forJSON:stopReason:)` (de `Fakes.swift`).
- Produces: `extension ClaudeExplainer: CaptureExplainer`, con `explainCapture(_:forcing:)`.

- [ ] **Step 1: Escribir los tests que fallan**

`Core/Tests/ParlaCoreTests/CaptureExplainerTests.swift`:

```swift
import Testing
import Foundation
@testable import ParlaCore

private let capture = Capture(imageData: Data([1, 2, 3]),
                              mediaType: "image/png",
                              capturedAt: Date(timeIntervalSince1970: 0))

private let correctJSON = #"{"kind":"correct","source":"I am agree","#
    + #""result":"I agree.","why":["\"Agree\" ya es verbo."],"vocab":[]}"#

private func explainer(_ streamer: any HTTPStreamer, apiKey: String = "sk-test") -> ClaudeExplainer {
    ClaudeExplainer(streamer: streamer, builder: ClaudeRequestBuilder(), apiKey: apiKey)
}

/// El texto que acompaña a la imagen en la petición.
private func instruction(of request: URLRequest) -> String? {
    guard let data = request.httpBody,
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let messages = root["messages"] as? [[String: Any]],
          let content = messages.first?["content"] as? [[String: Any]]
    else { return nil }
    return content.last?["text"] as? String
}

@Test func devuelveLaTarjetaDeCaptura() async throws {
    let card = try await explainer(FakeStreamer(lines: sseLines(forJSON: correctJSON)))
        .explainCapture(capture, forcing: nil)
    #expect(card.kind == .correct)
    #expect(card.result == "I agree.")
    #expect(card.why.count == 1)
}

@Test func unSkipVuelveComoTarjetaNoComoNil() async throws {
    let json = #"{"kind":"skip","source":"","result":"","why":[],"vocab":[]}"#
    let card = try await explainer(FakeStreamer(lines: sseLines(forJSON: json)))
        .explainCapture(capture, forcing: nil)
    #expect(card.kind == .skip)
}

@Test func unCasoDesconocidoEsRespuestaMalformada() async {
    let json = #"{"kind":"summarize","source":"","result":"","why":[],"vocab":[]}"#
    await #expect(throws: ExplainerError.malformedResponse) {
        try await explainer(FakeStreamer(lines: sseLines(forJSON: json)))
            .explainCapture(capture, forcing: nil)
    }
}

@Test func laCapturaDetectaElRechazo() async {
    let lines = sseLines(forJSON: correctJSON, stopReason: "refusal")
    await #expect(throws: ExplainerError.refused) {
        try await explainer(FakeStreamer(lines: lines)).explainCapture(capture, forcing: nil)
    }
}

@Test func laCapturaDistingueElRateLimit() async {
    await #expect(throws: ExplainerError.rateLimited) {
        try await explainer(FakeStreamer(statusCode: 429)).explainCapture(capture, forcing: nil)
    }
}

@Test func laCapturaFallaLimpioSiElStreamSeCorta() async {
    let truncated = [
        #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
        #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"{\"kind\":\"cor"}}"#,
    ]
    await #expect(throws: ExplainerError.malformedResponse) {
        try await explainer(FakeStreamer(lines: truncated)).explainCapture(capture, forcing: nil)
    }
}

@Test func laCapturaExigeApiKeyAntesDeTocarLaRed() async {
    await #expect(throws: ExplainerError.missingAPIKey) {
        try await explainer(FakeStreamer(lines: []), apiKey: "").explainCapture(capture, forcing: nil)
    }
}

@Test func elCasoForzadoLlegaALaPeticion() async throws {
    let streamer = ScriptedStreamer { _ in (200, sseLines(forJSON: correctJSON)) }
    _ = try await explainer(streamer).explainCapture(capture, forcing: .understand)
    let request = try #require(streamer.requests.first)
    #expect(instruction(of: request)?.contains("El caso es understand.") == true)
}
```

- [ ] **Step 2: Ver que fallan**

Run: `make test`
Expected: FAIL de compilación: `value of type 'ClaudeExplainer' has no member 'explainCapture'`.

- [ ] **Step 3: Implementar**

Al final de `Core/Sources/ParlaCore/ClaudeExplainer.swift`, en el mismo archivo
para poder usar `streamJSON`, `builder` y `apiKey`, que son `private`:

```swift
// MARK: - Captura

extension ClaudeExplainer: CaptureExplainer {
    public func explainCapture(_ capture: Capture,
                               forcing kind: CaptureKind?) async throws -> CaptureCard {
        let request = try builder.makeCaptureRequest(for: capture, forcing: kind, apiKey: apiKey)
        let json = try await streamJSON(request)

        guard let data = json.data(using: .utf8),
              let card = try? JSONDecoder().decode(CaptureCard.self, from: data)
        else { throw ExplainerError.malformedResponse }

        return card
    }
}
```

- [ ] **Step 4: Ver que pasan**

Run: `make test`
Expected: PASS, 73 tests.

- [ ] **Step 5: Commit**

```bash
git add Core/Sources/ParlaCore/ClaudeExplainer.swift Core/Tests/ParlaCoreTests/CaptureExplainerTests.swift
git commit -m "feat(core): explicar una captura con el mismo cliente SSE"
```

---

### Task 5: Evaluación de la detección (`make eval-capture`)

Ocho capturas de muestra, generadas desde HTML para que se puedan regenerar, y un
ejecutable que le pasa cada una a la API y cuenta los aciertos del caso.

**Files:**
- Modify: `Core/Package.swift`, `Makefile`
- Create: `Core/Sources/parla-eval/main.swift`
- Create: `Core/Fixtures/capturas/render.sh`, `Core/Fixtures/capturas/fuentes/*.html` (8), `Core/Fixtures/capturas/*.png` (8, generadas)

**Interfaces:**
- Consumes: `ClaudeExplainer.explainCapture(_:forcing:)` (Task 4), `ClaudeRequestBuilder(model:)`, `Capture`, `CaptureKind`.
- Produces: `make eval-capture`, que imprime `Acierto: n/8`.

- [ ] **Step 1: Declarar el ejecutable**

`Core/Package.swift`, en `targets`:

```swift
    targets: [
        .target(name: "ParlaCore"),
        // `make eval-capture`: manda las capturas de muestra a la API real. Gasta
        // tokens, por eso no es un test.
        .executableTarget(name: "parla-eval", dependencies: ["ParlaCore"]),
        .testTarget(name: "ParlaCoreTests", dependencies: ["ParlaCore"]),
    ]
```

- [ ] **Step 2: Escribir el ejecutable**

`Core/Sources/parla-eval/main.swift`:

```swift
import Foundation
import ParlaCore

// Uso: PARLA_API_KEY=… swift run parla-eval <carpeta>
// El caso esperado va al principio del nombre: correct-03-borrador.png.
// PARLA_MODEL cambia el modelo (por defecto, el de la app).

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    print("uso: parla-eval <carpeta con capturas>")
    exit(2)
}
guard let apiKey = ProcessInfo.processInfo.environment["PARLA_API_KEY"], !apiKey.isEmpty else {
    print("Falta PARLA_API_KEY.")
    exit(2)
}
let model = ProcessInfo.processInfo.environment["PARLA_MODEL"] ?? "claude-opus-5-5"

let folder = URL(fileURLWithPath: arguments[1])
let files = try FileManager.default
    .contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    .filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

let explainer = ClaudeExplainer(builder: ClaudeRequestBuilder(model: model), apiKey: apiKey)
print("Modelo: \(model) — \(files.count) capturas\n")

var hits = 0
for file in files {
    let name = file.lastPathComponent
    let expected = name.split(separator: "-").first.flatMap { CaptureKind(rawValue: String($0)) }
    let mediaType = file.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
    let capture = Capture(imageData: try Data(contentsOf: file),
                          mediaType: mediaType,
                          capturedAt: Date())
    do {
        let card = try await explainer.explainCapture(capture, forcing: nil)
        let ok = card.kind == expected
        if ok { hits += 1 }
        print("\(ok ? "✓" : "✗") \(name): esperado \(expected?.rawValue ?? "?"), "
              + "eligió \(card.kind.rawValue)")
        print("   source: \(card.source)")
        print("   result: \(card.result)")
        for line in card.why { print("   • \(line)") }
        if !card.vocab.isEmpty {
            print("   vocab: " + card.vocab.map { "\($0.term) = \($0.meaning)" }
                .joined(separator: " | "))
        }
    } catch {
        print("✗ \(name): \(error)")
    }
    print("")
}
print("Acierto: \(hits)/\(files.count)")
```

- [ ] **Step 3: Comprobar que compila y que `make test` sigue igual**

Run: `cd Core && swift build --product parla-eval && cd .. && make test`
Expected: `Build complete!` y luego PASS, 73 tests.

- [ ] **Step 4: Escribir las ocho páginas de muestra**

Ninguna repite un texto de los ejemplos del prompt (Task 2).

`Core/Fixtures/capturas/fuentes/understand-01-articulo.html`:

```html
<!doctype html><meta charset="utf-8">
<style>body{margin:0;padding:40px 60px;font:19px/1.6 Georgia,serif;color:#222;background:#fff}
h1{font:700 30px/1.2 -apple-system,Helvetica,sans-serif;margin:0 0 18px}</style>
<h1>The future of the office</h1>
<p>Remote work isn't going anywhere. Companies that dragged their feet on flexible
policies are now scrambling to catch up, while the ones that got ahead of the curve
are reaping the benefits.</p>
```

`Core/Fixtures/capturas/fuentes/understand-02-mensaje-recibido.html`:

```html
<!doctype html><meta charset="utf-8">
<style>body{margin:0;font:15px -apple-system,Helvetica,sans-serif;color:#1d1c1d;background:#fff}
.top{padding:12px 20px;border-bottom:1px solid #ddd;font-weight:700}
.msg{display:flex;gap:10px;padding:16px 20px}.av{width:36px;height:36px;border-radius:6px;background:#2eb67d}
.name{font-weight:700}.time{color:#888;font-size:12px;margin-left:6px}
.compose{position:absolute;left:20px;right:20px;bottom:20px;border:1px solid #bbb;border-radius:8px;padding:12px;color:#999}</style>
<div class="top"># proyecto-web</div>
<div class="msg"><div class="av"></div><div><span class="name">Mike</span><span class="time">10:42 AM</span>
<div>No worries if you can't make it today — we can touch base tomorrow and figure out the next steps.</div></div></div>
<div class="compose">Message #proyecto-web</div>
```

`Core/Fixtures/capturas/fuentes/correct-03-borrador.html`:

```html
<!doctype html><meta charset="utf-8">
<style>body{margin:0;font:15px -apple-system,Helvetica,sans-serif;color:#1d1c1d;background:#fff}
.top{padding:12px 20px;border-bottom:1px solid #ddd;font-weight:700}
.compose{position:absolute;left:20px;right:20px;bottom:20px;border:1px solid #888;border-radius:8px;padding:12px}
.caret{display:inline-block;width:1px;height:18px;background:#1d1c1d;vertical-align:middle}</style>
<div class="top">Laura Gómez — Direct message</div>
<div class="compose">Thanks for your help, I will be very grateful if you can explain me how to configure it.<span class="caret"></span></div>
```

`Core/Fixtures/capturas/fuentes/correct-04-respuesta-con-contexto.html`:

```html
<!doctype html><meta charset="utf-8">
<style>body{margin:0;font:15px -apple-system,Helvetica,sans-serif;color:#1d1c1d;background:#fff}
.top{padding:12px 20px;border-bottom:1px solid #ddd;font-weight:700}
.msg{display:flex;gap:10px;padding:16px 20px}.av{width:36px;height:36px;border-radius:6px;background:#e01e5a}
.name{font-weight:700}.time{color:#888;font-size:12px;margin-left:6px}
.compose{position:absolute;left:20px;right:20px;bottom:20px;border:1px solid #888;border-radius:8px;padding:12px}
.caret{display:inline-block;width:1px;height:18px;background:#1d1c1d;vertical-align:middle}</style>
<div class="top">Tom Becker — Direct message</div>
<div class="msg"><div class="av"></div><div><span class="name">Tom Becker</span><span class="time">2:51 PM</span>
<div>Hey, are you joining the call at 3?</div></div></div>
<div class="compose">Yes, but maybe I arrive 5 minutes late because I am in other meeting.<span class="caret"></span></div>
```

`Core/Fixtures/capturas/fuentes/correct-05-correo-propio.html`:

```html
<!doctype html><meta charset="utf-8">
<style>body{margin:0;font:14px -apple-system,Helvetica,sans-serif;color:#222;background:#fff}
.bar{background:#ececec;padding:10px 16px;font-weight:600;border-bottom:1px solid #d0d0d0}
.row{padding:8px 16px;border-bottom:1px solid #e5e5e5;color:#666}.row b{color:#222;font-weight:400}
.body{padding:16px;line-height:1.6}</style>
<div class="bar">New Message</div>
<div class="row">To: <b>Ms. Taylor &lt;s.taylor@acme.com&gt;</b></div>
<div class="row">From: <b>Edwin Sandoval</b></div>
<div class="row">Subject: <b>Training on Monday</b></div>
<div class="body">Dear Ms. Taylor,<br><br>I am writing to inform you that I will not can attend the training
on Monday. I have a medical appointment since two weeks and I cannot change it. Please let me
know if exist another date.<br><br>Best regards,<br>Edwin</div>
```

`Core/Fixtures/capturas/fuentes/translate-06-espanol.html`:

```html
<!doctype html><meta charset="utf-8">
<style>body{margin:0;font:17px/1.5 -apple-system,Helvetica,sans-serif;color:#222;background:#fffdf4}
.head{background:#f7d64a;padding:10px 18px;font-weight:600}.text{padding:22px 24px}</style>
<div class="head">Notas</div>
<div class="text">Avísame cuando llegues al aeropuerto y te paso a buscar. Si se retrasa el vuelo, no te preocupes, me escribes y lo vemos.</div>
```

`Core/Fixtures/capturas/fuentes/skip-07-sin-texto.html`:

```html
<!doctype html><meta charset="utf-8">
<style>body{margin:0;height:100vh;background:linear-gradient(135deg,#1e3c72,#2a5298)}
.c{position:absolute;border-radius:50%;opacity:.7}</style>
<div class="c" style="left:120px;top:90px;width:180px;height:180px;background:#ff9a8b"></div>
<div class="c" style="left:420px;top:160px;width:240px;height:240px;background:#a8e6cf"></div>
<div class="c" style="left:700px;top:60px;width:120px;height:120px;background:#ffd3b6"></div>
```

`Core/Fixtures/capturas/fuentes/understand-08-frances.html`:

```html
<!doctype html><meta charset="utf-8">
<style>body{margin:0;padding:30px;font:16px -apple-system,Helvetica,sans-serif;background:#fff}
.who{color:#888;font-size:12px;margin:0 0 4px 12px}
.bubble{display:inline-block;max-width:60%;background:#e9e9eb;border-radius:18px;padding:10px 14px}</style>
<div class="who">Claire</div>
<div class="bubble">Je suis désolée, je ne pourrai pas venir ce soir. On remet ça à la semaine prochaine ?</div>
```

- [ ] **Step 5: Script para generar las capturas**

`Core/Fixtures/capturas/render.sh`:

```bash
#!/bin/bash
# Regenera las capturas de muestra a partir de las páginas de fuentes/.
# Escala 2 para que se parezcan a una captura de una pantalla Retina.
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for html in fuentes/*.html; do
  name=$(basename "$html" .html)
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=2 --window-size=900,500 \
    --screenshot="$PWD/$name.png" "file://$PWD/$html" >/dev/null 2>&1
  echo "$name.png"
done
```

Run:

```bash
chmod +x Core/Fixtures/capturas/render.sh && Core/Fixtures/capturas/render.sh
```

Expected: 8 líneas `*.png`. Mira dos o tres con la herramienta Read para
confirmar que el texto se lee y que la caja de redacción se distingue del mensaje
recibido.

- [ ] **Step 6: Target de Make**

En `Makefile`, añade `eval-capture` a `.PHONY` y debajo de `test-app`:

```makefile
# Manda las capturas de Core/Fixtures/capturas a la API real y cuenta cuántas
# veces acierta el caso. Necesita PARLA_API_KEY y gasta tokens: no es un test.
eval-capture:
	cd Core && swift run parla-eval Fixtures/capturas
```

- [ ] **Step 7: Primera medición**

Son 8 peticiones con Opus 5.5, unos 20 a 40 centavos de dólar. Antes de lanzarla,
pide a Edwin la clave o que la exporte él.

Run: `PARLA_API_KEY=… make eval-capture`
Expected: termina con `Acierto: n/8`. Anota el resultado en el mensaje del
commit.

- Si `n < 7`: no cambies código en esta tarea. Anota qué casos fallan y
  avísalo al terminar. Las palancas están en § 10 del spec, y decidir cuál usar
  es una conversación con Edwin.
- Lee también las explicaciones: tienen que cumplir las reglas del prompt (en
  español, una diferencia por punto, sin metalenguaje vacío).

- [ ] **Step 8: Commit**

```bash
git add Core/Package.swift Core/Sources/parla-eval Core/Fixtures Makefile
git commit -m "feat(core): make eval-capture con ocho capturas de muestra

Primera medición con claude-opus-5-5: n/8."
```

---

### Task 6: `ImageDownscaler`

**Files:**
- Create: `App/Capture/ImageDownscaler.swift`
- Test: `AppTests/ImageDownscalerTests.swift`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `enum ImageDownscaler` con `static let maxLongEdge = 2576`, `static let maxVisualTokens = 4784`, `static let maxBase64Bytes = 10_000_000`
  - `enum Failure: Error, Equatable { case unreadable, tooLarge }`
  - `struct Prepared: Equatable { let data: Data; let mediaType: String }`
  - `static func visualTokens(width: Int, height: Int) -> Int`
  - `static func fittedSize(width: Int, height: Int) -> (width: Int, height: Int)`
  - `static func prepare(_ imageData: Data, maxBase64Bytes: Int = maxBase64Bytes) throws -> Prepared`
  - `static func encode(_ image: CGImage, as type: UTType, quality: Double? = nil) throws -> Data` (lo usa el plan B)

- [ ] **Step 1: Escribir los tests que fallan**

`AppTests/ImageDownscalerTests.swift`:

```swift
import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Parla

/// Una imagen de prueba: un rectángulo negro sobre blanco, o ruido, que no
/// comprime y sirve para forzar tamaños grandes.
private func image(width: Int, height: Int, noise: Bool = false, type: UTType = .png) -> Data {
    let context = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if noise {
        let count = context.bytesPerRow * height
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: count)
        for index in 0 ..< count { pixels[index] = UInt8.random(in: 0 ... 255) }
    } else {
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: max(1, height / 8)))
    }
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

private func pixelSize(of data: Data) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    return (image.width, image.height)
}

@Test func losTokensSonParchesDe28() {
    #expect(ImageDownscaler.visualTokens(width: 1000, height: 1000) == 1296)
    #expect(ImageDownscaler.visualTokens(width: 2576, height: 1449) == 4784)
}

@Test func unaImagenGrandeCabeEnAmbosLimites() {
    let size = ImageDownscaler.fittedSize(width: 4000, height: 3000)
    #expect(max(size.width, size.height) <= 2576)
    let tokens = ImageDownscaler.visualTokens(width: size.width, height: size.height)
    #expect(tokens <= 4784)
    // Que quepa no basta: tampoco puede encogerse de más y perder legibilidad.
    #expect(tokens > 4500)
    #expect(abs(Double(size.width) / Double(size.height) - 4.0 / 3.0) < 0.01)
}

@Test func nuncaAmplia() {
    let size = ImageDownscaler.fittedSize(width: 100, height: 50)
    #expect(size.width == 100 && size.height == 50)
}

@Test func unPNGPequenoPasaSinTocar() throws {
    let original = image(width: 800, height: 200)
    let prepared = try ImageDownscaler.prepare(original)
    #expect(prepared.data == original)
    #expect(prepared.mediaType == "image/png")
}

@Test func unaRegionDiminutaPasaIntacta() throws {
    // Un clic sin arrastrar puede dejar una región de unos pocos píxeles.
    let original = image(width: 4, height: 4)
    let prepared = try ImageDownscaler.prepare(original)
    #expect(prepared.data == original)
}

@Test func reduceDeVerdadLaImagen() throws {
    let prepared = try ImageDownscaler.prepare(image(width: 4000, height: 3000))
    let size = try #require(pixelSize(of: prepared.data))
    let expected = ImageDownscaler.fittedSize(width: 4000, height: 3000)
    #expect(size.width == expected.width && size.height == expected.height)
    #expect(prepared.mediaType == "image/png")
}

@Test func unJPEGSeConvierteAPNG() throws {
    let prepared = try ImageDownscaler.prepare(image(width: 300, height: 100, type: .jpeg))
    #expect(prepared.mediaType == "image/png")
    #expect(pixelSize(of: prepared.data)?.width == 300)
}

@Test func siElPNGNoCabeSeRecodificaComoJPEG() throws {
    // El ruido no comprime en PNG; en JPEG sí. El límite se pone entre los dos
    // tamaños medidos, no adivinados.
    let original = image(width: 600, height: 600, noise: true)
    let source = try #require(CGImageSourceCreateWithData(original as CFData, nil))
    let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let jpegSize = ImageDownscaler.base64Size(
        try ImageDownscaler.encode(decoded, as: .jpeg, quality: 0.9))
    let pngSize = ImageDownscaler.base64Size(original)
    try #require(jpegSize < pngSize)
    let limit = (jpegSize + pngSize) / 2
    let prepared = try ImageDownscaler.prepare(original, maxBase64Bytes: limit)
    #expect(prepared.mediaType == "image/jpeg")
    #expect(ImageDownscaler.base64Size(prepared.data) <= limit)
}

@Test func siNiElJPEGCabeFalla() {
    #expect(throws: ImageDownscaler.Failure.tooLarge) {
        try ImageDownscaler.prepare(image(width: 100, height: 100), maxBase64Bytes: 10)
    }
}

@Test func unosBytesQueNoSonImagenFallan() {
    #expect(throws: ImageDownscaler.Failure.unreadable) {
        try ImageDownscaler.prepare(Data("hola".utf8))
    }
}
```

- [ ] **Step 2: Ver que fallan**

Run: `make test-app`
Expected: FAIL de compilación: `cannot find 'ImageDownscaler' in scope`.

- [ ] **Step 3: Implementar**

`App/Capture/ImageDownscaler.swift`:

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Deja la captura en lo que el modelo aprovecha. Lo que pase de ahí, la API lo
/// reduce igual: mandarlo es pagar bytes y latencia por nada.
///
/// Límites de los modelos de alta resolución (Opus 5.5, Sonnet 5.5), según la
/// documentación de visión a 2026-10-01.
enum ImageDownscaler {
    static let maxLongEdge = 2576
    static let maxVisualTokens = 4784
    static let maxBase64Bytes = 10_000_000

    enum Failure: Error, Equatable {
        case unreadable
        /// Ni reducida ni en JPEG cabe en el límite de la API.
        case tooLarge
    }

    struct Prepared: Equatable {
        let data: Data
        let mediaType: String
    }

    /// El modelo ve la imagen en parches de 28×28 píxeles.
    static func visualTokens(width: Int, height: Int) -> Int {
        ((width + 27) / 28) * ((height + 27) / 28)
    }

    /// El tamaño más grande que cabe en los dos límites conservando la
    /// proporción. Nunca amplía.
    static func fittedSize(width: Int, height: Int) -> (width: Int, height: Int) {
        func scaled(_ scale: Double) -> (width: Int, height: Int) {
            (max(1, Int(Double(width) * scale)), max(1, Int(Double(height) * scale)))
        }
        var scale = min(1.0, Double(maxLongEdge) / Double(max(width, height)))
        while true {
            let size = scaled(scale)
            if visualTokens(width: size.width, height: size.height) <= maxVisualTokens {
                return size
            }
            scale *= 0.99
        }
    }

    static func base64Size(_ data: Data) -> Int { (data.count + 2) / 3 * 4 }

    /// PNG siempre que quepa: el texto se lee mejor sin artefactos de
    /// compresión. JPEG solo si el PNG no cabe (un fotograma de vídeo con
    /// subtítulos puede no caber).
    static func prepare(_ imageData: Data,
                        maxBase64Bytes: Int = maxBase64Bytes) throws -> Prepared {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Failure.unreadable }

        let target = fittedSize(width: image.width, height: image.height)
        let unchanged = target.width == image.width && target.height == image.height
        let isPNG = (CGImageSourceGetType(source) as String?) == UTType.png.identifier
        let scaled = unchanged ? image : try resize(image, to: target)

        let png = unchanged && isPNG ? imageData : try encode(scaled, as: .png)
        if base64Size(png) <= maxBase64Bytes {
            return Prepared(data: png, mediaType: "image/png")
        }
        let jpeg = try encode(scaled, as: .jpeg, quality: 0.9)
        if base64Size(jpeg) <= maxBase64Bytes {
            return Prepared(data: jpeg, mediaType: "image/jpeg")
        }
        throw Failure.tooLarge
    }

    static func encode(_ image: CGImage, as type: UTType, quality: Double? = nil) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, type.identifier as CFString, 1, nil)
        else { throw Failure.unreadable }
        let options = quality.map {
            [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary
        }
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unreadable }
        return data as Data
    }

    private static func resize(_ image: CGImage,
                               to size: (width: Int, height: Int)) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: size.width, height: size.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Failure.unreadable }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let resized = context.makeImage() else { throw Failure.unreadable }
        return resized
    }
}
```

- [ ] **Step 4: Ver que pasan**

Run: `make test-app`
Expected: `** TEST SUCCEEDED **`, 25 tests: 15 de antes y 10 nuevos.

- [ ] **Step 5: Commit**

```bash
git add App/Capture/ImageDownscaler.swift AppTests/ImageDownscalerTests.swift
git commit -m "feat: reducir la captura a lo que el modelo aprovecha"
```

---

### Task 7: Historial — origen, caso y migración

**Files:**
- Create: `App/CaptureKind+UI.swift`
- Modify: `App/Store/StoredCard.swift`, `App/Store/CardStore.swift`, `App/Store/Persistence.swift`, `App/UI/HistoryWindow.swift`
- Modify: `AppTests/CardStoreTests.swift`
- Test: `AppTests/StoredCardMigrationTests.swift`

**Interfaces:**
- Consumes: `Capture`, `CaptureCard`, `CaptureKind` (Task 2).
- Produces:
  - `StoredCard` con `source`, `result`, `origin: String` (`"voice"` | `"screen"`), `kind: String?`; `convenience init(capture: Capture, card: CaptureCard)`
  - `CardStore.save(capture: Capture, card: CaptureCard)`, que reemplaza si el `id` ya existe e ignora `skip`
  - `Persistence.makeContainer(_ configuration: ModelConfiguration = ModelConfiguration()) throws -> ModelContainer`
  - `extension CaptureKind { var label: String; var menuLabel: String }`

- [ ] **Step 1: Escribir los tests que fallan**

`AppTests/StoredCardMigrationTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import Parla

/// El esquema tal como estaba antes de la captura. Anidado en un
/// `VersionedSchema` para que la entidad se siga llamando `StoredCard`.
enum LegacySchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [StoredCard.self, StoredVocab.self] }

    @Model
    final class StoredCard {
        var id: UUID
        var spanish: String
        var english: String
        var why: [String]
        var createdAt: Date
        @Relationship(deleteRule: .cascade) var vocab: [StoredVocab]

        init(id: UUID, spanish: String, english: String, why: [String],
             createdAt: Date, vocab: [StoredVocab]) {
            self.id = id
            self.spanish = spanish
            self.english = english
            self.why = why
            self.createdAt = createdAt
            self.vocab = vocab
        }
    }

    @Model
    final class StoredVocab {
        var term: String
        var meaning: String

        init(term: String, meaning: String) {
            self.term = term
            self.meaning = meaning
        }
    }
}

@Test func unaBaseConElEsquemaAnteriorConservaSusTarjetas() throws {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "parla-migracion-\(UUID().uuidString).store")

    do {
        let legacy = try ModelContainer(for: Schema(versionedSchema: LegacySchema.self),
                                        configurations: ModelConfiguration(url: url))
        let context = ModelContext(legacy)
        context.insert(LegacySchema.StoredCard(
            id: UUID(), spanish: "me da igual", english: "I don't mind.",
            why: ["\"Me da igual\" no se traduce literal."],
            createdAt: Date(timeIntervalSince1970: 7),
            vocab: [LegacySchema.StoredVocab(term: "either way", meaning: "de cualquier forma")]))
        try context.save()
    }

    let current = try Persistence.makeContainer(ModelConfiguration(url: url))
    let stored = try ModelContext(current).fetch(FetchDescriptor<StoredCard>())
    #expect(stored.count == 1)
    #expect(stored.first?.source == "me da igual")
    #expect(stored.first?.result == "I don't mind.")
    #expect(stored.first?.origin == "voice")
    #expect(stored.first?.kind == nil)
    #expect(stored.first?.vocab.first?.term == "either way")
}
```

En `AppTests/CardStoreTests.swift`, cambia `stored[0].spanish` por
`stored[0].source` y `stored[0].english` por `stored[0].result`. Después añade
al final:

```swift
private func memoryStore() throws -> (CardStore, ModelContainer) {
    let container = try ModelContainer(
        for: StoredCard.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return (CardStore(modelContainer: container), container)
}

private let capture = Capture(imageData: Data([1]), mediaType: "image/png",
                              capturedAt: Date(timeIntervalSince1970: 99))

private func captureCard(_ kind: CaptureKind) -> CaptureCard {
    CaptureCard(kind: kind, source: "I am agree", result: "I agree.",
                why: ["\"Agree\" ya es verbo."],
                vocab: [VocabTerm(term: "agree", meaning: "estar de acuerdo")])
}

@Test func guardaUnaCapturaConSuCasoYSuOrigen() async throws {
    let (store, container) = try memoryStore()
    await store.save(capture: capture, card: captureCard(.correct))

    let stored = try ModelContext(container).fetch(FetchDescriptor<StoredCard>())
    #expect(stored.count == 1)
    #expect(stored.first?.id == capture.id)
    #expect(stored.first?.origin == "screen")
    #expect(stored.first?.kind == "correct")
    #expect(stored.first?.source == "I am agree")
    #expect(stored.first?.createdAt == Date(timeIntervalSince1970: 99))
    #expect(stored.first?.vocab.first?.meaning == "estar de acuerdo")
}

@Test func reclasificarVariasVecesDejaUnaSolaFila() async throws {
    let (store, container) = try memoryStore()
    await store.save(capture: capture, card: captureCard(.correct))
    await store.save(capture: capture, card: captureCard(.understand))
    await store.save(capture: capture, card: captureCard(.translate))

    let stored = try ModelContext(container).fetch(FetchDescriptor<StoredCard>())
    #expect(stored.count == 1)
    #expect(stored.first?.kind == "translate")
}

@Test func unSkipNoVaAlHistorial() async throws {
    let (store, container) = try memoryStore()
    await store.save(capture: capture,
                     card: CaptureCard(kind: .skip, source: "", result: "", why: [], vocab: []))
    #expect(try ModelContext(container).fetch(FetchDescriptor<StoredCard>()).isEmpty)
}
```

- [ ] **Step 2: Ver que fallan**

Run: `make test-app`
Expected: FAIL de compilación: `value of type 'StoredCard' has no member 'source'`.

- [ ] **Step 3: Implementar el modelo**

`App/Store/StoredCard.swift` (reemplaza la clase `StoredCard` y deja `StoredVocab`
como está):

```swift
@Model
final class StoredCard {
    var id: UUID
    /// Lo que se dijo o lo que se leyó en la captura. El nombre antiguo
    /// (`spanish`) mentía en cuanto una captura en inglés lo llenaba.
    @Attribute(originalName: "spanish") var source: String
    /// La traducción, la corrección o el inglés.
    @Attribute(originalName: "english") var result: String
    var why: [String]
    var createdAt: Date
    /// `"voice"` o `"screen"`. Con valor por defecto para que las filas
    /// antiguas migren solas.
    var origin: String = "voice"
    /// `CaptureKind.rawValue`; `nil` en las tarjetas de voz.
    var kind: String?
    @Relationship(deleteRule: .cascade) var vocab: [StoredVocab]

    init(id: UUID, source: String, result: String, why: [String], createdAt: Date,
         origin: String = "voice", kind: String? = nil, vocab: [StoredVocab]) {
        self.id = id
        self.source = source
        self.result = result
        self.why = why
        self.createdAt = createdAt
        self.origin = origin
        self.kind = kind
        self.vocab = vocab
    }

    convenience init(utterance: Utterance, card: Card) {
        self.init(id: utterance.id,
                  source: utterance.text,
                  result: card.english,
                  why: card.why,
                  createdAt: utterance.startedAt,
                  vocab: card.vocab.map { StoredVocab(term: $0.term, meaning: $0.meaning) })
    }

    convenience init(capture: Capture, card: CaptureCard) {
        self.init(id: capture.id,
                  source: card.source,
                  result: card.result,
                  why: card.why,
                  createdAt: capture.capturedAt,
                  origin: "screen",
                  kind: card.kind.rawValue,
                  vocab: card.vocab.map { StoredVocab(term: $0.term, meaning: $0.meaning) })
    }
}
```

- [ ] **Step 4: Implementar el store y la apertura de la base**

`App/Store/CardStore.swift`, dentro del actor y debajo de `save(utterance:card:)`:

```swift
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
```

`App/Store/Persistence.swift`: sustituye el cuerpo del enum:

```swift
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
```

Conserva el comentario de documentación que ya hay sobre el enum.

- [ ] **Step 5: Etiquetas de los casos**

`App/CaptureKind+UI.swift`:

```swift
import ParlaCore

extension CaptureKind {
    /// La etiqueta de la tarjeta y del historial.
    var label: String {
        switch self {
        case .understand: "📷 Para entender"
        case .correct:    "📷 Corrección"
        case .translate:  "📷 Traducción"
        case .skip:       "📷 Sin texto"
        }
    }

    /// Lo que ofrece «¿No era eso?». `skip` no se ofrece nunca.
    var menuLabel: String {
        switch self {
        case .understand: "No lo escribí yo: explícamelo"
        case .correct:    "Lo escribí yo: corrígelo"
        case .translate:  "Tradúcelo al inglés"
        case .skip:       ""
        }
    }
}
```

- [ ] **Step 6: Historial**

`App/UI/HistoryWindow.swift`: añade `import ParlaCore` y cambia el filtro y la fila.

```swift
    private var filtered: [StoredCard] {
        guard !search.isEmpty else { return cards }
        return cards.filter {
            $0.source.localizedStandardContains(search)
                || $0.result.localizedStandardContains(search)
        }
    }
```

```swift
            VStack(alignment: .leading, spacing: 6) {
                if let kind = card.kind.flatMap(CaptureKind.init(rawValue:)) {
                    Text(kind.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text("«\(card.source)»").font(.caption).foregroundStyle(.secondary)
                Text(card.result).font(.headline)
```

El resto de la fila (las viñetas y el vocabulario) no cambia.

- [ ] **Step 7: Ver que pasan**

Run: `make test-app`
Expected: `** TEST SUCCEEDED **`, 29 tests.

Si `unaBaseConElEsquemaAnteriorConservaSusTarjetas` falla al abrir la base
(error de migración), la migración automática no basta. En ese caso, en
`Persistence.swift`, añade un plan explícito y haz que `makeContainer` lo use:

```swift
enum ParlaSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [StoredCard.self, StoredVocab.self] }

    @Model final class StoredCard {
        var id: UUID
        var spanish: String
        var english: String
        var why: [String]
        var createdAt: Date
        @Relationship(deleteRule: .cascade) var vocab: [StoredVocab]
        init(id: UUID, spanish: String, english: String, why: [String],
             createdAt: Date, vocab: [StoredVocab]) {
            self.id = id; self.spanish = spanish; self.english = english
            self.why = why; self.createdAt = createdAt; self.vocab = vocab
        }
    }

    @Model final class StoredVocab {
        var term: String
        var meaning: String
        init(term: String, meaning: String) { self.term = term; self.meaning = meaning }
    }
}

enum ParlaSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [StoredCard.self, StoredVocab.self] }
}

enum ParlaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ParlaSchemaV1.self, ParlaSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: ParlaSchemaV1.self, toVersion: ParlaSchemaV2.self)]
    }
}
```

```swift
    static func makeContainer(_ configuration: ModelConfiguration = ModelConfiguration())
        throws -> ModelContainer {
        try ModelContainer(for: Schema(versionedSchema: ParlaSchemaV2.self),
                           migrationPlan: ParlaMigrationPlan.self,
                           configurations: configuration)
    }
```

Vuelve a correr `make test-app` hasta verlo en verde.

- [ ] **Step 8: Comprobar con la base real**

La base real de Edwin está en
`~/Library/Containers/app.schoolaid.Parla/Data/Library/Application Support/default.store`.
Cópiala antes de tocar nada:

```bash
cp -R ~/Library/Containers/app.schoolaid.Parla/Data/Library/Application\ Support \
  /private/tmp/claude-501/-Users-edwinsandoval-Work-Free/6fcb88aa-8ba8-40a7-aba7-4479d2b39660/scratchpad/respaldo-historial
```

Luego `make run`, abre Historial desde el menú de la barra y confirma que las
tarjetas antiguas siguen ahí.

- [ ] **Step 9: Commit**

```bash
git add App/CaptureKind+UI.swift App/Store App/UI/HistoryWindow.swift AppTests/CardStoreTests.swift AppTests/StoredCardMigrationTests.swift
git commit -m "feat: el historial guarda capturas y migra la base existente"
```

---

### Task 8: `ScreenCapturer` (plan A: `screencapture -i`)

**Solo si la Task 1 decidió el plan A.** Si decidió el B, sáltala y haz la 8B.

**Files:**
- Create: `App/Capture/ScreenCapturer.swift`
- Test: `AppTests/ScreenCapturerTests.swift`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `struct ScreenCapturer: Sendable`, con `func captureRegion() async throws -> Data?` (`nil` = cancelado)
  - `enum Failure: Error, Equatable { case noPermission, failed(status: Int32) }`
  - `static let live: ScreenCapturer`

- [ ] **Step 1: Escribir los tests que fallan**

`AppTests/ScreenCapturerTests.swift`:

```swift
import Testing
import Foundation
@testable import Parla

/// Hace de `screencapture`: anota cómo lo llamaron y deja, o no, el archivo.
private final class FakeProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(URL, [String])] = []
    var calls: [(URL, [String])] { lock.withLock { recorded } }

    let writes: Data?
    let status: Int32

    init(writes: Data?, status: Int32) {
        self.writes = writes
        self.status = status
    }

    func run(_ executable: URL, _ arguments: [String]) async throws -> Int32 {
        lock.withLock { recorded.append((executable, arguments)) }
        if let writes, let path = arguments.last {
            try writes.write(to: URL(fileURLWithPath: path))
        }
        return status
    }
}

private func scratchDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "parla-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func capturer(_ fake: FakeProcess, permission: Bool = true,
                      in directory: URL) -> ScreenCapturer {
    ScreenCapturer(runner: { try await fake.run($0, $1) },
                   hasPermission: { permission },
                   directory: directory)
}

@Test func sinPermisoNiSiquieraAbreLaSeleccion() async throws {
    let fake = FakeProcess(writes: nil, status: 0)
    let directory = try scratchDirectory()
    await #expect(throws: ScreenCapturer.Failure.noPermission) {
        try await capturer(fake, permission: false, in: directory).captureRegion()
    }
    #expect(fake.calls.isEmpty)
}

@Test func lanzaScreencaptureInteractivoYSilencioso() async throws {
    let fake = FakeProcess(writes: Data([1]), status: 0)
    _ = try await capturer(fake, in: try scratchDirectory()).captureRegion()
    let (executable, arguments) = try #require(fake.calls.first)
    #expect(executable.path == "/usr/sbin/screencapture")
    #expect(Array(arguments.dropLast()) == ["-i", "-x", "-t", "png"])
}

@Test func devuelveLosBytesDeLaRegion() async throws {
    let fake = FakeProcess(writes: Data([1, 2, 3]), status: 0)
    let data = try await capturer(fake, in: try scratchDirectory()).captureRegion()
    #expect(data == Data([1, 2, 3]))
}

@Test func sinArchivoYConCodigoDeCancelarEsNil() async throws {
    for status in ScreenCapturer.cancelStatuses {
        let fake = FakeProcess(writes: nil, status: status)
        let data = try await capturer(fake, in: try scratchDirectory()).captureRegion()
        #expect(data == nil)
    }
}

@Test func sinArchivoYConOtroCodigoEsUnFallo() async throws {
    let fake = FakeProcess(writes: nil, status: 99)
    let directory = try scratchDirectory()
    await #expect(throws: ScreenCapturer.Failure.failed(status: 99)) {
        try await capturer(fake, in: directory).captureRegion()
    }
}

@Test func noDejaElArchivoTemporal() async throws {
    let directory = try scratchDirectory()
    _ = try await capturer(FakeProcess(writes: Data([1]), status: 0), in: directory)
        .captureRegion()
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
}
```

- [ ] **Step 2: Ver que fallan**

Run: `make test-app`
Expected: FAIL de compilación: `cannot find 'ScreenCapturer' in scope`.

- [ ] **Step 3: Implementar**

`App/Capture/ScreenCapturer.swift`. En `cancelStatuses` pon los códigos que
anotó la Task 1. El ejemplo supone que Esc salió con 1.

```swift
import CoreGraphics
import Foundation

/// Abre la selección de región de macOS (la cruz de ⌘⇧4) y devuelve el PNG.
struct ScreenCapturer: Sendable {

    enum Failure: Error, Equatable {
        /// Sin el permiso, macOS no falla: devuelve las ventanas en blanco. Por
        /// eso se comprueba antes y no se intenta adivinar mirando la imagen.
        case noPermission
        case failed(status: Int32)
    }

    /// Ejecuta un proceso y devuelve su código de salida.
    typealias Runner = @Sendable (_ executable: URL, _ arguments: [String]) async throws -> Int32

    /// Códigos con los que `screencapture -i` termina sin archivo cuando el
    /// usuario cancela. Medidos en la sonda de la Task 1.
    static let cancelStatuses: Set<Int32> = [0, 1]

    let runner: Runner
    let hasPermission: @Sendable () -> Bool
    /// Dentro del contenedor del sandbox: el único sitio donde la app puede
    /// escribir sin pedir nada.
    let directory: URL

    static let live = ScreenCapturer(runner: { try await runProcess($0, $1) },
                                     hasPermission: { CGPreflightScreenCaptureAccess() },
                                     directory: FileManager.default.temporaryDirectory)

    /// `nil` si el usuario canceló con Esc.
    func captureRegion() async throws -> Data? {
        guard hasPermission() else { throw Failure.noPermission }

        let file = directory.appending(path: "parla-\(UUID().uuidString).png")
        // La imagen solo existe en disco el tiempo de leerla.
        defer { try? FileManager.default.removeItem(at: file) }

        let status = try await runner(URL(fileURLWithPath: "/usr/sbin/screencapture"),
                                      ["-i", "-x", "-t", "png", file.path])
        if let data = try? Data(contentsOf: file), !data.isEmpty { return data }
        if Self.cancelStatuses.contains(status) { return nil }
        throw Failure.failed(status: status)
    }

    static func runProcess(_ executable: URL, _ arguments: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
```

- [ ] **Step 4: Ver que pasan**

Run: `make test-app`
Expected: `** TEST SUCCEEDED **`, 35 tests.

- [ ] **Step 5: Commit**

```bash
git add App/Capture/ScreenCapturer.swift AppTests/ScreenCapturerTests.swift
git commit -m "feat: seleccionar una región con la cruz nativa de macOS"
```

---

### Task 8B: `ScreenCapturer` (plan B: capa propia + ScreenCaptureKit)

**Solo si la Task 1 descartó el plan A.** La interfaz pública es la misma que
en la Task 8, así que las tareas siguientes no cambian.

**Files:**
- Create: `App/Capture/SelectionOverlay.swift`, `App/Capture/ScreenCapturer.swift`
- Test: `AppTests/ScreenCapturerTests.swift`

**Interfaces:**
- Consumes: `ImageDownscaler.encode(_:as:quality:)` (Task 6).
- Produces: lo mismo que la Task 8 (`captureRegion()`, `Failure`, `live`), más `static func displaySpace(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect`.

- [ ] **Step 1: Escribir los tests que fallan**

`AppTests/ScreenCapturerTests.swift`:

```swift
import Testing
import Foundation
import CoreGraphics
@testable import Parla

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var rects: [CGRect] = []
    var grabbed: [CGRect] { lock.withLock { rects } }
    func record(_ rect: CGRect) { lock.withLock { rects.append(rect) } }
}

@Test func sinPermisoNiSiquieraAbreLaSeleccion() async {
    let recorder = Recorder()
    let capturer = ScreenCapturer(hasPermission: { false },
                                  select: { CGRect(x: 0, y: 0, width: 10, height: 10) },
                                  grab: { recorder.record($0); return Data([1]) })
    await #expect(throws: ScreenCapturer.Failure.noPermission) {
        try await capturer.captureRegion()
    }
    #expect(recorder.grabbed.isEmpty)
}

@Test func cancelarLaSeleccionEsNil() async throws {
    let capturer = ScreenCapturer(hasPermission: { true }, select: { nil },
                                  grab: { _ in Data([1]) })
    #expect(try await capturer.captureRegion() == nil)
}

@Test func capturaElRectanguloElegido() async throws {
    let recorder = Recorder()
    let rect = CGRect(x: 10, y: 20, width: 300, height: 100)
    let capturer = ScreenCapturer(hasPermission: { true }, select: { rect },
                                  grab: { recorder.record($0); return Data([7]) })
    #expect(try await capturer.captureRegion() == Data([7]))
    #expect(recorder.grabbed == [rect])
}

@Test func pasaDeCoordenadasDeAppKitALasDeLaPantalla() {
    // AppKit mide desde abajo a la izquierda de la pantalla principal;
    // ScreenCaptureKit, desde arriba a la izquierda.
    let appKit = CGRect(x: 100, y: 200, width: 300, height: 50)
    #expect(ScreenCapturer.displaySpace(appKit, primaryHeight: 1000)
            == CGRect(x: 100, y: 750, width: 300, height: 50))
}
```

- [ ] **Step 2: Ver que fallan**

Run: `make test-app`
Expected: FAIL de compilación: `cannot find 'ScreenCapturer' in scope`.

- [ ] **Step 3: La capa de selección**

`App/Capture/SelectionOverlay.swift`:

```swift
import AppKit

/// Una capa sobre la pantalla del ratón para arrastrar un rectángulo. Existe
/// porque `screencapture -i` no funciona dentro del sandbox (sonda de la Task 1).
@MainActor
enum SelectionOverlay {

    /// El rectángulo en coordenadas globales de AppKit, o `nil` si el usuario
    /// pulsó Esc o no arrastró.
    static func selectRegion() async -> CGRect? {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main
        else { return nil }

        return await withCheckedContinuation { continuation in
            let window = OverlayWindow(screen: screen) { continuation.resume(returning: $0) }
            // Sin activar la app, la capa no recibe el Esc.
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            NSCursor.crosshair.push()
        }
    }
}

private final class OverlayWindow: NSWindow {
    private let finish: (CGRect?) -> Void
    private var finished = false

    init(screen: NSScreen, finish: @escaping (CGRect?) -> Void) {
        self.finish = finish
        super.init(contentRect: screen.frame, styleMask: .borderless,
                   backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.15)
        isReleasedWhenClosed = false
        contentView = SelectionView { [weak self] rect in self?.complete(rect) }
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        // 53 es Esc.
        if event.keyCode == 53 { complete(nil) } else { super.keyDown(with: event) }
    }

    private func complete(_ local: CGRect?) {
        guard !finished else { return }
        finished = true
        NSCursor.pop()
        orderOut(nil)
        let global = local.map { convertToScreen($0) }
        // Un clic sin arrastrar no es una región.
        finish(global.flatMap { $0.width >= 4 && $0.height >= 4 ? $0 : nil })
    }
}

private final class SelectionView: NSView {
    private let onEnd: (CGRect?) -> Void
    private var start: CGPoint?
    private var current: CGPoint?

    init(onEnd: @escaping (CGRect?) -> Void) {
        self.onEnd = onEnd
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("no se usa desde un nib") }

    private var selection: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(current.x - start.x), height: abs(current.y - start.y))
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        onEnd(selection)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let selection else { return }
        NSColor.clear.setFill()
        selection.fill(using: .copy)
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection)
        border.lineWidth = 1
        border.stroke()
    }
}
```

- [ ] **Step 4: El capturador**

`App/Capture/ScreenCapturer.swift`:

```swift
import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Selecciona una región con `SelectionOverlay` y la captura con
/// ScreenCaptureKit, que sí funciona dentro del sandbox.
struct ScreenCapturer: Sendable {

    enum Failure: Error, Equatable {
        /// Sin el permiso, macOS no falla: devuelve las ventanas en blanco. Por
        /// eso se comprueba antes y no se intenta adivinar mirando la imagen.
        case noPermission
        case failed(status: Int32)
    }

    let hasPermission: @Sendable () -> Bool
    /// Coordenadas globales de AppKit; `nil` si se canceló.
    let select: @Sendable () async -> CGRect?
    /// Devuelve el PNG de ese rectángulo.
    let grab: @Sendable (CGRect) async throws -> Data

    static let live = ScreenCapturer(
        hasPermission: { CGPreflightScreenCaptureAccess() },
        select: { await SelectionOverlay.selectRegion() },
        grab: { rect in
            let primaryHeight = await MainActor.run { NSScreen.screens.first?.frame.height ?? 0 }
            let image = try await SCScreenshotManager.captureImage(
                in: displaySpace(rect, primaryHeight: primaryHeight))
            return try ImageDownscaler.encode(image, as: .png)
        })

    /// `nil` si el usuario canceló con Esc.
    func captureRegion() async throws -> Data? {
        guard hasPermission() else { throw Failure.noPermission }
        guard let rect = await select() else { return nil }
        // La capa tiene que haber desaparecido antes de la foto.
        try await Task.sleep(for: .milliseconds(80))
        return try await grab(rect)
    }

    /// AppKit mide desde abajo a la izquierda de la pantalla principal;
    /// ScreenCaptureKit, desde arriba a la izquierda.
    static func displaySpace(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
```

- [ ] **Step 5: Ver que pasan**

Run: `make test-app`
Expected: `** TEST SUCCEEDED **`, 33 tests.

- [ ] **Step 6: Comprobar a mano**

`make install` y abre Parla desde Spotlight. Todavía no hay atajo (llega en la
Task 10), así que esta comprobación se hace al final de la Task 10, Step 9, en
lugar de aquí.

- [ ] **Step 7: Commit**

```bash
git add App/Capture AppTests/ScreenCapturerTests.swift
git commit -m "feat: seleccionar una región con una capa propia y ScreenCaptureKit"
```

---

### Task 9: Panel — tarjetas con origen y `CaptureCardView`

**Files:**
- Modify: `App/CardPresentation.swift`, `App/AppState.swift`, `App/UI/CardView.swift`, `AppTests/CardOrderingTests.swift`
- Create: `App/UI/CardParts.swift`, `App/UI/CaptureCardView.swift`
- Test: `AppTests/FlowLayoutTests.swift`, `AppTests/CardOrderingTests.swift`

**Interfaces:**
- Consumes: `Capture`, `CaptureCard`, `CaptureKind` (Task 2); `CaptureKind.label` y `.menuLabel` (Task 7).
- Produces:
  - `enum CardOrigin: Sendable { case voice(Utterance), capture(Capture) }`
  - `enum CardState` con el caso nuevo `readyCapture(CaptureCard)`
  - `CardPresentation`: `init(utterance:state:)`, `init(capture:state:)`, `origin`, `utterance: Utterance?`, `capture: Capture?`, `nonisolated var date: Date`, `var forcedKind: CaptureKind?`
  - `CaptureCardView(presentation:onRetry:onReclassify:)`
  - `CardSkeleton`, `WhyList(lines:)`, `VocabChips(vocab:)`, `FlowLayout`, con `static func rows(for widths: [CGFloat], maxWidth: CGFloat, spacing: CGFloat) -> [[Int]]`

- [ ] **Step 1: Escribir los tests que fallan**

`AppTests/FlowLayoutTests.swift`:

```swift
import Testing
import CoreGraphics
@testable import Parla

@Test func lasPiezasQueCabenVanEnLaMismaFila() {
    #expect(FlowLayout.rows(for: [50, 50, 50], maxWidth: 200, spacing: 6) == [[0, 1, 2]])
}

@Test func laQueNoCabeBajaALaSiguienteFila() {
    #expect(FlowLayout.rows(for: [100, 100, 100], maxWidth: 250, spacing: 6) == [[0, 1], [2]])
}

@Test func unaPiezaMasAnchaQueLaFilaVaSola() {
    // No se puede partir un chip: ocupa su fila aunque desborde.
    #expect(FlowLayout.rows(for: [300, 50], maxWidth: 250, spacing: 6) == [[0], [1]])
}

@Test func sinPiezasNoHayFilas() {
    #expect(FlowLayout.rows(for: [], maxWidth: 250, spacing: 6).isEmpty)
}
```

En `AppTests/CardOrderingTests.swift`, cambia las tres apariciones de
`\.utterance.text` y `.utterance.text` por `\.utterance?.text` y
`.utterance?.text`. Después añade:

```swift
@Test @MainActor func mezclaVozYCapturasPorFecha() {
    let voice = presentation("voz", at: 10)
    let older = presentation("vieja", at: 5)
    let capture = CardPresentation(capture: Capture(imageData: Data(), mediaType: "image/png",
                                                    capturedAt: Date(timeIntervalSince1970: 20)))
    #expect(AppState.mostRecent([voice, capture, older]).map(\.id)
            == [capture.id, voice.id, older.id])
}
```

- [ ] **Step 2: Ver que fallan**

Run: `make test-app`
Expected: FAIL de compilación: `cannot find 'FlowLayout' in scope` y
`extra argument 'capture'`.

- [ ] **Step 3: `CardPresentation` con origen**

`App/CardPresentation.swift`: sustituye `CardState` y la clase. La extensión de
`ExplainerError` del final no cambia.

```swift
/// De dónde salió la tarjeta. Las dos clases comparten el panel y el orden.
enum CardOrigin: Sendable {
    case voice(Utterance)
    case capture(Capture)
}

enum CardState: Sendable {
    case pending
    case ready(Card)
    case readyCapture(CaptureCard)
    case failed(ExplainerError)
}

@MainActor
@Observable
final class CardPresentation: Identifiable {
    let origin: CardOrigin
    var state: CardState
    /// El caso que el usuario pidió con «¿No era eso?». `nil`: decide el modelo.
    var forcedKind: CaptureKind? = nil

    nonisolated var id: UUID {
        switch origin {
        case .voice(let utterance): utterance.id
        case .capture(let capture): capture.id
        }
    }

    /// Cuándo se dijo la frase o se tomó la captura. Ordena el panel, porque
    /// las respuestas llegan desordenadas.
    nonisolated var date: Date {
        switch origin {
        case .voice(let utterance): utterance.startedAt
        case .capture(let capture): capture.capturedAt
        }
    }

    var utterance: Utterance? {
        if case .voice(let utterance) = origin { return utterance }
        return nil
    }

    var capture: Capture? {
        if case .capture(let capture) = origin { return capture }
        return nil
    }

    init(utterance: Utterance, state: CardState = .pending) {
        self.origin = .voice(utterance)
        self.state = state
    }

    init(capture: Capture, state: CardState = .pending) {
        self.origin = .capture(capture)
        self.state = state
    }
}
```

- [ ] **Step 4: Que `AppState` compile con el origen**

En `App/AppState.swift`:

- En `mostRecent`, cambia `$0.utterance.startedAt > $1.utterance.startedAt` por
  `$0.date > $1.date`.
- En `retry(_:)`, sustituye el cuerpo por:

```swift
    func retry(_ presentation: CardPresentation) {
        guard let apiKey = KeychainStore.shared.apiKey,
              let utterance = presentation.utterance
        else { return }
        presentation.state = .pending
        let explainer = makeExplainer(apiKey: apiKey)
        Task {
            do {
                if let card = try await explainer.explain(utterance) {
                    presentation.state = .ready(card)
                    await store.save(utterance: utterance, card: card)
                }
            } catch let error as ExplainerError {
                presentation.state = .failed(error)
            } catch {
                presentation.state = .failed(.network(error.localizedDescription))
            }
        }
    }
```

- [ ] **Step 5: Piezas compartidas de las tarjetas**

`App/UI/CardParts.swift`:

```swift
import SwiftUI
import ParlaCore

/// Lo que se ve mientras llega la respuesta.
struct CardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4).frame(height: 22)
            RoundedRectangle(cornerRadius: 4).frame(height: 12).padding(.trailing, 60)
        }
        .foregroundStyle(.quaternary)
        .redacted(reason: .placeholder)
    }
}

/// El porqué, en viñetas.
struct WhyList: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                    Text(line).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// El vocabulario. En filas que saltan de línea: una captura larga trae hasta
/// cinco términos y no caben en una fila del panel.
struct VocabChips: View {
    let vocab: [VocabTerm]

    var body: some View {
        FlowLayout {
            ForEach(Array(vocab.enumerated()), id: \.offset) { _, term in
                Text(term.term)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.tint.opacity(0.15), in: Capsule())
                    .help(term.meaning)
            }
        }
    }
}

/// Coloca las vistas en filas y salta de línea cuando la siguiente no cabe.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    /// Los índices de cada fila. Una pieza más ancha que la fila va sola: un
    /// chip no se puede partir.
    static func rows(for widths: [CGFloat], maxWidth: CGFloat, spacing: CGFloat) -> [[Int]] {
        var rows: [[Int]] = []
        var current: [Int] = []
        var used: CGFloat = 0
        for (index, width) in widths.enumerated() {
            let needed = current.isEmpty ? width : used + spacing + width
            if needed > maxWidth, !current.isEmpty {
                rows.append(current)
                current = [index]
                used = width
            } else {
                current.append(index)
                used = needed
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = Self.rows(for: sizes.map(\.width),
                             maxWidth: proposal.width ?? .infinity, spacing: spacing)
        let width = rows.map { row in
            row.map { sizes[$0].width }.reduce(0, +) + spacing * CGFloat(row.count - 1)
        }.max() ?? 0
        let height = rows.map { row in row.map { sizes[$0].height }.max() ?? 0 }
            .reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var y = bounds.minY
        for row in Self.rows(for: sizes.map(\.width), maxWidth: bounds.width, spacing: spacing) {
            var x = bounds.minX
            for index in row {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sizes[index]))
                x += sizes[index].width + spacing
            }
            y += (row.map { sizes[$0].height }.max() ?? 0) + spacing
        }
    }
}
```

- [ ] **Step 6: `CardView` usa las piezas**

`App/UI/CardView.swift`:

- Cambia `Text("«\(presentation.utterance.text)»")` por
  `Text("«\(presentation.utterance?.text ?? "")»")`.
- En el `switch`, añade `case .readyCapture: EmptyView()` (una tarjeta de voz
  nunca recibe una de captura).
- Borra la propiedad `skeleton` y usa `CardSkeleton()` en el caso `.pending`.
- En `ready(_:)`, sustituye el `VStack` de las viñetas por `WhyList(lines: card.why)`
  y el bloque `if !card.vocab.isEmpty { HStack … }` por
  `if !card.vocab.isEmpty { VocabChips(vocab: card.vocab) }`.

- [ ] **Step 7: `CaptureCardView`**

`App/UI/CaptureCardView.swift`:

```swift
import SwiftUI
import ParlaCore

struct CaptureCardView: View {
    let presentation: CardPresentation
    let onRetry: () -> Void
    let onReclassify: (CaptureKind) -> Void

    @State private var sourceExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch presentation.state {
            case .pending:
                header(presentation.forcedKind?.label ?? "📷 Leyendo…")
                CardSkeleton()
            case .readyCapture(let card) where card.kind == .skip:
                Text("📷 No encontré texto en la captura.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .readyCapture(let card):
                ready(card)
            case .failed(let error):
                header("📷 Captura")
                failed(error)
            case .ready:
                // Una captura nunca recibe una tarjeta de voz.
                EmptyView()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func ready(_ card: CaptureCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(card.kind.label)

            Text("«\(card.source)»")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(sourceExpanded ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { sourceExpanded.toggle() }

            Text(card.result)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if card.kind == .correct && card.why.isEmpty {
                Label("Nada que corregir", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else {
                WhyList(lines: card.why)
            }

            if !card.vocab.isEmpty { VocabChips(vocab: card.vocab) }

            Menu("¿No era eso?") {
                ForEach(CaptureKind.allCases.filter { $0 != .skip && $0 != card.kind },
                        id: \.self) { kind in
                    Button(kind.menuLabel) { onReclassify(kind) }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func failed(_ error: ExplainerError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(error == .refused ? "No se pudo leer esta captura." : error.readableMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
            if error.allowsRetry {
                Button("Reintentar", action: onRetry).controlSize(.small)
            }
        }
    }
}
```

- [ ] **Step 8: Ver que pasan**

Run: `make test-app`
Expected: `** TEST SUCCEEDED **`. Son 40 tests con el plan A y 38 con el B.

- [ ] **Step 9: Commit**

```bash
git add App/CardPresentation.swift App/AppState.swift App/UI/CardParts.swift App/UI/CardView.swift App/UI/CaptureCardView.swift AppTests/FlowLayoutTests.swift AppTests/CardOrderingTests.swift
git commit -m "feat: el panel distingue tarjetas de voz y de captura"
```

---

### Task 10: Cablear — atajo, menú, ajustes y permiso

**Files:**
- Modify: `App/AppState.swift`, `App/ParlaApp.swift`, `App/UI/SettingsView.swift`, `App/UI/PanelView.swift`

**Interfaces:**
- Consumes: `ScreenCapturer.live.captureRegion()` y `ScreenCapturer.Failure` (Task 8 u 8B), `ImageDownscaler.prepare(_:)` y `.Failure` (Task 6), `ClaudeExplainer.explainCapture(_:forcing:)` (Task 4), `CardStore.save(capture:card:)` (Task 7), `CardPresentation(capture:)` y `CaptureCardView` (Task 9).
- Produces:
  - `AppState.captureScreen()`, `reclassify(_:as:)`, `needsScreenRecordingAccess: Bool`, `captureError: String?`, `static func openScreenRecordingSettings()`
  - `KeyboardShortcuts.Name.captureScreen` (⌃⌥C por defecto)
  - El ítem de menú «Capturar pantalla»

`AppState` no tiene tests unitarios: depende del Llavero, de las ventanas y de la
API. Esta tarea se verifica en la app real con los pasos 7 a 9.

- [ ] **Step 1: Estado y captura en `AppState`**

En `App/AppState.swift`, debajo de `private(set) var cards: [CardPresentation] = []`:

```swift
    /// Sin el permiso de Grabación de pantalla no se captura. macOS no lo
    /// aplica hasta que la app se reabre, y el aviso lo dice.
    private(set) var needsScreenRecordingAccess = false
    private(set) var captureError: String?
```

Junto a las otras propiedades privadas (`engine`, `pipelineTask`, `panel`):

```swift
    @ObservationIgnored private let capturer = ScreenCapturer.live
    /// Mientras la cruz está abierta, otro atajo no abre una segunda.
    private var isSelectingRegion = false
    /// `CGRequestScreenCaptureAccess` solo muestra el diálogo una vez por
    /// identidad de app. Pedirlo más veces no hace nada.
    private var askedForScreenAccess = false
```

Debajo de `openMicrophoneSettings()`:

```swift
    /// Abre el panel de Privacidad › Grabación de pantalla directamente.
    static func openScreenRecordingSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
```

En `upsert(_:_:)`, sustituye la línea `if cards.count > 30 { … }` por una llamada
a `trimCards()`, y añade:

```swift
    /// El panel guarda las 30 últimas. Al salir del búfer, la imagen de una
    /// captura deja de existir en memoria.
    private func trimCards() {
        if cards.count > 30 { cards.removeFirst(cards.count - 30) }
    }
```

Una sección nueva al final de la clase, antes de `showPanel()`:

```swift
    // MARK: - Captura de pantalla

    /// La clave se comprueba antes de abrir la cruz: seleccionar una región
    /// para luego enterarse de que falta la clave es trabajo tirado.
    func captureScreen() {
        guard !isSelectingRegion else { return }
        guard let apiKey = KeychainStore.shared.apiKey else {
            setupError = ExplainerError.missingAPIKey.readableMessage
            showPanel()
            return
        }
        isSelectingRegion = true
        captureError = nil

        Task {
            defer { isSelectingRegion = false }

            let png: Data?
            do {
                png = try await grabRegion()
            } catch ScreenCapturer.Failure.noPermission {
                needsScreenRecordingAccess = true
                if !askedForScreenAccess {
                    askedForScreenAccess = true
                    _ = CGRequestScreenCaptureAccess()
                }
                showPanel()
                return
            } catch {
                captureError = "No se pudo capturar la pantalla (\(error))."
                showPanel()
                return
            }
            // Esc: ni tarjeta, ni coste, ni mensaje.
            guard let png else { return }
            needsScreenRecordingAccess = false

            let prepared: ImageDownscaler.Prepared
            do {
                prepared = try ImageDownscaler.prepare(png)
            } catch ImageDownscaler.Failure.tooLarge {
                captureError = "La región es demasiado grande. Selecciona menos."
                showPanel()
                return
            } catch {
                captureError = "No se pudo leer la captura."
                showPanel()
                return
            }

            let presentation = CardPresentation(capture: Capture(
                imageData: prepared.data, mediaType: prepared.mediaType, capturedAt: Date()))
            cards.append(presentation)
            trimCards()
            showPanel()
            sendCapture(presentation, apiKey: apiKey)
        }
    }

    /// `PARLA_CAPTURE_FILE` salta la selección y usa ese archivo: así se prueba
    /// el flujo entero desde la terminal, sin ratón y sin permiso de pantalla.
    /// La ruta tiene que estar dentro del contenedor del sandbox.
    private func grabRegion() async throws -> Data? {
        if let path = ProcessInfo.processInfo.environment["PARLA_CAPTURE_FILE"] {
            return try Data(contentsOf: URL(fileURLWithPath: path))
        }
        return try await capturer.captureRegion()
    }

    /// «¿No era eso?»: la misma imagen, con el caso que el usuario eligió.
    func reclassify(_ presentation: CardPresentation, as kind: CaptureKind) {
        guard let apiKey = KeychainStore.shared.apiKey else { return }
        presentation.forcedKind = kind
        sendCapture(presentation, apiKey: apiKey)
    }

    private func sendCapture(_ presentation: CardPresentation, apiKey: String) {
        guard let capture = presentation.capture else { return }
        presentation.state = .pending
        let explainer = makeExplainer(apiKey: apiKey)
        let forced = presentation.forcedKind
        Task {
            do {
                let card = try await explainer.explainCapture(capture, forcing: forced)
                Log.pipeline.info("captura: \(card.kind.rawValue) — \(card.source.prefix(60))")
                presentation.state = .readyCapture(card)
                await store.save(capture: capture, card: card)
            } catch let error as ExplainerError {
                Log.pipeline.error("captura fallida: \(error.readableMessage)")
                presentation.state = .failed(error)
            } catch {
                presentation.state = .failed(.network(error.localizedDescription))
            }
        }
    }
```

En `retry(_:)`, como primera línea dentro de la función:

```swift
        if presentation.capture != nil {
            guard let apiKey = KeychainStore.shared.apiKey else { return }
            sendCapture(presentation, apiKey: apiKey)
            return
        }
```

- [ ] **Step 2: El atajo**

`App/UI/SettingsView.swift`, en la extensión de `KeyboardShortcuts.Name`:

```swift
    static let captureScreen = Self("captureScreen",
                                    default: .init(.c, modifiers: [.control, .option]))
```

Y en `Section("Atajo")`, debajo del grabador que ya existe:

```swift
                KeyboardShortcuts.Recorder("Capturar pantalla:", name: .captureScreen)
```

- [ ] **Step 3: Atajo y menú en la app**

`App/ParlaApp.swift`, en `init()`, debajo del `onKeyUp` de `.toggleListening`:

```swift
        KeyboardShortcuts.onKeyUp(for: .captureScreen) {
            Task { @MainActor in state.captureScreen() }
        }
```

En `MenuBarView.body`, justo después del botón de empezar o detener la escucha:

```swift
        Button("Capturar pantalla") { state.captureScreen() }
```

- [ ] **Step 4: El panel**

`App/UI/PanelView.swift`, debajo del bloque `if state.needsMicrophoneAccess { … }`:

```swift
                if state.needsScreenRecordingAccess {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Parla necesita permiso de Grabación de pantalla. Después de "
                             + "darlo, cierra Parla y vuelve a abrirla: macOS no lo aplica antes.")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Abrir Ajustes del Sistema") {
                            AppState.openScreenRecordingSettings()
                        }
                        .controlSize(.small)
                    }
                }

                if let error = state.captureError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
```

Sustituye el `ForEach` de las tarjetas:

```swift
                ForEach(state.visibleCards) { card in
                    if card.capture != nil {
                        CaptureCardView(presentation: card,
                                        onRetry: { state.retry(card) },
                                        onReclassify: { state.reclassify(card, as: $0) })
                    } else {
                        CardView(presentation: card) { state.retry(card) }
                    }
                }
```

Y la condición del botón «Cerrar el panel». Si no, un aviso de permiso sin
tarjetas dejaría el panel sin forma de cerrarse:

```swift
                if !state.isListening
                    && (!state.visibleCards.isEmpty
                        || state.needsScreenRecordingAccess
                        || state.captureError != nil) {
```

- [ ] **Step 5: Compilar y que los tests sigan en verde**

Run: `make test && make test-app`
Expected: 73 tests de Core en verde y `** TEST SUCCEEDED **` en la app.

- [ ] **Step 6: Instalar**

Run: `make install`

- [ ] **Step 7: El flujo entero sin ratón**

```bash
CONT=~/Library/Containers/app.schoolaid.Parla/Data/tmp
mkdir -p "$CONT" && cp Core/Fixtures/capturas/correct-04-respuesta-con-contexto.png "$CONT/"
pkill -f 'Parla.app/Contents/MacOS/Parla'
PARLA_API_KEY=… PARLA_STDERR_LOG=1 \
PARLA_CAPTURE_FILE="$CONT/correct-04-respuesta-con-contexto.png" \
PARLA_CLICK_MENU="Capturar pantalla" PARLA_CLICK_AFTER=3 \
/Applications/Parla.app/Contents/MacOS/Parla 2>&1 | grep -E "hook: .*Capturar|captura"
```

Expected, en unos 10 segundos:

```
[pipeline] INFO: hook: activa=… → ejecuta «Capturar pantalla»
[pipeline] INFO: captura: correct — Yes, but maybe I arrive 5 minutes late…
```

Con la herramienta de capturas de computer-use, confirma que el panel muestra la
tarjeta «📷 Corrección» con el menú «¿No era eso?». Para con Ctrl-C.

- [ ] **Step 8: «¿No era eso?» y el historial**

Con la app del paso anterior abierta, pide a Edwin que elija en la tarjeta «¿No
era eso? › No lo escribí yo: explícamelo». Se espera:

- la tarjeta pasa a «📷 Para entender» y luego muestra la traducción al español;
- en el log aparece `captura: understand`;
- en Historial hay **una** fila para esa captura, con la etiqueta «📷 Para entender».

- [ ] **Step 9: Con la pantalla real (Edwin al teclado)**

Abre Parla desde Spotlight, no desde la terminal. Si no, macOS atribuye el
permiso a la Terminal. Pide a Edwin:

1. Pulsar ⌃⌥C. Sin permiso, el panel debe mostrar el aviso con el botón. Que
   conceda el permiso, cierre Parla y la vuelva a abrir.
2. Pulsar ⌃⌥C y arrastrar sobre un texto en inglés de otra persona (una web).
   Se espera «📷 Para entender».
3. Pulsar ⌃⌥C y pulsar Esc. No debe pasar nada: ni tarjeta, ni mensaje.
4. Pulsar ⌃⌥C y, con la cruz abierta, pulsar ⌃⌥C otra vez. Debe haber una sola
   cruz (Review Focus 1).
5. Con la escucha apagada, capturar: el panel aparece y «Cerrar el panel» lo
   cierra.
6. Capturar sobre una app a pantalla completa: el panel aparece encima.

Anota lo que no se cumpla y arréglalo antes del commit.

- [ ] **Step 10: Commit**

```bash
git add App/AppState.swift App/ParlaApp.swift App/UI/SettingsView.swift App/UI/PanelView.swift
git commit -m "feat: capturar la pantalla con ⌃⌥C y explicar lo que se ve"
```

---

### Task 11: README y verificación final

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: la documentación de la función y la rama lista para revisión.

- [ ] **Step 1: «Cómo funciona» y privacidad**

En `README.md`, en la primera frase, cambia «App de macOS que escucha lo que
dices en español y muestra» por «App de macOS que escucha lo que dices en español,
o lee lo que capturas de la pantalla, y muestra».

En la tabla de «Cómo funciona», debajo de la fila de «Traducción y explicación»:

```markdown
| Lectura de capturas | API de Anthropic: la imagen de la región que seleccionas |
```

Sustituye `**Tu audio nunca sale del equipo.** Solo viaja el texto transcrito.`
por:

```markdown
**Tu audio nunca sale del equipo.** Solo viaja el texto transcrito.

**Las capturas sí salen:** la imagen de la región que seleccionas viaja a la API.
No se guarda en tu Mac; al historial va solo el texto que Claude leyó en ella.
```

- [ ] **Step 2: Sección de uso**

Debajo de «### Al vuelo o en lote»:

```markdown
### Capturar la pantalla

Pulsa **⌃⌥C** (o «Capturar pantalla» en el menú de la barra) y arrastra un
rectángulo sobre el texto, igual que con ⌘⇧4. Esc cancela sin gastar nada. Parla
decide qué hacer con lo que ve:

- **Español** → cómo se dice en inglés y por qué, igual que con la voz.
- **Inglés que escribiste tú** (una caja de redacción, tus burbujas en un chat,
  un correo que estás redactando) → la versión corregida y qué estaba mal.
- **Inglés de otra persona** → qué significa y qué tiene de no evidente.

Si se equivoca de caso, «¿No era eso?» en la tarjeta vuelve a mandar la misma
imagen con el caso que elijas.

La primera vez macOS pide el permiso de **Grabación de pantalla**. Después de
darlo hay que cerrar Parla y volver a abrirla. Como cada compilación firmada ad
hoc es una app nueva para macOS, tras cada `make install` hay que volver a darlo.
```

- [ ] **Step 3: Compilar y depurar**

En «## Compilar», debajo de `make test-app`:

```markdown
make eval-capture  # manda Core/Fixtures/capturas a la API y cuenta aciertos del caso
```

Y debajo, una línea: «`make eval-capture` necesita `PARLA_API_KEY` y gasta
tokens: unas 8 peticiones. Para añadir una captura real, guárdala en
`Core/Fixtures/capturas/` con el caso esperado al principio del nombre
(`correct-09-mi-correo.png`).»

En «## Depuración», en la lista de variables:

```markdown
- `PARLA_CAPTURE_FILE=/ruta.png` salta la selección de región y usa ese archivo.
  La ruta tiene que estar dentro del contenedor del sandbox
  (`~/Library/Containers/app.schoolaid.Parla/Data/tmp/`). Con
  `PARLA_CLICK_MENU="Capturar pantalla"` se prueba el flujo entero sin ratón.
```

- [ ] **Step 4: Verificación final**

Run: `make test && make test-app`
Expected: Core en verde y `** TEST SUCCEEDED **`. Copia las dos últimas líneas
en el informe final.

Run: `PARLA_API_KEY=… make eval-capture`
Expected: `Acierto: n/8`, con n igual o mejor que en la Task 5.

Recorre la checklist manual del spec (§ 9) y confirma cada punto:

- [ ] la cruz aparece y Esc no deja rastro;
- [ ] el panel aparece sobre una app a pantalla completa;
- [ ] el permiso de pantalla se pide una sola vez y el aviso aparece si se deniega;
- [ ] «¿No era eso?» reemplaza la tarjeta en el panel y en el historial.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: captura de pantalla en el README"
```

---

## Notas para quien ejecute el plan

- **Orden:** 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 (u 8B) → 9 → 10 → 11. Las tareas 2 a 5
  solo tocan `Core` y no necesitan Xcode. La 6 y la 7 son independientes entre sí.
- **Pasos con Edwin al teclado:** Task 1 (permiso, arrastrar, Esc), Task 5,
  Step 7 (la clave para la API), Task 7, Step 8 (mirar el historial), y Task 10,
  Steps 8 y 9. Los demás se hacen solos.
- **Si el recuento de tests no coincide** con el que dice un paso, no lo ajustes
  a mano. Mira qué test falta o sobra: el recuento existe para notar un test que
  no corrió.
- Si el `make eval-capture` de la Task 5 da menos de 7/8, avísalo al terminar esa
  tarea y sigue con la 6. Ajustar el prompt o el esfuerzo es una decisión para
  tomar con Edwin, no un arreglo en silencio.
