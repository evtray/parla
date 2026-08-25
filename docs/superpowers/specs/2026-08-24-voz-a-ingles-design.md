# Parla — diseño

**Fecha:** 2026-08-24
**Estado:** aprobado, listo para plan de implementación
**Nombre en clave:** Parla (provisional)

## 1. Problema

Edwin quiere aprender inglés hablando. Las herramientas de traducción le dan
el resultado pero no el motivo, así que traduce sin aprender: la próxima vez
vuelve a construir la frase igual de mal.

Parla escucha lo que dice en español y muestra, en una ventana flotante sobre
cualquier app, cómo se diría en inglés **y por qué se dice así**. El valor no
está en la traducción; está en la explicación.

## 2. Alcance

**v1 hace esto:**

- Escucha el micrófono mientras el usuario enciende la sesión de práctica.
- Transcribe español en el dispositivo, con transcripción parcial visible.
- Corta por frases y traduce cada una al inglés.
- Explica la construcción en 2-3 viñetas, en español.
- Resalta hasta 3 términos de vocabulario (puede no haber ninguno).
- Guarda todo en una base local navegable y buscable.

**v1 no hace esto** (decisiones tomadas, no omisiones):

- No escucha el audio del sistema, solo el micrófono.
- No corrige inglés hablado; el flujo es español → inglés.
- No pronuncia las frases (sin TTS ni IPA).
- No ofrece registros alternativos (formal/casual).
- No implementa repaso espaciado ni exporta a Anki.
- No manda contexto conversacional: cada frase se traduce aislada.
- No reintenta automáticamente los fallos de red.

## 3. Arquitectura

Cada pieza tiene un propósito único y un límite explícito.

```
micrófono
   │
   ▼
AudioCapture ──buffers──▶ Transcriber
                            ├─ .partial(String) ─────────▶ panel (texto gris en vivo)
                            └─ .final(String)
                                    │
                                    ▼
                            UtteranceSegmenter ──Utterance──▶ AppState
                                                                 │
                                                    crea Card(.pendiente)
                                                                 │
                                                                 ▼
                                                          ClaudeExplainer
                                                            (HTTP + SSE)
                                                                 │
                                                          Card completa
                                                                 │
                                                    ┌────────────┴────────────┐
                                                    ▼                         ▼
                                              FloatingPanel              CardStore
                                                                        (SwiftData)
```

| Pieza | Responsabilidad | Depende de |
|---|---|---|
| `AudioCapture` | Tap sobre `AVAudioEngine`, conversión al formato del analizador, nivel RMS | AVFoundation |
| `Transcriber` (protocolo) | Buffers → `.partial` / `.final` | — |
| `SpeechTranscriberEngine` | Implementación con `SpeechAnalyzer` | Speech.framework |
| `UtteranceSegmenter` | Decide dónde termina una frase | `Transcriber` |
| `Explainer` (protocolo) | `Utterance` → `Card` | — |
| `ClaudeExplainer` | Implementación HTTP/SSE contra la API de Anthropic | URLSession, Keychain |
| `CardStore` | Persistencia y consulta | SwiftData |
| `AppState` | Orquesta: encendido, tarjetas vivas, errores | todas |
| UI | `MenuBarExtra`, `FloatingPanel`, `HistoryWindow`, `SettingsWindow` | AppKit/SwiftUI |

### Por qué protocolos en Transcriber y Explainer

No es abstracción especulativa. `Explainer` necesita un doble falso para poder
probar el pipeline completo sin red ni gasto de API. `Transcriber` necesita lo
mismo para probar el segmentador y la UI sin micrófono. Ninguno de los dos
protocolos existe para soportar una segunda implementación real.

### Concurrencia

Cada `Utterance` se procesa en su propio `Task`. Tres frases seguidas no hacen
cola. Como pueden completarse desordenadas, el panel y el historial ordenan por
`Utterance.startedAt`, no por orden de llegada de la respuesta.

`AppState` es un `@MainActor @Observable`. `CardStore` escribe desde un
`ModelActor` para no bloquear la UI.

## 4. Componentes

### 4.1 AudioCapture

Abre `AVAudioEngine`, instala un tap en `inputNode` y publica una
`AsyncStream<AnalyzerInput>` ya convertida al formato que pide el analizador
(`SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)`), usando
`AVAudioConverter`.

Publica también el nivel RMS, que el panel usa para un indicador de que sí está
oyendo.

Se suscribe a `AVAudioEngine.configurationChangeNotification`: si el usuario
desconecta unos auriculares, reconstruye el tap y sigue.

### 4.2 SpeechTranscriberEngine

API verificada contra el SDK local de macOS 26.5
(`Speech.framework/.../arm64e-apple-macos.swiftinterface`):

```swift
let transcriber = SpeechTranscriber(
    locale: Locale(identifier: "es-419"),   // resuelto vía supportedLocale(equivalentTo:)
    preset: .progressiveTranscription       // incluye volatileResults
)
let analyzer = SpeechAnalyzer(modules: [transcriber])
try await analyzer.start(inputSequence: audioCapture.stream)

for try await result in transcriber.results {
    // result.text: AttributedString
    // result.range: CMTimeRange
    // result.resultsFinalizationTime: CMTime
    // result.isFinal: Bool   (extensión de SpeechModuleResult)
}
```

Arranque en tres pasos, cada uno con su estado visible en la UI:

1. `SpeechTranscriber.supportedLocale(equivalentTo:)` resuelve el locale de
   español del usuario. Si devuelve `nil`, error explícito.
2. `AssetInventory.status(forModules:)` → `unsupported` / `supported` /
   `downloading` / `installed`. Si no está instalado,
   `AssetInventory.assetInstallationRequest(supporting:)` lo descarga con
   progreso.
3. `AssetInventory.reserve(locale:)` para que el sistema no libere el modelo.

**No se usa `SFSpeechRecognizer`.** La interfaz Swift de `SpeechAnalyzer` no
expone ninguna API de autorización, lo que confirma que la ruta nueva no pasa
por `requestAuthorization`. Aun así el `Info.plist` declara
`NSMicrophoneUsageDescription` **y** `NSSpeechRecognitionUsageDescription`, por
si el TCC de reconocimiento aplica en tiempo de ejecución. Cuesta dos líneas y
evita un crash.

### 4.3 UtteranceSegmenter

La pieza con más lógica propia y cero dependencias del sistema.

Entrada: el flujo de `.partial` / `.final` más un reloj inyectado.
Salida: `Utterance(id: UUID, text: String, startedAt: Date)`.

Regla: acumula texto finalizado; cierra la frase cuando pasan **900 ms** sin
resultados nuevos, o cuando el texto acumulado supera 240 caracteres (frases
larguísimas se cortan para no dejar al usuario esperando).

Descarta frases de menos de 3 caracteres antes de gastar una llamada.

El reloj es inyectado precisamente para que los tests no duerman.

### 4.4 ClaudeExplainer

Swift no tiene SDK oficial de Anthropic, así que se habla HTTP directo con
`URLSession`, que es la ruta documentada para lenguajes sin SDK.

**Petición:**

```
POST https://api.anthropic.com/v1/messages
content-type: application/json
x-api-key: <Keychain>
anthropic-version: 2023-06-01
anthropic-beta: server-side-fallback-2026-07-01
```

```jsonc
{
  "model": "claude-opus-5",
  "max_tokens": 4000,
  "stream": true,
  "fallbacks": "default",
  "output_config": {
    "effort": "low",
    "format": {
      "type": "json_schema",
      "schema": {
        "type": "object",
        "properties": {
          "english": { "type": "string" },
          "why":     { "type": "array", "items": { "type": "string" },
                       "minItems": 1, "maxItems": 3 },
          "vocab":   { "type": "array", "maxItems": 3,
                       "items": { "type": "object",
                                  "properties": { "term":    { "type": "string" },
                                                  "meaning": { "type": "string" } },
                                  "required": ["term", "meaning"],
                                  "additionalProperties": false } },
          "skip":    { "type": "boolean" }
        },
        "required": ["english", "why", "vocab", "skip"],
        "additionalProperties": false
      }
    }
  },
  "system": [
    { "type": "text", "text": "<instrucciones + 3-4 ejemplos resueltos>",
      "cache_control": { "type": "ephemeral" } }
  ],
  "messages": [ { "role": "user", "content": "<la frase en español>" } ]
}
```

Notas sobre cada decisión del cuerpo:

- **`claude-opus-5` con `effort: "low"`.** El modelo más capaz, con el esfuerzo
  de razonamiento bajado para responder rápido. La calidad de la explicación
  gramatical es el producto; ahí no se recorta. Coste estimado ~$0.011 por
  tarjeta sin caché, menos con ella.
- **No se envía `thinking`.** En Opus 5 el pensamiento adaptativo está activo
  por defecto; omitir el parámetro equivale a `{"type": "adaptive"}`.
- **`output_config.format` con `json_schema`** garantiza que el primer bloque de
  texto sea JSON válido con esa forma exacta. No se pide JSON por prompt.
- **`skip`** existe porque el segmentador va a capturar toses, dudas y palabras
  a medias. Cuando la entrada no es una frase real, el modelo lo marca y la app
  descarta la tarjeta en silencio.
- **`cache_control` en el system prompt.** Los 3-4 ejemplos resueltos fijan el
  tono de las explicaciones y de paso empujan el prompt por encima de los ~1024
  tokens que la API exige como mínimo para cachear. Como es idéntico en cada
  llamada, el coste de entrada cae mucho tras la primera frase.

**Reglas que el system prompt debe imponer** (no quedan a criterio de quien lo
escriba):

1. La traducción es la que diría un hablante nativo en esa situación, no la
   literal.
2. Las viñetas van en español, máximo dos líneas cada una.
3. Cada viñeta explica **una** diferencia entre lo que el usuario dijo y lo que
   el inglés exige. Se prioriza el error que un hispanohablante cometería:
   falsos amigos, preposición regida, tiempo verbal, orden de palabras.
4. Prohibido el metalenguaje vacío ("es más natural", "suena mejor") sin decir
   por qué.
5. `skip: true` cuando la entrada no es una frase: ruido, muletillas sueltas,
   una palabra cortada.
- **`fallbacks: "default"`** con su cabecera beta: si un clasificador de
  seguridad declina una frase, la API reintenta sola con otro modelo dentro de
  la misma llamada en vez de dejar la tarjeta en error.

**Respuesta:** SSE. Se consumen `content_block_delta` con `text_delta`,
acumulando el texto del bloque de tipo `text` (los bloques `thinking` se
ignoran). Al llegar `message_stop` se decodifica el JSON completo.

Se comprueba `stop_reason == "refusal"` antes de leer el contenido.

**El render es al final, no incremental.** El streaming se usa para evitar
timeouts y dar señal de progreso, no para pintar a medias. Salida documentada
si se siente lento: `english` es la primera clave del esquema y puede extraerse
del buffer parcial para mostrar la traducción ~1 s antes que el resto. Fuera de
v1.

### 4.5 CardStore

SwiftData, un `ModelActor` para escrituras, `@Query` en la ventana de historial.

## 5. Interfaz

### Barra de menú

La app no tiene icono en el Dock (`LSUIElement`). Vive en la barra de menú: un
icono de micrófono que refleja el estado, clic para encender/apagar, y un menú
con Historial, Ajustes y Salir. Atajo global configurable, por defecto
`⌃⌥Space`.

### Panel flotante

`NSPanel` con `styleMask` que incluye `.nonactivatingPanel`:

- `isFloatingPanel = true`, `level = .floating` — encima de cualquier app.
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` — sigue al
  usuario entre escritorios y aparece sobre apps en pantalla completa.
- No roba el foco: se puede seguir escribiendo en otra app y aun así pulsar los
  botones del panel.
- `isMovableByWindowBackground = true`; la posición se recuerda en
  `UserDefaults`. Por defecto, abajo a la derecha.
- Solo visible mientras la escucha está encendida.

Muestra la transcripción parcial en gris arriba y las **3 tarjetas más
recientes**, la nueva abajo.

### Anatomía de la tarjeta

```
┌──────────────────────────────────────────────┐
│ "necesito que me avises cuando llegues"  ⟲   │  ← español, gris, pequeño
│                                              │
│ I need you to let me know when you get in.   │  ← inglés, grande
│                                              │
│ • "avisar" casi nunca es "advise": aquí es   │
│   "let me know". "Advise" suena a consultor. │  ← el porqué, en español
│ • "cuando llegues" va en presente ("when you │
│   get in"), no en futuro: en inglés el       │
│   futuro no se usa tras "when".              │
│                                              │
│  let me know   get in                        │  ← vocabulario
└──────────────────────────────────────────────┘
```

Estados visibles: *transcribiendo* → *pensando* (esqueleto animado) → *lista*,
más *error* con botón de reintentar.

### Historial y ajustes

Historial: ventana normal, lista buscable agrupada por día, con la tarjeta
completa de cada frase.

Ajustes: API key (Keychain), locale de español, atajo global, y el selector de
posición del panel.

## 6. Modelo de datos

```swift
@Model final class Card {
    var id: UUID
    var spanish: String
    var english: String
    var why: [String]
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var vocab: [VocabItem]
}

@Model final class VocabItem {
    var term: String
    var meaning: String
}
```

La API key vive **solo** en Keychain. Nunca en `UserDefaults`, nunca en un
archivo del repositorio.

## 7. Errores

| Fallo | Respuesta |
|---|---|
| Sin permiso de micrófono | El panel lo dice y ofrece un botón que abre Ajustes del Sistema en la sección correcta |
| Modelo de español no instalado | `AssetInventory` reporta `downloading` → barra de progreso; `unsupported` → error explícito |
| Sin API key configurada | La tarjeta invita a abrir Ajustes, no falla con un error de red |
| Red caída / 5xx | Tarjeta en estado error con botón *reintentar*; sin reintentos automáticos en v1 |
| 429 rate limit | Mensaje distinto al de red ("vas muy rápido"), sin reintento inmediato |
| `stop_reason == "refusal"` tras el fallback | Tarjeta en error, mensaje neutro |
| `skip: true` | Se descarta en silencio, sin tarjeta |
| Cambia el dispositivo de audio | Se atiende la notificación de cambio de configuración y se reinicia el engine |

## 8. Pruebas

La implementación va con TDD: test que falla, código mínimo, refactor.

- **`UtteranceSegmenter`** — reloj inyectado y secuencia de eventos falsos.
  Casos: silencio corto, silencio largo, texto que llega tras el silencio,
  frases pegadas, frase que supera el límite de caracteres, frase demasiado
  corta.
- **Parser SSE y decodificación de `Card`** — fixtures de streams reales
  grabados, incluyendo uno cortado a la mitad, uno con `skip: true` y uno con
  `stop_reason: "refusal"`.
- **`CardStore`** — contenedor SwiftData en memoria.
- **Pipeline completo** — `FakeTranscriber` + `FakeExplainer` de punta a punta,
  sin hardware ni red.
- **Manual, con checklist** — captura de audio real y comportamiento del panel
  (que quede encima, que siga entre escritorios, que no robe el foco). No se
  automatiza razonablemente.

## 9. Proyecto y build

Xcode (el usuario lo está instalando). El proyecto se define en un `project.yml`
y se genera con **XcodeGen**: el `.xcodeproj` es hostil de editar sin la UI y
genera conflictos en git; un YAML legible no.

**Dependencias — una sola:**

| Paquete | Versión | Licencia | Deps transitivas | Por qué |
|---|---|---|---|---|
| `sindresorhus/KeyboardShortcuts` | 3.0.1 | MIT | cero | Atajos globales + UI de grabación. Usa `RegisterEventHotKey`, una de las pocas APIs de Carbon que Apple nunca reemplazó. No provoca diálogos de permisos y es compatible con sandbox. |

GRDB se evaluó y se descartó: SwiftData cubre este modelo de datos sin añadir
dependencia. GRDB solo compensaría con búsqueda FTS5 sobre decenas de miles de
frases, que no es el caso en v1.

## 10. Decisiones registradas

| Decisión | Alternativa descartada | Motivo |
|---|---|---|
| Español → inglés | Corregir inglés hablado; bidireccional | Es el flujo que el usuario pidió; lo demás es v2 |
| Toggle de sesión | Escucha permanente; push-to-talk | No traduce conversaciones ajenas, sin gesto por frase |
| Voz local + Claude en la nube | Todo local; todo en la nube | El audio no sale de la máquina y la explicación es buena |
| `claude-opus-5`, `effort: "low"` | Sonnet 5; Haiku 4.5 | La calidad de la explicación es el producto |
| SwiftData | GRDB | Una dependencia menos, first-party, suficiente |
| Sin `LegacyTranscriber` | Fallback a `SFSpeechRecognizer` | El SDK local confirma `SpeechAnalyzer`; el seguro sobraba |
| XcodeGen | `.xcodeproj` a mano | Legible y sin conflictos en git |
| Frase aislada | Contexto conversacional | Más simple, más barato, cacheable |

## 11. Riesgos abiertos

- **Calidad de la segmentación.** 900 ms es una conjetura razonable, no un dato.
  Es el primer parámetro a ajustar con uso real, y por eso vive en un solo sitio.
- **Latencia percibida.** Si la tarjeta tarda más de ~3 s, la experiencia se
  rompe. Mitigación ya diseñada: la transcripción parcial aparece al instante y
  el esqueleto de la tarjeta se muestra antes de la respuesta. Escape
  documentado: render incremental de `english`.
- **Locale de español.** `es-419` puede no estar entre los soportados; se
  resuelve en runtime con `supportedLocale(equivalentTo:)` y se cae a `es-ES`.
- **Xcode aún no instalado.** Bloquea el primer build, no el plan.
