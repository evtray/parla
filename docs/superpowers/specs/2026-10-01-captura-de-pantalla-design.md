# Parla — captura de pantalla: diseño

**Fecha:** 2026-10-01
**Estado:** borrador para revisión
**Parte de:** Parla v0.1 + modo lote (`feat/lote`)

## 1. Problema

Parla solo aprende de lo que Edwin dice en voz alta. Pero buena parte del inglés
con el que se cruza está escrito en pantalla: mensajes de Slack, correos,
artículos, subtítulos, juegos. Y buena parte del inglés que produce también es
escrito: el mensaje o el correo que está a punto de mandar.

Hoy, para aprender de ese texto, tiene que copiarlo a otro sitio, y en muchos
casos (subtítulos, juegos, imágenes) ni siquiera se puede copiar.

La captura de pantalla cierra ese hueco. Pulsa un atajo, selecciona una región y
Parla le devuelve una tarjeta con el mismo espíritu que las de voz: no solo qué
dice o cómo se dice, sino **por qué**.

## 2. Alcance

**Esta versión hace esto:**

- Un atajo global, y un ítem del menú de la barra, que abren la selección de una
  región de la pantalla.
- Manda la imagen de esa región a Claude, que lee el texto y decide qué caso es:
  - **Traducir:** texto en español → cómo se dice en inglés y por qué (lo mismo
    que la voz).
  - **Corregir:** inglés escrito por Edwin → versión corregida y por qué.
  - **Entender:** inglés escrito por otra persona → qué significa y qué tiene
    de no evidente para un hispanohablante.
- Adapta la tarjeta a textos de una línea y también a correos enteros.
- Un menú «¿No era eso?» en la tarjeta, que reenvía la misma imagen forzando
  otro caso.
- Las tarjetas de captura comparten el panel flotante y el historial con las de
  voz.

**Esta versión no hace esto** (decisiones tomadas, no omisiones):

- No guarda imágenes: ni en disco ni en el historial. Solo el texto leído.
- No hay OCR local. La imagen va a la API (ver § 8, Privacidad).
- No marca las diferencias palabra a palabra (tachado o resaltado) en las
  correcciones.
- No captura de forma automática ni continua. Siempre es un gesto explícito.
- Las capturas no entran en el modo lote. Se mandan al momento.
- No pronuncia nada (sin TTS), igual que la voz.

## 3. Arquitectura

```
atajo «Capturar pantalla» / ítem del menú
   │
   ▼
ScreenCapturer ── selección de región (cruz nativa) ── Esc → fin, sin coste
   │
   ▼  PNG
ImageDownscaler ── encaja en 2576 px de lado largo y 4784 tokens visuales
   │
   ▼
Capture { id, imageData, mediaType, capturedAt }            (Core)
   │
   ▼
ClaudeExplainer.explainCapture(_:forcing:)                   (Core)
   │   imagen + CaptureSystemPrompt + esquema de CaptureCard
   ▼
CaptureCard ──▶ AppState ──┬──▶ FloatingPanel (misma lista que la voz)
                           └──▶ CardStore (historial)
```

| Pieza | Responsabilidad | Dónde | Depende de |
|---|---|---|---|
| `ScreenCapturer` | Selección interactiva de la región y permiso de Grabación de pantalla | App | `screencapture` o ScreenCaptureKit (§ 4.1) |
| `ImageDownscaler` | Reducir la imagen a lo que el modelo aprovecha | App | ImageIO / CoreGraphics |
| `Capture` | Valor: los bytes de la imagen y cuándo se tomó | Core | — |
| `CaptureKind` | `understand` / `correct` / `translate` / `skip` | Core | — |
| `CaptureCard` | Lo que devuelve Claude; coincide con el esquema | Core | — |
| `CaptureExplainer` (protocolo) | `Capture` → `CaptureCard` | Core | — |
| `ClaudeRequestBuilder.makeCaptureRequest` | Cuerpo de la petición con imagen | Core | — |
| `CaptureSystemPrompt` | Instrucciones y ejemplos de los tres casos | Core | — |
| `AppState` | Orquesta: captura, tarjeta pendiente, reintento, «¿No era eso?» | App | todas |

### Por qué un protocolo `CaptureExplainer` aparte

`Explainer` lo implementan los dobles de `SessionPipelineTests`. Si se le añadiera
un requisito, habría que tocar cada doble sin que el pipeline de voz gane nada.
`ClaudeExplainer` implementa los dos protocolos, y `AppState` usa cada uno donde
corresponde.

### Concurrencia

- Mientras la selección está abierta, otro atajo de captura se ignora: no puede
  haber dos cruces a la vez.
- Puede haber varias capturas en vuelo hacia la API al mismo tiempo, igual que las
  frases. Cada una lleva su propio `Task`.
- El panel ordena por `capturedAt` o `startedAt`, según el origen.

## 4. Componentes

### 4.1 ScreenCapturer

**Plan A — la cruz nativa.** Lanza `/usr/sbin/screencapture -i -x -t png <tmp>`:

- `-i` da la selección interactiva de ⌘⇧4: arrastrar, Esc para cancelar,
  espacio para cambiar a ventana.
- `-x` silencia el sonido.
- `<tmp>` es un archivo en el directorio temporal del contenedor.

Si al terminar el proceso no existe el archivo, el usuario canceló. El archivo se
lee y se borra en el acto.

**Riesgo que se verifica primero:** Parla corre con App Sandbox, y el proceso hijo
hereda las restricciones. No está comprobado que `screencapture -i` funcione desde
dentro del sandbox. **La primera tarea del plan es una prueba de 15 minutos** que
lo confirma o lo descarta.

**Plan B, si A no funciona:**

- Una ventana transparente a pantalla completa, por encima de todo, donde se
  arrastra el rectángulo, con Esc para cancelar.
- La región se captura con `SCScreenshotManager` de ScreenCaptureKit, que es
  compatible con sandbox. La firma exacta para capturar un rectángulo se verifica
  contra el SDK local en la misma prueba.
- `CGWindowListCreateImage` no es opción: está obsoleta desde macOS 15.

**Permiso.** Antes de capturar se llama a `CGPreflightScreenCaptureAccess()`. Si
devuelve `false`:

- se llama una vez a `CGRequestScreenCaptureAccess()`, que muestra el diálogo
  del sistema;
- el panel muestra «Parla necesita permiso de Grabación de pantalla» con un
  botón que abre
  `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`.

Sin el permiso, macOS no falla: entrega una captura con las ventanas ajenas en
blanco. Por eso la comprobación va antes, y no se intenta adivinar a partir de la
imagen.

### 4.2 ImageDownscaler

Límites verificados contra la documentación de visión (2026-10-01). Opus 5.5 y
Sonnet 5.5 están en el nivel de alta resolución:

| Límite | Valor |
|---|---|
| Lado largo máximo | 2576 px |
| Tokens visuales máximos | 4784, con `⌈ancho/28⌉ × ⌈alto/28⌉` |
| Tamaño máximo por imagen | 10 MB en base64 (API directa) |
| Formatos | PNG, JPEG, GIF, WebP |

Regla:

- Si la imagen excede cualquiera de los dos primeros límites, se reduce
  conservando la proporción hasta que quepa en ambos.
- Nunca se amplía.
- Se reduce en el Mac aunque la API también lo haría, para no mandar bytes que
  luego se tiran y para bajar la latencia.

La salida es PNG, porque el texto se lee mejor sin artefactos de compresión. Solo
si el PNG en base64 supera los 10 MB (un fotograma de vídeo con subtítulos puede
llegar), se recodifica como JPEG con calidad 0,9.

Esta función es pura (imagen de entrada → bytes de salida) y se prueba sin
capturar nada.

### 4.3 Tipos en Core

```swift
public struct Capture: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let imageData: Data
    public let mediaType: String      // "image/png" o "image/jpeg"
    public let capturedAt: Date
}

public enum CaptureKind: String, Sendable, Codable, CaseIterable {
    case understand, correct, translate, skip
}

/// Coincide con el esquema de `makeCaptureRequest`.
public struct CaptureCard: Sendable, Equatable, Codable {
    public let kind: CaptureKind
    public let source: String         // el texto leído en la imagen
    public let result: String         // traducción | corrección | inglés
    public let why: [String]
    public let vocab: [VocabTerm]     // reutiliza el tipo de Card
}

public protocol CaptureExplainer: Sendable {
    /// `forcing == nil` deja que el modelo decida el caso.
    func explainCapture(_ capture: Capture,
                        forcing kind: CaptureKind?) async throws -> CaptureCard
}
```

A diferencia de la voz, `explainCapture` **nunca devuelve `nil`**. Un `skip` vuelve
como tarjeta con `kind == .skip`, porque el usuario hizo un gesto explícito y
merece respuesta. La UI lo pinta como aviso breve.

Antes de pedir nada se valida `forcing != .skip`: forzar un skip no tiene
sentido.

### 4.4 La petición

```jsonc
{
  "model": "<el elegido en Ajustes>",
  "max_tokens": 16000,
  "stream": true,
  "fallbacks": "default",
  "output_config": {
    "effort": "low",
    "format": { "type": "json_schema", "schema": {
      "type": "object",
      "properties": {
        "kind":   { "type": "string",
                    "enum": ["understand", "correct", "translate", "skip"] },
        "source": { "type": "string" },
        "result": { "type": "string" },
        "why":    { "type": "array", "items": { "type": "string" } },
        "vocab":  { "type": "array", "items": { "type": "object",
                    "properties": { "term": { "type": "string" },
                                    "meaning": { "type": "string" } },
                    "required": ["term", "meaning"],
                    "additionalProperties": false } }
      },
      "required": ["kind", "source", "result", "why", "vocab"],
      "additionalProperties": false
    } }
  },
  "system": [{ "type": "text", "text": "<CaptureSystemPrompt>",
               "cache_control": { "type": "ephemeral" } }],
  "messages": [{ "role": "user", "content": [
    { "type": "image",
      "source": { "type": "base64", "media_type": "image/png", "data": "…" } },
    { "type": "text", "text": "Decide tú el caso." }
  ] }]
}
```

Mismas cabeceras que hoy, `server-side-fallback-2026-07-01` incluida.

Notas sobre cada decisión del cuerpo:

- **La imagen va antes que el texto,** que es el orden que la documentación
  recomienda.
- **El bloque de texto lleva el caso forzado** cuando se usa «¿No era eso?». Por
  ejemplo: «El usuario indica que este texto lo escribió él: el caso es correct.»
  El system prompt no cambia, y así la caché se mantiene.
- **System prompt propio y cacheado.** No comparte prefijo con el de la voz, así
  que tiene su propia caché, y está bien. Sus ejemplos lo dejan holgadamente por
  encima del mínimo cacheable.
- **`max_tokens: 16000`.** Un correo largo corregido, más su explicación, más el
  razonamiento adaptativo, no cabe en los 4000 de una frase. Con streaming no hay
  riesgo de timeout.
- **`effort: "low"`, como la voz.** Si el `make eval-capture` (§ 9) muestra que la
  detección del caso falla, `medium` es la primera palanca, antes que tocar el
  prompt.
- **Sin límites de longitud en el esquema** (`maxItems` y compañía): la salida
  estructurada los rechaza. Los límites los impone el prompt, como hoy.
- **`enum` sí está admitido** en la salida estructurada.

**Coste estimado por captura con Opus 5.5** ($4 / $20 por MTok):

| Concepto | Tokens | Coste |
|---|---|---|
| Imagen, región típica (1000×300 px) | ~400 | — |
| Imagen, tope | 4784 | ~$0,019 |
| Salida | entre 300 y 1500 | entre $0,006 y $0,03 |

En total, entre 1 y 5 centavos de dólar por captura. Es una estimación: se
confirma con `usage` en las primeras capturas reales.

### 4.5 CaptureSystemPrompt

Hereda el tono y las reglas 2, 3, 4 y 6 del prompt de la voz:

- las explicaciones van en español y son breves;
- cada una cubre una sola diferencia;
- está prohibido el metalenguaje vacío;
- el vocabulario se limita a lo que vale la pena recordar.

Las reglas nuevas, que no quedan a criterio de quien escriba el prompt:

1. **`source`** es el texto que se lee en la imagen, tal cual, sin la interfaz
   que lo rodea (menús, nombres de canal, horas). Si hay varios bloques, solo
   los que importan para el caso elegido.
2. **Elección del caso:**

   | Lo que se ve | `kind` | Señales |
   |---|---|---|
   | Texto en español | `translate` | — |
   | Inglés escrito por el usuario | `correct` | Caja de redacción o campo con cursor; burbujas alineadas a la derecha en un chat; el usuario como remitente |
   | Inglés de otra persona | `understand` | Es el caso por defecto si no hay señales de autoría: artículos, webs, subtítulos, mensajes recibidos |
   | Mensaje ajeno + borrador del usuario | `correct` | Se corrige el borrador. El mensaje ajeno solo sirve de contexto (por ejemplo, para ver si la respuesta encaja) |
   | Nada legible, o solo cosas que no son lenguaje (números, código, iconos) | `skip` | `source`, `result` y las listas, vacíos. Un texto corto pero real (por ejemplo, «Sounds good») no es `skip`: se procesa según su caso |

3. **`result` va siempre completo.** Es la traducción entera, el texto corregido
   entero o el inglés entero. Nunca un resumen.
4. **Tamaño:**
   - Con 1 o 2 frases, `why` tiene entre 1 y 3 puntos y `vocab` hasta 3.
   - Con textos más largos, `why` tiene hasta 5 puntos y `vocab` hasta 5. Se
     eligen los puntos que más enseñan, **nunca uno por frase**. Un error
     repetido se agrupa en un solo punto con su recuento.
5. **`correct` sin nada que corregir:** `result` es igual a `source` y `why` va
   vacío. Nada de elogios.
6. **`understand`:** `why` explica lo que un hispanohablante no deduciría
   palabra a palabra: modismos, phrasal verbs, falsos amigos, construcciones
   que no existen en español, registro. Lo transparente no se explica.
7. **Caso forzado:** si el bloque de texto fija el caso, se obedece aunque las
   señales digan otra cosa.

**Ejemplos obligatorios:** al menos uno por caso, más el caso mixto
(mensaje + borrador) y un `skip`. Van en texto (lo que se vería en la imagen,
descrito), porque meter imágenes en el system prompt encarecería cada
petición.

### 4.6 ClaudeExplainer

`explainCapture(_:forcing:)` reutiliza `streamJSON`, que ya existe, y decodifica
`CaptureCard`. Los errores son los mismos `ExplainerError`, sin casos nuevos.

## 5. Interfaz

### 5.1 Atajo, menú y ajustes

- `KeyboardShortcuts.Name.captureScreen`, con ⌃⌥C por defecto.
- En Ajustes › Atajo, una segunda fila: «Capturar pantalla:».
- En el menú de la barra, el ítem «Capturar pantalla», debajo de «Empezar a
  escuchar». Además, permite probar con `PARLA_CLICK_MENU="Capturar pantalla"`.
- Afordancia de desarrollo: `PARLA_CAPTURE_FILE=/ruta.png` salta la selección y
  usa ese archivo. Permite probar el flujo entero desde la terminal sin ratón y
  sin permiso de pantalla.

### 5.2 Panel

`CardPresentation` pasa a tener un origen:

```swift
enum CardOrigin { case voice(Utterance), capture(Capture) }
enum CardState  { case pending, ready(Card), readyCapture(CaptureCard), failed(ExplainerError) }
```

(La forma exacta de los estados se decide en el plan. Lo que fija este diseño es
que un mismo arreglo ordenado contiene los dos orígenes.)

- Las tarjetas de captura entran en el mismo arreglo y en el mismo orden, con la
  nueva arriba, y cuentan para el límite de 3 visibles en modo inmediato.
- Capturar abre el panel aunque la escucha esté apagada. El botón «Cerrar el
  panel» que ya existe sirve igual.

### 5.3 Tarjeta de captura

```
┌──────────────────────────────────────────────┐
│ 📷 Corrección                                │  ← etiqueta del caso
│ «I am agree with you, we can discuss it in   │  ← source, gris, máx. 3 líneas,
│  the next meeting»                           │    clic para expandir
│                                              │
│ I agree with you, we can discuss it at the   │  ← result, grande, seleccionable
│ next meeting.                                │
│                                              │
│ • "Agree" ya es verbo: "I agree". "I am      │  ← why
│   agree" calca "estoy de acuerdo".           │
│ • Las reuniones van con "at": "at the        │
│   meeting", no "in".                         │
│                                              │
│                              ¿No era eso? ▾  │  ← Entender / Traducir
└──────────────────────────────────────────────┘
```

- Etiquetas: «📷 Para entender», «📷 Corrección», «📷 Traducción».
- `correct` con `why` vacío muestra «✓ Nada que corregir» en lugar de las
  viñetas.
- `skip` es una tarjeta mínima («No encontré texto en la captura»), sin menú ni
  reintento. No va al historial.
- «¿No era eso? ▾» ofrece los otros dos casos que no son `skip`. Al elegir uno,
  la tarjeta vuelve a *pendiente* y se reemplaza al llegar la respuesta. En el
  historial, la versión forzada sustituye a la anterior (mismo `id`).
- Mientras está pendiente se muestra el mismo esqueleto que en la voz, con la
  etiqueta «📷 Leyendo…».

### 5.4 Historial

Muestra la etiqueta del caso en las tarjetas de captura. La búsqueda ya cubre
`source` y `result`, así que encuentra las dos clases sin cambios de lógica.

## 6. Modelo de datos

```swift
@Model final class StoredCard {
    var id: UUID
    @Attribute(originalName: "spanish") var source: String
    @Attribute(originalName: "english") var result: String
    var why: [String]
    var createdAt: Date
    var origin: String = "voice"      // "voice" | "screen"
    var kind: String?                 // CaptureKind.rawValue; nil en voz
    @Relationship(deleteRule: .cascade) var vocab: [StoredVocab]
}
```

**Por qué renombrar:** una tarjeta de «entender» guarda inglés en `source` y
español en `result`. Con los nombres actuales, el campo `spanish` guardaría
inglés.

**Por qué funciona:**

- `originalName` permite que la migración ligera automática de SwiftData lleve
  los datos existentes a los campos nuevos.
- Los campos añadidos tienen valor por defecto u opcional, que es lo que esa
  migración necesita.

Un test abre una base creada con el esquema actual y comprueba que las tarjetas
siguen ahí.

El `id` de la tarjeta de captura es el `Capture.id`. Guardar con un `id` que ya
existe reemplaza (lo usa «¿No era eso?»).

## 7. Errores

| Fallo | Respuesta |
|---|---|
| Esc en la selección | Nada. Sin tarjeta, sin coste, sin mensaje |
| Sin permiso de Grabación de pantalla | Aviso en el panel con botón a Privacidad › Grabación de pantalla. No se captura |
| `screencapture` termina con error (no por cancelar) | Aviso en el panel con el código de salida. No se reintenta solo |
| Imagen de más de 10 MB tras reducirla y recodificarla | «La región es demasiado grande. Selecciona menos.» No se manda |
| Sin API key | El mismo mensaje que la voz: invita a abrir Ajustes |
| Red, 5xx, respuesta incompleta | Tarjeta en error con «Reintentar», que reenvía la misma imagen |
| 429 | El mismo mensaje que hoy, sin reintento inmediato |
| `refusal` tras el fallback | «No se pudo leer esta captura.» Sin reintento |
| `kind == skip` | Tarjeta breve «No encontré texto en la captura». No va al historial |

**Memoria:** la imagen vive en la `CardPresentation` mientras la tarjeta está en
el búfer de 30, porque tanto «Reintentar» como «¿No era eso?» la necesitan. Al
salir del búfer se libera. Una captura típica de texto en PNG ocupa entre 100 y
500 KB.

## 8. Privacidad

Hasta ahora la promesa era: «Tu audio nunca sale del equipo. Solo viaja el texto
transcrito.» Con esta función ya no es completa.

El README pasa a decir, en la tabla de «Cómo funciona» y en el párrafo siguiente:

- **Voz:** el audio nunca sale del equipo. Solo viaja el texto transcrito.
- **Capturas:** la imagen de la región que seleccionas sí viaja a la API. No se
  guarda en tu Mac. Al historial va solo el texto que Claude leyó.

La selección de una región, y no de la pantalla entera, es también una decisión
de privacidad: se manda lo que el usuario encuadró y nada más.

## 9. Pruebas

TDD como en el resto del proyecto.

**Core** (`make test`, sin Xcode):

- `makeCaptureRequest`:
  - el bloque `image` va primero, en base64, con el `media_type` correcto;
  - el bloque de texto lleva o no lleva el caso forzado;
  - el system prompt de captura lleva `cache_control`;
  - el esquema tiene el `enum`;
  - `max_tokens` es 16000;
  - forzar `.skip` se rechaza.
- Decodificación de `CaptureCard`: los cuatro `kind`, y un `kind` desconocido →
  `malformedResponse`.
- `explainCapture` con el streamer falso: cada caso, `skip`, `refusal`, stream
  cortado y 429.

**App** (`make test-app`):

- `ImageDownscaler`:
  - una imagen de 4000×3000 cabe en ambos límites;
  - una de 800×200 no cambia;
  - la proporción se conserva;
  - una imagen que no cabe en 10 MB se recodifica como JPEG.
- Orden del panel con tarjetas de voz y de captura mezcladas.
- Migración de `StoredCard`: una base con el esquema actual abre y conserva sus
  tarjetas.
- Un reemplazo por `id` en `CardStore` no duplica.

**Detección del caso, con la API real** (`make eval-capture`):

- Un ejecutable en el paquete Core recorre `Core/Fixtures/capturas/`.
- El caso esperado va en el nombre del archivo:
  `correct-01-borrador-slack.png`, `understand-02-articulo.png`, etc.
- Imprime, para cada imagen, el caso esperado, el que eligió el modelo, `source`
  y `result`, y al final el acierto (`n/N`).
- Necesita `PARLA_API_KEY` y gasta tokens, así que **no corre en `make test`**.

Fixtures mínimas, siete:

1. un artículo en inglés;
2. un mensaje recibido en un chat;
3. un borrador propio en la caja de redacción;
4. un mensaje recibido + un borrador propio;
5. un correo propio con varios errores;
6. texto en español;
7. una imagen sin texto.

**Manual, con checklist:**

- la cruz aparece y Esc no deja rastro;
- el panel aparece sobre una app a pantalla completa;
- el permiso de pantalla se pide una sola vez y el aviso aparece si se deniega;
- «¿No era eso?» reemplaza la tarjeta en el panel y en el historial.

## 10. Riesgos

| Riesgo | Mitigación |
|---|---|
| `screencapture -i` no funciona dentro del sandbox | Prueba como primera tarea; plan B con ScreenCaptureKit (§ 4.1) |
| Cada compilación ad hoc es una app nueva para TCC, así que el permiso de pantalla se pierde tras cada `make install` | Documentarlo en el README. `PARLA_CAPTURE_FILE` permite desarrollar sin el permiso |
| La detección del caso falla más de lo aceptable | `make eval-capture` lo mide. Las palancas, en orden: subir el esfuerzo a `medium`, ajustar ejemplos, y «¿No era eso?» como red de seguridad |
| Una región enorme (pantalla Retina entera) encarece cada captura | El tope de 4784 tokens visuales la limita a unos $0,02 en imagen |

## 11. Decisiones registradas

| Decisión | Alternativa descartada | Motivo |
|---|---|---|
| La imagen va a Claude | OCR local con Vision; OCR + confirmación | Sin la composición no se distingue «lo escribí yo» de «me lo escribieron», y la detección automática es el requisito |
| Región seleccionada | Ventana activa; pantalla completa | Menos ruido, más barato, y se manda solo lo encuadrado |
| Detección automática + «¿No era eso?» | Elegir el caso antes de cada captura | Un solo gesto en el caso común; el menú cubre el error |
| `result` siempre completo | Resumir textos largos | Es lo que el usuario necesita para actuar (responder, enviar) |
| `why` acotado a 5 en textos largos | Una explicación por frase | Se aprende de lo importante, no del recuento |
| Prompt de captura separado | Ampliar el de la voz | El de la voz está afinado para frases habladas; mezclarlo empeora ambos |
| Protocolo `CaptureExplainer` aparte | Ampliar `Explainer` | No obliga a tocar los dobles del pipeline de voz |
| No guardar imágenes | Miniaturas en el historial | Privacidad y tamaño de la base; el texto leído basta para buscar |
| Capturas fuera del lote | Encolarlas | Pulsar el atajo ya es pedir la traducción |
| Renombrar `spanish`/`english` con `originalName` | Reutilizar los campos tal cual | Un campo `spanish` que guarda inglés es un error esperando a pasar |
