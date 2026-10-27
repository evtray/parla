# Lectura en vivo con cuadernos: plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un modo de Parla que vigila un recuadro de una ventana, traduce
cada línea nueva con el contexto de un cuaderno y guarda en ese cuaderno las
líneas que valen la pena.

**Architecture:** Lo que no depende de la Mac va en `ParlaCore`:

- el detector de líneas;
- el lector de texto, que usa Vision y por eso sirve también en iOS;
- el contexto, la petición y la respuesta;
- la geometría del recuadro.

La app pone ScreenCaptureKit, la sesión, SwiftData y las vistas. Todo se
conecta así: `LiveSession` recibe fotogramas de un `FrameSource`, los lee con
`TextReader`, filtra con `LineDetector`, traduce con un
`LiveReadingTranslator` y guarda con `NotebookStore`.

**Tech Stack:**

- Swift 6.2, SwiftUI y AppKit, macOS 26.4;
- ScreenCaptureKit, Vision (`RecognizeTextRequest`) y SwiftData;
- KeyboardShortcuts;
- Swift Testing;
- la Claude API con streaming y salida estructurada.

**Spec:** `docs/superpowers/specs/2026-10-26-lectura-en-vivo-design.md`

## Global Constraints

- Rama `feat/lectura-en-vivo`. Nada se mezcla con `main` sin el OK de Edwin.
- Todo el texto visible, los comentarios y los nombres de los tests van en
  español, con el estilo del repo: tests `@Test func fraseEnCamelCase()`,
  comentarios que explican el porqué.
- `make test` (Core) y `make test-app` (app alojada) tienen que quedar en
  verde al cerrar cada tarea que toque su lado. `make test-app` regenera el
  proyecto con XcodeGen, así que los archivos nuevos entran solos.
- **La clave de API** solo vive en el Llavero (servicio `app.schoolaid.Parla`,
  cuenta `anthropic-api-key`) o en `PARLA_API_KEY`. Nunca se imprime ni se
  escribe en archivos ni en tests: en los tests va `"k"` o
  `"sk-ant-prueba-no-valida"`.
- **Las evaluaciones gastan tokens.** Se corren solo con el OK de Edwin, con
  `PARLA_API_KEY="$(security find-generic-password -s app.schoolaid.Parla -a anthropic-api-key -w)"`.
- **`make install` lo corre Edwin**, porque mata Parla y puede reiniciar los
  permisos de TCC. Los permisos también los concede él.
- Commits que terminan en
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Haiku 5.5 es `claude-haiku-5-5` y cuesta $0,10 / $0,50 por millón de
  tokens. No admite fallback de servidor.
- Valores fijos:
  - atajos ⌃⌥L (sesión) y ⌃⌥R (leer ahora);
  - 2 fps;
  - confianza mínima de Vision 0,3;
  - umbral de parecido 0,9;
  - contexto de 12 líneas;
  - hasta 5 líneas por petición.
- Copias fijadas por el spec:
  - «De qué trata»;
  - «Sin cuaderno»;
  - «Automático» / «Cuando yo diga»;
  - «Leer ahora»;
  - «Guardar»;
  - «Reintentar»;
  - «sin traducir»;
  - «La ventana se cerró»;
  - «No encontré texto en el recuadro»;
  - «Parla no puede ver la ventana en pantalla completa»;
  - «Ver todas las líneas»;
  - «Modelo para la lectura en vivo».

## Review Focus

1. **La ventana del juego cambia de tamaño en plena sesión.** El recuadro
   debe recortar la misma zona en la imagen nueva. Lo cubre el test
   `elRecorteEscalaConLaImagen` (Tarea 8).
2. **Con la fuente «pantalla», el recuadro puede incluir la traducción de
   Parla** (la tapa, el subtítulo o el panel) y leerla en bucle. La sesión
   descarta un texto igual a una de sus últimas traducciones. Lo cubre el
   test `noVuelveATraducirSuPropiaTraduccion` (Tarea 10).
3. **Diálogos pasados a toda prisa: más de 5 líneas pendientes.** Se mandan en
   tandas de 5, en orden. Lo cubre el test
   `masDeCincoPendientesVanEnTandasDeCinco` (Tarea 10).
4. **La clave borrada a mitad de sesión.** Las líneas quedan «sin traducir»
   con el mensaje de la clave y la lectura sigue. Lo cubre el test
   `sinClaveLaLineaQuedaSinTraducirYLaLecturaSigue` (Tarea 10).
5. **Un recuadro con un párrafo entero** (una diapositiva) corta la
   respuesta por `max_tokens`. Debe quedar «sin traducir», no colgarse. Lo
   cubre el test `unaRespuestaCortadaEsMalformada` (Tarea 5).

---

### Tarea 1: Sondas de la app (spec §10: 2, 3 y 5)

Las sondas 1 y 4 necesitan código de tareas posteriores y van en las tareas 4
y 6. Esta tarea tampoco tiene test: su entregable son las líneas
**Resultado:** que se añaden a la §10 del spec.

**Files:**
- Modify: `App/DebugHooks.swift`
- Modify: `docs/superpowers/specs/2026-10-26-lectura-en-vivo-design.md` (§10)

- [ ] **Paso 1: Escribir `probeLive()` en `DebugHooks`**

  Se activa con `PARLA_PROBE_LIVE=1`, igual que `PARLA_PROBE_AUDIO`. Hace tres
  cosas:

  - **Sonda 5:** registra en `Log.audio.info` cada ventana de
    `SCShareableContent.current`, con
    `owningApplication?.bundleIdentifier`, `title`, `frame` e `isOnScreen`.
  - **Sonda 2:** a los 8 s abre un `SCStream` sobre la primera ventana cuyo
    `bundleIdentifier` sea el de `PARLA_PROBE_BUNDLE`, con
    `SCContentFilter(desktopIndependentWindow:)` y
    `minimumFrameInterval = CMTime(value: 1, timescale: 2)`. Durante 20 s
    registra cuántos fotogramas `.complete` llegan cada segundo.
  - **Sonda 3:** muestra un `NSPanel` rojo semitransparente de 300×80. Usa el
    mismo `level`, `collectionBehavior` e `ignoresMouseEvents` que
    `SubtitleOverlay` (líneas 41-43).

- [ ] **Paso 2: Compilar**

  Run: `make build`
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Paso 3: Correr las sondas con Edwin**

  Edwin abre AFK Journey, lanza el binario de Debug con
  `PARLA_PROBE_LIVE=1 PARLA_PROBE_BUNDLE=<bundle del juego>` y hace tres
  pasadas de 20 s:

  1. ventana visible;
  2. ventana medio tapada por otra;
  3. juego a pantalla completa.

  En la tercera, además, dice si el panel rojo se ve encima del juego. Los
  registros se leen con
  `log show --last 5m --predicate 'subsystem == "app.schoolaid.Parla"'`.

  Expected: un fps por segundo en cada pasada, más la respuesta de Edwin sobre
  el panel.

- [ ] **Paso 4: Anotar y decidir**

  Bajo cada sonda de la §10 va una línea **Resultado:** con lo medido y la
  alternativa que se aplica, si hace falta. Si la sonda 2 da 0 fps en pantalla
  completa, la Tarea 9 emite `.paused(.fullScreenUnavailable)`. Si la sonda 3
  falla, la Tarea 11 cambia a la vista A en pantalla completa. Si la sonda 5 no
  trae `bundleIdentifier`, `LiveSource.window` guarda el nombre de la app en
  `bundleID`.

- [ ] **Paso 5: Commit**

  ```bash
  git add App/DebugHooks.swift docs/superpowers/specs/2026-10-26-lectura-en-vivo-design.md
  git commit -m "sondas: stream de ventana, panel a pantalla completa y lista de ventanas"
  ```

### Tarea 2: Haiku 5.5 y peticiones sin fallback

**Files:**
- Modify: `Core/Sources/ParlaCore/ClaudeRequestBuilder.swift` (`payload` y `request`)
- Modify: `App/ClaudeModel.swift`, `App/Preferences.swift`
- Test: `Core/Tests/ParlaCoreTests/ClaudeRequestBuilderTests.swift`, `AppTests/PreferencesTests.swift`

**Interfaces:**
- Produces:
  - `ClaudeRequestBuilder.supportsServerFallback: Bool`;
  - `ClaudeModel.haiku55`;
  - `Preferences.liveModel: ClaudeModel` (por defecto `.haiku55`);
  - `Preferences.liveDisplay: LiveDisplay` (por defecto `.panel`);
  - `Preferences.liveRhythm: LiveRhythm` (por defecto `.automatic`).

  `LiveDisplay` y `LiveRhythm` se definen en la Tarea 8. En esta tarea solo
  entra `liveModel`; las otras dos se añaden en la Tarea 8.

- [ ] **Paso 1: Tests que fallan**

  ```swift
  @Test func conHaikuNoPideFallbackNiCabeceraBeta() throws {
      let request = try ClaudeRequestBuilder(model: "claude-haiku-5-5")
          .makeRequest(for: utterance, apiKey: "k")
      #expect(request.value(forHTTPHeaderField: "anthropic-beta") == nil)
      #expect(try body(of: request)["fallbacks"] == nil)
  }

  @Test func conLosDemasModelosSiguePidiendoFallback() throws {
      for model in ["claude-opus-5-5", "claude-sonnet-5-5"] {
          let request = try ClaudeRequestBuilder(model: model).makeRequest(for: utterance, apiKey: "k")
          #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
          #expect(try body(of: request)["fallbacks"] as? String == "default")
      }
  }
  ```

  En `PreferencesTests`:

  - `laLecturaEnVivoEmpiezaConHaiku`: `liveModel == .haiku55` en un almacén
    vacío.
  - `elModeloDeLaLecturaEnVivoSobreviveAReabrirLaApp`.
  - `cambiarElModeloDeLaLecturaNoCambiaElDeLasCapturas`.

- [ ] **Paso 2: Verlos fallar**

  Run: `make test` y `make test-app`
  Expected: FAIL. `fallbacks` sigue presente con Haiku, y `haiku55` y
  `liveModel` no existen.

- [ ] **Paso 3: Implementar**

  - **Builder:** `supportsServerFallback` es
    `!model.hasPrefix("claude-haiku")`. Si es `false`, `payload` omite
    `fallbacks` y `request` omite `anthropic-beta`.
  - **`ClaudeModel`:** caso `haiku55 = "claude-haiku-5-5"`, con etiqueta
    «Haiku 5.5» y detalle «El más rápido y barato: $0,10 / $0,50 por millón de
    tokens.». El detalle de Sonnet 5.5 pasa a «Rápido y barato: $2 / $10 por
    millón de tokens.».
  - **`Preferences`:** `liveModel`, con clave `"liveModel"`, que cae a
    `.haiku55`.

- [ ] **Paso 4: Verlos pasar**

  Run: `make test && make test-app`
  Expected: todo en verde.

- [ ] **Paso 5: Commit** — `feat: Haiku 5.5 y peticiones sin fallback para Haiku`

### Tarea 3: LineDetector (Core)

**Files:**
- Create: `Core/Sources/ParlaCore/LineDetector.swift`
- Test: `Core/Tests/ParlaCoreTests/LineDetectorTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct LineDetector: Sendable {
      public static let similarityThreshold = 0.9
      public init()
      /// La línea, cuando el texto se asentó y no es la última que se soltó.
      public mutating func feed(_ text: String) -> String?
      /// Leer ahora: suelta el texto aunque se repita. `nil` solo si está vacío.
      public mutating func force(_ text: String) -> String?
      public static func normalize(_ text: String) -> String
      /// 1 − distancia de Levenshtein / longitud de la más larga; 0 si alguna está vacía.
      public static func similarity(_ a: String, _ b: String) -> Double
  }
  ```

- [ ] **Paso 1: Tests que fallan**, uno por regla de la §5.4 del spec:

  - **`elTextoQueApareceLetraPorLetraSaleUnaVez`.**
    `feed("The Gl")`, `feed("The Gloomwood")`,
    `feed("The Gloomwood stirs again.")` dos veces y otra lectura igual. Solo
    la cuarta llamada devuelve `"The Gloomwood stirs again."`.
  - **`unaLetraMalLeidaNoRepiteLaLinea`.** Tras soltar
    `"We have to hold the line until dawn."`, otras dos lecturas de
    `"We have to hold the Iine until dawn."` devuelven `nil`.
  - **`unaFraseRepetidaConOtraEnMedioSaleDosVeces`.** A, A (sale) → B, B
    (sale) → A, A (sale otra vez).
  - **`unRecuadroVacioPermiteRepetirLaFrase`.** A, A (sale) → `""` → A, A
    (sale).
  - **`forceSueltaAunqueSeRepita`.** Tras soltar A, `force(A) == A`, y
    `force("  ") == nil`.
  - **`losBordesNoCuentan`.** `normalize("| Hello   there _") == "Hello there"`.

- [ ] **Paso 2: Verlos fallar**

  Run: `make test`
  Expected: no compila porque `LineDetector` no existe.

- [ ] **Paso 3: Implementar**

  El estado es `candidate: String?` y `lastEmitted: String?`. En `feed`:

  1. Normaliza el texto.
  2. Si queda vacío, pone `candidate` y `lastEmitted` a `nil` y devuelve
     `nil`.
  3. Si es igual a `candidate` y
     `similarity(n, lastEmitted ?? "") < similarityThreshold`, lo guarda en
     `lastEmitted` y lo devuelve.
  4. En cualquier otro caso, `candidate = n` y devuelve `nil`.

  `force` normaliza el texto, lo guarda en `lastEmitted` y en `candidate`, y
  lo devuelve.

- [ ] **Paso 4: Verlos pasar** — `make test`, todo en verde.

- [ ] **Paso 5: Commit** — `feat: detector de líneas nuevas`

### Tarea 4: TextReader (Core) y sonda 1

`TextReader` va en Core y no en la app, como decía la §5.3 del spec. Vision
existe también en iOS, y así se prueba en `make test`. Hay que apuntarlo en
el ledger como `Ruling:`.

**Files:**
- Create: `Core/Sources/ParlaCore/TextReader.swift`
- Test: `Core/Tests/ParlaCoreTests/TextReaderTests.swift`
- Modify: `Core/Sources/parla-eval/main.swift` (subcomando `ocr`), `Makefile` (`eval-ocr`)
- Create: `Core/Fixtures/en-vivo/imagenes/` (capturas de Edwin, `<nombre>.png` con `<nombre>.txt` al lado)

**Interfaces:**
- Produces:
  ```swift
  public enum TextReader {
      public static let minimumConfidence: Float = 0.3
      /// Las líneas de arriba abajo, unidas con un espacio. "" si no hay texto.
      public static func read(_ image: CGImage) async throws -> String
  }
  ```

- [ ] **Paso 1: Tests que fallan**

  Un helper de test, `render(_ lines: [String]) -> CGImage`, dibuja texto
  negro de 32 pt sobre blanco con CoreText, en un lienzo de 900×200.

  - **`leeLasLineasDeArribaAbajoEnUnSoloTexto`.**
    `read(render(["The Gloomwood stirs again.", "We have to hold the line."]))`
    es `"The Gloomwood stirs again. We have to hold the line."`.
  - **`unaImagenSinTextoDevuelveVacio`.** Un lienzo en blanco devuelve `""`.

- [ ] **Paso 2: Verlos fallar** — `make test`; no compila.

- [ ] **Paso 3: Implementar**

  - Configura `RecognizeTextRequest` con `recognitionLevel = .accurate`,
    `recognitionLanguages = [Locale.Language(identifier: "en-US")]` y
    `usesLanguageCorrection = true`.
  - Descarta las observaciones con confianza menor de `minimumConfidence`.
  - Ordena por `boundingBox` (Vision mide desde abajo): primero el `maxY`
    mayor y, a igualdad, el `minX` menor.
  - Une el primer candidato de cada observación con `" "`.

- [ ] **Paso 4: Verlos pasar** — `make test`.

- [ ] **Paso 5: Subcomando `parla-eval ocr <carpeta>`**

  - Para cada `.png`, lee la imagen con `TextReader` y la compara con su
    `.txt` usando `LineDetector.normalize` en los dos lados.
  - Imprime `✓`/`✗`, el texto leído y los milisegundos. Al final, `N/M
    exactas`.
  - No usa la API ni la clave.
  - Target del Makefile:
    `eval-ocr: cd Core && swift run parla-eval ocr Fixtures/en-vivo/imagenes`.
  - Sin argumentos de subcomando, `parla-eval <carpeta>` sigue haciendo la
    evaluación de capturas de siempre.

- [ ] **Paso 6: Sonda 1**

  Run: `make eval-ocr` con las 10 capturas de AFK Journey de Edwin. Se recorta
  solo el cuadro de diálogo y el `.txt` lleva el texto que se ve.

  Expected: al menos 8 de 10 exactas y menos de 300 ms por imagen.

  Si no llega, se aplica la alternativa de la §10:

  1. probar sin corrección de idioma;
  2. probar con la imagen ampliada ×2;
  3. si sigue sin llegar, parar y hablarlo con Edwin, porque la lectura mixta
     cambia el alcance.

  El resultado se anota en la §10. Si Edwin aún no ha mandado las capturas, se
  apunta en el ledger y se sigue; la sonda tiene que estar hecha antes de la
  Tarea 13.

- [ ] **Paso 7: Commit** — `feat: lector de texto con Vision y evaluación de OCR`

### Tarea 5: Petición y respuesta de la lectura en vivo (Core)

**Files:**
- Create: `Core/Sources/ParlaCore/LiveReading.swift` (tipos, `NotebookContext` y el protocolo)
- Create: `Core/Sources/ParlaCore/LiveReadingSystemPrompt.swift`
- Modify: `Core/Sources/ParlaCore/ClaudeRequestBuilder.swift`, `Core/Sources/ParlaCore/ClaudeExplainer.swift`
- Test: `Core/Tests/ParlaCoreTests/LiveReadingRequestTests.swift`, `Core/Tests/ParlaCoreTests/LiveReadingTranslatorTests.swift`

**Interfaces:**
- Consumes: `supportsServerFallback` (Tarea 2).
- Produces:
  ```swift
  public struct LiveExpression: Codable, Sendable, Equatable { public let phrase: String; public let meaning: String }
  public struct LiveTranslation: Codable, Sendable, Equatable {
      public let spanish: String; public let save: Bool; public let expressions: [LiveExpression]
  }
  public struct NotebookContext: Sendable, Equatable {
      public static let lineLimit = 12
      public let about: String
      public let recentLines: [String]          // en inglés, de la más vieja a la más nueva
      public init(about: String, recentLines: [String])   // se queda con las últimas 12
      public var promptText: String
  }
  public protocol LiveReadingTranslator: Sendable {
      /// Una entrada por línea pedida, en el mismo orden; `nil` = sin traducir.
      func translate(_ lines: [String], context: NotebookContext) async throws -> [LiveTranslation?]
      func explain(_ line: String, context: NotebookContext) async throws -> LiveTranslation?
  }
  extension ClaudeRequestBuilder {
      public func makeLiveReadingRequest(lines: [String], context: NotebookContext, apiKey: String) throws -> URLRequest
      public func makeExplainLineRequest(line: String, context: NotebookContext, apiKey: String) throws -> URLRequest
  }
  extension ClaudeExplainer: LiveReadingTranslator
  ```

  El texto de `promptText` va en este orden:

  1. `"De qué trata: <about>"`, que se omite si `about` está vacío tras
     recortar;
  2. `"Líneas anteriores:"` con las líneas numeradas `1.` a `n.`, que se
     omite si no hay ninguna.

  Los bloques van separados por una línea en blanco. La petición manda como
  mensaje del usuario `promptText`, una línea en blanco y
  `"Líneas nuevas:\n1. …"`. `makeExplainLineRequest` añade al final
  `"Explica siempre esta línea: save en true y al menos una expresión."`. Las
  dos peticiones comparten el system prompt, para compartir caché.

  El esquema es
  `{lines: [{spanish, save, expressions: [{phrase, meaning}]}]}`, con todos
  los campos obligatorios, `additionalProperties: false` y sin
  `minItems`/`maxItems`. El system prompt (`LiveReadingSystemPrompt.text`)
  sigue la §5.6: español natural de Latinoamérica, usar el contexto, `save`
  solo para expresiones, modismos o usos que valga la pena estudiar, y cada
  explicación en una o dos frases, con cuándo se usa.

- [ ] **Paso 1: Tests que fallan**

  En `LiveReadingRequestTests`:

  - **`elContextoLlevaDeQueTrataYLasUltimasDoce`.** Con 15 líneas, solo
    entran de la 4 a la 15, numeradas `1.`–`12.`.
  - **`sinDeQueTrataNoSeMandaEseBloque`.**
  - **`laPeticionNumeraLasLineasNuevas`.** Con 2 líneas, el contenido termina
    en `"Líneas nuevas:\n1. A\n2. B"`.
  - **`elEsquemaPideTraduccionGuardarYExpresiones`.**
  - **`explicarComparteElSystemPromptYPideExplicar`.**
  - **`conHaikuLaLecturaEnVivoVaSinFallback`.**

  En `LiveReadingTranslatorTests`, con `FakeStreamer` y `sseLines(forJSON:)`:

  - **`traduceVariasLineasEnOrden`.**
  - **`descartaLasExpresionesVacias`.** `{"phrase":"","meaning":"x"}` y
    `{"phrase":"x","meaning":"  "}` desaparecen.
  - **`unaLineaSinEspanolQuedaSinTraducir`.** `spanish: ""` da `nil` en su
    posición.
  - **`siFaltanLineasLasUltimasQuedanSinTraducir`.** Se piden 3, llegan 2 y
    el resultado es `[t1, t2, nil]`.
  - **`unaRespuestaCortadaEsMalformada`.** Con un JSON truncado y
    `stopReason: "max_tokens"`, lanza `ExplainerError.malformedResponse`.

- [ ] **Paso 2: Verlos fallar** — `make test`; no compila.

- [ ] **Paso 3: Implementar**

  - Los esquemas siguen el patrón de `captureSchema`.
  - El streaming reusa `streamJSON`.
  - Antes de devolver, la respuesta se ajusta a `lines.count`: se rellena con
    `nil` o se recorta.

- [ ] **Paso 4: Verlos pasar** — `make test`.

- [ ] **Paso 5: Commit** — `feat: petición y respuesta de la lectura en vivo`

### Tarea 6: Evaluación de la lectura en vivo y sonda 4

**Files:**
- Modify: `Core/Sources/parla-eval/main.swift` (subcomando `live`), `Makefile` (`eval-live`)
- Create: `Core/Fixtures/en-vivo/dialogos/*.json` (al menos 6)

**Interfaces:**
- Consumes: `ClaudeExplainer.translate(_:context:)` (Tarea 5).
- Formato de un fixture:
  ```json
  { "about": "RPG de fantasía; Maren es la capitana; el Gloomwood es un bosque maldito.",
    "history": ["The Gloomwood stirs again. We have to hold the line until dawn."],
    "lines": [ { "english": "Then we hold it together. Nobody falls back.",
                 "expectSave": false, "mustMention": ["línea", "aguant", "resist"] } ] }
  ```
  `mustMention` se cumple si la traducción contiene **alguna** de las
  palabras, sin distinguir mayúsculas.

- [ ] **Paso 1: Escribir los fixtures**

  Los diálogos son inventados, al estilo de AFK Journey:

  - una línea que solo se entiende con contexto («hold it»);
  - una expresión que debe guardarse («don't sweat it»);
  - dos triviales que no se guardan («Let's go», «Thank you»);
  - `cinco-lineas.json`, con 5 líneas en una sola petición (la sonda 4);
  - una con el «De qué trata» vacío.

- [ ] **Paso 2: Subcomando `parla-eval live <carpeta>`**

  - Usa `PARLA_MODEL`, o `claude-haiku-5-5` si no está.
  - Para cada fixture, imprime por línea:
    - si salió `nil`;
    - si `save` coincide con lo esperado;
    - si se cumple `mustMention`.
  - Al final imprime `N/M líneas correctas`.
  - Target del Makefile:
    `eval-live: cd Core && swift run parla-eval live Fixtures/en-vivo/dialogos`.

- [ ] **Paso 3: Compilar**

  Run: `cd Core && swift build --product parla-eval`
  Expected: `Build complete!`

- [ ] **Paso 4: Correrla con el OK de Edwin**

  Primero con Haiku y luego con `PARLA_MODEL=claude-opus-5-5`.

  Expected:

  - Al menos el 80 % de las líneas correctas con Haiku.
  - `cinco-lineas.json` trae 5 traducciones no vacías, en orden: la
    `mustMention` de cada una coincide.

  Si la sonda 4 falla, `LiveSession.maxBatch` pasa a 1 en la Tarea 10. Se
  anota en la §10 y en el ledger.

- [ ] **Paso 5: Commit** — `feat: evaluación de la lectura en vivo`

### Tarea 7: Cuadernos en SwiftData

**Files:**
- Create: `App/Store/Notebook.swift` (`Notebook`, `NotebookLine`, `StoredExpression`)
- Create: `App/Store/NotebookStore.swift`
- Modify: `App/Store/Persistence.swift` (`makeContainer` con los modelos nuevos)
- Test: `AppTests/NotebookStoreTests.swift`, `AppTests/StoredCardMigrationTests.swift`

**Interfaces:**
- Consumes: `LiveTranslation`, `NotebookContext` (Tarea 5).
- Produces:
  ```swift
  @Model final class Notebook { var id: UUID; var name: String; var about: String = ""; var createdAt: Date
      @Relationship(deleteRule: .cascade, inverse: \NotebookLine.notebook) var lines: [NotebookLine] = [] }
  @Model final class NotebookLine { var id: UUID; var english: String; var spanish: String?
      var sessionID: UUID; var readAt: Date; var notebook: Notebook?; var isSaved: Bool = false
      @Relationship(deleteRule: .cascade) var expressions: [StoredExpression] = [] }
  @Model final class StoredExpression { var phrase: String; var meaning: String }

  @ModelActor actor NotebookStore {
      func createNotebook(name: String, about: String) -> UUID
      func updateNotebook(_ id: UUID, name: String, about: String)
      func deleteNotebook(_ id: UUID)
      func insertLine(id: UUID, english: String, sessionID: UUID, notebookID: UUID?, readAt: Date)
      /// `nil` deja la línea sin traducir. Guarda si `translation.save`.
      func apply(_ translation: LiveTranslation?, toLine id: UUID)
      /// «Guardar» a mano: guarda aunque el modelo no la hubiera marcado.
      func save(line id: UUID, with translation: LiveTranslation)
      func unsave(line id: UUID)
      /// Con cuaderno, sus últimas 12 en cualquier sesión; sin él, las de la sesión.
      func context(notebookID: UUID?, sessionID: UUID) -> NotebookContext
      func neighbors(ofLine id: UUID) -> (before: String?, after: String?)
  }
  ```

- [ ] **Paso 1: Tests que fallan**

  Usan un contenedor en memoria creado con `Persistence.makeContainer`, que
  recibe una `ModelConfiguration(isStoredInMemoryOnly: true)`.

  - **`elContextoCruzaSesionesDelMismoCuaderno`.** 8 líneas en una sesión y 8
    en otra: el contexto trae las 12 últimas por `readAt`.
  - **`sinCuadernoElContextoEsSoloDeLaSesion`.**
  - **`elContextoLlevaElDeQueTrataDelCuaderno`.**
  - **`aplicarUnaTraduccionConSaveLaGuarda`.**
  - **`aplicarNilLaDejaSinTraducir`.**
  - **`guardarAManoGuardaConSusExpresiones`.**
  - **`lasVecinasSonDeLaMismaSesion`.** Una línea de otra sesión intercalada
    por fecha no cuenta.
  - **`borrarUnCuadernoBorraSusLineas`.**

  En `StoredCardMigrationTests`, el test
  `unaBaseSinCuadernosAbreConLosModelosNuevos` crea la base solo con el
  esquema de `StoredCard` actual, la reabre con `Persistence.makeContainer` y
  comprueba que la tarjeta sigue ahí y que se puede insertar un `Notebook`.

- [ ] **Paso 2: Verlos fallar** — `make test-app`; no compila.

- [ ] **Paso 3: Implementar**

  `makeContainer` pasa a
  `ModelContainer(for: StoredCard.self, Notebook.self, NotebookLine.self, configurations: configuration)`.

- [ ] **Paso 4: Verlos pasar** — `make test-app`.

- [ ] **Paso 5: Commit** — `feat: cuadernos y líneas en SwiftData`

### Tarea 8: LiveSetup, geometría del recuadro y preferencias

**Files:**
- Create: `Core/Sources/ParlaCore/LiveSetup.swift`
- Modify: `App/Preferences.swift`
- Test: `Core/Tests/ParlaCoreTests/LiveSetupTests.swift`, `AppTests/PreferencesTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum LiveSource: Codable, Sendable, Equatable { case window(bundleID: String, title: String); case screen }
  public enum LiveRhythm: String, Codable, Sendable, CaseIterable { case automatic, onDemand }
  public enum LiveDisplay: String, Codable, Sendable, CaseIterable { case subtitle, panel, cover }
  /// `region`: con `.window`, fracciones 0…1 de la ventana con origen ARRIBA a la izquierda (como
  /// la imagen del stream); con `.screen`, coordenadas globales de ScreenCaptureKit (también arriba).
  public struct LiveSetup: Codable, Sendable, Equatable { public var source: LiveSource; public var region: CGRect; public var notebookID: UUID? }
  public struct WindowCandidate: Sendable, Equatable { public let windowID: UInt32; public let bundleID: String; public let title: String; public let frame: CGRect }
  public enum LiveGeometry {
      public static func fraction(of rect: CGRect, in window: CGRect) -> CGRect
      public static func pixelRect(fraction: CGRect, imageWidth: Int, imageHeight: Int) -> CGRect   // entero, dentro de la imagen
      /// El mismo título dentro de la app y, si no, la ventana más grande de esa app.
      public static func pickWindow(for source: LiveSource, among: [WindowCandidate]) -> WindowCandidate?
  }
  public struct LiveSetupMemory: Codable, Sendable, Equatable {
      public var last: LiveSetup?; public var byApp: [String: LiveSetup]
      public mutating func remember(_ setup: LiveSetup)
  }
  ```

  En `Preferences` se añaden `liveSetupMemory` (JSON en la clave
  `"liveSetupMemory"`), `liveRhythm` y `liveDisplay`.

- [ ] **Paso 1: Tests que fallan**

  - **`laFraccionYElRecorteSonInversos`.** Ventana `(100, 50, 800, 600)`,
    recuadro `(140, 500, 720, 120)`: la fracción da `(0.05, 0.75, 0.9, 0.2)`,
    y `pixelRect` con una imagen de 1600×1200 da `(80, 900, 1440, 240)`.
  - **`elRecorteEscalaConLaImagen`.** La misma fracción con 800×600 da
    `(40, 450, 720, 120)`.
  - **`elRecorteNoSeSaleDeLaImagen`.** La fracción `(0.9, 0.9, 0.3, 0.3)` se
    recorta al borde.
  - **`reencuentraLaVentanaPorTituloYSiNoLaMasGrande`.**
  - **`recordarGuardaLaUltimaYLaDeSuApp`.** Con `.screen` no se toca `byApp`.

  En `PreferencesTests`:

  - **`laMemoriaDeLaLecturaSobreviveAReabrir`.**
  - **`laVistaEmpiezaEnElPanelYElRitmoEnAutomatico`.**

- [ ] **Paso 2: Verlos fallar** — `make test` y `make test-app`.

- [ ] **Paso 3: Implementar** — en `pixelRect`, redondea hacia fuera y
  recorta contra la imagen.

- [ ] **Paso 4: Verlos pasar** — `make test && make test-app`.

- [ ] **Paso 5: Commit** — `feat: configuración y geometría de la lectura en vivo`

### Tarea 9: Fuente de fotogramas (ScreenCaptureKit)

**Files:**
- Create: `App/Live/FrameSource.swift` (protocolo y eventos), `App/Live/RegionWatcher.swift`
- Test: `AppTests/RegionWatcherTests.swift`

**Interfaces:**
- Consumes: `LiveSetup`, `LiveGeometry`, `WindowCandidate` (Tarea 8).
- Produces:
  ```swift
  enum LivePauseReason: Equatable, Sendable { case windowHidden, windowClosed, fullScreenUnavailable, readerFailed(String) }
  enum LiveFrameEvent: Sendable { case frame(CGImage); case paused(LivePauseReason); case resumed }
  protocol FrameSource: Sendable {
      /// Fotogramas ya recortados al recuadro, a 2 fps.
      func frames() -> AsyncStream<LiveFrameEvent>
      /// Una sola imagen recortada, para «Leer ahora» y el ritmo «Cuando yo diga».
      func snapshot() async throws -> CGImage
  }
  final class RegionWatcher: FrameSource   // init(setup: LiveSetup)
  enum WindowList { static func candidates() async throws -> [WindowCandidate] }   // sin Parla y sin ventanas de menos de 100×100
  ```

- [ ] **Paso 1: Test que falla**

  `elRecorteSeCalculaSobreElTamañoDelFotograma`: una función pura,
  `RegionWatcher.crop(_ image: CGImage, setup: LiveSetup) -> CGImage?`, sobre
  una imagen sintética de 400×300 con la fracción `(0.5, 0.5, 0.5, 0.5)` da
  una imagen de 200×150.

- [ ] **Paso 2: Verlo fallar** — `make test-app`.

- [ ] **Paso 3: Implementar**

  - **Con ventana:** un `SCStream` con
    `SCContentFilter(desktopIndependentWindow:)`, a 2 fps
    (`minimumFrameInterval`) y con el tamaño de la configuración igual al de
    la ventana por su `pointPixelScale`.
  - **Cambios de tamaño:** cada segundo se compara el `frame` de la ventana en
    `SCShareableContent`. Si cambió, `updateConfiguration`. Si ya no está,
    emite `.paused(.windowClosed)`, y cuando `LiveGeometry.pickWindow` la
    encuentra otra vez, `.resumed`.
  - **Sin fotogramas:** si pasan más de 3 s sin un fotograma `.complete`,
    emite `.paused(.windowHidden)`. Si la sonda 2 dio 0 fps en pantalla
    completa, usa `.fullScreenUnavailable` cuando la ventana ocupa toda la
    pantalla.
  - **Con pantalla:** el filtro de la pantalla excluye las ventanas de Parla
    (`excludingApplications` con la app propia) y usa `sourceRect = region`.
  - **`snapshot()`:** `SCScreenshotManager.captureImage` con el mismo filtro y
    el mismo recorte.

- [ ] **Paso 4: Verlo pasar** — `make test-app`.

- [ ] **Paso 5: Commit** — `feat: fotogramas del recuadro con ScreenCaptureKit`

### Tarea 10: LiveSession

**Files:**
- Create: `App/Live/LiveSession.swift`
- Test: `AppTests/LiveSessionTests.swift` (con fakes: `FakeFrameSource` sobre una continuación de `AsyncStream`, un lector que devuelve un guion de textos y `FakeLiveTranslator` con una puerta para retener respuestas)

**Interfaces:**
- Consumes:
  - `FrameSource` y `LiveFrameEvent` (Tarea 9);
  - `LineDetector` (Tarea 3);
  - `LiveReadingTranslator` y `LiveTranslation` (Tarea 5);
  - `NotebookStore` (Tarea 7);
  - `LiveSetup` y `LiveRhythm` (Tarea 8).
- Produces:
  ```swift
  struct LiveLineState: Identifiable, Equatable {
      enum Status: Equatable { case translating, translated(LiveTranslation), untranslated(String) }  // String = motivo para el panel
      let id: UUID; let english: String; var status: Status; var isSaved: Bool
  }
  enum LiveSessionState: Equatable { case running, paused(LivePauseReason), stopped }
  @MainActor @Observable final class LiveSession {
      static var maxBatch = 5            // 1 si la sonda 4 falló
      init(setup: LiveSetup, rhythm: LiveRhythm, frames: any FrameSource,
           read: @escaping @Sendable (CGImage) async throws -> String,
           translator: any LiveReadingTranslator, store: NotebookStore, sessionID: UUID = UUID())
      private(set) var state: LiveSessionState
      private(set) var lines: [LiveLineState]      // la más nueva primero
      private(set) var notice: String?             // «No encontré texto en el recuadro»
      var rhythm: LiveRhythm                        // al cambiarlo, arranca o para el stream
      func start(); func stop()
      func readNow() async
      func retry(_ id: UUID)
      func save(_ id: UUID)                         // si no traía expresiones, llama a explain
  }
  ```

- [ ] **Paso 1: Tests que fallan**

  - **`unaLineaNuevaSeTraduceYSeGuarda`.** El texto estable entra al store y
    su estado pasa a `.translated`.
  - **`lasPendientesVanJuntasEnOrden`.** Llegan A, B y C mientras A está
    retenida: la segunda llamada al traductor es `[B, C]`.
  - **`masDeCincoPendientesVanEnTandasDeCinco`.** Con 7 pendientes, las
    llamadas son de 5 y de 2, en orden.
  - **`unErrorDejaLaLineaSinTraducirYSePuedeReintentar`.** `retry` vuelve a
    pedir solo esa línea.
  - **`sinClaveLaLineaQuedaSinTraducirYLaLecturaSigue`.** Un
    `ExplainerError.missingAPIKey` da un `.untranslated` con
    «Falta la clave de API», y la línea siguiente se sigue procesando.
  - **`noVuelveATraducirSuPropiaTraduccion`.** Un texto igual al `spanish`
    de una de las últimas 12 líneas se ignora.
  - **`laPausaDetieneLaLectura`.** Tras `.paused(.windowClosed)` el estado es
    `.paused` y los fotogramas siguientes no leen nada hasta `.resumed`.
  - **`leerAhoraConElRecuadroVacioAvisa`.** Pone `notice ==
    "No encontré texto en el recuadro"`.
  - **`enCuandoYoDigaNoSeConsumenFotogramas`.**
  - **`guardarAManoSinExpresionesPideExplicar`.**
  - **`unFalloDelLectorPausaLaSesion`.** Si `read` lanza, el estado es
    `.paused(.readerFailed(...))` y se registra en `Log`.

- [ ] **Paso 2: Verlos fallar** — `make test-app`.

- [ ] **Paso 3: Implementar**

  - Hay una sola petición en vuelo. Al terminar, toma hasta `maxBatch`
    pendientes.
  - El contexto se pide a `store.context(notebookID:sessionID:)` justo antes
    de cada petición.
  - Mensajes de `ExplainerError` para el panel:

    | Error | Mensaje |
    |---|---|
    | `missingAPIKey` | «Falta la clave de API» |
    | `rateLimited` | «Demasiadas peticiones; prueba en un momento» |
    | `network` | «Sin conexión» |
    | `malformedResponse`, `refused`, `server` | «No se pudo traducir» |

- [ ] **Paso 4: Verlos pasar** — `make test-app`.

- [ ] **Paso 5: Commit** — `feat: sesión de lectura en vivo`

### Tarea 11: Atajos, modo, arranque y vistas de la traducción

**Files:**
- Modify:
  - `Core/Sources/ParlaCore/SetupStatus.swift` (`ParlaMode.live`; `.apiKey` y `.screenRecording` incluyen `.live`)
  - `App/Shortcuts.swift` (`toggleLiveReading` ⌃⌥L, `readLiveNow` ⌃⌥R)
  - `App/ParlaApp.swift` (los dos `onKeyUp` y el icono activo si hay sesión)
  - `App/MenuBar/ModeTile.swift`, `App/MenuBar/MenuBarPopover.swift`, `App/Welcome/WelcomeView.swift` (cuarta casilla «Lectura en vivo», símbolo `text.viewfinder`)
  - `App/AppState.swift` (`liveSession`, `toggleLiveReading()`, `readLiveNow()`, `liveModel`, `liveDisplay`)
  - `App/Studio/SettingsSection.swift` (selector «Modelo para la lectura en vivo», «Ver la traducción» con A/B/C, y los dos `Recorder` «Lectura en vivo:» y «Leer ahora:»)
- Create:
  - `App/Live/LiveSetupFlow.swift` (ventana: lista de `WindowList.candidates()` más «Un recuadro de la pantalla», luego el recuadro con `SelectionOverlay` limitado a la ventana, luego el cuaderno: existentes, «Nuevo cuaderno» con nombre y «De qué trata», o «Sin cuaderno»)
  - `App/Live/LivePanelView.swift` (B: interruptor «Automático / Cuando yo diga», fuente, cuaderno, «Leer ahora», «Terminar», y las líneas con «Guardar», «Reintentar» y «sin traducir»)
  - `App/Live/LiveSubtitleStrip.swift` (A: franja encima del recuadro con el estilo de `SubtitleOverlay`)
  - `App/Live/LiveCover.swift` (C: panel sin bordes, `ignoresMouseEvents`, fondo opaco, sobre el recuadro)
- Test: `Core/Tests/ParlaCoreTests/SetupStatusTests.swift`, `AppTests/ModeTileTests.swift`, `AppTests/LiveSetupFlowTests.swift`

**Interfaces:**
- Consumes:
  - `LiveSession` (Tarea 10);
  - `RegionWatcher` y `WindowList` (Tarea 9);
  - `LiveSetupMemory` y `Preferences` (Tarea 8);
  - `NotebookStore` (Tarea 7);
  - `ClaudeExplainer` con `liveModel.requestBuilder`.
- Produces: `AppState.liveSession: LiveSession?`, que usa la Tarea 12 para
  «Seguir leyendo».

- [ ] **Paso 1: Tests que fallan**

  - **`laLecturaEnVivoNecesitaClaveYGrabacionDePantalla`**
    (`SetupStatusTests`): `blockers(for: .live)` contiene los dos.
  - **`laCasillaDeLecturaEnVivoTieneNombreYSimbolo`** (`ModeTileTests`).
  - En `LiveSetupFlowTests`, el estado puro del flujo,
    `LiveSetupFlowModel`, con los pasos `.source`, `.region` y `.notebook`:
    - **`conUnaConfiguracionRecordadaArrancaSinPreguntar`.** Si
      `memory.last` existe y `pickWindow` la encuentra, `nextStep == nil`.
    - **`sinLaVentanaRecordadaEmpiezaPorLaFuente`.**
    - **`alElegirUnaAppRecordadaSaltaAlCuaderno`.** Con `byApp`, la región
      ya viene puesta.

- [ ] **Paso 2: Verlos fallar** — `make test && make test-app`.

- [ ] **Paso 3: Implementar**

  - **El panel B** es una instancia aparte de `FloatingPanel` con
    `LivePanelView`, no el `PanelView` de las capturas, para que las dos
    listas no se mezclen. Hay que apuntarlo como `Ruling:`.
  - **Arranque:** ⌃⌥L pasa por `canStart(.live)`, igual que los demás modos.
  - **Coordenadas del recuadro:** `SelectionOverlay` devuelve coordenadas de
    AppKit, con origen abajo. Antes de `LiveGeometry.fraction` se convierten
    con `ScreenCapturer.displaySpace`, porque el `frame` de la ventana viene
    de ScreenCaptureKit, con origen arriba.
  - **Vista de la traducción:** según `liveDisplay`, se muestra A, B o C. En A
    y C el panel se abre desde la casilla del menú emergente.
  - **Pantalla completa:** si la sonda 3 falló, con la ventana a pantalla
    completa se usa A en lugar de C y se avisa una vez.

- [ ] **Paso 4: Verlos pasar** — `make test && make test-app`.

- [ ] **Paso 5: Compilar y abrir**

  Run: `make run`

  Expected: el menú emergente muestra cuatro casillas, y ⌃⌥L abre el flujo de
  configuración. Se revisa con una captura (`PARLA_SNAPSHOT_AFTER`).

- [ ] **Paso 6: Commit** — `feat: arranque, atajos y vistas de la lectura en vivo`

### Tarea 12: Estudio › Cuadernos

**Files:**
- Modify: `App/Studio/StudioRouter.swift` (`case notebooks`, título «Cuadernos», símbolo `books.vertical`), `App/Studio/StudioView.swift` (la fila de la lista y el `switch`)
- Create: `App/Studio/NotebooksSection.swift` (lista con el número de líneas guardadas; «Sin cuaderno» al final; «+»), `App/Studio/NotebookDetailView.swift`
- Test: `AppTests/StudioRouterTests.swift`, `AppTests/NotebookListTests.swift`

**Interfaces:**
- Consumes: `Notebook`, `NotebookLine` y `NotebookStore` (Tarea 7).
- Produces:
  ```swift
  enum NotebookListEntry: Hashable { case notebook(UUID); case none }
  enum NotebookList {
      /// Por fecha de creación, la más nueva arriba, y «Sin cuaderno» siempre al final.
      static func entries(_ notebooks: [Notebook]) -> [NotebookListEntry]
  }
  /// La línea guardada, con sus expresiones subrayadas: rangos de `phrase` dentro de `english`, sin mayúsculas.
  enum ExpressionHighlight { static func ranges(of phrases: [String], in english: String) -> [Range<String.Index>] }
  ```

- [ ] **Paso 1: Tests que fallan**

  - **`sinCuadernoVaSiempreAlFinal`.**
  - **`resaltaLaExpresionSinImportarMayusculas`.** `"hold the line"` dentro de
    `"We have to Hold the line until dawn."` da un rango.
  - **`unaExpresionQueNoApareceNoResaltaNada`.**
  - **`abrirCuadernosCambiaLaSeccion`** (`StudioRouterTests`).

- [ ] **Paso 2: Verlos fallar** — `make test-app`.

- [ ] **Paso 3: Implementar**

  - **Detalle del cuaderno:**
    - arriba, el nombre y el «De qué trata», editables con
      `updateNotebook`;
    - debajo, las líneas guardadas con `@Query`, filtradas por cuaderno y
      `isSaved`, de la más reciente a la más vieja. Cada una lleva el
      «antes» y el «después» en gris (`neighbors`), el inglés en serif con
      las expresiones subrayadas en el acento, el español y las
      explicaciones.
  - **«Ver todas las líneas»:** cambia a la lista completa, sin
    explicaciones.
  - **Borrar:** quitar una línea (`unsave`) y borrar el cuaderno, con
    confirmación. «Sin cuaderno» no se puede renombrar ni borrar.

- [ ] **Paso 4: Verlos pasar** — `make test-app`.

- [ ] **Paso 5: Commit** — `feat: sección Cuadernos en Estudio`

### Tarea 13: Prueba real con AFK Journey

No escribe código. Su entregable es el visto bueno de Edwin o una lista de
fallos, cada uno convertido en test y arreglo, como en el fix pass final.

- [ ] **Paso 1:** comprobar que las sondas 1 y 4 están anotadas en la §10.
  Si falta alguna, se hace ahora.
- [ ] **Paso 2:** `make test && make test-app`, todo en verde.
- [ ] **Paso 3:** Edwin corre `make install` y prueba lo siguiente:
  - la primera vez con ⌃⌥L: ventana, recuadro y cuaderno nuevo con «De qué
    trata»;
  - 10 minutos en Automático;
  - cambiar a «Cuando yo diga» y leer con ⌃⌥R;
  - mover y redimensionar la ventana;
  - minimizarla;
  - cambiar entre las vistas A, B y C;
  - guardar una línea a mano;
  - terminar, abrir Estudio › Cuadernos y volver con ⌃⌥L para que arranque
    directo.
- [ ] **Paso 4:** lo que falle se arregla con su test y queda en el ledger.
