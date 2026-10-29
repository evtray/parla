# Parla — Lectura en vivo con cuadernos: diseño

**Fecha:** 2026-10-26
**Estado:** borrador para revisión
**Rama:** `feat/lectura-en-vivo`, sacada de `main` (`7e31825`)

## 1. Problema

La captura de pantalla sirve para una frase suelta: ⌃⌥C, marcar el área,
leer la tarjeta. Cuando el inglés no para de cambiar en el mismo sitio (los
diálogos de un juego de rol como AFK Journey, unas diapositivas), hay que
repetir el gesto por cada línea y se pierde el hilo:

- **Cada captura es un gesto completo.** Marcar el área otra vez por cada
  diálogo saca del juego.
- **Cada captura llega sin contexto.** El modelo no sabe quién habla, qué se
  dijo antes ni de qué va la historia, así que «hold it» o «make it» se
  traducen a ciegas.
- **Lo aprendido queda revuelto.** Todas las tarjetas van al mismo historial;
  las expresiones de un juego se mezclan con las de una presentación de
  trabajo.

## 2. Alcance

**Esta versión hace esto:**

- Un modo nuevo, **Lectura en vivo** (⌃⌥L): Parla vigila un recuadro dentro
  de una ventana (o de la pantalla) y traduce cada línea nueva que aparece.
- Dos ritmos: **Automático** (traduce al detectar una línea nueva) y **Cuando
  yo diga** (solo al apretar ⌃⌥R, «Leer ahora»).
- Lectura del texto en la Mac con Vision; a Claude solo le llega texto.
- **Cuadernos**: cada sesión escribe en uno. El cuaderno tiene un «De qué
  trata» opcional y aporta las últimas líneas como contexto al modelo.
- Guardado automático de las líneas con algo que aprender, con su explicación
  y su «antes y después»; cualquier otra se guarda con un clic.
- Tres formas de ver la traducción, a elegir en Ajustes: **A** subtítulo
  encima del diálogo, **B** el panel con las líneas anteriores, **C** tapar el
  inglés.
- Un modelo propio para este modo, elegible en Ajustes; **Haiku 5.5** por
  defecto, que se añade a `ClaudeModel`.
- Sección **Cuadernos** en Estudio.

**Esta versión no hace esto** (decisiones tomadas, no omisiones):

- No traduce toda la pantalla: siempre hay un recuadro.
- No excluye zonas dentro del recuadro.
- No manda imágenes a Claude, ni como respaldo cuando Vision duda (la lectura
  mixta queda para otra versión si se ven errores de lectura).
- No hay barra flotante de botones; en la Mac bastan los atajos y el panel.
  La barra se pensará para una futura Parla para teléfono, que es otro
  proyecto.
- No exporta cuadernos.
- No cambia las capturas, la voz ni los subtítulos, salvo que Haiku aparece
  también en su selector de modelo.

## 3. Cómo se usa

1. **Primera vez, ⌃⌥L.** Parla pide tres cosas:
   - **la fuente:** una ventana de la lista (con el icono y el nombre de su
     app) o «Un recuadro de la pantalla»;
   - **el recuadro:** se marca arrastrando, como en las capturas; si la fuente
     es una ventana, el arrastre queda limitado a ella;
   - **el cuaderno:** uno existente, uno nuevo (nombre y «De qué trata») o
     «Sin cuaderno».
2. **Siguientes veces, ⌃⌥L.** Arranca directo con la última configuración. Si
   la ventana de esa app no está abierta, vuelve al paso 1. Desde el panel se
   cambia la fuente, el recuadro o el cuaderno.
3. **Durante la sesión.**
   - El recuadro de una ventana sigue a la ventana: se guarda en proporción a
     su tamaño, así que moverla o redimensionarla no lo descoloca.
   - Si la ventana se minimiza, se cierra o deja de verse, la sesión se pausa
     sola y lo dice el panel.
   - El interruptor **Automático / Cuando yo diga** está en el panel.
   - ⌃⌥R lee en el momento en los dos ritmos; en Automático sirve para forzar
     una lectura que Parla no detectó.
   - Cada línea del panel tiene «Guardar».
4. **Para terminar,** ⌃⌥L otra vez o «Terminar» en el panel.

El menú emergente de la barra gana una cuarta casilla, «Lectura en vivo», con
su atajo, como las otras tres.

## 4. Arquitectura

```
ventana o pantalla
   │  ScreenCaptureKit, ~2 imágenes/s (Automático) o 1 (⌃⌥R)
   ▼
RegionWatcher (App) ── recorta el recuadro ──► TextReader (App, Vision)
                                                  │ líneas de texto
                                                  ▼
                                   LineDetector (Core) ── texto estable y nuevo
                                                  │
                                                  ▼
                       LiveReadingTranslator (Core) ◄── NotebookContext (Core)
                                                  │ traducción + guardar? + expresiones
                                                  ▼
                          LiveSession (App) ──► NotebookStore (App, SwiftData)
                                                  │
                                    panel / subtítulo / tapa  ·  Estudio › Cuadernos
```

Lo que no depende de la Mac vive en `ParlaCore`: detector, contexto, petición
y lectura de la respuesta. Así se prueba sin pantalla y una Parla para
teléfono podría reusarlo.

## 5. Componentes

### 5.1 LiveSource y LiveSetup (Core)

- `LiveSource`: `.window(bundleID: String, title: String)` o `.screen`.
- `LiveSetup`: la fuente, el recuadro y el cuaderno (`UUID?`, `nil` = «Sin
  cuaderno»).
  - Con una ventana, el recuadro se guarda en **fracciones** del tamaño de la
    ventana (`0…1` en cada eje).
  - Con la pantalla, en coordenadas globales.
- `Preferences` recuerda la última `LiveSetup` y, además, una por app
  (`bundleID`): al volver a elegir AFK Journey se recuperan su recuadro y su
  cuaderno.
- Para reencontrar la ventana se busca primero el mismo título dentro de la
  app y, si no está, la ventana más grande de esa app.

### 5.2 RegionWatcher (App)

- Con una ventana: un `SCStream` con un filtro de esa sola ventana
  (`SCContentFilter(desktopIndependentWindow:)`), a 2 fps. Cada fotograma se
  recorta con las fracciones del recuadro. El filtro capta la ventana aunque
  otra la tape a medias.
- Con la pantalla: el mismo stream sobre la pantalla que contiene el
  recuadro, con `sourceRect` igual al recuadro.
- Cuando el stream deja de entregar fotogramas (ventana minimizada o en otro
  Escritorio) o la ventana desaparece de `SCShareableContent`, emite
  `.paused(reason)`. Al volver la ventana, reanuda.
- En «Cuando yo diga» no hay stream: ⌃⌥R hace una captura única con
  `SCScreenshotManager` y el mismo recorte.
- **Excluye las ventanas de Parla** (panel, subtítulo, tapa) del filtro de
  pantalla, para no leer su propia traducción.

### 5.3 TextReader (App)

- `VNRecognizeTextRequest` con `recognitionLevel = .accurate`,
  `recognitionLanguages = ["en-US"]` y corrección de idioma activada.
- Devuelve las líneas de arriba abajo y las une con un espacio en un solo
  texto: la unidad es **el contenido del recuadro**, no cada renglón. En el
  resto del documento, «línea» quiere decir eso.
- Descarta observaciones con confianza menor de 0,3.

### 5.4 LineDetector (Core)

Recibe lecturas sucesivas y decide cuándo hay una línea nueva. Es una
estructura pura con `mutating func feed(_ text: String) -> String?`.

- **Normaliza:** recorta, colapsa espacios y quita los caracteres que Vision
  confunde con el borde del recuadro (`|`, `_` sueltos).
- **Espera a que el texto se asiente:** suelta la línea cuando dos lecturas
  seguidas coinciden tras normalizar. Así ignora el texto que aparece letra
  por letra.
- **Ignora lo que ya tradujo:** si se parece al menos un 90 % a la última
  línea soltada (distancia de edición normalizada), no la suelta otra vez. Un
  error de lectura de una letra no cuenta como línea nueva.
- **Una frase repetida sí cuenta** cuando entre medias hubo otra distinta o el
  recuadro quedó vacío.
- **Vacío:** un recuadro sin texto reinicia la espera, sin soltar nada.
- ⌃⌥R pasa por `force(_ text:)`, que suelta el texto aunque sea igual al
  último. Leer ahora es una orden explícita.

### 5.5 NotebookContext (Core)

Arma el contexto de una petición:

- el «De qué trata» del cuaderno, si lo tiene;
- las últimas **12** líneas **del cuaderno**, en orden, aunque sean de una
  sesión anterior: al retomar el juego al día siguiente, la historia sigue;
- con «Sin cuaderno», solo las últimas 12 líneas **de la sesión**.

### 5.6 LiveReadingTranslator (Core)

- Petición nueva en `ClaudeRequestBuilder`:
  `makeLiveReadingRequest(lines:context:apiKey:)`.
  - Admite **una o varias** líneas, para la cola de §7.
  - System prompt propio: traducir al español natural usando el contexto,
    marcar `save` solo si la línea trae una expresión, un modismo o un uso que
    valga la pena estudiar (no saludos ni frases triviales) y, en ese caso,
    explicar cada expresión en una o dos frases, con cuándo se usa.
- Salida estructurada:
  `{ "lines": [ { "spanish": String, "save": Bool, "expressions": [ { "phrase": String, "meaning": String } ] } ] }`.
- `effort: "low"`, como las demás peticiones.
- **Haiku 5.5** (`claude-haiku-5-5`) no admite fallback de servidor: con él la
  petición va **sin** `fallbacks` y **sin** la cabecera
  `anthropic-beta: server-side-fallback-2026-07-01`. Los demás modelos
  conservan las dos. La regla vive en el builder y vale para todas las
  peticiones, no solo para esta.
- Al leer la respuesta:
  - se descartan las expresiones con `phrase` o `meaning` vacíos;
  - una línea sin `spanish` queda «sin traducir»;
  - si llegan menos líneas que las pedidas, las que faltan quedan «sin
    traducir».
- **Explicar a mano:** `makeExplainLineRequest(line:context:apiKey:)` para el
  «Guardar» de una línea que el modelo no marcó. Usa el mismo esquema con una
  sola línea y la instrucción de explicar siempre.

### 5.7 ClaudeModel (App)

- Nuevo caso `haiku55 = "claude-haiku-5-5"`, etiqueta «Haiku 5.5», detalle
  «El más rápido y barato: $0,10 / $0,50 por millón de tokens.».
- El detalle de Sonnet 5.5 deja de decir «el más rápido y barato».
- Aparece en los dos selectores: el de siempre y el nuevo «Modelo para la
  lectura en vivo» (`Preferences.liveModel`, por defecto `.haiku55`).

### 5.8 LiveSession (App)

Orquesta una sesión y vive en `AppState`.

- **Estados:** `.idle`, `.choosingSetup`, `.running(rhythm)`,
  `.paused(reason)`.
- Une `RegionWatcher` → `TextReader` → `LineDetector` →
  `LiveReadingTranslator` y guarda cada línea en `NotebookStore`.
- **Cola:** las líneas se traducen en orden y hay una sola petición en vuelo.
  Si al terminar hay más de una pendiente, van juntas, hasta 5 por petición.
- Publica las líneas de la sesión para la vista que se haya elegido.

### 5.9 Vistas de la traducción (App)

`Preferences.liveDisplay` elige entre:

- **A · Subtítulo:** una franja justo encima del recuadro, con la última línea
  en español. Reusa el estilo de la banda de subtítulos.
- **B · Panel** (por defecto): el panel flotante de siempre. Arriba, el
  interruptor de ritmo, la fuente y el cuaderno; debajo, las líneas de la
  sesión, la más nueva arriba, con «Guardar» y una marca si ya se guardó.
- **C · Tapa:** una ventana sin bordes, que deja pasar los clics, exactamente
  sobre el recuadro, con el español sobre fondo opaco.

En A y C el panel sigue existiendo, pero cerrado. Se abre desde el menú
emergente para cambiar ritmo, fuente o cuaderno.

### 5.10 Estudio › Cuadernos (App)

- Nueva fila **Cuadernos** en la barra lateral de Estudio, con la lista de
  cuadernos y el número de líneas guardadas de cada uno. Al final aparece
  «Sin cuaderno», que agrupa las líneas sin cuaderno y no se puede renombrar
  ni borrar.
- Al abrir un cuaderno:
  - **arriba:** nombre y «De qué trata», editables;
  - **debajo:** las líneas guardadas, la más reciente arriba. Cada una con su
    «antes» y «después» en gris, la línea en serif con las expresiones
    subrayadas, el español y las explicaciones.
  - **«Ver todas las líneas»:** cambia a la lista completa de la sesión, sin
    explicaciones.
- Una línea guardada se puede quitar del cuaderno y un cuaderno se puede
  borrar, con confirmación, como el historial.
- Crear un cuaderno se hace al empezar una sesión o con un «+» en la lista.

## 6. Datos

Dos modelos nuevos de SwiftData en el mismo contenedor que `StoredCard`
(`Persistence.makeContainer`):

- `Notebook`: `id`, `name`, `about` (`String`, vacío por defecto),
  `createdAt`. Al borrarlo se borran sus líneas en cascada.
- `NotebookLine`:
  - **texto:** `id`, `english`, `spanish` (`String?`; `nil` = sin traducir);
  - **origen:** `sessionID`, `readAt`, `notebook` (`Notebook?`; `nil` = «Sin
    cuaderno»);
  - **estudio:** `isSaved` y `expressions` (relación en cascada con
    `phrase` y `meaning`).

El «antes y después» no se guarda: son las líneas vecinas de la misma
`sessionID`, ordenadas por `readAt`.

Son tablas nuevas, así que la migración es ligera y `StoredCard` no cambia.

## 7. Errores

- **Sin permiso de grabación de pantalla:** ⌃⌥L muestra el aviso de
  `SetupStatus` que ya usan las capturas, con el botón a Ajustes del Sistema.
  No arranca sin él. `SetupStatus` añade `ParlaMode.live` con el mismo
  requisito que `.capture`.
- **Sin clave de API:** el mismo aviso que los demás modos.
- **La ventana se cierra:** la sesión se pausa con «La ventana se cerró». Si
  aparece otra ventana de la misma app, la retoma sola, con la regla de §5.1.
- **Sin red o error de la API:** la línea queda «sin traducir», con
  «Reintentar» en el panel. La lectura no se detiene y la línea se guarda en
  la sesión igualmente. Los errores no se reintentan solos, para no gastar a
  ciegas.
- **⌃⌥R con el recuadro vacío:** el panel dice «No encontré texto en el
  recuadro».
- **Respuesta mal formada:** todas las líneas de esa petición quedan «sin
  traducir».
- **Vision no está disponible o falla:** la sesión se pausa con el error y se
  registra en `Log`.

## 8. Privacidad y coste

- Las imágenes **nunca salen de la Mac**: se leen con Vision y se descartan.
- A Anthropic llegan el texto del recuadro, el «De qué trata» y las últimas 12
  líneas.
- Solo se lee mientras hay una sesión activa. El icono de la barra de menús
  lo indica, como con la escucha.
- **Coste orientativo con Haiku 5.5:** unos 1.500 tokens de entrada y 200 de
  salida por línea, o sea $0,00025. Con ~300 líneas por hora de juego salen
  unos 8 centavos de dólar por hora.

## 9. Pruebas

**Core (`make test`):**

- `LineDetector`:
  - el texto que aparece letra por letra suelta una sola línea;
  - una letra mal leída no repite la línea;
  - una frase repetida con otra entre medias se suelta dos veces;
  - un recuadro vacío reinicia la espera;
  - `force` suelta aunque el texto sea igual;
  - los bordes `|` no cuentan.
- `NotebookContext`:
  - incluye el «De qué trata» cuando existe y lo omite si está vacío;
  - toma las últimas 12 líneas del cuaderno, cruzando sesiones;
  - sin cuaderno, solo las de la sesión.
- `ClaudeRequestBuilder`:
  - el cuerpo y el esquema de `makeLiveReadingRequest` con una y con varias
    líneas;
  - con Haiku, sin `fallbacks` ni cabecera beta, en todas las peticiones; con
    los demás modelos, con ambas.
- Lectura de la respuesta: expresiones vacías descartadas, línea sin
  `spanish`, menos líneas que las pedidas.
- «Antes y después»: vecinas de la misma sesión, no de otra.

**App (`make test-app`):**

- Migración: una base con solo `StoredCard` abre con los modelos nuevos sin
  perder tarjetas, con el patrón de las pruebas de migración existentes.
- `LiveSetup`: las fracciones del recuadro se convierten bien a píxeles de la
  ventana y vuelven.
- `LiveSession` con fuente y traductor falsos:
  - la cola respeta el orden y agrupa más de una pendiente;
  - un error deja la línea «sin traducir»;
  - la pausa detiene la lectura.

**Evaluación (`make eval-capture`, nuevo directorio `Fixtures/en-vivo`):**

- Secuencias de diálogo inventadas que comprueban dos cosas:
  - la traducción usa el contexto («Then we hold it» → «it» es «the line»);
  - las líneas útiles se marcan `save` y las triviales («Let's go») no.
- Se corre con Haiku 5.5 y con el modelo de capturas.

**A mano:** una sesión real con AFK Journey en los dos ritmos y las tres
vistas.

## 10. Riesgos y sondas

Son la primera tarea del plan. Cada riesgo tiene una alternativa decidida de
antemano:

1. **Vision con las fuentes del juego.** Se leen 10 capturas de diálogos de
   AFK Journey (las toma Edwin y van a `Fixtures/en-vivo/imagenes`) y se mide cuántas salen exactas y cuánto tarda cada lectura.
   Si falla más de 2 de 10, se prueba sin corrección de idioma y con el
   recuadro ampliado ×2 antes de leer. Si sigue fallando, se adelanta la
   lectura mixta (imagen cuando la confianza es baja) a esta versión.
2. **El stream de una ventana tapada o en pantalla completa.** Hay que
   comprobar que `desktopIndependentWindow` entrega fotogramas con la ventana
   medio tapada y si los entrega con el juego en pantalla completa en otro
   Escritorio. Si no los entrega en pantalla completa, la sesión se pausa con
   «Parla no puede ver la ventana en pantalla completa».
3. **La tapa (C) sobre un juego a pantalla completa.** Un `NSPanel` con
   `.fullScreenAuxiliary` y `.canJoinAllSpaces` debe verse encima. Si no, en
   pantalla completa se cambia solo a A y se avisa una vez.
4. **Haiku y la salida estructurada con varias líneas.** Con 5 líneas en una
   petición, la respuesta tiene que traer las 5 en orden. Si se desordena o
   recorta, la cola manda una línea por petición.
5. **Lista de ventanas en el sandbox.** `SCShareableContent` con el permiso
   concedido debe listar las ventanas de otras apps con su `bundleID`. Si no
   da el `bundleID`, se recuerda la app por su nombre.

**Resultados (29-oct-2026, AFK Journey en una Mac con macOS 26.5):**

- **Sonda 2: pasa.** El stream entrega 2 fotogramas completos por segundo,
  durante 20 s, con la ventana visible, medio tapada y a pantalla completa
  en otro Escritorio. No hace falta el aviso de pantalla completa.
- **Sonda 3: pasa.** El panel se ve encima del juego en ventana y a
  pantalla completa. No hace falta cambiar a A.
- **Sonda 5: pasa.** Todas las ventanas traen su `bundleID`; el juego es
  `com.farlightgames.igame.ios`. Además de la ventana principal, el juego
  tiene franjas de 30 px de alto que no se pintan: hay que elegir la ventana
  como `WindowList`, sin las de menos de 100 px de alto.
- **Sondas 1 y 4:** pendientes.

## 11. Decisiones registradas

- **Leer el texto en la Mac, no mandar imágenes:** cuesta casi nada, responde
  rápido y no manda nada mientras el diálogo no cambia. Se acepta que una
  fuente muy decorada se lea mal alguna vez.
- **Dos ritmos y un atajo propio para leer ahora (⌃⌥R),** separado de la
  captura (⌃⌥C), para que «Leer ahora» no cambie de sentido según haya o no
  una sesión.
- **⌃⌥L para la sesión,** en la familia ⌃⌥ de los otros atajos.
- **El cuaderno es el contexto del modelo:** «De qué trata» escrito por el
  usuario más las últimas 12 líneas, cruzando sesiones.
- **Guardado automático con explicación,** más «Guardar» a mano para lo que
  se escape, en vez de solo a mano, para no soltar el juego para tomar notas.
- **Modelo elegible para este modo,** con Haiku 5.5 por defecto: 8/8 en la
  evaluación de capturas, y es el más barato y rápido.
- **La vista de la traducción se elige en Ajustes** (A, B o C), con B por
  defecto porque no tapa nada del juego.
- **El «antes y después» se deriva, no se copia:** una sola fuente de verdad
  por línea.
- **Lógica en `ParlaCore`** para que una futura Parla para teléfono la reuse.
  Esa app es otro proyecto, con su propia investigación: el iPhone no deja
  leer la pantalla de otras apps tan fácilmente.
