# Parla — subtítulos del sistema: diseño

**Fecha:** 2026-10-01
**Estado:** borrador para revisión
**Parte de:** Parla + captura de pantalla (`feat/captura`)

## 1. Problema

Edwin ve videos en inglés en el navegador (YouTube, cursos, series) y quiere
entenderlos sin pausar. Las tarjetas de Parla enseñan, pero son lentas por
diseño: esperan a que termine la frase, llaman a la API y explican. Aquí la
prioridad es la contraria: **la traducción en pantalla, al momento, sin
explicaciones.**

Parla gana un tercer modo, junto a la voz y la captura: escucha el audio del
sistema y muestra subtítulos en español sobre lo que se esté viendo.

## 2. Alcance

**Esta versión hace esto:**

- Un atajo global (⌃⌥S) y un ítem del menú de la barra que encienden y apagan
  los subtítulos.
- Captura el audio del sistema, sin el de la propia Parla.
- Transcribe en inglés en el dispositivo y traduce al español en el
  dispositivo, mientras se habla.
- Muestra los subtítulos en una banda sobre cualquier app, también sobre videos
  a pantalla completa, sin interceptar clics.
- Guarda cada frase cerrada (inglés y español) en el historial, con un filtro
  por origen.

**Esta versión no hace esto** (decisiones tomadas, no omisiones):

- No usa Claude. La traducción con Claude (enfoque B) queda para después, como
  opción en Ajustes, si la calidad de los modismos se queda corta.
- Solo inglés → español.
- La banda no se arrastra ni cambia de tamaño.
- Micrófono y subtítulos no funcionan a la vez.
- No se elige una app: entra todo el audio del sistema, incluidas las
  notificaciones y la música.
- No muestra el inglés en pantalla. Se guarda en el historial.

## 3. Arquitectura

```
atajo «Subtítulos» (⌃⌥S) / ítem del menú
   │
   ▼
SystemAudioCapture ── ScreenCaptureKit: capturesAudio, excludesCurrentProcessAudio
   │  AudioChunk ya convertido al formato del analizador
   ▼
SpeechTranscriberEngine(source: .system, locale: en-US)
   │  (TranscriptEvent, Date): .partial(String) / .final(String)
   ▼
SubtitlePipeline (Core) ◀──▶ LiveTranslator (Translation, .lowLatency)
   │  SubtitleOutput: .show(SubtitleFrame) / .hide / .line(SubtitleLine)
   ├──▶ SubtitleOverlay (NSPanel, banda inferior)
   └──▶ CardStore.save(subtitle:)  (solo .line)
```

| Pieza | Responsabilidad | Dónde | Depende de |
|---|---|---|---|
| `AudioSource` (protocolo) | Entregar `AudioChunk` en el formato pedido; permiso propio | App | — |
| `AudioCapture` | El micrófono de hoy, ahora conforme a `AudioSource` | App | AVFoundation |
| `SystemAudioCapture` | Audio del sistema vía `SCStream`, convertido con `AVAudioConverter` | App | ScreenCaptureKit |
| `SpeechTranscriberEngine` | Igual que hoy, pero recibe la fuente y el idioma | App | Speech |
| `Translator` (protocolo) | `String` → `String`, en español | Core | — |
| `SubtitlePipeline` | Decide qué se ve, qué se traduce y qué se guarda | Core | `Translator`, reloj |
| `LiveTranslator` | `Translator` con `TranslationSession(installedSource:target:preferredStrategy: .lowLatency)` | App | Translation |
| `SubtitleOverlay` | La banda en pantalla | App | AppKit/SwiftUI |
| `AppState` | Encender y apagar el modo; exclusión con la escucha | App | todas |

### Por qué `SpeechTranscriberEngine` recibe la fuente

Hoy crea su `AudioCapture` dentro, pide el permiso del micrófono y, si no
encuentra el idioma, cae a `es-ES`. Esas tres cosas son de la fuente y del
idioma, no del motor:

- **Fuente:** `AudioSource` con `requestAccess() async -> Bool`,
  `start(outputFormat:) throws -> AsyncStream<AudioChunk>`, `stop()` y
  `isReceivingAudio`.
- **Permiso:** lo pide la fuente. El micrófono pide el suyo y el sistema
  comprueba Grabación de pantalla.
- **Idioma:** el motor recibe una lista de `Locale` preferidos. La voz pasa
  `[es-419, es-ES]` y los subtítulos `[en-US, en-GB]`.

El resto del motor (resolución del idioma, descarga del modelo, `phase`,
`events`) no cambia. La voz sigue funcionando igual y sus tests no se tocan.

### Exclusión con la escucha

Los dos modos usan el reconocimiento de voz y no tiene sentido hablarle a
Parla mientras ves un video:

- Encender los subtítulos apaga la escucha.
- Encender la escucha apaga los subtítulos.

La captura de pantalla sigue disponible en los dos modos.

## 4. Componentes

### 4.1 SystemAudioCapture

- `SCShareableContent.current` → la pantalla principal → un
  `SCContentFilter(display:excludingWindows: [])`.
- `SCStreamConfiguration`:
  - `capturesAudio = true` y `excludesCurrentProcessAudio = true`;
  - `sampleRate = 48_000` y `channelCount = 1`;
  - vídeo mínimo, porque ScreenCaptureKit lo exige: `width = 2`, `height = 2`,
    `minimumFrameInterval = CMTime(value: 1, timescale: 1)`. No se añade salida
    de vídeo.
- `SCStreamOutput` de tipo `.audio`: `CMSampleBuffer` → `AVAudioPCMBuffer` →
  `AVAudioConverter` → el formato del analizador. Es la misma conversión que
  ya hace `AudioCapture`, y si se puede, se comparte.
- `isReceivingAudio` es `false` mientras no llegue un buffer con señal. Esto
  no es un error: puede que no suene nada.
- `SCStreamDelegate.stream(_:didStopWithError:)` → un reintento. Si falla de
  nuevo, el modo se apaga con un aviso.

### 4.2 SubtitlePipeline (Core)

Lógica pura, con reloj y traductor inyectados, como `UtteranceSegmenter`.

**Entradas:**
- los eventos del motor, `(TranscriptEvent, Date)`;
- un `Translator`: `func translate(_ text: String) async throws -> String`.

**Salidas** (`AsyncStream<SubtitleOutput>`):

```swift
public struct SubtitleFrame: Sendable, Equatable {
    public let previous: String?   // la frase anterior, ya cerrada
    public let current: String     // la que se está diciendo
    public let currentIsFinal: Bool
    public let currentIsOriginal: Bool   // true si es el inglés porque falló la traducción
}

public struct SubtitleLine: Sendable, Equatable {
    public let id: UUID
    public let english: String
    public let spanish: String
    public let spokenAt: Date
}

public enum SubtitleOutput: Sendable, Equatable {
    case show(SubtitleFrame)
    case hide
    case line(SubtitleLine)   // una frase cerrada, para el historial
}
```

**Reglas:**

1. **Parcial:** se guarda el último texto. Se traduce si han pasado ≥ 250 ms
   desde la última traducción de parcial; si no, se programa para cuando se
   cumplan. Solo la última versión, nunca una cola.
2. **Final:** se traduce al momento y reemplaza al parcial. Pasa a ser
   `previous` en cuanto empiece la siguiente frase, y se emite una sola vez
   como `.line`.
3. **Orden:** cada traducción lleva un número de secuencia. Si llega una cuyo
   número es menor que el de la última mostrada, se descarta.
4. **Fallo de traducción:** se muestra el inglés con `currentIsOriginal =
   true`. La `.line` se emite igual, con `spanish` vacío, y el historial la
   muestra como «(sin traducción)». Un fallo no detiene el modo.
5. **Silencio:** 4 s sin eventos nuevos → `.hide`. Con el siguiente parcial
   vuelve a mostrarse.
6. **Finales vacíos:** se ignoran. El motor emite uno al cerrarse el stream
   para vaciar lo pendiente, y no es una frase.

### 4.3 LiveTranslator

- `TranslationSession(installedSource: en, target: es, preferredStrategy:
  .lowLatency)`. Se crea una vez al encender el modo y se reutiliza.
- Antes de crearla: `LanguageAvailability().status(from: en, to: es)`.
  - `.installed` → adelante.
  - `.supported` → faltan los idiomas: aviso con el botón a Ajustes del Sistema
    › General › Idioma y región › Idiomas de traducción. La sonda (§ 9)
    comprueba si `prepareTranslation()` puede pedir la descarga desde la app;
    si puede, se usa eso en lugar del aviso.
  - `.unsupported` → aviso y el modo no se enciende.
- Un `actor`, para que las traducciones no se pisen entre sí.

### 4.4 SubtitleOverlay

- `NSPanel` con `styleMask` `[.borderless, .nonactivatingPanel]`.
- `ignoresMouseEvents = true`: los clics la atraviesan.
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary,
  .ignoresCycle]`.
- `level` por encima de una ventana a pantalla completa. El valor exacto se
  verifica a mano con un video de YouTube a pantalla completa (§ 9).
- **Posición:** centrada abajo en la pantalla donde está el ratón al encender
  el modo, a un 8 % del borde inferior. Ancho máximo, el 70 % de la pantalla.
  Es una función pura, `SubtitleLayout.frame(for:screen:textHeight:)`, que se
  prueba.
- **Texto:** blanco, 28 pt semibold, centrado, sobre un fondo negro al 60 % con
  esquinas redondeadas.
  - `previous` va al 55 % de opacidad;
  - `current` va completo;
  - si `currentIsOriginal`, va en cursiva y atenuado.
- Cada bloque ocupa como máximo dos líneas. Si no cabe, se ve el **final** de
  la frase, que es lo que se acaba de decir.
- `.hide` → se desvanece en 0,3 s.
- Los avisos (descarga del modelo, idiomas que faltan) salen en la misma banda,
  con el texto del aviso en lugar del subtítulo.

### 4.5 Historial

- `CardStore.save(subtitle: SubtitleLine)` → `StoredCard`:
  - `origin = "system"`;
  - `source` = el inglés, `result` = el español;
  - `why` y `vocab` vacíos, `kind = nil`.
- `HistoryView` gana un selector: **Todo / Voz / Capturas / Subtítulos**. Filtra
  por `origin`, con una función pura que se prueba. La búsqueda funciona igual
  dentro de cada filtro.
- Las filas de subtítulos llevan la etiqueta «🎧 Subtítulos».

### 4.6 AppState, menú y ajustes

- `isSubtitling: Bool`, `toggleSubtitles()`, `subtitleNotice: String?`.
- Atajo `KeyboardShortcuts.Name.toggleSubtitles`, con ⌃⌥S por defecto. Va en
  Ajustes › Atajo junto a los otros dos.
- Ítem del menú: «Mostrar subtítulos» / «Ocultar subtítulos».
- Icono de la barra mientras está encendido: `captions.bubble.fill`.
- `PARLA_SUBTITLES_AUTOSTART=1` enciende el modo al arrancar, para probar desde
  la terminal, como `PARLA_AUTOSTART`.

## 5. Errores

| Situación | Qué pasa |
|---|---|
| Falta el permiso de Grabación de pantalla | El mismo aviso que la captura (panel, botón a Ajustes); el modo no se enciende |
| Falta el modelo de voz en inglés | Se descarga solo; la banda muestra «Descargando el modelo de inglés… n %» |
| Faltan los idiomas de traducción | Aviso en la banda con el botón a Ajustes del Sistema (§ 4.3) |
| Idiomas no soportados | Aviso y el modo no se enciende |
| Una frase no se puede traducir | Se muestra el inglés atenuado y en cursiva; el modo sigue |
| El stream de audio se para | Un reintento; si falla, el modo se apaga con un aviso en el panel |
| La escucha del micrófono estaba encendida | Se apaga sola al encender los subtítulos, y al revés |
| No suena nada | No se ve nada; no es un error |

## 6. Rendimiento

| Medida | Objetivo | Cómo se comprueba |
|---|---|---|
| Del habla al parcial en pantalla | < 1 s | Sonda (§ 9) y a mano |
| Del final de la frase a su traducción | < 0,5 s | Sonda: latencia de `translate` con `.lowLatency` |
| Traducciones de parcial | ≤ 4 por segundo | Test del pipeline (250 ms) |
| CPU con un video en marcha | Que no se note en el video | A mano, con Monitor de Actividad |

## 7. Privacidad

- **El audio del sistema no sale del Mac:** la transcripción y la traducción
  son locales.
- **En este modo no se manda nada a Anthropic.**
- Al historial van el inglés y el español de cada frase cerrada.
- **El log del sistema no recibe el texto de los subtítulos,** solo eventos
  (encendido, apagado, errores). Hoy el motor registra cada resultado de la voz
  con `privacy: .public`. Para la fuente del sistema, ese registro se quita o se
  marca `.private`.

El README añade una fila a la tabla de «Cómo funciona» y una línea en la
sección de privacidad.

## 8. Versión mínima de macOS

`TranslationSession.Strategy.lowLatency` existe desde **macOS 26.4**. La app
sube su mínimo de 26.0 a **26.4** (`project.yml`: `deploymentTarget` y
`LSMinimumSystemVersion`). Core se queda en `.v26`, porque no usa Translation.

## 9. Pruebas

**Sonda previa** (primera tarea del plan), dentro del sandbox y con un video de
YouTube sonando:

1. `SCStream` con solo audio entrega buffers, y `isReceivingAudio` pasa a `true`.
2. `SpeechAnalyzer` en `en-US` transcribe esos buffers (parciales y finales en
   el log).
3. `LanguageAvailability` en → es en este Mac: `installed`, `supported` o
   `unsupported`.
4. `TranslationSession(installedSource:…, preferredStrategy: .lowLatency)`
   traduce una frase, y cuánto tarda (media de 20 frases).
5. Si los idiomas no están instalados, si `prepareTranslation()` puede pedir
   la descarga desde la app.

**Core** (`make test`), `SubtitlePipeline` con `FakeTranslator` y un reloj
inyectado:

- dos parciales en menos de 250 ms producen una sola traducción, la del último;
- un parcial a los 300 ms del anterior produce una traducción nueva;
- el final se traduce aunque el último parcial se haya traducido hace 10 ms;
- el final reemplaza al parcial y, con la siguiente frase, pasa a `previous`;
- cada final se emite una sola vez como `.line`;
- una traducción tardía (secuencia menor) no reemplaza a una más nueva;
- si la traducción falla, se muestra el inglés con `currentIsOriginal` y la `.line` lleva `spanish` vacío;
- 4 s de silencio → `.hide`, y el siguiente parcial vuelve a mostrar la banda;
- un final vacío se ignora.

**App** (`make test-app`):

- `SubtitleLayout.frame`: centrada, a un 8 % del borde, como mucho el 70 % del
  ancho, también en pantallas pequeñas;
- `CardStore.save(subtitle:)` guarda `origin = "system"` con inglés y español;
- el filtro del historial por origen;
- `AudioCapture` sigue conforme a `AudioSource` sin cambiar su comportamiento
  (los tests de audio que ya existen siguen en verde).

**A mano:**

- un video en el navegador, en ventana y a pantalla completa;
- los clics atraviesan la banda y el video no pierde el foco;
- la banda se desvanece en las pausas y vuelve con la siguiente frase;
- ⌃⌥S con la escucha encendida la apaga, y al revés;
- en el historial, el filtro «Subtítulos» muestra las frases con su inglés;
- en Monitor de Actividad, la CPU es razonable con un video de 10 minutos.

## 10. Riesgos

| Riesgo | Mitigación |
|---|---|
| ScreenCaptureKit no entrega audio dentro del sandbox | Sonda como primera tarea. Alternativa: process taps de Core Audio (`AudioHardwareCreateProcessTap`), con su propio permiso de audio del sistema |
| Los idiomas de traducción no están instalados y la app no puede pedir la descarga | Aviso con instrucciones y el botón a Ajustes del Sistema |
| `.lowLatency` traduce peor que la estrategia por defecto | La sonda compara las dos con las mismas 20 frases; si la diferencia es grande, se usa la de por defecto para los finales |
| La banda no queda encima de un video a pantalla completa | Se verifica el `level` a mano; el panel ya resuelve un caso parecido |
| `SpeechAnalyzer` tarda en cerrar frases en un audio sin pausas (música de fondo) | El parcial se sigue viendo y traduciendo; la banda muestra el final del texto |

## 11. Decisiones registradas

| Decisión | Alternativa descartada | Motivo |
|---|---|---|
| Todo en el Mac (Speech + Translation) | Claude Haiku; híbrido | Velocidad y coste cero; es lo que se pidió |
| Audio de todo el sistema con ScreenCaptureKit | Process tap de una app concreta | Usa el permiso que Parla ya tiene; no hay que elegir app |
| Subtítulos + historial | Solo banda; solo panel | Pedido explícitamente |
| Exclusión con la escucha del micrófono | Los dos a la vez | Dos analizadores sin un caso de uso que los pida |
| El motor recibe fuente e idioma | Un segundo motor | Una sola implementación de descarga del modelo y de resultados |
| Subir la app a macOS 26.4 | `#available` con estrategia por defecto en 26.0 | App personal en un Mac con 26.6; menos ramas |
| Mostrar el inglés si falla la traducción | Dejar la banda vacía | Mejor algo que un hueco |
