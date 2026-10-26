# Estudio, identidad y primer uso — plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Parla gana identidad propia (icono, acento terracota e inglés en serif) y una ventana Estudio con Historial y Ajustes. Además:
- una bienvenida guiada en el primer arranque;
- un menú emergente con los tres modos;
- una sola fuente de «qué falta por preparar».

**Architecture:**
- **Core.** Dos piezas puras y probadas:
  - `SetupStatus`: qué falta y qué modos bloquea;
  - `APIKeyValidator`: comprueba la clave contra la lista de modelos.
- **App.**
  - `SetupMonitor` traduce el sistema (Llavero, permisos, idiomas) a `SetupStatus`. Alimenta la bienvenida, el menú emergente, Estudio y el panel.
  - `WindowCoordinator` abre Estudio y la bienvenida como `NSWindow` con contenido SwiftUI, así el panel flotante también puede abrirlas.
  - El `MenuBarExtra` pasa a estilo ventana.

**Tech Stack:** Swift 6 (concurrencia estricta), swift-testing, SPM + XcodeGen, SwiftUI + AppKit (`NSHostingController`, `MenuBarExtra`), SwiftData, Security (Llavero), AVFoundation (permisos), KeyboardShortcuts.

**Spec:** `docs/superpowers/specs/2026-10-02-estudio-y-primer-uso-design.md`

## Global Constraints

- **Plataforma.** La app sigue en **macOS 26.4** mínimo y Core en `.macOS(.v26)`. Concurrencia estricta completa (`SWIFT_STRICT_CONCURRENCY: complete`).
- **`Core` solo importa Foundation.** AVFoundation, Security, AppKit y SwiftUI viven en App.
- **Ninguna dependencia nueva.**
- **Colores:**
  - acento `#B84A26` en claro y `#F0997B` en oscuro;
  - texto sobre el acento blanco en claro y `#4A1B0C` en oscuro;
  - icono: fondo `#D85A30` con «Aa» en `#FAECE7`.
- **Tipografía:** el inglés va en serif del sistema (`.system(_, design: .serif)`); el resto, en la fuente del sistema.
- **Icono de la barra:** `character.bubble` en reposo y `character.bubble.fill` con un modo activo.
- **Tamaños:**
  - Estudio: 760 × 520 como mínimo;
  - bienvenida: 480 × 440 fija;
  - menú emergente: 300 pt de ancho, con 2 avisos visibles como mucho.
- **Clave:**
  - vive solo en el Llavero;
  - se comprueba con `GET https://api.anthropic.com/v1/models?limit=1`, `x-api-key`, `anthropic-version: 2023-06-01`, tiempo límite **10 s**;
  - nunca va al log, y tampoco el texto de las tarjetas.
- **Textos de interfaz en español.** Ningún aviso muestra el texto en bruto de un error.
- **Fuera de alcance.** El panel flotante, las tarjetas y la banda de subtítulos no se rediseñan: heredan el acento, y el panel lee sus avisos de `SetupStatus`.
- **Proyecto.** Después de crear archivos en `App/` o `AppTests/`, `make test-app` y `make build` regeneran el proyecto solos (`xcodegen generate`).
- **Permisos y compilaciones.** Cada compilación nueva es una app nueva para macOS y pierde los permisos de micrófono y de Grabación de pantalla. Edwin los resetea con `tccutil` y los concede él. La clave nunca se escribe en un campo: la real ya está en el Llavero.
- **Rama `feat/estudio`.** Cada commit termina con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Pegar la clave con espacios o un salto de línea.** Se comprueba y se guarda sin ellos. → `seMandaLaClaveSinEspaciosNiSaltos` (Task 4) y `unaClaveBuenaSeGuardaSinEspacios` (Task 7).
2. **Pulsar Guardar o Continuar con el campo vacío.** Nunca borra la clave que ya está en el Llavero: hoy `KeychainStore.apiKey = ""` la borra. → `unCampoVacioNuncaBorraLaClaveGuardada` (Task 7).
3. **Cerrar la bienvenida con el botón de la ventana a mitad de un paso.** Cuenta como vista y no vuelve a salir sola. → `cerrarLaVentanaDeBienvenidaLaDaPorVista` (Task 12).
4. **Varios avisos a la vez y un modo bloqueado.** Lo que impide arrancar sale arriba; se ven dos como mucho y el resto se cuenta. → `loQueImpideArrancarSubeArriba` (Task 9).
5. **Micrófono «restringido»** (control parental o gestión del Mac). Cuenta como denegado y ofrece Ajustes del Sistema, no un «Permitir» que no haría nada. → `losPermisosDelSistemaSeTraducenBien` (Task 6).

---

## Estructura de archivos

```
Core/Sources/ParlaCore/
  SetupStatus.swift            # NUEVO: ParlaMode, PermissionState, LanguageState, SetupInputs,
                               #        SetupItem, SetupFix, SetupIssue, SetupStatus
  APIKeyValidator.swift        # NUEVO: KeyCheck, APIKeyValidator
  ClaudeRequestBuilder.swift   # + makeModelsRequest(apiKey:)
Core/Tests/ParlaCoreTests/
  SetupStatusTests.swift       # NUEVO
  APIKeyValidatorTests.swift   # NUEVO
  ClaudeRequestBuilderTests.swift  # + la petición de modelos
App/
  Assets.xcassets/             # NUEVO: AccentColor (+ AppIcon si la sonda 3 lo decide)
  Parla.icon                   # NUEVO solo si la sonda 3 elige Icon Composer
  Shortcuts.swift              # NUEVO: KeyboardShortcuts.Name (sale de SettingsView) + ParlaMode.shortcutName
  Notices.swift                # NUEVO: RuntimeNotice, Notice, NoticeList
  UI/Theme.swift               # NUEVO: acento, texto sobre acento, inglés en serif, contraste
  Setup/SetupSources.swift     # NUEVO: protocolo SetupSources, SystemSettingsPane, LiveSetupSources
  Setup/SetupMonitor.swift     # NUEVO
  Setup/SetupIssue+UI.swift    # NUEVO: títulos, motivos, botones
  Setup/SetupIssueRow.swift    # NUEVO: la fila de un pendiente
  Setup/APIKeyEntry.swift      # NUEVO: el campo de la clave, compartido
  Windows/WindowCoordinator.swift  # NUEVO
  Studio/StudioRouter.swift    # NUEVO: StudioSection, StudioRouter
  Studio/StudioView.swift      # NUEVO: barra lateral + detalle
  Studio/SetupBanner.swift     # NUEVO
  Studio/SettingsSection.swift # MOVIDO desde UI/SettingsView.swift
  Studio/HistorySection.swift  # MOVIDO desde UI/HistoryWindow.swift
  Studio/HistoryRow.swift      # NUEVO
  Studio/EnglishSide.swift     # NUEVO: dónde está el inglés, CardOriginStyle
  MenuBar/MenuBarPopover.swift # NUEVO
  MenuBar/ModeTile.swift       # NUEVO: ModeTileModel + vista
  MenuBar/NoticeRows.swift     # NUEVO: RuntimeNoticeRow
  MenuBar/LastPhraseView.swift # NUEVO
  Welcome/WelcomeFlow.swift    # NUEVO
  Welcome/WelcomeView.swift    # NUEVO
  AppState.swift               # setup, windows, blockedMode, avisos; fuera los needs*
  ParlaApp.swift               # solo MenuBarExtra (estilo ventana); fuera Settings y Window
  CaptureKind+UI.swift         # + title
  DebugHooks.swift             # abrir el menú emergente; forzar apariencia
  Preferences.swift            # + hasSeenWelcome, screenRecordingRequested
  Security/KeychainStore.swift # + hasAPIKey
  Store/StoredCard.swift       # + isFavorite
  UI/PanelView.swift           # avisos desde SetupStatus
scripts/make-icon.swift        # NUEVO: dibuja el icono
docs/superpowers/notes/2026-10-02-sondas-estudio.md  # NUEVO: resultado de las sondas
AppTests/
  ThemeTests.swift, SetupMonitorTests.swift, APIKeyEntryTests.swift, StudioRouterTests.swift,
  NoticeListTests.swift, EnglishSideTests.swift, ModeTileTests.swift, WelcomeFlowTests.swift  # NUEVOS
  PreferencesTests.swift, StoredCardMigrationTests.swift, CardStoreTests.swift, HistoryFilterTests.swift  # ampliados
```

Recuento de tests de partida: **Core 97, App 61.**

---

### Task 1: Sondas — los cinco riesgos de la §10

Cada sonda responde a una pregunta y deja su resultado en `docs/superpowers/notes/2026-10-02-sondas-estudio.md`. Ese archivo se commitea, a diferencia del ledger, que no se versiona. Quedan en el repo:
- el icono;
- `KeychainStore.hasAPIKey`;
- el script del icono;
- la nota.

El resto del código de las sondas se descarta.

**Files:**
- Create: `docs/superpowers/notes/2026-10-02-sondas-estudio.md`
- Create: `scripts/make-icon.swift`
- Create: `App/Assets.xcassets/Contents.json`, y el icono (`App/Assets.xcassets/AppIcon.appiconset/` o `App/Parla.icon`, según la sonda 3)
- Modify: `App/Security/KeychainStore.swift` (se queda `hasAPIKey`)
- Modify: `project.yml` (nombre del icono)
- Temporal (se revierte): `App/ParlaApp.swift`, `App/ProbeWindow.swift`

**Interfaces:**
- Produces: `KeychainStore.hasAPIKey: Bool`. Las Tasks 6 y 8 lo usan.
- Produces: el resultado de cada sonda, que deciden estas Tasks:
  - sonda 1 → Task 11 (`MenuBarWindow.close()`, sí o no);
  - sonda 4 → Task 10 (barra de herramientas o cabecera);
  - sonda 5 → Tasks 8 y 11 (atajo en la vista o monitor de teclado).

- [ ] **Step 1: Crear la nota de sondas**

```markdown
# Sondas de Estudio y primer uso (2026-10-02)

Spec §10. Cada sonda: pregunta, cómo se probó, resultado y decisión.

| # | Pregunta | Resultado | Decisión |
|---|----------|-----------|----------|
| 1 | ¿`dismiss()` cierra el `MenuBarExtra` de estilo ventana? | | |
| 2 | ¿Consultar si existe la clave, sin pedir sus datos, evita el diálogo del Llavero? | | |
| 3 | ¿Qué formato de icono se ve en Finder con la forma del sistema y sin placa gris? | | |
| 4 | En una `NSWindow` con `NSHostingController`, ¿se ven la barra de herramientas y la búsqueda, y la ventana queda delante al arrancar? | | |
| 5 | ¿Un botón oculto con `.keyboardShortcut(",")` responde a ⌘, en esa ventana? | | |
```

- [ ] **Step 2: Añadir `hasAPIKey` a `KeychainStore` (se queda)**

En `App/Security/KeychainStore.swift`, después de `var apiKey`:

```swift
    /// Si hay clave, sin leerla. La consulta no pide los datos del elemento,
    /// así que el Llavero no tiene que abrirlo ni pedir la contraseña aunque la
    /// app se haya vuelto a firmar. Cualquier fallo cuenta como «no hay clave».
    var hasAPIKey: Bool {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["PARLA_API_KEY"],
           !override.isEmpty { return true }
        #endif
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
```

- [ ] **Step 3: Sonda 2 — el Llavero sin diálogo**

En `App/ParlaApp.swift`, dentro del `#if DEBUG` de `init()`, añade temporalmente:

```swift
        Log.pipeline.info("sonda: hasAPIKey=\(KeychainStore.shared.hasAPIKey)")
```

Run, sin `PARLA_API_KEY` en el entorno:

```bash
log stream --predicate 'subsystem == "app.schoolaid.Parla"' --style compact > "$TMPDIR/parla-sonda2.log" &
make run
```

Espera 5 s. Haz una captura de pantalla con computer-use para ver si hay diálogo de `SecurityAgent`. Luego lee el log y para `log stream`.
Expected: no aparece ningún diálogo del Llavero y el log dice `sonda: hasAPIKey=true`, porque la clave de Edwin está en el Llavero desde compilaciones anteriores.
- Si sale el diálogo, la decisión es la alternativa del spec: recordar `hasAPIKey` en `Preferences` al guardar o borrar la clave. Ledger: `Task 1: Ruling: …`, y la Task 6 lee la preferencia en lugar del Llavero.

Anota el resultado en la fila 2.

- [ ] **Step 4: Sonda 1 — cerrar el menú emergente**

En `App/ParlaApp.swift`, temporalmente:
- sustituye `MenuBarView(state: state)` por `ProbePopover()`;
- añade `.menuBarExtraStyle(.window)` a la escena `MenuBarExtra`;
- añade al final del archivo:

```swift
private struct ProbePopover: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button("Cerrar (sonda)") {
            dismiss()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                let visibles = NSApp.windows.filter(\.isVisible)
                    .map { "\($0.className) nivel=\($0.level.rawValue)" }
                Log.pipeline.info("sonda: visibles tras dismiss: \(visibles.joined(separator: " | "))")
            }
        }
        .padding()
        .frame(width: 240)
    }
}
```

`make run`. Con computer-use, pide acceso al menú de la barra, haz clic en el icono de Parla, captura de pantalla, clic en «Cerrar (sonda)» y otra captura. Lee el log.
Expected: la ventana del menú emergente desaparece, y en el log no queda ninguna ventana visible con `MenuBarExtra` en el nombre de clase.
- Si queda visible, la decisión es que la Task 11 use `MenuBarWindow.close()`. Anota el nombre de clase exacto que salió en el log, porque la Task 11 filtra por él.

Anota el resultado en la fila 1.

- [ ] **Step 5: Sondas 4 y 5 — ventana AppKit con SwiftUI, y ⌘,**

Crea `App/ProbeWindow.swift`:

```swift
#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum ProbeWindow {
    static var window: NSWindow?

    static func show() {
        let controller = NSHostingController(rootView: ProbeView())
        controller.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct ProbeView: View {
    @State private var section: String? = "Historial"
    @State private var filter = 0
    @State private var search = ""
    @State private var presses = 0

    var body: some View {
        NavigationSplitView {
            List(["Historial", "Ajustes"], id: \.self, selection: $section) { Text($0) }
        } detail: {
            VStack(spacing: 12) {
                Text("Sección: \(section ?? "-")")
                Text("⌘, pulsado \(presses) veces")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .searchable(text: $search, prompt: "Buscar en tus frases")
            .toolbar {
                Picker("Mostrar", selection: $filter) {
                    Text("Todo").tag(0)
                    Text("Voz").tag(1)
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle("Sonda")
        .frame(minWidth: 760, minHeight: 520)
        .background {
            Button("Ajustes") { section = "Ajustes"; presses += 1 }
                .keyboardShortcut(",", modifiers: .command)
                .hidden()
        }
    }
}
#endif
```

En `App/ParlaApp.swift`, dentro del `#if DEBUG` de `init()`, añade temporalmente:

```swift
        if ProcessInfo.processInfo.environment["PARLA_PROBE_WINDOW"] == "1" {
            _ = NotificationCenter.default.addObserver(
                forName: NSApplication.didFinishLaunchingNotification,
                object: nil, queue: .main
            ) { _ in MainActor.assumeIsolated { ProbeWindow.show() } }
        }
```

Run: `make build`. Después lanza el binario con la variable:

```bash
APP="$(xcodebuild -project Parla.xcodeproj -scheme Parla -configuration Debug -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2}')/Parla.app"
pkill -f 'Parla.app/Contents/MacOS/Parla'; PARLA_PROBE_WINDOW=1 "$APP/Contents/MacOS/Parla" &
```

Espera 3 s y haz una captura de pantalla.
Expected (sonda 4): la ventana «Sonda» está delante de las demás, con el selector «Todo | Voz» y el campo de búsqueda en la barra de herramientas.
- Si la barra no aparece, la decisión es que la Task 10 use la cabecera dentro del contenido.

Con computer-use, haz clic en la ventana y pulsa `cmd+,`. Haz otra captura.
Expected (sonda 5): «⌘, pulsado 1 veces» y «Sección: Ajustes».
- Si no responde, la decisión es que las Tasks 8 y 11 usen el monitor local de teclado.

Anota las filas 4 y 5. Para la app con `pkill -f 'Parla.app/Contents/MacOS/Parla'`.

- [ ] **Step 6: Revertir el código de sonda**

```bash
git checkout -- App/ParlaApp.swift
rm App/ProbeWindow.swift
git status --short
```

Expected: solo quedan `App/Security/KeychainStore.swift` modificado y la nota sin seguimiento.

- [ ] **Step 7: Sonda 3 — el script del icono**

Crea `scripts/make-icon.swift`:

```swift
#!/usr/bin/env swift
// Dibuja el icono de Parla: «Aa» en serif, crema sobre terracota.
//
// Uso:
//   swift scripts/make-icon.swift appiconset <carpeta .appiconset>   # a sangre completa
//   swift scripts/make-icon.swift rounded <carpeta .appiconset>      # forma clásica, con margen
//   swift scripts/make-icon.swift glyph <archivo .png>               # solo «Aa», para Icon Composer
import AppKit

let terracota = NSColor(srgbRed: 0xD8 / 255, green: 0x5A / 255, blue: 0x30 / 255, alpha: 1)
let crema = NSColor(srgbRed: 0xFA / 255, green: 0xEC / 255, blue: 0xE7 / 255, alpha: 1)

enum Style { case fullBleed, rounded, glyph }

func render(pixels: Int, style: Style) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let side = CGFloat(pixels)
    switch style {
    case .fullBleed:
        terracota.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
    case .rounded:
        // La rejilla clásica de macOS: 824 de 1024, radio 185.
        let body = side * 824 / 1024
        let inset = (side - body) / 2
        terracota.setFill()
        NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: body, height: body),
                     xRadius: side * 185 / 1024, yRadius: side * 185 / 1024).fill()
    case .glyph:
        break
    }
    let size = side * (style == .rounded ? 0.38 : 0.46)
    let base = NSFont.systemFont(ofSize: size, weight: .medium)
    let font = base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    let text = NSAttributedString(string: "Aa", attributes: [.font: font, .foregroundColor: crema])
    let bounds = text.size()
    text.draw(at: NSPoint(x: (side - bounds.width) / 2, y: (side - bounds.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("uso: make-icon.swift appiconset|rounded|glyph <destino>")
    exit(2)
}
let destination = URL(fileURLWithPath: arguments[2])

if arguments[1] == "glyph" {
    try render(pixels: 1024, style: .glyph).write(to: destination)
    exit(0)
}

let style: Style = arguments[1] == "rounded" ? .rounded : .fullBleed
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    try render(pixels: pixels, style: style)
        .write(to: destination.appending(path: "icon_\(pixels).png"))
}
// Cada tamaño en puntos, a 1x y a 2x.
let slots: [(points: Int, scale: Int)] = [16, 32, 128, 256, 512].flatMap { [($0, 1), ($0, 2)] }
let images = slots.map { slot in
    """
        { "filename" : "icon_\(slot.points * slot.scale).png", "idiom" : "mac", \
    "scale" : "\(slot.scale)x", "size" : "\(slot.points)x\(slot.points)" }
    """
}
let contents = """
{
  "images" : [
\(images.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try contents.write(to: destination.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
```

Crea `App/Assets.xcassets/Contents.json`:

```json
{
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 8: Sonda 3 — probar el appiconset a sangre completa**

Orden invertido respecto al spec §10.3, que proponía probar primero el `.icon`. Este camino se genera entero con un script y se puede reproducir; el `.icon` necesita manejar Icon Composer a mano. El criterio de aceptación es el mismo. Ledger: `Task 1: Ruling: appiconset antes que .icon — reproducible por script; mismo criterio — si falla, se prueba el .icon igualmente`.

```bash
swift scripts/make-icon.swift appiconset App/Assets.xcassets/AppIcon.appiconset
```

En `project.yml`, en `targets.Parla.settings.base`, añade:

```yaml
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
```

Run:

```bash
make install
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' /Applications/Parla.app/Contents/Info.plist
qlmanage -t -s 512 -o "$TMPDIR" /Applications/Parla.app >/dev/null 2>&1; ls "$TMPDIR"/Parla.app.png
```

Expected: imprime `AppIcon`, y la miniatura existe. Ábrela con Read para verla.
- **Pasa** si el icono tiene la forma redondeada del sistema, sin esquinas cuadradas y sin placa gris alrededor. Confírmalo también en Finder: ventana de `/Applications`, captura y zoom sobre Parla.
- **Si sale cuadrado**, regenera con la forma clásica y repite la comprobación:
  ```bash
  rm -rf App/Assets.xcassets/AppIcon.appiconset
  swift scripts/make-icon.swift rounded App/Assets.xcassets/AppIcon.appiconset
  ```
- **Si sale con placa gris** (con cualquiera de las dos variantes), sigue al Step 9.

- [ ] **Step 9: Sonda 3 — `.icon` de Icon Composer (solo si el Step 8 falló)**

```bash
swift scripts/make-icon.swift glyph "$TMPDIR/parla-glyph.png"
open /Applications/Xcode.app/Contents/Applications/Icon\ Composer.app
```

Con computer-use (pide acceso a «Icon Composer»), en un documento nuevo:
- fondo sólido `#D85A30`;
- arrastra `parla-glyph.png` como capa;
- guárdalo como `App/Parla.icon`.

Si no se puede manejar la app, pide a Edwin estos tres pasos.

Después:
- borra `App/Assets.xcassets/AppIcon.appiconset`;
- cambia el ajuste a `ASSETCATALOG_COMPILER_APPICON_NAME: Parla`;
- añade bajo `options:` de `project.yml`:

```yaml
  # Un .icon es una carpeta, pero Xcode lo trata como un archivo que compila actool.
  fileTypes:
    icon:
      file: true
      buildPhase: resources
```

Repite los comandos del Step 8: ahora `CFBundleIconName` debe ser `Parla`. Expected: la misma comprobación visual que en el Step 8.
- Si ninguna variante pasa, quédate con la que mejor se vea. Ledger: `Task 1: Ruling: icono … — … — se rehace con Icon Composer a mano`.

Anota la fila 3.

- [ ] **Step 10: Commit**

```bash
git add docs/superpowers/notes/2026-10-02-sondas-estudio.md scripts/make-icon.swift \
  App/Assets.xcassets App/Security/KeychainStore.swift project.yml
git add App/Parla.icon 2>/dev/null || true
git commit -m "feat: icono de Parla y sondas de Estudio

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Identidad — acento, tema y símbolo de la barra

**Files:**
- Create: `App/Assets.xcassets/AccentColor.colorset/Contents.json`
- Create: `App/UI/Theme.swift`
- Create: `AppTests/ThemeTests.swift`
- Modify: `project.yml` (acento global)
- Modify: `App/ParlaApp.swift:40-43` (símbolo)

**Interfaces:**
- Produces: `Theme.accent: Color`, `Theme.onAccent: Color`, `Theme.english(_ style: Font.TextStyle) -> Font`.
- Produces: `Theme.RGB(hex:)`, `Theme.Palette.{accentLight, accentDark, onAccentLight, onAccentDark, iconBackground, white}` y `Theme.contrastRatio(_:_:) -> Double`.

- [ ] **Step 1: Escribir los tests**

`AppTests/ThemeTests.swift`:

```swift
import Testing
import AppKit
@testable import Parla

@Test func elBlancoSeLeeSobreElAcentoClaro() {
    #expect(Theme.contrastRatio(Theme.Palette.accentLight, Theme.Palette.onAccentLight) >= 4.5)
}

@Test func elTextoOscuroSeLeeSobreElAcentoOscuro() {
    #expect(Theme.contrastRatio(Theme.Palette.accentDark, Theme.Palette.onAccentDark) >= 4.5)
}

@Test func elTerracotaDelIconoNoServiriaParaTexto() {
    // Por esto el acento de la interfaz no es el del icono.
    #expect(Theme.contrastRatio(Theme.Palette.iconBackground, Theme.Palette.white) < 4.5)
}

@Test func elContrasteDeNegroSobreBlancoEsVeintiuno() {
    let ratio = Theme.contrastRatio(Theme.RGB(hex: 0x000000), Theme.RGB(hex: 0xFFFFFF))
    #expect(abs(ratio - 21) < 0.01)
}

@Test func elAcentoDelCatalogoEsElDeLaPaleta() throws {
    // Si el catálogo y el código divergieran, los tests de contraste mentirían.
    let named = try #require(NSColor(named: "AccentColor"))
    var light: NSColor?
    NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
        light = named.usingColorSpace(.sRGB)
    }
    let color = try #require(light)
    #expect(Int((color.redComponent * 255).rounded()) == 0xB8)
    #expect(Int((color.greenComponent * 255).rounded()) == 0x4A)
    #expect(Int((color.blueComponent * 255).rounded()) == 0x26)
}
```

- [ ] **Step 2: Comprobar que fallan**

Run: `make test-app 2>&1 | tail -20`
Expected: no compila, `cannot find 'Theme' in scope`.

- [ ] **Step 3: Implementar**

`App/Assets.xcassets/AccentColor.colorset/Contents.json`:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0x26", "green" : "0x4A", "red" : "0xB8" }
      },
      "idiom" : "universal"
    },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0x7B", "green" : "0x99", "red" : "0xF0" }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

En `project.yml`, en `targets.Parla.settings.base`:

```yaml
        # El acento del catálogo tiñe controles, selección y `.tint` en toda la app.
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
```

`App/UI/Theme.swift`:

```swift
import AppKit
import SwiftUI

/// La identidad de Parla en un solo sitio: el acento, el texto que va encima y
/// la letra del inglés. El panel y las tarjetas la reutilizarán cuando se
/// rediseñen.
enum Theme {

    /// Un color sRGB, para poder calcular contrastes en los tests.
    struct RGB: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double

        init(hex: UInt32) {
            red = Double((hex >> 16) & 0xFF) / 255
            green = Double((hex >> 8) & 0xFF) / 255
            blue = Double(hex & 0xFF) / 255
        }

        /// Luminancia relativa, como la define WCAG.
        var luminance: Double {
            func linear(_ channel: Double) -> Double {
                channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }

        var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    }

    enum Palette {
        /// Igual que `AccentColor` en el catálogo; un test lo vigila.
        static let accentLight = RGB(hex: 0xB84A26)
        static let accentDark = RGB(hex: 0xF0997B)
        static let onAccentLight = RGB(hex: 0xFFFFFF)
        static let onAccentDark = RGB(hex: 0x4A1B0C)
        /// Más vivo que el acento: el icono no lleva texto pequeño encima.
        static let iconBackground = RGB(hex: 0xD85A30)
        static let white = RGB(hex: 0xFFFFFF)
    }

    /// El acento del catálogo, el mismo que tiñe los controles.
    static let accent = Color.accentColor

    /// Texto e iconos sobre un relleno de acento.
    static let onAccent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? Palette.onAccentDark.nsColor
            : Palette.onAccentLight.nsColor
    })

    /// El inglés, que es lo que se estudia, va en serif.
    static func english(_ style: Font.TextStyle) -> Font {
        .system(style, design: .serif)
    }

    static func contrastRatio(_ first: RGB, _ second: RGB) -> Double {
        let lighter = max(first.luminance, second.luminance)
        let darker = min(first.luminance, second.luminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}
```

En `App/ParlaApp.swift`, el `label:` de `MenuBarExtra` pasa a:

```swift
        } label: {
            // Un solo símbolo: qué modo está activo se ve en el menú emergente.
            Image(systemName: state.isListening || state.isSubtitling
                  ? "character.bubble.fill" : "character.bubble")
        }
```

- [ ] **Step 4: Comprobar que pasan**

Run: `make test-app 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, 66 tests (61 + 5).

- [ ] **Step 5: Commit**

```bash
git add App/Assets.xcassets/AccentColor.colorset App/UI/Theme.swift AppTests/ThemeTests.swift project.yml App/ParlaApp.swift
git commit -m "feat: acento terracota, inglés en serif y un solo símbolo en la barra

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `SetupStatus` (Core)

**Files:**
- Create: `Core/Sources/ParlaCore/SetupStatus.swift`
- Create: `Core/Tests/ParlaCoreTests/SetupStatusTests.swift`

**Interfaces:**
- Produces:

```swift
public enum ParlaMode: Sendable, CaseIterable, Hashable { case voice, capture, subtitles }
public enum PermissionState: Sendable, Equatable { case granted, notDetermined, denied }
public enum LanguageState: Sendable, Equatable { case unknown, ready, needsDownload, unsupported }
public struct SetupInputs: Sendable, Equatable {
    public init(hasAPIKey: Bool, microphone: PermissionState, screenRecordingGranted: Bool,
                screenRecordingRequested: Bool, languages: LanguageState)
}
public enum SetupItem: Sendable, CaseIterable, Hashable { case apiKey, microphone, screenRecording, languages }
public enum SetupFix: Sendable, Equatable {
    case enterAPIKey, requestMicrophone, openMicrophoneSettings, requestScreenRecording,
         openScreenRecordingSettingsOrRelaunch, openLanguageSettings, unavailable
    public var isPermissionRequest: Bool
}
public struct SetupIssue: Sendable, Equatable, Identifiable { public let item: SetupItem; public let fix: SetupFix; public var id: SetupItem }
public struct SetupStatus: Sendable, Equatable {
    public init(_ inputs: SetupInputs)
    public let issues: [SetupIssue]
    public var isComplete: Bool
    public func blockers(for mode: ParlaMode) -> [SetupIssue]
    public func startBlockers(for mode: ParlaMode) -> [SetupIssue]
}
```

Ruling, al empezar esta task. El spec llama `none` al arreglo que no existe. Aquí se llama `unavailable`, porque `.none` choca con `Optional.none` en cualquier contexto opcional. Ledger: `Task 3: Ruling: SetupFix.none → .unavailable — evita la ambigüedad con Optional.none — un renombrado`.

- [ ] **Step 1: Escribir los tests**

`Core/Tests/ParlaCoreTests/SetupStatusTests.swift`:

```swift
import Testing
@testable import ParlaCore

private func inputs(hasAPIKey: Bool = true,
                    microphone: PermissionState = .granted,
                    screen: Bool = true,
                    requested: Bool = false,
                    languages: LanguageState = .ready) -> SetupInputs {
    SetupInputs(hasAPIKey: hasAPIKey, microphone: microphone, screenRecordingGranted: screen,
                screenRecordingRequested: requested, languages: languages)
}

@Test func conTodoListoNoHayPendientes() {
    let status = SetupStatus(inputs())
    #expect(status.issues.isEmpty)
    #expect(status.isComplete)
}

@Test func sinClaveSeOfreceEscribirla() {
    #expect(SetupStatus(inputs(hasAPIKey: false)).issues
            == [SetupIssue(item: .apiKey, fix: .enterAPIKey)])
}

@Test func elMicrofonoSinDecidirSePide() {
    #expect(SetupStatus(inputs(microphone: .notDetermined)).issues
            == [SetupIssue(item: .microphone, fix: .requestMicrophone)])
}

@Test func elMicrofonoDenegadoLlevaAAjustes() {
    #expect(SetupStatus(inputs(microphone: .denied)).issues
            == [SetupIssue(item: .microphone, fix: .openMicrophoneSettings)])
}

@Test func laPantallaNuncaPedidaSePide() {
    #expect(SetupStatus(inputs(screen: false, requested: false)).issues
            == [SetupIssue(item: .screenRecording, fix: .requestScreenRecording)])
}

@Test func laPantallaYaPedidaLlevaAAjustesOAReabrir() {
    // macOS solo enseña su diálogo una vez y no aplica el permiso hasta reabrir.
    #expect(SetupStatus(inputs(screen: false, requested: true)).issues
            == [SetupIssue(item: .screenRecording, fix: .openScreenRecordingSettingsOrRelaunch)])
}

@Test func losIdiomasSinDescargarLlevanAIdiomaYRegion() {
    #expect(SetupStatus(inputs(languages: .needsDownload)).issues
            == [SetupIssue(item: .languages, fix: .openLanguageSettings)])
}

@Test func unMacSinTraduccionSoloLoExplica() {
    #expect(SetupStatus(inputs(languages: .unsupported)).issues
            == [SetupIssue(item: .languages, fix: .unavailable)])
}

@Test func losIdiomasTodaviaSinComprobarNoSonPendientes() {
    // Aún no se sabe: no se alarma.
    #expect(SetupStatus(inputs(languages: .unknown)).isComplete)
}

@Test func losPendientesSalenSiempreEnElMismoOrden() {
    let status = SetupStatus(inputs(hasAPIKey: false, microphone: .denied, screen: false,
                                    languages: .needsDownload))
    #expect(status.issues.map(\.item) == [.apiKey, .microphone, .screenRecording, .languages])
}

@Test func cadaModoVeSoloLoQueNecesita() {
    let status = SetupStatus(inputs(hasAPIKey: false, microphone: .denied, screen: false,
                                    requested: true, languages: .needsDownload))
    #expect(status.blockers(for: .voice).map(\.item) == [.apiKey, .microphone])
    #expect(status.blockers(for: .capture).map(\.item) == [.apiKey, .screenRecording])
    #expect(status.blockers(for: .subtitles).map(\.item) == [.screenRecording, .languages])
}

@Test func pedirUnPermisoNoImpideArrancar() {
    // El propio arranque lanza el diálogo del sistema, como hoy.
    let status = SetupStatus(inputs(microphone: .notDetermined, screen: false, requested: false))
    #expect(status.blockers(for: .voice).map(\.item) == [.microphone])
    #expect(status.startBlockers(for: .voice).isEmpty)
    #expect(status.startBlockers(for: .capture).isEmpty)
    #expect(status.startBlockers(for: .subtitles).isEmpty)
}

@Test func unPermisoDenegadoSiImpideArrancar() {
    let status = SetupStatus(inputs(microphone: .denied, screen: false, requested: true))
    #expect(status.startBlockers(for: .voice).map(\.item) == [.microphone])
    #expect(status.startBlockers(for: .capture).map(\.item) == [.screenRecording])
}
```

- [ ] **Step 2: Comprobar que fallan**

Run: `make test 2>&1 | tail -15`
Expected: no compila, `cannot find 'SetupInputs' in scope`.

- [ ] **Step 3: Implementar**

`Core/Sources/ParlaCore/SetupStatus.swift`:

```swift
import Foundation

/// Los tres modos de Parla, para preguntar qué necesita cada uno.
public enum ParlaMode: Sendable, CaseIterable, Hashable {
    case voice, capture, subtitles
}

public enum PermissionState: Sendable, Equatable {
    case granted, notDetermined, denied
}

public enum LanguageState: Sendable, Equatable {
    /// Todavía no se ha preguntado: la respuesta es asíncrona.
    case unknown
    case ready, needsDownload, unsupported
}

/// Lo que la app sabe del sistema. Lo rellena `SetupMonitor`; aquí no se toca
/// nada del sistema, para poder probarlo.
public struct SetupInputs: Sendable, Equatable {
    public var hasAPIKey: Bool
    public var microphone: PermissionState
    public var screenRecordingGranted: Bool
    /// Si ya se lanzó alguna vez el diálogo del sistema para la pantalla.
    public var screenRecordingRequested: Bool
    public var languages: LanguageState

    public init(hasAPIKey: Bool, microphone: PermissionState, screenRecordingGranted: Bool,
                screenRecordingRequested: Bool, languages: LanguageState) {
        self.hasAPIKey = hasAPIKey
        self.microphone = microphone
        self.screenRecordingGranted = screenRecordingGranted
        self.screenRecordingRequested = screenRecordingRequested
        self.languages = languages
    }
}

/// Lo que se puede tener pendiente, en el orden en que se enseña.
public enum SetupItem: Sendable, CaseIterable, Hashable {
    case apiKey, microphone, screenRecording, languages

    /// Los modos que no funcionan sin esto.
    var modes: Set<ParlaMode> {
        switch self {
        case .apiKey:          [.voice, .capture]
        case .microphone:      [.voice]
        case .screenRecording: [.capture, .subtitles]
        case .languages:       [.subtitles]
        }
    }
}

public enum SetupFix: Sendable, Equatable {
    case enterAPIKey
    case requestMicrophone
    case openMicrophoneSettings
    case requestScreenRecording
    /// Abrir Ajustes del Sistema y, si ya se concedió, reabrir Parla.
    case openScreenRecordingSettingsOrRelaunch
    case openLanguageSettings
    /// Este Mac no puede: solo se explica.
    case unavailable

    /// Pedir un permiso no impide arrancar: el propio arranque lanza el
    /// diálogo del sistema, que es justo cuando su motivo es evidente.
    public var isPermissionRequest: Bool {
        self == .requestMicrophone || self == .requestScreenRecording
    }
}

public struct SetupIssue: Sendable, Equatable, Identifiable {
    public let item: SetupItem
    public let fix: SetupFix

    public var id: SetupItem { item }

    public init(item: SetupItem, fix: SetupFix) {
        self.item = item
        self.fix = fix
    }
}

/// Qué falta para que cada modo funcione. La única fuente de esa respuesta: la
/// bienvenida, el menú emergente, Estudio y el panel la leen de aquí.
public struct SetupStatus: Sendable, Equatable {
    public let issues: [SetupIssue]

    public init(_ inputs: SetupInputs) {
        var issues: [SetupIssue] = []
        if !inputs.hasAPIKey {
            issues.append(SetupIssue(item: .apiKey, fix: .enterAPIKey))
        }
        switch inputs.microphone {
        case .granted: break
        case .notDetermined: issues.append(SetupIssue(item: .microphone, fix: .requestMicrophone))
        case .denied: issues.append(SetupIssue(item: .microphone, fix: .openMicrophoneSettings))
        }
        if !inputs.screenRecordingGranted {
            issues.append(SetupIssue(item: .screenRecording,
                                     fix: inputs.screenRecordingRequested
                                         ? .openScreenRecordingSettingsOrRelaunch
                                         : .requestScreenRecording))
        }
        switch inputs.languages {
        case .unknown, .ready: break
        case .needsDownload: issues.append(SetupIssue(item: .languages, fix: .openLanguageSettings))
        case .unsupported: issues.append(SetupIssue(item: .languages, fix: .unavailable))
        }
        self.issues = issues
    }

    public var isComplete: Bool { issues.isEmpty }

    /// Todos los pendientes que afectan al modo, para mostrarlos.
    public func blockers(for mode: ParlaMode) -> [SetupIssue] {
        issues.filter { $0.item.modes.contains(mode) }
    }

    /// Los que impiden arrancarlo: `blockers(for:)` sin los de pedir permiso.
    public func startBlockers(for mode: ParlaMode) -> [SetupIssue] {
        blockers(for: mode).filter { !$0.fix.isPermissionRequest }
    }
}
```

- [ ] **Step 4: Comprobar que pasan**

Run: `make test 2>&1 | tail -15`
Expected: `Test run with 110 tests passed` (97 + 13).

- [ ] **Step 5: Commit**

```bash
git add Core/Sources/ParlaCore/SetupStatus.swift Core/Tests/ParlaCoreTests/SetupStatusTests.swift
git commit -m "feat(core): SetupStatus dice qué falta y qué modos bloquea

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `APIKeyValidator` y la petición de modelos (Core)

**Files:**
- Create: `Core/Sources/ParlaCore/APIKeyValidator.swift`
- Create: `Core/Tests/ParlaCoreTests/APIKeyValidatorTests.swift`
- Modify: `Core/Sources/ParlaCore/ClaudeRequestBuilder.swift` (después de `private static let endpoint`)
- Modify: `Core/Tests/ParlaCoreTests/ClaudeRequestBuilderTests.swift` (un test al final)

**Interfaces:**
- Consumes: `HTTPStreamer`, `URLSessionStreamer` (ya existen).
- Produces:

```swift
extension ClaudeRequestBuilder { public static func makeModelsRequest(apiKey: String) -> URLRequest }
public enum KeyCheck: Sendable, Equatable { case valid, invalid, unverified; public var shouldSave: Bool }
public struct APIKeyValidator: Sendable {
    public init(streamer: any HTTPStreamer = URLSessionStreamer())
    public static func normalize(_ key: String) -> String
    public func check(_ key: String) async -> KeyCheck
}
```

- [ ] **Step 1: Escribir los tests**

Al final de `Core/Tests/ParlaCoreTests/ClaudeRequestBuilderTests.swift`:

```swift
@Test func laPeticionDeModelosEsUnGETSinCosteConTiempoLimite() {
    let request = ClaudeRequestBuilder.makeModelsRequest(apiKey: "sk-test")
    #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/models?limit=1")
    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
    #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    #expect(request.timeoutInterval == 10)
    #expect(request.httpBody == nil)
}
```

`Core/Tests/ParlaCoreTests/APIKeyValidatorTests.swift`:

```swift
import Testing
import Foundation
@testable import ParlaCore

@Test func unaClaveAceptadaEsValida() async {
    #expect(await APIKeyValidator(streamer: FakeStreamer(statusCode: 200)).check("sk-ant-1") == .valid)
}

@Test func unaClaveRechazadaEsInvalida() async {
    for status in [401, 403] {
        #expect(await APIKeyValidator(streamer: FakeStreamer(statusCode: status)).check("sk-ant-1")
                == .invalid)
    }
}

@Test func otrosErroresDelServidorNoDicenNadaDeLaClave() async {
    for status in [429, 500, 529] {
        #expect(await APIKeyValidator(streamer: FakeStreamer(statusCode: status)).check("sk-ant-1")
                == .unverified)
    }
}

@Test func sinRedLaClaveQuedaSinComprobar() async {
    let offline = FakeStreamer(failWith: URLError(.notConnectedToInternet))
    #expect(await APIKeyValidator(streamer: offline).check("sk-ant-1") == .unverified)
}

@Test func elTiempoAgotadoTambienQuedaSinComprobar() async {
    let slow = FakeStreamer(failWith: URLError(.timedOut))
    #expect(await APIKeyValidator(streamer: slow).check("sk-ant-1") == .unverified)
}

@Test func seMandaLaClaveSinEspaciosNiSaltos() async {
    let streamer = ScriptedStreamer { _ in (200, []) }
    _ = await APIKeyValidator(streamer: streamer).check("  sk-ant-abc\n")
    #expect(streamer.requests.first?.value(forHTTPHeaderField: "x-api-key") == "sk-ant-abc")
}

@Test func unaClaveVaciaEsInvalidaSinTocarLaRed() async {
    let streamer = ScriptedStreamer { _ in (200, []) }
    #expect(await APIKeyValidator(streamer: streamer).check(" \n") == .invalid)
    #expect(streamer.requests.isEmpty)
}

@Test func soloUnaClaveRechazadaNoSeGuarda() {
    #expect(KeyCheck.valid.shouldSave)
    #expect(KeyCheck.unverified.shouldSave)
    #expect(!KeyCheck.invalid.shouldSave)
}
```

- [ ] **Step 2: Comprobar que fallan**

Run: `make test 2>&1 | tail -15`
Expected: no compila, `type 'ClaudeRequestBuilder' has no member 'makeModelsRequest'` y `cannot find 'APIKeyValidator' in scope`.

- [ ] **Step 3: Implementar**

En `Core/Sources/ParlaCore/ClaudeRequestBuilder.swift`, justo después de `private static let endpoint = …`:

```swift
    private static let modelsEndpoint = URL(string: "https://api.anthropic.com/v1/models?limit=1")!

    /// La petición más barata que exige una clave válida: la lista de modelos no
    /// consume tokens. Diez segundos bastan para saber si hay red.
    public static func makeModelsRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: modelsEndpoint, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        return request
    }
```

`Core/Sources/ParlaCore/APIKeyValidator.swift`:

```swift
import Foundation

public enum KeyCheck: Sendable, Equatable {
    case valid
    /// La API la rechazó (401 o 403).
    case invalid
    /// No se pudo saber: sin red, tiempo agotado u otro error del servidor.
    case unverified

    /// Se guarda salvo que la API la haya rechazado: perder una clave buena
    /// por un wifi caído sería peor que guardar una sin comprobar.
    public var shouldSave: Bool { self != .invalid }
}

/// Comprueba una clave antes de guardarla, para que una clave mala se note al
/// escribirla y no en la primera traducción.
public struct APIKeyValidator: Sendable {
    private let streamer: any HTTPStreamer

    public init(streamer: any HTTPStreamer = URLSessionStreamer()) {
        self.streamer = streamer
    }

    /// Al pegar es fácil arrastrar un espacio o un salto de línea.
    public static func normalize(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func check(_ key: String) async -> KeyCheck {
        let key = Self.normalize(key)
        guard !key.isEmpty else { return .invalid }
        do {
            let response = try await streamer.stream(ClaudeRequestBuilder.makeModelsRequest(apiKey: key))
            switch response.statusCode {
            case 200: return .valid
            case 401, 403: return .invalid
            default: return .unverified
            }
        } catch {
            return .unverified
        }
    }
}
```

- [ ] **Step 4: Comprobar que pasan**

Run: `make test 2>&1 | tail -15`
Expected: `Test run with 119 tests passed` (110 + 9).

- [ ] **Step 5: Commit**

```bash
git add Core/Sources/ParlaCore/APIKeyValidator.swift Core/Sources/ParlaCore/ClaudeRequestBuilder.swift \
  Core/Tests/ParlaCoreTests/APIKeyValidatorTests.swift Core/Tests/ParlaCoreTests/ClaudeRequestBuilderTests.swift
git commit -m "feat(core): comprobar la clave con la lista de modelos

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Datos — favoritas y preferencias nuevas

**Files:**
- Modify: `App/Store/StoredCard.swift` (después de `var kind`)
- Modify: `App/Preferences.swift`
- Modify: `AppTests/PreferencesTests.swift`, `AppTests/StoredCardMigrationTests.swift:66-72`, `AppTests/CardStoreTests.swift`

**Interfaces:**
- Produces:
  - `StoredCard.isFavorite: Bool`, con `false` por defecto;
  - `Preferences.hasSeenWelcome: Bool`;
  - `Preferences.screenRecordingRequested: Bool`.

- [ ] **Step 1: Escribir los tests**

Al final de `AppTests/PreferencesTests.swift`:

```swift
@Test func laBienvenidaNoSeHaVistoAlEmpezar() {
    withScratchDefaults { defaults in
        #expect(!Preferences(defaults: defaults).hasSeenWelcome)
    }
}

@Test func haberVistoLaBienvenidaSobreviveAReabrir() {
    withScratchDefaults { defaults in
        Preferences(defaults: defaults).hasSeenWelcome = true
        #expect(Preferences(defaults: defaults).hasSeenWelcome)
    }
}

@Test func laPantallaNoSeHaPedidoAlEmpezar() {
    withScratchDefaults { defaults in
        #expect(!Preferences(defaults: defaults).screenRecordingRequested)
    }
}

@Test func haberPedidoLaPantallaSobreviveAReabrir() {
    // macOS solo enseña su diálogo una vez por app: volver a pedirlo no hace nada.
    withScratchDefaults { defaults in
        Preferences(defaults: defaults).screenRecordingRequested = true
        #expect(Preferences(defaults: defaults).screenRecordingRequested)
    }
}
```

En `AppTests/StoredCardMigrationTests.swift`, después de `#expect(stored.first?.kind == nil)`:

```swift
    #expect(stored.first?.isFavorite == false)
```

Al final de `AppTests/CardStoreTests.swift`:

```swift
@Test func borrarUnaTarjetaBorraSuVocabulario() throws {
    let container = try ModelContainer(
        for: StoredCard.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    context.insert(StoredCard(id: UUID(), source: "me da igual", result: "I don't mind.",
                              why: [], createdAt: Date(),
                              vocab: [StoredVocab(term: "mind", meaning: "importar")]))
    try context.save()

    let card = try #require(try context.fetch(FetchDescriptor<StoredCard>()).first)
    context.delete(card)
    try context.save()

    #expect(try context.fetch(FetchDescriptor<StoredCard>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<StoredVocab>()).isEmpty)
}

@Test func marcarFavoritaSobreviveAGuardar() throws {
    let container = try ModelContainer(
        for: StoredCard.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let card = StoredCard(id: UUID(), source: "hola", result: "hello", why: [],
                          createdAt: Date(), vocab: [])
    context.insert(card)
    #expect(!card.isFavorite)
    card.isFavorite = true
    try context.save()

    let fresh = ModelContext(container)
    #expect(try fresh.fetch(FetchDescriptor<StoredCard>()).first?.isFavorite == true)
}
```

- [ ] **Step 2: Comprobar que fallan**

Run: `make test-app 2>&1 | tail -20`
Expected: no compila, `value of type 'Preferences' has no member 'hasSeenWelcome'` y `value of type 'StoredCard' has no member 'isFavorite'`.

- [ ] **Step 3: Implementar**

En `App/Store/StoredCard.swift`, después de `var kind: String?`:

```swift
    /// Marcada con la estrella del historial. Con valor por defecto para que
    /// las filas antiguas migren solas, como `origin`.
    var isFavorite: Bool = false
```

En `App/Preferences.swift`, en `enum Key` añade:

```swift
        static let hasSeenWelcome = "hasSeenWelcome"
        static let screenRecordingRequested = "screenRecordingRequested"
```

y, al final del struct:

```swift
    /// La bienvenida sale sola solo la primera vez. Cerrarla en cualquier paso
    /// cuenta como vista.
    var hasSeenWelcome: Bool {
        get { defaults.bool(forKey: Key.hasSeenWelcome) }
        nonmutating set { defaults.set(newValue, forKey: Key.hasSeenWelcome) }
    }

    /// macOS enseña el diálogo de Grabación de pantalla una sola vez por app.
    /// Recordarlo entre arranques decide si se ofrece «Permitir» o Ajustes del
    /// Sistema.
    var screenRecordingRequested: Bool {
        get { defaults.bool(forKey: Key.screenRecordingRequested) }
        nonmutating set { defaults.set(newValue, forKey: Key.screenRecordingRequested) }
    }
```

- [ ] **Step 4: Comprobar que pasan**

Run: `make test-app 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, 72 tests (66 + 6). `borrarUnaTarjetaBorraSuVocabulario` caracteriza la cascada que ya existía. El fallo del Step 2 lo dieron los otros cinco.

- [ ] **Step 5: Commit**

```bash
git add App/Store/StoredCard.swift App/Preferences.swift AppTests/PreferencesTests.swift \
  AppTests/StoredCardMigrationTests.swift AppTests/CardStoreTests.swift
git commit -m "feat: favoritas en el historial y preferencias de bienvenida y pantalla

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `SetupMonitor`, sus fuentes y la fila de un pendiente

**Files:**
- Create: `App/Setup/SetupSources.swift`
- Create: `App/Setup/SetupMonitor.swift`
- Create: `App/Setup/SetupIssue+UI.swift`
- Create: `App/Setup/SetupIssueRow.swift`
- Create: `AppTests/SetupMonitorTests.swift`
- Modify: `App/AppState.swift` (propiedad `setup` e `init()`)

**Interfaces:**
- Consumes:
  - de la Task 3, `SetupStatus`, `SetupInputs`, `SetupFix`, `PermissionState` y `LanguageState`;
  - de la Task 5, `Preferences.screenRecordingRequested`;
  - de la Task 1, `KeychainStore.hasAPIKey`.
- Produces:

```swift
@MainActor protocol SetupSources {
    var hasAPIKey: Bool { get }
    var microphone: PermissionState { get }
    var screenRecordingGranted: Bool { get }
    func languages() async -> LanguageState
    func requestMicrophone() async
    func requestScreenRecording()
    func open(_ pane: SystemSettingsPane)
    func relaunch()
}
enum SystemSettingsPane: Sendable { case microphone, screenRecording, languages; var url: URL }
@MainActor struct LiveSetupSources: SetupSources
extension PermissionState { init(_ status: AVAuthorizationStatus) }
extension LanguageState { init(_ readiness: LiveTranslator.Readiness) }

@MainActor @Observable final class SetupMonitor {
    init(sources: any SetupSources, preferences: Preferences = .shared)
    private(set) var status: SetupStatus
    func refreshNow()
    func refresh() async
    func perform(_ fix: SetupFix) async
    func requestScreenRecording()
    func screenRecordingWasDenied()
    func relaunch()
    func startObserving()
}
extension SetupItem { var title: String; var symbol: String }
extension SetupFix { var buttonTitle: String? }
extension SetupIssue { var reason: String }
struct SetupIssueRow: View { init(issue: SetupIssue, setup: SetupMonitor, onEnterKey: @escaping () -> Void) }
AppState.setup: SetupMonitor
```

- [ ] **Step 1: Escribir los tests**

`AppTests/SetupMonitorTests.swift`:

```swift
import Testing
import Foundation
import AVFoundation
import ParlaCore
@testable import Parla

@MainActor
private final class FakeSources: SetupSources {
    var hasAPIKey = true
    var microphone: PermissionState = .granted
    var screenRecordingGranted = true
    var languageAnswer: LanguageState = .ready
    private(set) var calls: [String] = []

    func languages() async -> LanguageState { languageAnswer }
    func requestMicrophone() async { calls.append("requestMicrophone"); microphone = .granted }
    func requestScreenRecording() { calls.append("requestScreenRecording") }
    func open(_ pane: SystemSettingsPane) { calls.append("open \(pane)") }
    func relaunch() { calls.append("relaunch") }
}

/// Un almacén propio por test: los ajustes reales de Parla no se tocan.
private func scratchPreferences() -> (Preferences, () -> Void) {
    let name = "parla-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    return (Preferences(defaults: defaults), { defaults.removePersistentDomain(forName: name) })
}

@Test @MainActor func losIdiomasNoSeSabenHastaPreguntar() async {
    let (preferences, cleanup) = scratchPreferences()
    defer { cleanup() }
    let sources = FakeSources()
    sources.languageAnswer = .needsDownload
    let monitor = SetupMonitor(sources: sources, preferences: preferences)
    #expect(monitor.status.isComplete)
    await monitor.refresh()
    #expect(monitor.status.issues.map(\.item) == [.languages])
}

@Test @MainActor func refrescarRecogeLoQueCambioFuera() {
    let (preferences, cleanup) = scratchPreferences()
    defer { cleanup() }
    let sources = FakeSources()
    let monitor = SetupMonitor(sources: sources, preferences: preferences)
    sources.hasAPIKey = false
    monitor.refreshNow()
    #expect(monitor.status.issues.map(\.item) == [.apiKey])
}

@Test @MainActor func pedirLaPantallaQuedaApuntadoParaLaProximaVez() {
    let (preferences, cleanup) = scratchPreferences()
    defer { cleanup() }
    let sources = FakeSources()
    sources.screenRecordingGranted = false
    let monitor = SetupMonitor(sources: sources, preferences: preferences)
    #expect(monitor.status.issues.first?.fix == .requestScreenRecording)

    monitor.requestScreenRecording()

    #expect(sources.calls == ["requestScreenRecording"])
    #expect(monitor.status.issues.first?.fix == .openScreenRecordingSettingsOrRelaunch)
    // Al reabrir Parla se sigue sabiendo.
    let reopened = SetupMonitor(sources: sources, preferences: preferences)
    #expect(reopened.status.issues.first?.fix == .openScreenRecordingSettingsOrRelaunch)
}

@Test @MainActor func unaPantallaDenegadaPorPrimeraVezLanzaElDialogo() {
    let (preferences, cleanup) = scratchPreferences()
    defer { cleanup() }
    let sources = FakeSources()
    sources.screenRecordingGranted = false
    SetupMonitor(sources: sources, preferences: preferences).screenRecordingWasDenied()
    #expect(sources.calls == ["requestScreenRecording"])
    #expect(preferences.screenRecordingRequested)
}

@Test @MainActor func unaPantallaDenegadaOtraVezNoRepiteElDialogo() {
    let (preferences, cleanup) = scratchPreferences()
    defer { cleanup() }
    preferences.screenRecordingRequested = true
    let sources = FakeSources()
    sources.screenRecordingGranted = false
    SetupMonitor(sources: sources, preferences: preferences).screenRecordingWasDenied()
    #expect(sources.calls.isEmpty)
}

@Test @MainActor func cadaArregloLlamaALoQueToca() async {
    let (preferences, cleanup) = scratchPreferences()
    defer { cleanup() }
    let sources = FakeSources()
    sources.microphone = .notDetermined
    let monitor = SetupMonitor(sources: sources, preferences: preferences)

    await monitor.perform(.requestMicrophone)
    await monitor.perform(.openMicrophoneSettings)
    await monitor.perform(.openScreenRecordingSettingsOrRelaunch)
    await monitor.perform(.openLanguageSettings)
    await monitor.perform(.unavailable)

    #expect(sources.calls == ["requestMicrophone", "open microphone",
                              "open screenRecording", "open languages"])
    #expect(monitor.status.isComplete)
}

@Test func losPermisosDelSistemaSeTraducenBien() {
    #expect(PermissionState(AVAuthorizationStatus.authorized) == .granted)
    #expect(PermissionState(AVAuthorizationStatus.notDetermined) == .notDetermined)
    #expect(PermissionState(AVAuthorizationStatus.denied) == .denied)
    // Restringido no se puede pedir: «Permitir» no haría nada.
    #expect(PermissionState(AVAuthorizationStatus.restricted) == .denied)
}

@Test func laDisponibilidadDeIdiomasSeTraduceBien() {
    #expect(LanguageState(LiveTranslator.Readiness.ready) == .ready)
    #expect(LanguageState(LiveTranslator.Readiness.needsLanguages) == .needsDownload)
    #expect(LanguageState(LiveTranslator.Readiness.unsupported) == .unsupported)
}

@Test func cadaPendienteTieneTituloMotivoEIcono() {
    let issues = [
        SetupIssue(item: .apiKey, fix: .enterAPIKey),
        SetupIssue(item: .microphone, fix: .requestMicrophone),
        SetupIssue(item: .microphone, fix: .openMicrophoneSettings),
        SetupIssue(item: .screenRecording, fix: .requestScreenRecording),
        SetupIssue(item: .screenRecording, fix: .openScreenRecordingSettingsOrRelaunch),
        SetupIssue(item: .languages, fix: .openLanguageSettings),
        SetupIssue(item: .languages, fix: .unavailable),
    ]
    for issue in issues {
        #expect(!issue.item.title.isEmpty)
        #expect(!issue.item.symbol.isEmpty)
        #expect(!issue.reason.isEmpty)
    }
    // Pedir y denegar no se explican igual.
    #expect(issues[1].reason != issues[2].reason)
}

@Test func soloLoQueNoTieneArregloVaSinBoton() {
    #expect(SetupFix.unavailable.buttonTitle == nil)
    for fix: SetupFix in [.enterAPIKey, .requestMicrophone, .openMicrophoneSettings,
                          .requestScreenRecording, .openScreenRecordingSettingsOrRelaunch,
                          .openLanguageSettings] {
        #expect(fix.buttonTitle != nil)
    }
}
```

- [ ] **Step 2: Comprobar que fallan**

Run: `make test-app 2>&1 | tail -20`
Expected: no compila, `cannot find type 'SetupSources' in scope`.

- [ ] **Step 3: Implementar las fuentes**

`App/Setup/SetupSources.swift`:

```swift
import AppKit
import AVFoundation
import CoreGraphics
import ParlaCore

/// Lo que `SetupMonitor` pregunta y pide al sistema. Un protocolo para poder
/// probar el monitor sin tocar permisos reales.
@MainActor
protocol SetupSources {
    var hasAPIKey: Bool { get }
    var microphone: PermissionState { get }
    var screenRecordingGranted: Bool { get }
    func languages() async -> LanguageState
    func requestMicrophone() async
    func requestScreenRecording()
    func open(_ pane: SystemSettingsPane)
    func relaunch()
}

/// Los paneles de Ajustes del Sistema que arreglan algo, abiertos directamente.
enum SystemSettingsPane: Sendable {
    case microphone, screenRecording, languages

    var url: URL {
        switch self {
        case .microphone:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        case .screenRecording:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        case .languages:
            URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!
        }
    }
}

extension PermissionState {
    /// «Restringido» (control parental, gestión del Mac) no se puede pedir:
    /// cuenta como denegado, que lleva a Ajustes del Sistema.
    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized: self = .granted
        case .notDetermined: self = .notDetermined
        default: self = .denied
        }
    }
}

extension LanguageState {
    init(_ readiness: LiveTranslator.Readiness) {
        switch readiness {
        case .ready: self = .ready
        case .needsLanguages: self = .needsDownload
        case .unsupported: self = .unsupported
        }
    }
}

@MainActor
struct LiveSetupSources: SetupSources {
    var hasAPIKey: Bool { KeychainStore.shared.hasAPIKey }

    var microphone: PermissionState {
        PermissionState(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    func languages() async -> LanguageState {
        LanguageState(await LiveTranslator.readiness())
    }

    func requestMicrophone() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
    }

    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    func open(_ pane: SystemSettingsPane) {
        NSWorkspace.shared.open(pane.url)
    }

    /// macOS no aplica el permiso de Grabación de pantalla hasta que la app se
    /// reabre: se abre una instancia nueva y esta termina.
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL,
                                           configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    Log.pipeline.error("no se pudo reabrir Parla: \(error.localizedDescription)")
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }
}
```

- [ ] **Step 4: Implementar el monitor**

`App/Setup/SetupMonitor.swift`:

```swift
import AppKit
import Observation
import ParlaCore

/// Traduce el sistema a `SetupStatus` y ejecuta los arreglos. Es el único sitio
/// que pregunta por la clave, los permisos y los idiomas para saber qué falta.
@MainActor
@Observable
final class SetupMonitor {
    private(set) var status: SetupStatus

    @ObservationIgnored private let sources: any SetupSources
    @ObservationIgnored private let preferences: Preferences
    /// La única respuesta asíncrona. Hasta que llega, no se alarma.
    @ObservationIgnored private var languages: LanguageState = .unknown
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    init(sources: any SetupSources, preferences: Preferences = .shared) {
        self.sources = sources
        self.preferences = preferences
        status = SetupStatus(Self.inputs(sources, preferences, languages: .unknown))
    }

    private static func inputs(_ sources: any SetupSources, _ preferences: Preferences,
                               languages: LanguageState) -> SetupInputs {
        SetupInputs(hasAPIKey: sources.hasAPIKey,
                    microphone: sources.microphone,
                    screenRecordingGranted: sources.screenRecordingGranted,
                    screenRecordingRequested: preferences.screenRecordingRequested,
                    languages: languages)
    }

    /// Lo que se sabe sin esperar: la clave y los permisos.
    func refreshNow() {
        status = SetupStatus(Self.inputs(sources, preferences, languages: languages))
    }

    /// Además pregunta por los idiomas, que tarda.
    func refresh() async {
        refreshNow()
        languages = await sources.languages()
        refreshNow()
    }

    func perform(_ fix: SetupFix) async {
        switch fix {
        case .enterAPIKey, .unavailable: break
        case .requestMicrophone: await sources.requestMicrophone()
        case .openMicrophoneSettings: sources.open(.microphone)
        case .requestScreenRecording: requestScreenRecording()
        case .openScreenRecordingSettingsOrRelaunch: sources.open(.screenRecording)
        case .openLanguageSettings: sources.open(.languages)
        }
        await refresh()
    }

    /// El diálogo del sistema sale una vez por identidad de app: se apunta para
    /// ofrecer Ajustes del Sistema las siguientes veces.
    func requestScreenRecording() {
        preferences.screenRecordingRequested = true
        sources.requestScreenRecording()
        refreshNow()
    }

    /// La captura o los subtítulos se encontraron sin permiso: la primera vez se
    /// lanza el diálogo; las demás, pedirlo no haría nada.
    func screenRecordingWasDenied() {
        if preferences.screenRecordingRequested {
            refreshNow()
        } else {
            requestScreenRecording()
        }
    }

    func relaunch() {
        sources.relaunch()
    }

    /// Al volver de Ajustes del Sistema, el aviso desaparece solo.
    func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refresh() }
            }
        }
    }
}
```

- [ ] **Step 5: Implementar los textos y la fila**

`App/Setup/SetupIssue+UI.swift`:

```swift
import ParlaCore

extension SetupItem {
    var title: String {
        switch self {
        case .apiKey:          "Falta la clave de Anthropic"
        case .microphone:      "Parla no puede usar el micrófono"
        case .screenRecording: "Falta el permiso de Grabación de pantalla"
        case .languages:       "Falta el inglés en Traducción"
        }
    }

    var symbol: String {
        switch self {
        case .apiKey:          "key"
        case .microphone:      "mic"
        case .screenRecording: "rectangle.dashed"
        case .languages:       "globe"
        }
    }
}

extension SetupFix {
    /// `nil` cuando no hay nada que pulsar.
    var buttonTitle: String? {
        switch self {
        case .enterAPIKey: "Añadir clave"
        case .requestMicrophone, .requestScreenRecording: "Permitir"
        case .openMicrophoneSettings, .openScreenRecordingSettingsOrRelaunch: "Abrir Ajustes del Sistema"
        case .openLanguageSettings: "Abrir Idioma y región"
        case .unavailable: nil
        }
    }
}

extension SetupIssue {
    var reason: String {
        switch (item, fix) {
        case (.apiKey, _):
            "La voz y las capturas usan Claude. La clave se guarda en el Llavero."
        case (.microphone, .requestMicrophone):
            "El modo voz lo necesita para oírte."
        case (.microphone, _):
            "Lo denegaste antes. Actívalo para Parla en Ajustes del Sistema."
        case (.screenRecording, .requestScreenRecording):
            "Las capturas y los subtítulos lo necesitan para ver y oír la pantalla."
        case (.screenRecording, _):
            "Actívalo para Parla en Ajustes del Sistema. Si ya lo hiciste, reabre Parla: "
                + "macOS no lo aplica antes."
        case (.languages, .unavailable):
            "Este Mac no puede traducir del inglés al español."
        case (.languages, _):
            "Los subtítulos se traducen en tu Mac. Añade inglés y español en Idiomas de traducción."
        }
    }
}
```

`App/Setup/SetupIssueRow.swift`:

```swift
import SwiftUI
import ParlaCore

/// Un pendiente con su arreglo. La misma fila en el panel, el menú emergente,
/// Estudio y la bienvenida.
struct SetupIssueRow: View {
    let issue: SetupIssue
    let setup: SetupMonitor
    /// La clave se escribe en Ajustes de Estudio: quien muestra la fila sabe
    /// cómo llegar.
    let onEnterKey: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: issue.item.symbol)
                .foregroundStyle(Theme.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.item.title)
                    .font(.callout.weight(.medium))
                Text(issue.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let title = issue.fix.buttonTitle {
                        Button(title, action: act)
                    }
                    if issue.fix == .openScreenRecordingSettingsOrRelaunch {
                        Button("Reabrir Parla") { setup.relaunch() }
                    }
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func act() {
        if issue.fix == .enterAPIKey {
            onEnterKey()
        } else {
            Task { await setup.perform(issue.fix) }
        }
    }
}
```

En `App/AppState.swift`, después de `let audioDevices = AudioDeviceMonitor()`:

```swift
    /// Qué falta por preparar. Lo leen la bienvenida, el menú emergente,
    /// Estudio y el panel.
    let setup = SetupMonitor(sources: LiveSetupSources())

    init() {
        setup.startObserving()
        Task { await setup.refresh() }
    }
```

- [ ] **Step 6: Comprobar que pasan**

Run: `make test-app 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, 82 tests (72 + 10).

- [ ] **Step 7: Commit**

```bash
git add App/Setup AppTests/SetupMonitorTests.swift App/AppState.swift
git commit -m "feat: SetupMonitor traduce el sistema a qué falta por preparar

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: `APIKeyEntry` — el campo de la clave, compartido

**Files:**
- Create: `App/Setup/APIKeyEntry.swift`
- Create: `AppTests/APIKeyEntryTests.swift`

**Interfaces:**
- Consumes: de la Task 4, `APIKeyValidator`, `APIKeyValidator.normalize(_:)` y `KeyCheck.shouldSave`.
- Produces:

```swift
@MainActor @Observable final class APIKeyEntry {
    init(validator: APIKeyValidator = APIKeyValidator(),
         save: @escaping @MainActor (String) -> Void = { KeychainStore.shared.apiKey = $0 })
    var text: String
    private(set) var message: String?
    private(set) var isChecking: Bool
    @discardableResult func submit() async -> KeyCheck?   // nil = campo vacío
}
extension KeyCheck { var message: String }
```

- [ ] **Step 1: Escribir los tests**

`AppTests/APIKeyEntryTests.swift`:

```swift
import Testing
import Foundation
import ParlaCore
@testable import Parla

private struct StatusStreamer: HTTPStreamer {
    let status: Int
    func stream(_ request: URLRequest) async throws -> HTTPStreamResponse {
        HTTPStreamResponse(statusCode: status, lines: AsyncThrowingStream { $0.finish() })
    }
}

private struct OfflineStreamer: HTTPStreamer {
    func stream(_ request: URLRequest) async throws -> HTTPStreamResponse {
        throw URLError(.notConnectedToInternet)
    }
}

@MainActor
private final class SavedKeys {
    var values: [String] = []
}

@MainActor
private func entry(_ streamer: any HTTPStreamer, saved: SavedKeys) -> APIKeyEntry {
    APIKeyEntry(validator: APIKeyValidator(streamer: streamer),
                save: { saved.values.append($0) })
}

@Test @MainActor func unaClaveBuenaSeGuardaSinEspacios() async {
    let saved = SavedKeys()
    let field = entry(StatusStreamer(status: 200), saved: saved)
    field.text = "  sk-ant-abc\n"
    #expect(await field.submit() == .valid)
    #expect(saved.values == ["sk-ant-abc"])
    #expect(field.text.isEmpty)
    #expect(field.message == KeyCheck.valid.message)
}

@Test @MainActor func unCampoVacioNuncaBorraLaClaveGuardada() async {
    // Guardar una cadena vacía en el Llavero borra la clave que hay.
    let saved = SavedKeys()
    let field = entry(StatusStreamer(status: 200), saved: saved)
    field.text = "   \n"
    #expect(await field.submit() == nil)
    #expect(saved.values.isEmpty)
}

@Test @MainActor func unaClaveRechazadaNoSeGuardaYSeQuedaEnElCampo() async {
    let saved = SavedKeys()
    let field = entry(StatusStreamer(status: 401), saved: saved)
    field.text = "sk-ant-mala"
    #expect(await field.submit() == .invalid)
    #expect(saved.values.isEmpty)
    #expect(field.text == "sk-ant-mala")
    #expect(field.message == KeyCheck.invalid.message)
}

@Test @MainActor func sinRedSeGuardaConAviso() async {
    let saved = SavedKeys()
    let field = entry(OfflineStreamer(), saved: saved)
    field.text = "sk-ant-abc"
    #expect(await field.submit() == .unverified)
    #expect(saved.values == ["sk-ant-abc"])
    #expect(field.message == KeyCheck.unverified.message)
}
```

- [ ] **Step 2: Comprobar que fallan**

Run: `make test-app 2>&1 | tail -20`
Expected: no compila, `cannot find 'APIKeyEntry' in scope`.

- [ ] **Step 3: Implementar**

`App/Setup/APIKeyEntry.swift`:

```swift
import Foundation
import Observation
import ParlaCore

/// El campo de la clave, compartido por la bienvenida y Ajustes: los dos
/// comprueban y guardan igual.
@MainActor
@Observable
final class APIKeyEntry {
    var text = ""
    private(set) var message: String?
    private(set) var isChecking = false

    @ObservationIgnored private let validator: APIKeyValidator
    @ObservationIgnored private let save: @MainActor (String) -> Void

    init(validator: APIKeyValidator = APIKeyValidator(),
         save: @escaping @MainActor (String) -> Void = { KeychainStore.shared.apiKey = $0 }) {
        self.validator = validator
        self.save = save
    }

    /// `nil` si el campo estaba vacío: no hay nada que comprobar, y guardar una
    /// cadena vacía borraría la clave que ya hay.
    @discardableResult
    func submit() async -> KeyCheck? {
        let key = APIKeyValidator.normalize(text)
        guard !key.isEmpty else {
            message = nil
            return nil
        }
        isChecking = true
        let check = await validator.check(key)
        isChecking = false
        message = check.message
        if check.shouldSave {
            save(key)
            text = ""
        }
        return check
    }
}

extension KeyCheck {
    var message: String {
        switch self {
        case .valid: "Clave guardada."
        case .unverified: "No se pudo comprobar la clave; se guardó igualmente."
        case .invalid: "Esa clave no funciona. Revisa que esté completa."
        }
    }
}
```

- [ ] **Step 4: Comprobar que pasan**

Run: `make test-app 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, 86 tests (82 + 4).

- [ ] **Step 5: Commit**

```bash
git add App/Setup/APIKeyEntry.swift AppTests/APIKeyEntryTests.swift
git commit -m "feat: el campo de la clave comprueba antes de guardar y nunca borra

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Estudio — ventana, barra lateral, Ajustes y aviso superior

**Files:**
- Create: `App/Studio/StudioRouter.swift`
- Create: `App/Studio/StudioView.swift`
- Create: `App/Studio/SetupBanner.swift`
- Create: `App/Windows/WindowCoordinator.swift`
- Create: `App/Shortcuts.swift`
- Create: `AppTests/StudioRouterTests.swift`
- Move: `App/UI/SettingsView.swift` → `App/Studio/SettingsSection.swift` (struct `SettingsSection`)
- Move: `App/UI/HistoryWindow.swift` → `App/Studio/HistorySection.swift` (struct `HistorySection`)
- Modify: `App/AppState.swift` (`windows`, `import SwiftUI`)
- Modify: `App/ParlaApp.swift` (fuera `Settings` y `Window`; el menú de texto abre Estudio)

**Interfaces:**
- Consumes:
  - de la Task 7, `APIKeyEntry`;
  - de la Task 6, `SetupMonitor`, `SetupIssueRow` y `AppState.setup`;
  - de la Task 2, `Theme`.
- Produces:

```swift
enum StudioSection: Hashable, CaseIterable { case history, settings; var title: String; var symbol: String }
@MainActor @Observable final class StudioRouter { var section: StudioSection; func open(_ section: StudioSection?) }
@MainActor final class WindowCoordinator: NSObject, NSWindowDelegate {
    init(preferences: Preferences = .shared,
         studioContent: @escaping @MainActor (StudioRouter) -> AnyView,
         welcomeContent: @escaping @MainActor () -> AnyView)
    let router: StudioRouter
    func showStudio(_ section: StudioSection? = nil)
    func showWelcome()
    func closeWelcome()
    func welcomeDidClose()
}
AppState.windows: WindowCoordinator
extension KeyboardShortcuts.Name { toggleListening, captureScreen, toggleSubtitles }   // movido
extension ParlaMode { var shortcutName: KeyboardShortcuts.Name }
```

- [ ] **Step 1: Escribir los tests**

`AppTests/StudioRouterTests.swift`:

```swift
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
```

- [ ] **Step 2: Comprobar que fallan**

Run: `make test-app 2>&1 | tail -20`
Expected: no compila, `cannot find 'StudioRouter' in scope`.

- [ ] **Step 3: Mover los archivos**

```bash
git mv App/UI/SettingsView.swift App/Studio/SettingsSection.swift
git mv App/UI/HistoryWindow.swift App/Studio/HistorySection.swift
```

En `App/Studio/HistorySection.swift`, renombra `struct HistoryView` → `struct HistorySection`. En el mismo archivo, quita `.frame(minWidth: 520, minHeight: 420)`: el tamaño lo pone Estudio.

Crea `App/Shortcuts.swift` y mueve ahí, tal cual, el bloque `extension KeyboardShortcuts.Name { … }` que estaba al principio de `SettingsSection.swift`. Añade:

```swift
import KeyboardShortcuts
import ParlaCore

// (el bloque `extension KeyboardShortcuts.Name` movido aquí)

extension ParlaMode {
    /// El atajo global de cada modo, para enseñarlo donde se ofrece el modo.
    var shortcutName: KeyboardShortcuts.Name {
        switch self {
        case .voice: .toggleListening
        case .capture: .captureScreen
        case .subtitles: .toggleSubtitles
        }
    }
}
```

- [ ] **Step 4: El router y el coordinador**

`App/Studio/StudioRouter.swift`:

```swift
import Observation

enum StudioSection: Hashable, CaseIterable {
    case history, settings

    var title: String {
        switch self {
        case .history: "Historial"
        case .settings: "Ajustes"
        }
    }

    var symbol: String {
        switch self {
        case .history: "clock"
        case .settings: "gearshape"
        }
    }
}

/// Qué sección de Estudio se ve. Fuera de la vista para que el menú emergente,
/// el panel y ⌘, puedan abrir Estudio donde toca.
@MainActor
@Observable
final class StudioRouter {
    var section: StudioSection = .history

    /// `nil` deja la sección que estuviera: reabrir Estudio no te saca de donde
    /// estabas.
    func open(_ section: StudioSection?) {
        if let section { self.section = section }
    }
}
```

`App/Windows/WindowCoordinator.swift`:

```swift
import AppKit
import SwiftUI

/// Las ventanas de Estudio y de la bienvenida.
///
/// Son `NSWindow` con contenido SwiftUI y no escenas `Window`: el panel
/// flotante también tiene que poder abrir Estudio, y fuera de las escenas de
/// SwiftUI no hay `openWindow`.
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    let router = StudioRouter()

    private let preferences: Preferences
    private let studioContent: @MainActor (StudioRouter) -> AnyView
    private let welcomeContent: @MainActor () -> AnyView
    private var studio: NSWindow?
    private var welcome: NSWindow?

    init(preferences: Preferences = .shared,
         studioContent: @escaping @MainActor (StudioRouter) -> AnyView,
         welcomeContent: @escaping @MainActor () -> AnyView) {
        self.preferences = preferences
        self.studioContent = studioContent
        self.welcomeContent = welcomeContent
        super.init()
    }

    func showStudio(_ section: StudioSection? = nil) {
        router.open(section)
        let window = studio ?? makeStudioWindow()
        studio = window
        bringToFront(window)
    }

    func showWelcome() {
        if let welcome, !welcome.isVisible {
            // Siempre desde el paso 1: una vista nueva no arrastra el paso de
            // la vez anterior.
            welcome.contentViewController = NSHostingController(rootView: welcomeContent())
        }
        let window = welcome ?? makeWelcomeWindow()
        welcome = window
        window.center()
        bringToFront(window)
    }

    func closeWelcome() {
        welcome?.close()
    }

    /// Cerrarla en cualquier paso cuenta como vista: lo pendiente sigue en los
    /// avisos.
    func welcomeDidClose() {
        preferences.hasSeenWelcome = true
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === welcome else { return }
        welcomeDidClose()
    }

    /// Parla vive en la barra de menús y nunca es la app activa: sin activarla,
    /// la ventana se abre detrás de la app en uso. `activate()` a secas es
    /// cooperativa y macOS la ignora cuando quien la pide no es ya la activa.
    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeStudioWindow() -> NSWindow {
        let controller = NSHostingController(rootView: studioContent(router))
        // La barra de herramientas y el título de SwiftUI pasan a la ventana.
        controller.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 860, height: 600))
        window.center()
        return window
    }

    private func makeWelcomeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: welcomeContent()))
        window.title = "Bienvenida a Parla"
        window.styleMask.remove([.resizable, .miniaturizable])
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}
```

Si la sonda 5 decidió el monitor de teclado, añade al coordinador lo siguiente y llama a `installSettingsShortcut()` al final de `init`, después de `super.init()`:

```swift
    private var settingsShortcut: Any?

    /// ⌘, abre Estudio en Ajustes (sonda 5: el atajo dentro de la vista no respondía).
    private func installSettingsShortcut() {
        settingsShortcut = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "," else { return event }
            MainActor.assumeIsolated { self?.showStudio(.settings) }
            return nil
        }
    }
```

En ese caso, quita también los `.background { Button("Ajustes") … }` de `StudioView` (abajo) y de `MenuBarPopover` (Task 11).

- [ ] **Step 5: Las vistas de Estudio**

`App/Studio/SetupBanner.swift`:

```swift
import SwiftUI
import ParlaCore

/// Lo que falta, encima del contenido de Estudio. No aparece si no falta nada.
struct SetupBanner: View {
    let setup: SetupMonitor
    let onEnterKey: () -> Void

    var body: some View {
        if !setup.status.isComplete {
            VStack(alignment: .leading, spacing: 10) {
                Text(setup.status.issues.count == 1
                     ? "Falta una cosa para usar todos los modos"
                     : "Faltan \(setup.status.issues.count) cosas para usar todos los modos")
                    .font(.callout.weight(.semibold))
                ForEach(setup.status.issues) { issue in
                    SetupIssueRow(issue: issue, setup: setup, onEnterKey: onEnterKey)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent.opacity(0.08))
            Divider()
        }
    }
}
```

`App/Studio/StudioView.swift`:

```swift
import SwiftUI

/// La ventana principal: el historial y los ajustes, y más adelante el repaso
/// y la práctica, como filas nuevas de la barra lateral.
struct StudioView: View {
    @Bindable var state: AppState
    @Bindable var router: StudioRouter

    /// La lista solo lleva el Historial: Ajustes vive abajo, aparte.
    private var listSelection: Binding<StudioSection?> {
        Binding(get: { router.section },
                set: { if let section = $0 { router.section = section } })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: listSelection) {
                Label(StudioSection.history.title, systemImage: StudioSection.history.symbol)
                    .tag(StudioSection.history)
            }
            .safeAreaInset(edge: .bottom) {
                SidebarFooterButton(section: .settings, router: router)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            VStack(spacing: 0) {
                SetupBanner(setup: state.setup) { router.section = .settings }
                switch router.section {
                case .history: HistorySection()
                case .settings: SettingsSection(state: state)
                }
            }
        }
        .navigationTitle(router.section.title)
        .frame(minWidth: 760, minHeight: 520)
        .background {
            Button("Ajustes") { router.section = .settings }
                .keyboardShortcut(",", modifiers: .command)
                .hidden()
        }
        .task { await state.setup.refresh() }
    }
}

private struct SidebarFooterButton: View {
    let section: StudioSection
    @Bindable var router: StudioRouter

    var body: some View {
        Button { router.section = section } label: {
            Label(section.title, systemImage: section.symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(router.section == section ? Theme.accent.opacity(0.15) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(10)
    }
}
```

En `App/Studio/SettingsSection.swift`:
- renombra `struct SettingsView` → `struct SettingsSection`;
- quita `.frame(width: 420, height: 640)`, `.padding()` y el comentario del alto fijo;
- sustituye `@State private var apiKey = ""` y su comentario por:

```swift
    @State private var keyEntry = APIKeyEntry()
    /// Se pregunta sin leer la clave: el Llavero no pide contraseña.
    @State private var hasKey = false
```

La sección de la clave pasa a:

```swift
            Section("Clave de la API de Anthropic") {
                SecureField(hasKey ? "Hay una clave guardada; pega otra para cambiarla" : "sk-ant-…",
                            text: $keyEntry.text)
                    .onSubmit(saveKey)
                HStack {
                    Button("Guardar", action: saveKey)
                    if keyEntry.isChecking { ProgressView().controlSize(.small) }
                }
                if let message = keyEntry.message {
                    Text(message).font(.caption)
                }
                Text("Se guarda en el Llavero de macOS, nunca en un archivo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```

y `.onAppear` pasa a:

```swift
        .onAppear {
            hasKey = KeychainStore.shared.hasAPIKey
            state.audioDevices.start()
        }
```

Añade el método:

```swift
    private func saveKey() {
        Task {
            await keyEntry.submit()
            hasKey = KeychainStore.shared.hasAPIKey
            state.setup.refreshNow()
        }
    }
```

Quita `import KeyboardShortcuts` solo si ya no se usa. Se sigue usando: `KeyboardShortcuts.Recorder` está en la sección «Atajo».

- [ ] **Step 6: Cablear `AppState` y `ParlaApp`**

En `App/AppState.swift`, añade `import SwiftUI` y, junto a `let setup`:

```swift
    /// Las ventanas de Estudio y de la bienvenida. Se crea en `init` porque su
    /// contenido necesita a `self`.
    @ObservationIgnored private(set) var windows: WindowCoordinator!
```

El `init()` pasa a:

```swift
    init() {
        windows = WindowCoordinator(
            studioContent: { [unowned self] router in
                AnyView(StudioView(state: self, router: router)
                    .modelContainer(Persistence.container))
            },
            welcomeContent: { AnyView(EmptyView()) })
        setup.startObserving()
        Task { await setup.refresh() }
    }
```

En `App/ParlaApp.swift`:
- quita las líneas `Settings { SettingsView(state: state) }` y `Window("Historial", id: "history") { HistoryView() }` con su `.modelContainer`;
- en `MenuBarView`, quita `@Environment(\.openWindow)`, `@Environment(\.openSettings)` y `inFront`, junto con su comentario, que ya está en `WindowCoordinator`;
- los dos ítems pasan a:

```swift
        Button("Abrir Estudio…") { state.windows.showStudio(.history) }
        Button("Ajustes…") { state.windows.showStudio(.settings) }
            .keyboardShortcut(",", modifiers: .command)
```

Si `import SwiftData` queda sin uso en `ParlaApp.swift`, quítalo.

- [ ] **Step 7: Comprobar que pasan y compila**

Run: `make test-app 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, 89 tests (86 + 3).

Run: `make run`. Con computer-use, abre el menú de la barra → «Abrir Estudio…» y haz una captura.
Expected:
- Estudio aparece delante, con la barra lateral (Historial arriba, Ajustes abajo) y el historial de siempre;
- en Ajustes se ve el formulario y la clave dice «Hay una clave guardada…»;
- ⌘, con Estudio delante salta a Ajustes.

- [ ] **Step 8: Commit**

```bash
git add -A App AppTests/StudioRouterTests.swift
git commit -m "feat: ventana Estudio con Historial y Ajustes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Los avisos salen de `SetupStatus` — `AppState` y el panel

**Files:**
- Create: `App/Notices.swift`
- Create: `AppTests/NoticeListTests.swift`
- Modify: `App/AppState.swift`. Salen `needsMicrophoneAccess`, `needsScreenRecordingAccess`, `needsTranslationLanguages`, `askedForScreenAccess` y los `static func open…Settings`. Entran `blockedMode`, `panelIssues`, `runtimeNotices`, `dismiss(_:)`, `isBlocked(_:)` y `canStart(_:)`.
- Modify: `App/UI/PanelView.swift:28-56` y la condición de cierre en `:94-97`.

**Interfaces:**
- Consumes:
  - de la Task 3, `SetupStatus.startBlockers(for:)` y `blockers(for:)`;
  - de la Task 6, `SetupMonitor.refreshNow()`, `refresh()` y `screenRecordingWasDenied()`, y `SetupIssueRow`;
  - de la Task 8, `WindowCoordinator.showStudio(_:)`.
- Produces:

```swift
enum RuntimeNotice: Equatable, Identifiable, Sendable { case setup(String), capture(String), silentInput(String), batch(String); var id: String; var text: String }
enum Notice: Equatable, Identifiable { case runtime(RuntimeNotice), setup(SetupIssue); var id: String }
struct NoticeList: Equatable { init(runtime:issues:priority:limit:); let visible: [Notice]; let hiddenCount: Int }
AppState.blockedMode: ParlaMode?            // private(set)
AppState.panelIssues: [SetupIssue]
AppState.runtimeNotices: [RuntimeNotice]
AppState.dismiss(_ notice: RuntimeNotice)
AppState.isBlocked(_ mode: ParlaMode) -> Bool
```

- [ ] **Step 1: Escribir los tests**

`AppTests/NoticeListTests.swift`:

```swift
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
```

- [ ] **Step 2: Comprobar que fallan**

Run: `make test-app 2>&1 | tail -20`
Expected: no compila, `cannot find 'NoticeList' in scope`.

- [ ] **Step 3: Implementar los avisos**

`App/Notices.swift`:

```swift
import ParlaCore

/// Un error de esta sesión. Se ve hasta que se descarta o se vuelve a arrancar
/// el modo. Lo pendiente de preparar no va aquí: eso es `SetupIssue`.
enum RuntimeNotice: Equatable, Identifiable, Sendable {
    case setup(String)
    case capture(String)
    case silentInput(String)
    case batch(String)

    var id: String {
        switch self {
        case .setup: "setup"
        case .capture: "capture"
        case .silentInput: "silentInput"
        case .batch: "batch"
        }
    }

    var text: String {
        switch self {
        case .setup(let text), .capture(let text), .silentInput(let text), .batch(let text): text
        }
    }
}

enum Notice: Equatable, Identifiable {
    case runtime(RuntimeNotice)
    case setup(SetupIssue)

    var id: String {
        switch self {
        case .runtime(let notice): "runtime-\(notice.id)"
        case .setup(let issue): "setup-\(issue.item)"
        }
    }
}

/// Lo que cabe en el menú emergente: primero lo que impide arrancar el modo
/// que acabas de pulsar, luego los errores de la sesión y luego el resto de
/// pendientes. Lo que no cabe se cuenta.
struct NoticeList: Equatable {
    let visible: [Notice]
    let hiddenCount: Int

    init(runtime: [RuntimeNotice], issues: [SetupIssue],
         priority: [SetupIssue] = [], limit: Int = 2) {
        let rest = issues.filter { !priority.contains($0) }
        let all = priority.map(Notice.setup) + runtime.map(Notice.runtime) + rest.map(Notice.setup)
        visible = Array(all.prefix(limit))
        hiddenCount = max(0, all.count - limit)
    }
}
```

- [ ] **Step 4: `AppState` deja las banderas sueltas**

En `App/AppState.swift`:

1. Borra:
   - las propiedades `needsMicrophoneAccess`, `needsScreenRecordingAccess` (con su comentario), `needsTranslationLanguages` (con su comentario) y `askedForScreenAccess` (con su comentario);
   - los tres `static func open…Settings()`, que se mudaron a `SystemSettingsPane`.

2. Después de `let setup = …` añade:

```swift
    /// El modo que se intentó arrancar sin tener lo que necesita. El panel y el
    /// menú emergente enseñan primero sus pendientes.
    private(set) var blockedMode: ParlaMode?

    /// Los pendientes del modo bloqueado, con su arreglo.
    var panelIssues: [SetupIssue] {
        blockedMode.map { setup.status.blockers(for: $0) } ?? []
    }

    /// Los errores de esta sesión, en el orden en que se enseñan.
    var runtimeNotices: [RuntimeNotice] {
        [setupError.map(RuntimeNotice.setup),
         captureError.map(RuntimeNotice.capture),
         silentInputWarning.map(RuntimeNotice.silentInput),
         batchError.map(RuntimeNotice.batch)]
            .compactMap { $0 }
    }

    func dismiss(_ notice: RuntimeNotice) {
        switch notice {
        case .setup: setupError = nil
        case .capture: captureError = nil
        case .silentInput: silentInputWarning = nil
        case .batch: batchError = nil
        }
    }

    /// Lo que se arregla fuera de Parla impide arrancar; pedir un permiso no,
    /// porque el propio arranque lanza el diálogo del sistema. Lo usa el menú
    /// emergente, que ya enseña los avisos y no necesita el panel.
    func isBlocked(_ mode: ParlaMode) -> Bool {
        setup.refreshNow()
        let blocked = !setup.status.startBlockers(for: mode).isEmpty
        blockedMode = blocked ? mode : nil
        return blocked
    }

    /// Desde un atajo: si falta algo, el panel lo enseña con su botón.
    private func canStart(_ mode: ParlaMode) -> Bool {
        guard !isBlocked(mode) else {
            showPanel()
            return false
        }
        return true
    }
```

3. En `start()`, sustituye desde el principio hasta `isListening = true` por:

```swift
    private func start() {
        // Los dos modos usan el reconocimiento de voz: uno apaga al otro.
        if isSubtitling { stopSubtitles() }
        guard canStart(.voice) else { return }
        // `hasAPIKey` dijo que hay clave, pero leerla puede fallar igual (se
        // canceló el diálogo del Llavero).
        guard let apiKey = KeychainStore.shared.apiKey else {
            setupError = ExplainerError.missingAPIKey.readableMessage
            showPanel()
            return
        }
        isListening = true
```

y el bloque `do { try await engine.start() … }` por:

```swift
            do {
                try await engine.start()
            } catch TranscriberSetupError.microphoneDenied {
                setup.refreshNow()
                blockedMode = .voice
                stop()
                showPanel()
                return
            } catch TranscriberSetupError.localeUnsupported {
                setupError = "Tu Mac no tiene un modelo de voz en español disponible."
                stop()
                showPanel()
                return
            } catch {
                Log.audio.error("no se pudo encender la escucha: \(error)")
                setupError = "No se pudo encender la escucha."
                stop()
                showPanel()
                return
            }
```

4. En `startSubtitles()`:
   - después de `if isListening { stop() }`, añade `guard canStart(.subtitles) else { return }`;
   - cambia `needsTranslationLanguages = false` por `setupError = nil`.

   El bloque del aviso de idiomas pasa a:

```swift
            if let notice = LiveTranslator.notice(for: readiness) {
                subtitleModel.notice = notice
                await setup.refresh()
                blockedMode = .subtitles
                showPanel()
                try? await Task.sleep(for: .seconds(6))
                stopSubtitles()
                return
            }
```

   y los `catch` de `engine.start()` pasan a:

```swift
            } catch TranscriberSetupError.screenRecordingDenied {
                // Igual que la captura: el diálogo del sistema, una sola vez.
                setup.screenRecordingWasDenied()
                blockedMode = .subtitles
                showPanel()
                stopSubtitles()
                return
            } catch {
                // Apagados mientras arrancaban: no es un error que enseñar.
                guard isSubtitling, !(error is CancellationError) else { return }
                Log.audio.error("no se pudieron encender los subtítulos: \(error)")
                setupError = "No se pudieron encender los subtítulos."
                showPanel()
                stopSubtitles()
                return
            }
```

5. En `captureScreen()`, después de `guard !isSelectingRegion else { return }`, añade `guard canStart(.capture) else { return }`. Los `catch` de `grabRegion()` pasan a:

```swift
            } catch ScreenCapturer.Failure.noPermission {
                setup.screenRecordingWasDenied()
                blockedMode = .capture
                showPanel()
                return
            } catch {
                Log.pipeline.error("no se pudo capturar la pantalla: \(error)")
                captureError = "No se pudo capturar la pantalla."
                showPanel()
                return
            }
```

   y borra la línea `needsScreenRecordingAccess = false`.

6. En `hidePanel()`, añade `blockedMode = nil` al final.

- [ ] **Step 5: El panel lee los pendientes**

En `App/UI/PanelView.swift`, sustituye los tres bloques `if state.needsMicrophoneAccess`, `if state.needsScreenRecordingAccess` y `if state.needsTranslationLanguages` por:

```swift
                ForEach(state.panelIssues) { issue in
                    SetupIssueRow(issue: issue, setup: state.setup) {
                        state.windows.showStudio(.settings)
                    }
                }
```

y, en la condición del botón «Cerrar el panel», `|| state.needsScreenRecordingAccess` pasa a `|| !state.panelIssues.isEmpty`.

- [ ] **Step 6: Comprobar que pasan y que no queda nada de lo viejo**

Run: `grep -rn "needsMicrophoneAccess\|needsScreenRecordingAccess\|needsTranslationLanguages\|askedForScreenAccess\|openMicrophoneSettings\|openScreenRecordingSettings()\|openLanguageSettings()" App AppTests`
Expected: sin resultados.

Run: `make test-app 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, 94 tests (89 + 5).

- [ ] **Step 7: Commit**

```bash
git add App/Notices.swift AppTests/NoticeListTests.swift App/AppState.swift App/UI/PanelView.swift
git commit -m "refactor: los avisos de preparación salen de SetupStatus y no se quedan viejos

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Historial — inglés en serif, iconos, favoritas y borrar

**Files:**
- Create: `App/Studio/EnglishSide.swift`
- Create: `App/Studio/HistoryRow.swift`
- Create: `AppTests/EnglishSideTests.swift`
- Modify: `App/Studio/HistorySection.swift`
- Modify: `App/CaptureKind+UI.swift` (`title`)
- Modify: `AppTests/HistoryFilterTests.swift`

**Interfaces:**
- Consumes: de la Task 5, `StoredCard.isFavorite`; de la Task 2, `Theme.english(_:)` y `Theme.accent`.
- Produces:

```swift
enum EnglishSide: Equatable { case source, result, both; init(origin: String, kind: String?); var sourceIsEnglish: Bool; var resultIsEnglish: Bool }
extension StoredCard { var englishSide: EnglishSide; var englishText: String; var otherText: String }
enum CardOriginStyle { static func symbol(origin: String) -> String; static func name(origin: String, kind: String?) -> String }
extension CaptureKind { var title: String }
extension HistoryFilter { func includes(origin: String, isFavorite: Bool, favoritesOnly: Bool) -> Bool }
```

- [ ] **Step 1: Escribir los tests**

`AppTests/EnglishSideTests.swift`:

```swift
import Testing
import Foundation
import ParlaCore
@testable import Parla

private func card(origin: String, kind: String? = nil,
                  source: String = "original", result: String = "resultado") -> StoredCard {
    StoredCard(id: UUID(), source: source, result: result, why: [], createdAt: Date(),
               origin: origin, kind: kind, vocab: [])
}

@Test func enLaVozElInglesEsElResultado() {
    #expect(EnglishSide(origin: "voice", kind: nil) == .result)
}

@Test func enLosSubtitulosElInglesEsElOriginal() {
    #expect(EnglishSide(origin: "system", kind: nil) == .source)
}

@Test func enUnaCapturaDependeDelCaso() {
    #expect(EnglishSide(origin: "screen", kind: "understand") == .source)
    #expect(EnglishSide(origin: "screen", kind: "translate") == .result)
    #expect(EnglishSide(origin: "screen", kind: "correct") == .both)
    #expect(EnglishSide(origin: "screen", kind: "skip") == .source)
    #expect(EnglishSide(origin: "screen", kind: nil) == .source)
}

@Test func copiarElInglesDeUnaCorreccionCopiaLaVersionCorregida() {
    let corrected = card(origin: "screen", kind: "correct",
                         source: "I has a question", result: "I have a question")
    #expect(corrected.englishText == "I have a question")
    #expect(corrected.otherText == "I has a question")
}

@Test func copiarElInglesDeUnSubtituloCopiaElOriginal() {
    let line = card(origin: "system", source: "Welcome back", result: "Bienvenidos")
    #expect(line.englishText == "Welcome back")
    #expect(line.otherText == "Bienvenidos")
}

@Test func enLaVozElOtroLadoEsLoQueDijiste() {
    let spoken = card(origin: "voice", source: "me da igual", result: "I don't mind.")
    #expect(spoken.englishText == "I don't mind.")
    #expect(spoken.otherText == "me da igual")
}
```

Al final de `AppTests/HistoryFilterTests.swift`:

```swift
@Test func laEstrellaSeCombinaConElModo() {
    #expect(HistoryFilter.voice.includes(origin: "voice", isFavorite: true, favoritesOnly: true))
    #expect(!HistoryFilter.voice.includes(origin: "voice", isFavorite: false, favoritesOnly: true))
    #expect(!HistoryFilter.voice.includes(origin: "screen", isFavorite: true, favoritesOnly: true))
    #expect(HistoryFilter.all.includes(origin: "system", isFavorite: true, favoritesOnly: true))
    #expect(HistoryFilter.all.includes(origin: "system", isFavorite: false, favoritesOnly: false))
}

@Test func cadaOrigenTieneSuIconoYSuNombre() {
    #expect(CardOriginStyle.symbol(origin: "voice") == "mic")
    #expect(CardOriginStyle.symbol(origin: "screen") == "crop")
    #expect(CardOriginStyle.symbol(origin: "system") == "captions.bubble")
    #expect(CardOriginStyle.name(origin: "voice", kind: nil) == "Voz")
    #expect(CardOriginStyle.name(origin: "system", kind: nil) == "Subtítulos")
    #expect(CardOriginStyle.name(origin: "screen", kind: "correct") == "Corrección")
    #expect(CardOriginStyle.name(origin: "screen", kind: nil) == "Captura")
}

@Test func losCasosDeCapturaTienenNombreSinIcono() {
    #expect(CaptureKind.allCases.map(\.title)
            == ["Para entender", "Corrección", "Traducción", "Sin texto"])
}
```

Antes del Step 2, comprueba que `CaptureKind` es `CaseIterable` y que está en el orden understand, correct, translate, skip:

```bash
grep -n "enum CaptureKind" Core/Sources/ParlaCore/Capture.swift
```

Si no es `CaseIterable`, usa en el test el array explícito `[CaptureKind.understand, .correct, .translate, .skip].map(\.title)`, y deja la ruling en el ledger.

- [ ] **Step 2: Comprobar que fallan**

Run: `make test-app 2>&1 | tail -20`
Expected: no compila, `cannot find 'EnglishSide' in scope`.

- [ ] **Step 3: Implementar la lógica**

`App/Studio/EnglishSide.swift`:

```swift
import ParlaCore

/// En qué lado de la tarjeta está el inglés: es lo que va en serif y lo que se
/// copia. No siempre es el mismo campo: depende del modo y del caso.
enum EnglishSide: Equatable {
    case source, result, both

    init(origin: String, kind: String?) {
        switch origin {
        case "system":
            self = .source
        case "screen":
            switch kind.flatMap(CaptureKind.init(rawValue:)) {
            case .translate: self = .result
            case .correct: self = .both
            default: self = .source    // entender, o una fila sin caso
            }
        default:
            self = .result             // voz: dices en español, sale en inglés
        }
    }

    var sourceIsEnglish: Bool { self != .result }
    var resultIsEnglish: Bool { self != .source }
}

extension StoredCard {
    var englishSide: EnglishSide { EnglishSide(origin: origin, kind: kind) }

    /// Lo que copia «Copiar el inglés». En una corrección, la versión corregida.
    var englishText: String { englishSide == .source ? source : result }

    /// El otro lado: el español, o el borrador en una corrección.
    var otherText: String { englishSide == .source ? result : source }
}

/// El icono y el nombre de cada origen en el historial. Sustituyen al emoji.
enum CardOriginStyle {
    static func symbol(origin: String) -> String {
        switch origin {
        case "screen": "crop"
        case "system": "captions.bubble"
        default: "mic"
        }
    }

    static func name(origin: String, kind: String?) -> String {
        switch origin {
        case "screen": kind.flatMap(CaptureKind.init(rawValue:))?.title ?? "Captura"
        case "system": "Subtítulos"
        default: "Voz"
        }
    }
}
```

En `App/CaptureKind+UI.swift`, añade al `extension CaptureKind`:

```swift
    /// El nombre del caso, sin icono: el historial pone el suyo.
    var title: String {
        switch self {
        case .understand: "Para entender"
        case .correct:    "Corrección"
        case .translate:  "Traducción"
        case .skip:       "Sin texto"
        }
    }
```

En `App/Studio/HistorySection.swift`, añade a `enum HistoryFilter`:

```swift
    /// El filtro de modo y el de favoritas se combinan.
    func includes(origin: String, isFavorite: Bool, favoritesOnly: Bool) -> Bool {
        includes(origin: origin) && (!favoritesOnly || isFavorite)
    }
```

- [ ] **Step 4: Comprobar que pasan**

Run: `make test-app 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, 103 tests (94 + 9).

- [ ] **Step 5: La fila y la sección**

`App/Studio/HistoryRow.swift`:

```swift
import SwiftUI

struct HistoryRow: View {
    let card: StoredCard
    let onToggleFavorite: () -> Void

    private var side: EnglishSide { card.englishSide }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: CardOriginStyle.symbol(origin: card.origin))
                    Text(CardOriginStyle.name(origin: card.origin, kind: card.kind))
                    Text(card.createdAt, format: .dateTime.day().month().hour().minute())
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(card.source)
                    .font(side.sourceIsEnglish ? Theme.english(.body) : .callout)
                    .foregroundStyle(.secondary)
                Text(card.result.isEmpty ? "(sin traducción)" : card.result)
                    .font(side.resultIsEnglish ? Theme.english(.title3) : .headline)

                ForEach(Array(card.why.enumerated()), id: \.offset) { _, line in
                    Text("• \(line)").font(.callout)
                }
                if !card.vocab.isEmpty {
                    Text(card.vocab.map(\.term).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
            }
            Spacer(minLength: 0)
            Button(action: onToggleFavorite) {
                Image(systemName: card.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(card.isFavorite ? Theme.accent : .secondary)
            }
            .buttonStyle(.borderless)
            .help(card.isFavorite ? "Quitar de favoritas" : "Marcar como favorita")
        }
        .padding(.vertical, 6)
    }
}
```

En `App/Studio/HistorySection.swift`:
- añade `import AppKit` junto a los otros imports, porque el portapapeles lo necesita;
- sustituye la struct `HistorySection` entera por la de abajo y deja `HistoryFilter` como está.

```swift
struct HistorySection: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredCard.createdAt, order: .reverse) private var cards: [StoredCard]
    @State private var search = ""
    @State private var filter: HistoryFilter = .all
    @State private var favoritesOnly = false
    @State private var pendingDeletion: StoredCard?

    private var filtered: [StoredCard] {
        let visible = cards.filter {
            filter.includes(origin: $0.origin, isFavorite: $0.isFavorite, favoritesOnly: favoritesOnly)
        }
        guard !search.isEmpty else { return visible }
        return visible.filter {
            $0.source.localizedStandardContains(search)
                || $0.result.localizedStandardContains(search)
        }
    }

    var body: some View {
        Group {
            if cards.isEmpty {
                ContentUnavailableView(
                    "Tus frases aparecerán aquí",
                    systemImage: "character.bubble",
                    description: Text("Cada traducción, captura o subtítulo se guarda en el historial."))
            } else if filtered.isEmpty, !search.isEmpty {
                ContentUnavailableView.search(text: search)
            } else if filtered.isEmpty {
                ContentUnavailableView("Nada con este filtro",
                                       systemImage: "line.3.horizontal.decrease.circle")
            } else {
                List(filtered) { card in
                    HistoryRow(card: card) { toggleFavorite(card) }
                        .contextMenu {
                            Button("Copiar el inglés") { copyEnglish(card) }
                            Divider()
                            Button("Borrar…", role: .destructive) { pendingDeletion = card }
                        }
                }
            }
        }
        .searchable(text: $search, prompt: "Buscar en tus frases")
        .toolbar {
            ToolbarItemGroup {
                Picker("Mostrar", selection: $filter) {
                    ForEach(HistoryFilter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle(isOn: $favoritesOnly) {
                    Label("Solo favoritas", systemImage: favoritesOnly ? "star.fill" : "star")
                }
                .help("Solo favoritas")
            }
        }
        .confirmationDialog("¿Borrar esta frase?",
                            isPresented: Binding(get: { pendingDeletion != nil },
                                                 set: { if !$0 { pendingDeletion = nil } }),
                            presenting: pendingDeletion) { card in
            Button("Borrar", role: .destructive) { delete(card) }
        } message: { _ in
            Text("No se puede deshacer.")
        }
    }

    private func toggleFavorite(_ card: StoredCard) {
        card.isFavorite.toggle()
        try? context.save()
    }

    private func delete(_ card: StoredCard) {
        context.delete(card)
        try? context.save()
        pendingDeletion = nil
    }

    private func copyEnglish(_ card: StoredCard) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(card.englishText, forType: .string)
    }
}
```

Si la sonda 4 decidió la cabecera:
- quita `.searchable` y `.toolbar`;
- envuelve el `Group` en un `VStack(spacing: 0)` cuyo primer hijo sea esta cabecera, seguida de un `Divider()`:

```swift
                HStack(spacing: 10) {
                    Picker("Mostrar", selection: $filter) {
                        ForEach(HistoryFilter.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Toggle(isOn: $favoritesOnly) {
                        Label("Solo favoritas", systemImage: favoritesOnly ? "star.fill" : "star")
                    }
                    .toggleStyle(.button)
                    TextField("Buscar en tus frases", text: $search)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(10)
```

- [ ] **Step 6: Comprobar la suite y verlo**

Run: `make test-app 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, 103 tests.

Run: `make run`. Abre Estudio y haz una captura de pantalla. Con computer-use:
- marca una estrella y activa «Solo favoritas»;
- clic derecho en una fila → «Copiar el inglés»;
- clic derecho → «Borrar…» y luego cancela.

Expected:
- las filas llevan el icono del modo y el inglés en serif;
- la estrella filtra;
- el diálogo de borrar pide confirmación.

Comprueba el portapapeles con `pbpaste`.

- [ ] **Step 7: Commit**

```bash
git add App/Studio App/CaptureKind+UI.swift AppTests/EnglishSideTests.swift AppTests/HistoryFilterTests.swift
git commit -m "feat: historial con inglés en serif, iconos de modo, favoritas y borrado

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Menú emergente

**Files:**
- Create: `App/MenuBar/ModeTile.swift`
- Create: `App/MenuBar/MenuBarPopover.swift`
- Create: `App/MenuBar/NoticeRows.swift`
- Create: `App/MenuBar/LastPhraseView.swift`
- Create: `AppTests/ModeTileTests.swift`
- Modify: `App/ParlaApp.swift` (estilo ventana; fuera `MenuBarView`)
- Modify: `App/DebugHooks.swift` (abrir el menú emergente y forzar la apariencia)

**Interfaces:**
- Consumes:
  - de la Task 9, `NoticeList`, `AppState.runtimeNotices`, `dismiss(_:)`, `isBlocked(_:)` y `blockedMode`;
  - de la Task 6, `SetupIssueRow`;
  - de la Task 8, `ParlaMode.shortcutName` y `WindowCoordinator.showStudio(_:)`;
  - de la Task 10, `StoredCard.englishText` y `otherText`.
- Produces: `struct ModeTileModel: Equatable { init(mode:isActive:shortcut:); title; symbol; caption }`.

- [ ] **Step 1: Escribir los tests**

`AppTests/ModeTileTests.swift`:

```swift
import Testing
import ParlaCore
@testable import Parla

@Test func unModoApagadoEnsenaSuAtajo() {
    let tile = ModeTileModel(mode: .capture, isActive: false, shortcut: "⌃⌥C")
    #expect(tile.title == "Captura")
    #expect(tile.caption == "⌃⌥C")
}

@Test func laVozEncendidaDiceEscuchando() {
    let tile = ModeTileModel(mode: .voice, isActive: true, shortcut: "⌃⌥Space")
    #expect(tile.caption == "Escuchando")
    #expect(tile.symbol == "mic.fill")
}

@Test func losSubtitulosEncendidosDicenActivos() {
    let tile = ModeTileModel(mode: .subtitles, isActive: true, shortcut: "⌃⌥S")
    #expect(tile.caption == "Activos")
    #expect(tile.symbol == "captions.bubble.fill")
}

@Test func sinAtajoLoDice() {
    #expect(ModeTileModel(mode: .voice, isActive: false, shortcut: nil).caption == "Sin atajo")
}
```

- [ ] **Step 2: Comprobar que fallan**

Run: `make test-app 2>&1 | tail -20`
Expected: no compila, `cannot find 'ModeTileModel' in scope`.

- [ ] **Step 3: Implementar el botón de modo**

`App/MenuBar/ModeTile.swift`:

```swift
import SwiftUI
import ParlaCore

/// Lo que enseña cada botón de modo, fuera de la vista para probarlo.
struct ModeTileModel: Equatable {
    let mode: ParlaMode
    let isActive: Bool
    let shortcut: String?

    var title: String {
        switch mode {
        case .voice: "Voz"
        case .capture: "Captura"
        case .subtitles: "Subtítulos"
        }
    }

    var symbol: String {
        switch mode {
        case .voice: isActive ? "mic.fill" : "mic"
        case .capture: "crop"
        case .subtitles: isActive ? "captions.bubble.fill" : "captions.bubble"
        }
    }

    /// Encendido, el estado; apagado, el atajo para encenderlo sin abrir esto.
    var caption: String {
        if isActive { return mode == .voice ? "Escuchando" : "Activos" }
        return shortcut ?? "Sin atajo"
    }
}

struct ModeTile: View {
    let model: ModeTileModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: model.symbol).font(.title2)
                Text(model.title).font(.callout.weight(.medium))
                Text(model.caption)
                    .font(.caption2)
                    .foregroundStyle(model.isActive ? Theme.onAccent : Color.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .foregroundStyle(model.isActive ? Theme.onAccent : Color.primary)
            .background(model.isActive ? Theme.accent : Color.secondary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(model.title), \(model.caption)")
    }
}
```

- [ ] **Step 4: Comprobar que pasan**

Run: `make test-app 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, 107 tests (103 + 4).

- [ ] **Step 5: Las filas, la última frase y el menú emergente**

`App/MenuBar/NoticeRows.swift`:

```swift
import SwiftUI

/// Un error de la sesión, con «Descartar». El texto ya es legible: nunca es la
/// descripción en bruto de un error.
struct RuntimeNoticeRow: View {
    let notice: RuntimeNotice
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .frame(width: 18)
            Text(notice.text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Descartar", action: onDismiss)
                .controlSize(.small)
        }
    }
}
```

`App/MenuBar/LastPhraseView.swift`:

```swift
import SwiftUI

struct LastPhraseView: View {
    let card: StoredCard
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Última frase")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(card.englishText)
                    .font(Theme.english(.body))
                    .lineLimit(2)
                if !card.otherText.isEmpty {
                    Text(card.otherText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Abrir en Estudio")
    }
}
```

`App/MenuBar/MenuBarPopover.swift`:

```swift
import SwiftUI
import SwiftData
import KeyboardShortcuts
import ParlaCore

struct MenuBarPopover: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Query(MenuBarPopover.lastCard) private var last: [StoredCard]

    static var lastCard: FetchDescriptor<StoredCard> {
        var descriptor = FetchDescriptor<StoredCard>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return descriptor
    }

    private var notices: NoticeList {
        NoticeList(runtime: state.runtimeNotices,
                   issues: state.setup.status.issues,
                   priority: state.blockedMode.map { state.setup.status.startBlockers(for: $0) } ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ModeTile(model: tile(.voice)) { toggle(.voice) }
                ModeTile(model: tile(.capture)) { capture() }
                ModeTile(model: tile(.subtitles)) { toggle(.subtitles) }
            }

            if !notices.visible.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(notices.visible) { notice in
                        switch notice {
                        case .setup(let issue):
                            SetupIssueRow(issue: issue, setup: state.setup) { open(.settings) }
                        case .runtime(let runtime):
                            RuntimeNoticeRow(notice: runtime) { state.dismiss(runtime) }
                        }
                    }
                    if notices.hiddenCount > 0 {
                        Button(notices.hiddenCount == 1 ? "y 1 más" : "y \(notices.hiddenCount) más") {
                            open(nil)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            if state.mode == .batch, !state.pending.isEmpty {
                Button(state.pending.count == 1
                       ? "Traducir 1 frase"
                       : "Traducir \(state.pending.count) frases") {
                    state.sendBatch()
                }
                .disabled(state.isSendingBatch)
                .frame(maxWidth: .infinity)
            }

            if let card = last.first {
                Divider()
                LastPhraseView(card: card) { open(.history) }
            }

            Divider()
            HStack {
                Button("Abrir Estudio") { open(nil) }
                Spacer()
                Button { open(.settings) } label: { Image(systemName: "gearshape") }
                    .help("Ajustes")
                Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Salir de Parla")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .frame(width: 300)
        .task { await state.setup.refresh() }
        .background {
            Button("Ajustes") { open(.settings) }
                .keyboardShortcut(",", modifiers: .command)
                .hidden()
        }
    }

    private func tile(_ mode: ParlaMode) -> ModeTileModel {
        let isActive = switch mode {
        case .voice: state.isListening
        case .subtitles: state.isSubtitling
        case .capture: false
        }
        return ModeTileModel(mode: mode, isActive: isActive,
                             shortcut: KeyboardShortcuts.getShortcut(for: mode.shortcutName)?.description)
    }

    /// Apagar siempre se puede. Encender con algo pendiente no arranca: los
    /// avisos ya están a la vista y lo que lo impide sube arriba.
    private func toggle(_ mode: ParlaMode) {
        let isOn = mode == .voice ? state.isListening : state.isSubtitling
        guard isOn || !state.isBlocked(mode) else { return }
        if mode == .voice {
            state.toggleListening()
        } else {
            state.toggleSubtitles()
        }
    }

    /// La cruz no debe tener el menú emergente delante.
    private func capture() {
        guard !state.isBlocked(.capture) else { return }
        dismiss()
        state.captureScreen()
    }

    private func open(_ section: StudioSection?) {
        dismiss()
        state.windows.showStudio(section)
    }
}
```

Si la sonda 1 decidió `MenuBarWindow.close()`:
- crea `App/MenuBar/MenuBarWindow.swift` con el código de abajo, usando el nombre de clase que anotó la sonda;
- en `capture()` y en `open(_:)`, llama a `MenuBarWindow.close()` justo después de `dismiss()`.

```swift
import AppKit

/// Cierra la ventana del menú emergente: `dismiss()` no siempre la cierra
/// (sonda 1), y la cruz de captura no debe tenerla delante.
@MainActor
enum MenuBarWindow {
    static func close() {
        for window in NSApp.windows where window.className.contains("MenuBarExtra") {
            window.orderOut(nil)
        }
    }
}
```

- [ ] **Step 6: Cablear `ParlaApp` y `DebugHooks`**

En `App/ParlaApp.swift`, la escena pasa a:

```swift
    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(state: state)
                .modelContainer(Persistence.container)
        } label: {
            // Un solo símbolo: qué modo está activo se ve en el menú emergente.
            Image(systemName: state.isListening || state.isSubtitling
                  ? "character.bubble.fill" : "character.bubble")
        }
        .menuBarExtraStyle(.window)
    }
```

Borra la struct `MenuBarView` entera. Si `SwiftData` vuelve a hacer falta por `.modelContainer`, mantén `import SwiftData`.

En `App/DebugHooks.swift`:
- sustituye la documentación y el `guard let title = environment["PARLA_CLICK_MENU"]` de `install()`, el `clickMenuItem(titled:)` de la tarea y la función `clickMenuItem` entera por lo de abajo;
- conserva `logWindows` y la línea de tiempo de activación;
- añade el forzado de apariencia al principio de `install()`.

```swift
    /// `PARLA_OPEN_MENU=1` y `PARLA_CLICK_AFTER=4`: a los 4 s abre el menú
    /// emergente, igual que un clic en el icono.
    /// `PARLA_APPEARANCE=dark` (o `light`): fuerza la apariencia de la app, para
    /// revisar los dos modos sin tocar los ajustes del sistema.
    static func install() {
        let environment = ProcessInfo.processInfo.environment
        if environment["PARLA_PROBE_AUDIO"] == "1" { probeAudio() }
        switch environment["PARLA_APPEARANCE"] {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        guard environment["PARLA_OPEN_MENU"] == "1" else { return }
        let delay = environment["PARLA_CLICK_AFTER"].flatMap(Double.init) ?? 4

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            logWindows("antes")
            openMenuBarWindow()
            for milliseconds in [50, 150, 300, 500, 500] {
                try? await Task.sleep(for: .milliseconds(milliseconds))
                let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
                Log.pipeline.info("hook: activa=\(NSApp.isActive) "
                    + "clave=«\(NSApp.keyWindow?.title ?? "ninguna")» al frente=\(front)")
            }
            logWindows("después")
        }
    }

    private static func openMenuBarWindow() {
        let buttons = NSApp.windows
            .filter { $0.className.contains("StatusBar") }
            .compactMap { ($0.value(forKey: "statusItem") as? NSStatusItem)?.button }
        Log.pipeline.info("hook: \(buttons.count) botón(es) de barra")
        buttons.forEach { $0.performClick(nil) }
    }
```

- [ ] **Step 7: Comprobar la suite y verlo**

Run: `make test-app 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, 107 tests.

Run: `make build`. Después, desde la terminal:

```bash
APP="$(xcodebuild -project Parla.xcodeproj -scheme Parla -configuration Debug -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2}')/Parla.app"
pkill -f 'Parla.app/Contents/MacOS/Parla'; PARLA_OPEN_MENU=1 PARLA_CLICK_AFTER=3 "$APP/Contents/MacOS/Parla" &
```

Espera 5 s y haz una captura de pantalla.
Expected:
- el menú emergente está abierto, con los tres botones y sus atajos;
- los avisos aparecen si falta algo, porque la compilación nueva no tiene permisos;
- la última frase va en serif;
- el pie lleva Abrir Estudio, el engranaje y Salir.

Con computer-use:
- pulsa Captura: el menú emergente se cierra y sale la cruz o el aviso de permiso. Pulsa Esc para cerrarla;
- reabre el menú y pulsa el engranaje: Estudio aparece en Ajustes.

- [ ] **Step 8: Commit**

```bash
git add App/MenuBar App/ParlaApp.swift App/DebugHooks.swift AppTests/ModeTileTests.swift
git commit -m "feat: menú emergente con los tres modos, avisos y la última frase

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Bienvenida

**Files:**
- Create: `App/Welcome/WelcomeFlow.swift`
- Create: `App/Welcome/WelcomeView.swift`
- Create: `AppTests/WelcomeFlowTests.swift`
- Modify: `App/AppState.swift` (`welcomeContent`, `showWelcomeIfFirstLaunch()`)
- Modify: `App/ParlaApp.swift` (abrirla al terminar el arranque)
- Modify: `App/Studio/SettingsSection.swift` (botón «Ver la bienvenida otra vez»)

**Interfaces:**
- Consumes:
  - de la Task 7, `APIKeyEntry` y `KeyCheck.message`;
  - de la Task 8, `WindowCoordinator.showWelcome()`, `closeWelcome()` y `welcomeDidClose()`;
  - de la Task 6, `SetupMonitor` y `SetupIssueRow`;
  - de la Task 8, `ParlaMode.shortcutName`.
- Produces:

```swift
enum WelcomeStep: Int, CaseIterable { case hello, key, permissions, ready }
struct WelcomeFlow: Equatable {
    private(set) var step: WelcomeStep
    private(set) var keyMessage: String?
    var isLast: Bool
    mutating func advance()
    mutating func keySubmitted(_ check: KeyCheck?, hasSavedKey: Bool)
}
AppState.showWelcomeIfFirstLaunch()
```

- [ ] **Step 1: Escribir los tests**

`AppTests/WelcomeFlowTests.swift`:

```swift
import Testing
import Foundation
import SwiftUI
import ParlaCore
@testable import Parla

@Test func empiezaPorElSaludo() {
    #expect(WelcomeFlow().step == .hello)
}

@Test func ahoraNoAvanzaHastaElFinalYAhiSeQueda() {
    var flow = WelcomeFlow()
    flow.advance()
    #expect(flow.step == .key)
    flow.advance()
    flow.advance()
    #expect(flow.step == .ready)
    #expect(flow.isLast)
    flow.advance()
    #expect(flow.step == .ready)
}

@Test func unaClaveBuenaPasaALosPermisos() {
    var flow = WelcomeFlow()
    flow.advance()
    flow.keySubmitted(.valid, hasSavedKey: true)
    #expect(flow.step == .permissions)
    #expect(flow.keyMessage == nil)
}

@Test func unaClaveRechazadaSeQuedaEnElPasoConElMotivo() {
    var flow = WelcomeFlow()
    flow.advance()
    flow.keySubmitted(.invalid, hasSavedKey: false)
    #expect(flow.step == .key)
    #expect(flow.keyMessage == KeyCheck.invalid.message)
}

@Test func sinRedAvanzaYLoAvisaUnaSolaVez() {
    var flow = WelcomeFlow()
    flow.advance()
    flow.keySubmitted(.unverified, hasSavedKey: true)
    #expect(flow.step == .permissions)
    #expect(flow.keyMessage == KeyCheck.unverified.message)
    flow.advance()
    #expect(flow.keyMessage == nil)
}

@Test func continuarConElCampoVacioYUnaClaveGuardadaAvanza() {
    var flow = WelcomeFlow()
    flow.advance()
    flow.keySubmitted(nil, hasSavedKey: true)
    #expect(flow.step == .permissions)
}

@Test func continuarSinNingunaClavePideUna() {
    var flow = WelcomeFlow()
    flow.advance()
    flow.keySubmitted(nil, hasSavedKey: false)
    #expect(flow.step == .key)
    #expect(flow.keyMessage == "Pega tu clave o pulsa «Ahora no».")
}

@Test @MainActor func cerrarLaVentanaDeBienvenidaLaDaPorVista() {
    let name = "parla-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let preferences = Preferences(defaults: defaults)
    let coordinator = WindowCoordinator(preferences: preferences,
                                        studioContent: { _ in AnyView(EmptyView()) },
                                        welcomeContent: { AnyView(EmptyView()) })
    coordinator.showWelcome()
    #expect(!preferences.hasSeenWelcome)
    // Igual que el botón rojo de la ventana, a mitad de cualquier paso.
    coordinator.closeWelcome()
    #expect(preferences.hasSeenWelcome)
}
```

- [ ] **Step 2: Comprobar que fallan**

Run: `make test-app 2>&1 | tail -20`
Expected: no compila, `cannot find 'WelcomeFlow' in scope`.

- [ ] **Step 3: Implementar el flujo**

`App/Welcome/WelcomeFlow.swift`:

```swift
import ParlaCore

enum WelcomeStep: Int, CaseIterable {
    case hello, key, permissions, ready
}

/// El avance de la bienvenida, sin vista, para poder probarlo.
struct WelcomeFlow: Equatable {
    private(set) var step: WelcomeStep = .hello
    /// Lo que se dice bajo el campo de la clave o, si la clave se guardó sin
    /// comprobar, al principio del paso siguiente.
    private(set) var keyMessage: String?

    var isLast: Bool { step == .ready }

    /// «Ahora no» y «Continuar» en los pasos sin campo.
    mutating func advance() {
        keyMessage = nil
        if let next = WelcomeStep(rawValue: step.rawValue + 1) { step = next }
    }

    /// «Continuar» en el paso de la clave, con lo que respondió `APIKeyEntry`.
    /// `nil` es campo vacío: vale si ya había una clave guardada.
    mutating func keySubmitted(_ check: KeyCheck?, hasSavedKey: Bool) {
        switch check {
        case .valid?:
            advance()
        case .unverified?:
            advance()
            keyMessage = KeyCheck.unverified.message
        case .invalid?:
            keyMessage = KeyCheck.invalid.message
        case nil:
            if hasSavedKey {
                advance()
            } else {
                keyMessage = "Pega tu clave o pulsa «Ahora no»."
            }
        }
    }
}
```

- [ ] **Step 4: Comprobar que pasan**

Run: `make test-app 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, 115 tests (107 + 8).

- [ ] **Step 5: La vista**

`App/Welcome/WelcomeView.swift`:

```swift
import SwiftUI
import KeyboardShortcuts
import ParlaCore

struct WelcomeView: View {
    @Bindable var state: AppState
    let onFinish: () -> Void
    @State private var flow = WelcomeFlow()
    @State private var keyEntry = APIKeyEntry()

    private var setup: SetupMonitor { state.setup }

    private var hasSavedKey: Bool {
        !setup.status.issues.contains { $0.item == .apiKey }
    }

    private func issue(_ item: SetupItem) -> SetupIssue? {
        setup.status.issues.first { $0.item == item }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ProgressDots(current: flow.step.rawValue, total: WelcomeStep.allCases.count)
                .frame(maxWidth: .infinity)
            Group {
                switch flow.step {
                case .hello: hello
                case .key: key
                case .permissions: permissions
                case .ready: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(24)
        .frame(width: 480, height: 440)
        .task { await setup.refresh() }
    }

    private var hello: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bienvenida a Parla").font(.title.weight(.semibold))
            Text("Tres formas de practicar inglés sin dejar lo que estás haciendo:")
                .foregroundStyle(.secondary)
            ModeLine(symbol: "mic", title: "Voz",
                     text: "Dices una frase en español y te la da en inglés, con el porqué.")
            ModeLine(symbol: "crop", title: "Captura",
                     text: "Seleccionas texto en pantalla y te lo explica, corrige o traduce.")
            ModeLine(symbol: "captions.bubble", title: "Subtítulos",
                     text: "Traduce al momento lo que suena en tu Mac, como un video.")
        }
    }

    private var key: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tu clave de Anthropic").font(.title2.weight(.semibold))
            Text("La voz y las capturas usan Claude. La clave se guarda en el Llavero de tu Mac "
                 + "y solo viaja a Anthropic.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if hasSavedKey {
                Label("Ya hay una clave guardada. Pega otra solo si quieres cambiarla.",
                      systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
            SecureField("sk-ant-…", text: $keyEntry.text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submitKey)
            if keyEntry.isChecking {
                ProgressView("Comprobando la clave…").controlSize(.small)
            }
            if let message = flow.keyMessage {
                Text(message).font(.callout).foregroundStyle(.orange)
            }
            Link("Consigue una clave en la consola de Anthropic",
                 destination: URL(string: "https://console.anthropic.com/settings/keys")!)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permisos").font(.title2.weight(.semibold))
            if let message = flow.keyMessage {
                Text(message).font(.callout).foregroundStyle(.orange)
            }
            PermissionLine(symbol: "mic", title: "Micrófono", reason: "Para el modo voz.",
                           issue: issue(.microphone), setup: setup)
            PermissionLine(symbol: "rectangle.dashed", title: "Grabación de pantalla",
                           reason: "Para las capturas y los subtítulos.",
                           issue: issue(.screenRecording), setup: setup)
            Text("macOS te preguntará al pulsar «Permitir». Puedes cambiarlo cuando quieras en "
                 + "Ajustes del Sistema › Privacidad.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Listo").font(.title2.weight(.semibold))
            if let languages = issue(.languages) {
                SetupIssueRow(issue: languages, setup: setup) {}
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Atajos").font(.headline)
                ForEach(ParlaMode.allCases, id: \.self) { mode in
                    ShortcutLine(mode: mode)
                }
            }
            MenuBarHint()
        }
    }

    private var footer: some View {
        HStack {
            if !flow.isLast {
                Button("Ahora no") { flow.advance() }
            }
            Spacer()
            if flow.isLast {
                Button("Empezar", action: onFinish)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continuar", action: continueTapped)
                    .keyboardShortcut(.defaultAction)
                    .disabled(keyEntry.isChecking)
            }
        }
    }

    private func continueTapped() {
        if flow.step == .key { submitKey() } else { flow.advance() }
    }

    private func submitKey() {
        Task {
            let check = await keyEntry.submit()
            setup.refreshNow()
            flow.keySubmitted(check, hasSavedKey: hasSavedKey)
        }
    }
}

private struct ProgressDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Theme.accent : Color.secondary.opacity(0.3))
                    .frame(width: 22, height: 4)
            }
        }
        .accessibilityLabel("Paso \(current + 1) de \(total)")
    }
}

private struct ModeLine: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(text).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PermissionLine: View {
    let symbol: String
    let title: String
    let reason: String
    let issue: SetupIssue?
    let setup: SetupMonitor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let issue {
                VStack(alignment: .trailing, spacing: 4) {
                    if let label = issue.fix.buttonTitle {
                        Button(label) { Task { await setup.perform(issue.fix) } }
                    }
                    if issue.fix == .openScreenRecordingSettingsOrRelaunch {
                        Button("Reabrir Parla") { setup.relaunch() }
                    }
                }
                .controlSize(.small)
            } else {
                Label("Listo", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ShortcutLine: View {
    let mode: ParlaMode

    var body: some View {
        let model = ModeTileModel(
            mode: mode, isActive: false,
            shortcut: KeyboardShortcuts.getShortcut(for: mode.shortcutName)?.description)
        HStack {
            Label(model.title, systemImage: model.symbol)
            Spacer()
            Text(model.caption).foregroundStyle(.secondary).monospaced()
        }
        .font(.callout)
    }
}

/// macOS no ofrece una forma pública de abrir ni de localizar el icono de otra
/// app en la barra de menús: se enseña con un dibujo.
private struct MenuBarHint: View {
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "wifi")
                Image(systemName: "character.bubble")
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.accent, lineWidth: 1.5))
                Text("12:30")
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            Text("Parla vive aquí, en la barra de menús, arriba a la derecha.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
```

- [ ] **Step 6: Abrirla en el primer arranque, y desde Ajustes**

En `App/AppState.swift`, en `init()`, `welcomeContent:` pasa a:

```swift
            welcomeContent: { [unowned self] in
                AnyView(WelcomeView(state: self, onFinish: { [unowned self] in
                    self.windows.closeWelcome()
                }))
            })
```

y añade el método:

```swift
    /// La primera vez, la bienvenida; las demás, nada.
    func showWelcomeIfFirstLaunch() {
        guard !Preferences.shared.hasSeenWelcome else { return }
        windows.showWelcome()
    }
```

En `App/ParlaApp.swift`, en `init()`, después de registrar los atajos y antes del `#if DEBUG`:

```swift
        // El primer momento en que se puede enseñar una ventana.
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { state.showWelcomeIfFirstLaunch() }
        }
```

En `App/Studio/SettingsSection.swift`, al final del `Form`:

```swift
            Section("Bienvenida") {
                Button("Ver la bienvenida otra vez") { state.windows.showWelcome() }
            }
```

- [ ] **Step 7: Comprobar la suite y verlo**

Run: `make test-app 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, 115 tests.

Run:

```bash
defaults delete ~/Library/Containers/app.schoolaid.Parla/Data/Library/Preferences/app.schoolaid.Parla hasSeenWelcome 2>/dev/null
make run
```

Espera 4 s y haz una captura de pantalla.
Expected: la bienvenida está centrada y delante, en el paso 1, con los puntos de progreso en terracota. Con computer-use:
- **Continuar.** En el paso de la clave se lee «Ya hay una clave guardada…».
- **Continuar** con el campo vacío. Pasa a Permisos, con «Permitir» o «Listo» en cada fila.
- **Continuar.** En Listo están los atajos y el dibujo de la barra.
- **Empezar.** La ventana se cierra.

`make run` otra vez: la bienvenida ya no sale.

- [ ] **Step 8: Commit**

```bash
git add App/Welcome AppTests/WelcomeFlowTests.swift App/AppState.swift App/ParlaApp.swift App/Studio/SettingsSection.swift
git commit -m "feat: bienvenida guiada en el primer arranque

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: README y verificación a mano

**Files:**
- Modify: `README.md` (recuento de tests, Estudio, menú emergente, bienvenida, variables de depuración)

- [ ] **Step 1: README**

En `README.md`:
- **Recuento de tests.** `97 tests de Core` → `119 tests de Core` y `61 tests del target de la app` → `115 tests del target de la app`. Comprueba antes las cifras reales con `make test` y `make test-app`, y usa las que salgan.
- **Variables de depuración.** Sustituye las dos menciones de `PARLA_CLICK_MENU` por `PARLA_OPEN_MENU=1`, que abre el menú emergente al cabo de `PARLA_CLICK_AFTER` segundos. Añade `PARLA_APPEARANCE=dark|light`, que fuerza la apariencia para revisar los dos modos. La de «Capturar pantalla» pasa a: con `PARLA_OPEN_MENU=1` y `PARLA_CAPTURE_FILE`, se pulsa Captura en el menú emergente.
- **Sección de uso.** Añade un párrafo breve:
  - en el primer arranque sale una bienvenida;
  - el icono de la barra abre el menú emergente con los tres modos;
  - Estudio reúne el historial (favoritas, borrar, copiar el inglés) y los ajustes;
  - ⌘, abre Ajustes.

Run: `grep -n "PARLA_CLICK_MENU\|Historial…\|ventana de Ajustes" README.md`
Expected: sin resultados.

- [ ] **Step 2: Suites completas**

Run: `make test 2>&1 | tail -5 && make test-app 2>&1 | tail -5`
Expected: Core `119 tests passed`; App `** TEST SUCCEEDED **` con 115.

- [ ] **Step 3: Primer arranque desde cero**

Pide a Edwin que ejecute en su terminal:

```bash
tccutil reset ScreenCapture app.schoolaid.Parla && tccutil reset Microphone app.schoolaid.Parla
```

Después, run:

```bash
P=~/Library/Containers/app.schoolaid.Parla/Data/Library/Preferences/app.schoolaid.Parla
defaults delete "$P" hasSeenWelcome 2>/dev/null; defaults delete "$P" screenRecordingRequested 2>/dev/null
make install && open /Applications/Parla.app
```

Recorre la bienvenida con computer-use, con una captura en cada paso.
- **Paso de la clave.** Escribe la clave de prueba `sk-ant-prueba-no-valida` (no es la real) y pulsa Continuar. Expected: «Esa clave no funciona…» y te quedas en el paso. Borra el campo y pulsa Continuar: avanza, porque la real está guardada.
- **Permisos.** Pulsa «Permitir» en el micrófono. Pide a Edwin que acepte el diálogo. Expected: la fila pasa a «Listo».
- **Pantalla.** Pulsa «Permitir» en Grabación de pantalla. Pide a Edwin que lo active en Ajustes del Sistema. Expected: al volver a Parla, la fila ofrece «Abrir Ajustes del Sistema» y «Reabrir Parla».
- **Reabrir.** Pulsa «Reabrir Parla». Expected: Parla se reabre y la bienvenida no vuelve a salir, porque cerrarla la dio por vista. En el menú emergente ya no hay aviso de pantalla.

- [ ] **Step 4: Menú emergente, Estudio y apariencia**

- Con el menú emergente:
  - Voz enciende y el botón pasa a terracota con «Escuchando»; otra vez la apaga.
  - Subtítulos con un video de Chrome sonando: la banda aparece.
  - Captura cierra el menú emergente y saca la cruz.
- En Estudio:
  - el historial, con el inglés en serif;
  - una estrella y el filtro de favoritas;
  - «Copiar el inglés» (comprueba con `pbpaste`);
  - borrar con confirmación.
  - Expected: la «Última frase» del menú emergente cambia si borraste la más reciente.
- Apariencia: `pkill -f 'Parla.app/Contents/MacOS/Parla'; PARLA_APPEARANCE=dark /Applications/Parla.app/Contents/MacOS/Parla &`.
  - Ojo: es Debug solo si la instalada es Debug, que es lo que deja `make install`.
  - Abre Estudio y el menú emergente y haz capturas. Expected: el acento claro en oscuro (`#F0997B`) con texto legible sobre el botón activo.
- Icono:
  - `qlmanage -t -s 512 -o "$TMPDIR" /Applications/Parla.app` y míralo;
  - búscalo en Spotlight (⌘Espacio → «Parla») y haz una captura;
  - mira Ajustes del Sistema › Privacidad › Grabación de pantalla.
  - Expected: el icono terracota con «Aa» en los tres sitios.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: Estudio, menú emergente y bienvenida en el README

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Notas para quien ejecute el plan

- **Sondas.** Las decisiones de las sondas 1, 4 y 5 cambian código concreto en las Tasks 8, 10 y 11. Cada bloque alternativo está escrito en su task. Aplica el que diga la nota y deja la ruling en el ledger.
- **Recuentos de tests.** Los «Expected» con recuento asumen que no se ha añadido ni quitado ningún otro test. Si un recuento no cuadra, cuenta los `@Test` del archivo antes de dudar del código.
- **Captura de pantalla.** Cada compilación nueva pierde el permiso de Grabación de pantalla. Si una comprobación a mano lo necesita, pide a Edwin que lo conceda; no lo intentes desde la interfaz del sistema.
- **La clave real** nunca se escribe ni se imprime. Para el caso «clave rechazada» se usa `sk-ant-prueba-no-valida`.
