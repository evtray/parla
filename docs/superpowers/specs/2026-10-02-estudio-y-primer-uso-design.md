# Parla — Estudio, identidad y primer uso: diseño

**Fecha:** 2026-10-02
**Estado:** borrador para revisión
**Rama:** `feat/estudio`, sacada de `feat/subtitulos` (el PR #1 sigue abierto)
**Parte de:** mejora de UI/UX, sub-proyecto A. El B (panel, tarjetas y banda)
y la parte académica (repaso, práctica, mejores explicaciones) van después.

## 1. Problema

Parla ya hace tres cosas: voz → inglés, captura de pantalla y subtítulos del
sistema. La experiencia alrededor no ha crecido con ellas:

- **El primer uso no existe.** Parla vive en la barra de menús y no abre nada
  al arrancar. Quien la instala no sabe dónde está, ni que necesita una clave,
  dos permisos y los idiomas de Traducción.
- **No tiene identidad.** No hay icono de la app: Finder, Spotlight y los
  diálogos de permisos muestran el genérico.
- **El menú es una lista de texto.** No se ve qué modo está activo ni qué atajo
  tiene cada uno. Los errores salen como una línea roja sin forma de
  resolverlos.
- **El historial y los ajustes son dos ventanas sueltas.** El historial no
  permite marcar ni borrar nada.
- **Los avisos se quedan obsoletos.** `needsScreenRecordingAccess`,
  `needsTranslationLanguages` y `setupError` son variables sueltas en
  `AppState` que nadie limpia cuando el problema se resuelve.

## 2. Alcance

**Esta versión hace esto:**

- Identidad «cuaderno de estudio»: icono de la app, acento terracota y el
  inglés en serif.
- Una ventana **Estudio** con barra lateral (Historial y Ajustes), que
  sustituye a las ventanas de Historial y de Ajustes.
- Historial con favoritos y borrado.
- Una **bienvenida guiada** de cuatro pasos en el primer arranque.
- Un **menú emergente** con los tres modos, sus avisos y la última frase, en
  lugar del menú de texto.
- `SetupStatus`: una sola fuente de «qué falta por preparar», que alimenta la
  bienvenida, el menú emergente, Estudio y el panel.

**Esta versión no hace esto** (decisiones tomadas, no omisiones):

- No toca el panel flotante, las tarjetas ni la banda de subtítulos, salvo que
  heredan el color de acento y leen sus avisos de `SetupStatus`. Su rediseño
  es el sub-proyecto B.
- No añade Repaso ni Práctica, ni filas vacías en la barra lateral que los
  anuncien.
- No hay deshacer al borrar una tarjeta: se pide confirmación.
- La última frase del menú emergente abre el Historial, no salta a esa
  tarjeta.
- No hay ajustes nuevos más allá de «Ver la bienvenida otra vez».

## 3. Identidad

- **Icono de la app:** cuadrado redondeado terracota con «Aa» en serif, de
  color crema. Se dibuja como SVG en el repo y se genera con un script. El
  formato (Icon Composer `.icon` o `AppIcon.appiconset`) lo decide la sonda de
  la §10. Criterio: en Finder debe verse con la forma del sistema y sin la
  placa gris que macOS 26 pone a los iconos antiguos.
- **Color de acento:** `AccentColor` en un catálogo de assets nuevo, con dos
  valores: `#B84A26` en claro y `#F0997B` en oscuro. El icono usa `#D85A30`,
  más vivo, porque no lleva texto pequeño encima; en la interfaz, el blanco
  sobre `#D85A30` solo llega a 3,9:1. Se declara como acento
  global (`ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`) para que tiña
  controles, selección y `.tint` en toda la app.
- **Texto sobre el acento:** un color emparejado con contraste ≥ 4.5:1 en los
  dos modos: blanco sobre `#B84A26` (5,2:1), `#4A1B0C` sobre `#F0997B`
  (6,6:1).
- **Tipografía:** el inglés va en serif del sistema (New York) y el resto en la
  fuente del sistema. Las fuentes y colores de marca viven en un solo archivo
  (`App/UI/Theme.swift`), para que el sub-proyecto B lo reutilice.
- **Icono de la barra de menús:** `character.bubble` en reposo y
  `character.bubble.fill` con cualquier modo activo. Sigue siendo un símbolo
  monocromo, como exige macOS. Qué modo está activo se ve en el menú
  emergente.

## 4. Arquitectura

```
                 ┌──────────────── SetupMonitor (App, @MainActor) ───────────────┐
 Llavero ───────▶│ lee las fuentes reales y publica un SetupStatus               │
 AVCaptureDevice ▶│ refresca: al abrirse una vista, al volver a primer plano     │
 CGPreflight… ──▶│ y después de cada arreglo                                     │
 LiveTranslator ▶│ ejecuta los arreglos (pedir permiso, abrir Ajustes, reabrir)  │
                 └───────┬──────────────┬──────────────┬──────────────┬──────────┘
                         ▼              ▼              ▼              ▼
                    Bienvenida    Menú emergente    Estudio      Panel flotante
                                                  (aviso superior) (avisos de hoy)
```

- **`SetupStatus` (Core, puro).** Con unos datos de entrada dice qué queda
  pendiente, qué modos bloquea cada pendiente y cuál es su arreglo. No importa
  nada del sistema y se prueba en Core.
- **`SetupMonitor` (App).** Traduce el sistema a esos datos de entrada. Es el
  único sitio que llama a `AVCaptureDevice`, `CGPreflightScreenCaptureAccess`,
  `CGRequestScreenCaptureAccess`, al Llavero y a `LiveTranslator.readiness()`
  para preguntar por la preparación.
- **`APIKeyValidator` (Core).** Comprueba una clave contra la API. Usa el
  `HTTPStreamer` que ya existe, así que se prueba con el transporte falso de
  siempre.
- **`StudioRouter` (App).** Guarda qué sección de Estudio se muestra. Permite
  que el menú emergente y ⌘, abran Estudio directamente en Ajustes.
- **`WindowCoordinator` (App).** Abre y reutiliza las ventanas de Estudio y de
  la bienvenida: `NSWindow` con un `NSHostingController` de SwiftUI. Cualquiera
  puede llamarlo, también el panel flotante, que vive fuera de las escenas de
  SwiftUI y no tiene `openWindow`.
- **`AppState`** se queda con el estado de ejecución: escuchando, subtitulando,
  errores de una sesión y cola por lotes. Pierde
  `needsMicrophoneAccess`, `needsScreenRecordingAccess` y
  `needsTranslationLanguages`, y deja de poner en `setupError` los mensajes de
  preparación (clave, permisos, idiomas). Antes de arrancar un modo, pregunta a
  `SetupMonitor` por `startBlockers(for:)`. Si hay alguno, no arranca: el panel
  muestra los avisos de `SetupStatus` para ese modo, con su botón. Los
  pendientes de «pedir permiso» (`requestMicrophone`, `requestScreenRecording`)
  no bloquean: el propio arranque lanza el diálogo del sistema, como hoy, que es
  justo cuando su motivo es evidente.

## 5. Componentes

### 5.1 SetupStatus (Core)

```swift
public enum ParlaMode: Sendable, CaseIterable { case voice, capture, subtitles }

public enum PermissionState: Sendable { case granted, notDetermined, denied }

public enum LanguageState: Sendable { case unknown, ready, needsDownload, unsupported }

public struct SetupInputs: Sendable, Equatable {
    public var hasAPIKey: Bool
    public var microphone: PermissionState
    public var screenRecordingGranted: Bool
    /// Si ya se lanzó alguna vez el diálogo del sistema para la pantalla.
    public var screenRecordingRequested: Bool
    public var languages: LanguageState
}

public enum SetupItem: Sendable, CaseIterable { case apiKey, microphone, screenRecording, languages }

public enum SetupFix: Sendable, Equatable {
    case enterAPIKey
    case requestMicrophone
    case openMicrophoneSettings
    case requestScreenRecording
    /// Abrir Ajustes del Sistema y, si ya se concedió, reabrir Parla.
    case openScreenRecordingSettingsOrRelaunch
    case openLanguageSettings
    /// Este Mac no puede: solo se explica.
    case none
}

public struct SetupIssue: Sendable, Equatable {
    public let item: SetupItem
    public let fix: SetupFix
}

public struct SetupStatus: Sendable, Equatable {
    public init(_ inputs: SetupInputs)
    public var issues: [SetupIssue]                       // en el orden de SetupItem
    /// Todos los pendientes que afectan al modo, para mostrarlos.
    public func blockers(for mode: ParlaMode) -> [SetupIssue]
    /// Los que impiden arrancarlo: `blockers(for:)` sin los de pedir permiso.
    public func startBlockers(for mode: ParlaMode) -> [SetupIssue]
    public var isComplete: Bool                           // issues.isEmpty
}
```

**Qué necesita cada modo:**

| Modo       | Clave | Micrófono | Pantalla | Idiomas |
|------------|:-----:|:---------:|:--------:|:-------:|
| Voz        |   ✓   |     ✓     |          |         |
| Captura    |   ✓   |           |    ✓     |         |
| Subtítulos |       |           |    ✓     |    ✓    |

**Reglas:**

- Micrófono `.notDetermined` → `requestMicrophone`; `.denied` →
  `openMicrophoneSettings`.
- Pantalla sin conceder y nunca pedida → `requestScreenRecording`. Ya pedida →
  `openScreenRecordingSettingsOrRelaunch`. macOS solo muestra el diálogo una
  vez por identidad de app y no aplica el permiso hasta reabrir.
- Idiomas `.unknown` no es pendiente: aún no se sabe, y no se alarma.
  `.needsDownload` → `openLanguageSettings`; `.unsupported` → `none`.

Los textos de cada pendiente (título, motivo y botón) se escriben en la App
(`SetupIssue+UI.swift`), igual que `CaptureKind+UI.swift`.

### 5.2 SetupMonitor (App)

- `@MainActor @Observable final class SetupMonitor`, con
  `private(set) var status: SetupStatus` y `func refresh() async`. Vive en
  `AppState` y se pasa a las vistas.
- **Clave.** Se pregunta al Llavero si el elemento existe, sin pedir sus datos
  (sin `kSecReturnData`), así que no salta la petición de contraseña. Se añade
  a `KeychainStore` como `var hasAPIKey: Bool`. En Debug, `PARLA_API_KEY`
  cuenta como clave presente. Si la consulta falla por cualquier motivo, cuenta
  como «falta la clave».
- **Pantalla pedida.** `screenRecordingRequested` se guarda en `Preferences`,
  para que sobreviva a reabrir. Sustituye a `askedForScreenAccess`, que hoy
  vive en memoria.
- **Cuándo se refresca:**
  - al arrancar;
  - en `NSApplication.didBecomeActiveNotification`;
  - al aparecer la bienvenida, el menú emergente o Estudio;
  - después de guardar la clave o de ejecutar un arreglo.

  Como `readiness()` es asíncrono, `languages` empieza en `.unknown`.
- **`func perform(_ fix: SetupFix)`:**
  - **Pedir micrófono:** `AVCaptureDevice.requestAccess`.
  - **Pedir pantalla:** `CGRequestScreenCaptureAccess` y marcar como pedida.
  - **Abrir paneles:** usa las URL de `AppState.open…Settings`, que se mudan
    aquí.
  - **Reabrir Parla:** abre una instancia nueva del bundle con
    `NSWorkspace.openApplication` y termina la actual.
  - Al terminar, refresca.

### 5.3 APIKeyValidator (Core)

- `public struct APIKeyValidator { init(streamer: HTTPStreamer); func check(_ key: String) async -> KeyCheck }`
- `public enum KeyCheck: Sendable, Equatable { case valid, invalid, unverified }`
- **La petición:** `GET https://api.anthropic.com/v1/models?limit=1`, con
  `x-api-key` y `anthropic-version: 2023-06-01`, y `timeoutInterval = 10`. Se
  arma en `ClaudeRequestBuilder`, junto a las otras. No consume tokens.
- **Antes de comprobar** se quitan espacios y saltos de línea, que son
  frecuentes al pegar. Una clave vacía es `invalid` sin red.
- **Resultado:**
  - 200 → `valid`;
  - 401 o 403 → `invalid`;
  - cualquier otro estado, un error de red o un tiempo agotado → `unverified`.
- La clave nunca se registra en el log.
- **Guardado:**
  - `valid` → se guarda;
  - `unverified` → se guarda con el aviso «No se pudo comprobar la clave; se
    guardó igualmente»;
  - `invalid` → no se guarda: «Esa clave no funciona. Revisa que esté
    completa».

### 5.4 Bienvenida

- Ventana de `WindowCoordinator`, de tamaño fijo (~480 × 440) y centrada.
- `applicationDidFinishLaunching` la abre si
  `Preferences.hasSeenWelcome == false`. Activa la app al aparecer, para quedar
  delante.
- **Pasos**, con indicador de progreso arriba y «Ahora no» y
  «Continuar» abajo:
  1. **Hola.** Qué hace Parla, en tres filas, una por modo, con icono y una
     frase.
  2. **Clave.** `SecureField` y un enlace a
     `https://console.anthropic.com/settings/keys`. Al continuar, se comprueba
     según la §5.3:
     - `invalid` deja en el paso;
     - `unverified` avanza con el aviso.

     Si ya hay una clave guardada, se dice y el campo queda vacío para
     reemplazarla.
  3. **Permisos.** Una fila para el micrófono y otra para la grabación de
     pantalla. Cada fila tiene un motivo de una línea, su estado y el botón de
     su `SetupFix`. El diálogo del sistema solo sale al pulsar el botón.
  4. **Listo.**
     - El estado del inglés para subtítulos, con su botón si falta.
     - Los tres atajos actuales, leídos de `KeyboardShortcuts`.
     - Una ilustración de la barra de menús con el icono de Parla señalado.
       macOS no ofrece una forma pública de abrir ni de localizar el icono de
       otra app.
     - El botón «Empezar» cierra la ventana.
- **Fin de la bienvenida.** `hasSeenWelcome` pasa a `true` al pulsar «Empezar»
  o al cerrar la ventana en cualquier paso. Lo que quede pendiente vive en
  `SetupStatus`.
- **Volver a verla.** En Ajustes, «Ver la bienvenida otra vez» la abre desde el
  paso 1, sin tocar la preferencia.

### 5.5 Menú emergente

- `MenuBarExtra` con `.menuBarExtraStyle(.window)` y unos 300 pt de ancho.
  Lleva `modelContainer`, para leer la última tarjeta.
- **Fila de modos:** tres botones (Voz, Captura y Subtítulos), cada uno con su
  icono, nombre y atajo actual.
  - El modo activo se rellena con el acento y muestra «Escuchando» o «Activos».
  - Voz y Subtítulos alternan.
  - Captura cierra el menú emergente y luego llama a `captureScreen()`.
  - Un botón con pendientes no se desactiva. Si alguno impide arrancar
    (`startBlockers`), al pulsarlo el modo no arranca y esos pendientes suben al
    primer lugar de los avisos.
- **Avisos:** como mucho dos filas visibles; si hay más, «y N más», que abre
  Estudio.
  - **Orden:** primero los errores de ejecución de `AppState` (`setupError`,
    `captureError`, `silentInputWarning`, `batchError`), luego los pendientes
    de `SetupStatus`.
  - **Botones:** un pendiente lleva el botón de su arreglo; un error de
    ejecución lleva «Descartar».
  - **Textos:** siempre legibles (`readableMessage`), nunca el texto en bruto
    de un error.
- **Traducir N frases:** solo en modo por lotes y con frases en cola. Igual
  que hoy.
- **Última frase:** la tarjeta más reciente (`@Query` con `fetchLimit` 1), con
  el inglés en serif y el resultado debajo. Al pulsarla se abre Estudio en
  Historial. Sin tarjetas, la sección no aparece.
- **Pie:** «Abrir Estudio», un engranaje (Estudio › Ajustes) y «Salir».

### 5.6 Estudio

- Ventana de `WindowCoordinator` con `NavigationSplitView`, de 760 × 520 como
  mínimo. El `NSHostingController` pasa la barra de herramientas y el título a
  la ventana (`sceneBridgingOptions`). Sustituye a `Window("Historial")` y a la
  escena `Settings`.
- **Barra lateral:** Historial arriba y Ajustes abajo. La selección vive en
  `StudioRouter`.
- **Abrir Estudio** es `WindowCoordinator.showStudio(_ section:)`: fija la
  sección, activa la app y trae la ventana delante. ⌘, es un atajo de teclado
  dentro de Estudio y del menú emergente, que son las únicas ventanas con foco
  en las que tiene sentido.
- **Aviso superior:** si `SetupStatus` tiene pendientes, una franja sobre el
  detalle los lista con la misma fila que el menú emergente
  (`SetupIssueRow`).

**Historial**

- Filtro de modo segmentado (Todo, Voz, Capturas, Subtítulos), botón de
  estrella «solo favoritas» y búsqueda como hoy. El filtro de modo y el de
  favoritas se combinan.
- **Cada tarjeta:**
  - el icono del modo (`mic`, `crop`, `captions.bubble`) y la hora, en lugar
    del emoji;
  - el original y el resultado, con el inglés en serif;
  - el porqué y el vocabulario, como hoy;
  - una estrella que alterna `isFavorite`.
- **Clic derecho:** «Copiar el inglés» y «Borrar…». Borrar pide confirmación y
  elimina la tarjeta con su vocabulario: la relación ya es `.cascade`.
- **Dónde está el inglés** (`EnglishSide`, función pura en la App):
  - voz → el resultado;
  - subtítulos → el original;
  - captura `understand` → el original;
  - captura `translate` → el resultado;
  - captura `correct` → los dos.

  «Copiar el inglés» copia el resultado cuando son los dos, porque es la
  versión corregida.

**Ajustes**

- El formulario actual de `SettingsView`, sin su marco fijo de 420 × 640.
- Guardar la clave pasa por la §5.3.
- Se añade el botón «Ver la bienvenida otra vez».

## 6. Datos

- `StoredCard` gana `var isFavorite: Bool = false`. Las filas antiguas migran
  solas con el valor por defecto, igual que `origin`.
- `Preferences` gana `hasSeenWelcome` y `screenRecordingRequested`, los dos
  `false` si nunca se tocaron.
- Borrar y marcar favoritas se hace con el `modelContext` de la vista, que es
  el mismo contenedor que usa `CardStore`.

## 7. Errores

| Situación | Qué ve Edwin |
|---|---|
| El Llavero falla al comprobar | «Falta la clave», con su botón. Nunca bloquea ni pide contraseña. |
| La clave es rechazada (401/403) | «Esa clave no funciona», en el mismo sitio donde la escribió. No se guarda. |
| Sin red o tiempo agotado al comprobar | Se guarda y avisa: «No se pudo comprobar la clave; se guardó igualmente». |
| Pantalla concedida pero sin aplicar | La fila ofrece «Abrir Ajustes del Sistema» y «Reabrir Parla». |
| Se arranca un modo con pendientes desde un atajo | Si alguno impide arrancar, el modo no arranca y el panel muestra sus pendientes con botón. Si solo falta pedir un permiso, arranca y sale el diálogo del sistema. |
| Un pendiente se resuelve fuera de Parla | Al volver a primer plano el aviso desaparece solo. |
| Error de ejecución (captura, micrófono mudo…) | Aviso legible con «Descartar»; se limpia también al volver a arrancar el modo. |
| Se borra la tarjeta que sale como «última frase» | El menú emergente muestra la anterior. |
| Se cierra la bienvenida a mitad | Cuenta como vista; lo pendiente sigue en los avisos. |

## 8. Privacidad

- La clave sigue viviendo solo en el Llavero. La comprobación la envía
  únicamente a `api.anthropic.com`, como ya hacían las traducciones.
- Ni la clave ni el texto de las tarjetas se escriben en el log.
- La bienvenida no envía nada hasta que se pulsa «Continuar» con una clave
  escrita.

## 9. Pruebas

**Automáticas (TDD).**

- **Core:**
  - `SetupStatusTests`: la tabla de la §5.1, una prueba por regla;
    `.unknown` no es pendiente; `blockers(for:)` y `startBlockers(for:)` para
    cada modo (los de pedir permiso no impiden arrancar); `isComplete`.
  - `APIKeyValidatorTests`, con el transporte falso: 200, 401, 403, 429, 500,
    error de red, clave con espacios y saltos de línea, clave vacía (sin red).
  - `ClaudeRequestBuilderTests`: la petición de modelos (método, URL,
    cabeceras, tiempo límite).
- **App:**
  - `EnglishSideTests`: cada origen y cada `CaptureKind`.
  - `HistoryFilterTests`, ampliado: favoritas combinadas con cada origen.
  - `StoredCardMigrationTests`, ampliado: una base antigua abre con
    `isFavorite == false`.
  - `CardStoreTests`, ampliado: borrar elimina también el vocabulario.
  - `PreferencesTests`, ampliado: `hasSeenWelcome` y
    `screenRecordingRequested`.
  - `StudioRouterTests`: abrir en Ajustes fija la sección.

**Sondas (antes de escribir la UI, ver §10).** Cada una deja su resultado en
el ledger del plan.

**A mano, al final:**

- **Primer arranque desde cero:** borrar `hasSeenWelcome` y
  `screenRecordingRequested` y resetear los permisos con `tccutil`, que corre
  Edwin.
- La bienvenida completa, y otra vez saltando cada paso.
- El menú emergente con cada modo, con pendientes y sin ellos.
- Estudio en claro y en oscuro.
- El icono en Finder, Spotlight y la lista de Ajustes del Sistema ›
  Privacidad.

## 10. Riesgos y sondas

Son la primera tarea del plan. Cada riesgo tiene una alternativa decidida de
antemano:

1. **Cerrar el menú emergente antes de la cruz.** `dismiss` no siempre cierra
   un `MenuBarExtra` de estilo ventana. Si no cierra, se busca la ventana
   del `MenuBarExtra` entre las de la app y se cierra con `orderOut`. La
   prueba: la cruz aparece y el menú emergente no sale en la captura.
2. **Comprobar el Llavero sin la petición de contraseña.** En compilaciones
   ad hoc, leer los datos la provoca. Hay que confirmar que una consulta sin
   `kSecReturnData` no la provoca. Si la provocara, `hasAPIKey` se recordaría
   en `Preferences` al guardar o borrar la clave (no es secreto).
3. **Formato del icono en macOS 26.** Primero se prueba el `.icon` de Icon
   Composer: que XcodeGen lo incluya y que `actool` lo compile. Si no, se usa
   `AppIcon.appiconset` con un diseño a sangre completa. La prueba: Finder lo
   muestra con la forma del sistema y sin placa gris.
4. **Ventanas AppKit con contenido SwiftUI.** Hay que comprobar que la barra
   de herramientas (filtro y búsqueda) aparece con `sceneBridgingOptions` y que
   la ventana queda delante en una app `LSUIElement`, también al arrancar. Si
   la barra no aparece, el filtro y la búsqueda van en una cabecera dentro del
   contenido.
5. **⌘, sin menú visible.** El atajo dentro de la vista debe responder con
   Estudio o el menú emergente delante. Si no, un monitor local de teclado en
   `WindowCoordinator`.

## 11. Decisiones registradas

- **Estructura de Estudio:** barra lateral, no pestañas, porque Repaso y
  Práctica entran después como filas sin rediseño.
- **Identidad:** «cuaderno de estudio»: terracota y el inglés en serif. Los
  modos se distinguen por icono, no por color.
- **Primer uso:** bienvenida guiada que se puede saltar. Lo pendiente vive en
  avisos, no en una lista de tareas aparte.
- **Menú de la barra:** ventana emergente, no menú nativo. Se pierde la
  navegación por teclado del menú; los atajos globales siguen igual.
- **Ajustes:** dentro de Estudio. La escena `Settings` desaparece y ⌘, lleva a
  Estudio › Ajustes.
- **Una sola fuente de preparación** (`SetupStatus`), para que la bienvenida,
  el menú emergente, Estudio y el panel no puedan contradecirse.
- **Comprobar la clave** con la lista de modelos: sin coste, y distingue «clave
  mala» de «sin red».
- **Ventanas de Estudio y bienvenida en AppKit**, no escenas `Window`: el
  panel flotante tiene que poder abrir Estudio, y abrir la bienvenida al
  arrancar deja de depender de `defaultLaunchBehavior`.
- **Acento `#B84A26` en claro**, no `#D85A30`: con el blanco encima, el segundo
  no llega al 4,5:1 que pide el texto pequeño.
