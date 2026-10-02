# Sondas de Estudio y primer uso (2026-10-02)

Spec §10. Cada sonda: pregunta, cómo se probó, resultado y decisión.

| # | Pregunta | Resultado | Decisión |
|---|----------|-----------|----------|
| 1 | ¿`dismiss()` cierra el `MenuBarExtra` de estilo ventana? | Sí: visible antes (`_TtGC7SwiftUI18MenuBarExtraWindowVS_7AnyView_`, key) y no visible 300 ms después. Abrirlo por código con `performClick` solo funciona si antes se activa la app; si no, se cierra solo al no ser la ventana clave. | Basta `dismiss()`: no hace falta `MenuBarWindow.close()`. El gancho de depuración que abre el menú emergente activa la app antes del clic. |
| 2 | ¿Consultar si existe la clave, sin pedir sus datos, evita el diálogo del Llavero? | Sí: compilación nueva sin `PARLA_API_KEY`, el log dice `hasAPIKey=true` y no hay proceso `SecurityAgent` (ningún diálogo). | `hasAPIKey` consulta el Llavero directamente. |
| 3 | ¿Qué formato de icono se ve en Finder con la forma del sistema y sin placa gris? | `AppIcon.appiconset` a sangre completa: macOS 26 lo recorta a su forma redondeada con borde de cristal, sin placa gris (comprobado con `NSWorkspace.icon(forFile:)` y en Finder, junto a Pages). `qlmanage` se cuelga y no sirvió. | Appiconset a sangre completa generado por `scripts/make-icon.swift`; no hace falta Icon Composer. |
| 4 | En una `NSWindow` con `NSHostingController`, ¿se ven la barra de herramientas y la búsqueda, y la ventana queda delante al arrancar? | Sí: abierta en `didFinishLaunching`, la app queda activa y al frente, la ventana es la clave, la barra tiene 2 elementos (selector y búsqueda) y el título pasa a la ventana. | Barra de herramientas y `.searchable`, como en el plan; no hace falta la cabecera. |
| 5 | ¿Un botón oculto con `.keyboardShortcut(",")` responde a ⌘, en esa ventana? | Sí: un ⌘, enviado con `NSApp.sendEvent` llega al botón oculto y cambia la sección. | Atajo dentro de la vista; no hace falta el monitor de teclado. |

## Cómo se comprobó lo visual

Las herramientas de captura de pantalla de fuera no ven las ventanas de Parla (una app de la barra de menús no se puede autorizar para ellas). En Debug, `PARLA_SNAPSHOT_AFTER=3,8` hace que Parla guarde una imagen de cada ventana visible en `~/Library/Containers/app.schoolaid.Parla/Data/tmp/parla-snapshots/`. Limitación: las superficies de cristal (barra lateral, controles de la barra de herramientas) salen en blanco; la estructura y los textos se ven bien.
