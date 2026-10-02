# Parla

App de macOS que escucha lo que dices en español, o lee lo que capturas de la
pantalla, y muestra, en una ventana flotante sobre cualquier aplicación, cómo se diría en inglés **y por qué se dice
así**.

El objetivo no es traducir: es aprender. Cada tarjeta explica en qué se diferencia
lo que dijiste de lo que el inglés exige — falsos amigos, preposición regida,
tiempo verbal, orden de palabras.

```
┌──────────────────────────────────────────────┐
│ «necesito que me avises cuando llegues»      │
│                                              │
│ I need you to let me know when you get in.   │
│                                              │
│ • "Avisar" casi nunca es "advise": eso       │
│   significa aconsejar. Aquí es "let me know".│
│ • Tras "when" con sentido de futuro, el      │
│   inglés usa presente: "when you get in".    │
│                                              │
│  let me know   get in                        │
└──────────────────────────────────────────────┘
```

## Cómo funciona

| Etapa | Dónde corre |
|---|---|
| Transcripción de voz | **En tu Mac.** `SpeechAnalyzer` (macOS 26), sin conexión |
| Traducción y explicación | API de Anthropic, con el modelo que elijas (Opus 5.5 por defecto) |
| Lectura de capturas | API de Anthropic: la imagen de la región que seleccionas |
| Historial | SQLite local vía SwiftData |

**Tu audio nunca sale del equipo.** Solo viaja el texto transcrito.

**Las capturas sí salen:** la imagen de la región que seleccionas viaja a la API.
No se guarda en tu Mac; al historial va solo el texto que Claude leyó en ella.

## Requisitos

- macOS 26 o posterior
- Xcode 26 (solo para compilar)
- Una clave de API de Anthropic — se guarda en el Llavero, nunca en disco

## Uso

1. Abre Parla. Vive en la barra de menú, no en el Dock.
2. Ajustes → pega tu clave de API y elige un atajo global. Ahí mismo eliges el
   modelo, el micrófono y la salida de audio del Mac.
3. "Empezar a escuchar" y habla en español.

La escucha es una sesión que enciendes y apagas: no se queda escuchando de fondo.
El panel muestra las tres frases más recientes, la nueva arriba; el resto pasa al
historial, que es buscable.

### Al vuelo o en lote

En Ajustes › **Cuándo traducir** eliges entre dos formas de trabajar:

- **Cada frase al vuelo.** La tarjeta sale unos segundos después de hablar. Una
  petición a la API por frase.
- **Acumular y traducir cuando yo lo pida.** Las frases se quedan en una cola y
  no se manda nada hasta que pulsas «Traducir». Apagar la escucha tampoco manda
  nada: la cola sobrevive.

El lote no solo gasta menos. Como el modelo ve la sesión entera de una vez,
añade un bloque de **patrones**: los errores que repites, con cuántas frases de
cuántas, que es justo lo que no se ve mirando las tarjetas de una en una.

Los lotes de más de 20 frases se parten en varias peticiones. Si una se cae, sus
frases vuelven a la cola con el motivo a la vista y el botón de traducir hace de
reintento; el resto del lote llega igual.

### Capturar la pantalla

Pulsa **⌃⌥C** (o «Capturar pantalla» en el menú de la barra) y arrastra un
rectángulo sobre el texto, como con ⌘⇧4. Esc cancela sin gastar nada. Parla
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

La selección es una capa propia, no la de ⌘⇧4: dentro del sandbox,
`screencapture -i` termina sin mostrar la cruz. La región se captura con
ScreenCaptureKit.

## Compilar

```bash
make test      # 73 tests de Core, sin abrir Xcode
make test-app  # 38 tests del target de la app, alojados en Parla.app
make eval-capture  # manda Core/Fixtures/capturas a la API y cuenta aciertos del caso
make run       # compila y lanza
make install   # deja la app en /Applications
make release   # dist/Parla-X.Y.Z.zip
```

`make eval-capture` necesita `PARLA_API_KEY` y gasta tokens: unas 8 peticiones.
Para añadir una captura real, guárdala en `Core/Fixtures/capturas/` con el caso
esperado al principio del nombre (`correct-09-mi-correo.png`). Las de muestra se
regeneran desde HTML con `Core/Fixtures/capturas/render.sh`.

El proyecto de Xcode se genera desde `project.yml` con
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), así
que no está versionado: `make` lo regenera solo.

### Distribución

`make release` firma la app **ad-hoc**, que es todo lo que permite una máquina sin
certificado Developer ID. Consecuencia: funciona en el Mac donde se compiló, pero
en cualquier otro Gatekeeper la bloqueará. Para abrirla ahí, la primera vez:
clic derecho → Abrir, o `xattr -dr com.apple.quarantine Parla.app`.

Para distribuirla sin advertencias hacen falta un certificado *Developer ID
Application* (Apple Developer Program) y notarizarla con `notarytool`.

## Estructura

```
Core/     paquete SPM sin UI: segmentador de frases, cliente de la API,
          parser SSE. Solo importa Foundation, se prueba en 0,2 s.
App/      target de Xcode: audio, transcripción, panel flotante, persistencia.
docs/     el diseño y el plan de implementación con los que se construyó.
```

La frontera entre ambos es el protocolo `Explainer` y el tipo `Card`. Todo lo que
tiene lógica de verdad vive en `Core` y se prueba sin abrir Xcode.

## Depuración

```bash
# Log en vivo
log stream --predicate 'subsystem == "app.schoolaid.Parla"' --info

# O lanzar desde la terminal con el log en stderr
PARLA_STDERR_LOG=1 PARLA_AUTOSTART=1 /Applications/Parla.app/Contents/MacOS/Parla
```

`PARLA_AUTOSTART=1` enciende la escucha al arrancar, útil para probar sin clicar.
Otras variables para probar sin ratón:

- `PARLA_CLICK_MENU="Ajustes…"` ejecuta ese ítem del menú de la barra al cabo de
  `PARLA_CLICK_AFTER` segundos (4 por defecto) y escribe en el log qué ventanas
  quedaron y si la app se activó.
- `PARLA_CAPTURE_FILE=/ruta.png` salta la selección de región y usa ese archivo.
  La ruta tiene que estar dentro del contenedor del sandbox
  (`~/Library/Containers/app.schoolaid.Parla/Data/tmp/`). Con
  `PARLA_CLICK_MENU="Capturar pantalla"` se prueba el flujo entero sin ratón.
- `PARLA_PROBE_AUDIO=1` lista los dispositivos de audio con su UID y comprueba
  que se puede escribir la salida del sistema (escribe la que ya está puesta).
- Una preferencia se puede cambiar para un solo arranque, sin tocar las
  guardadas, pasándola como argumento: `Parla -model claude-sonnet-5-5
  -inputDeviceUID <uid>`.
- `PARLA_API_KEY=sk-…` usa esa clave y no toca el Llavero. Cada compilación
  firmada ad hoc es una app nueva para el Llavero, que pide contraseña y
  bloquea el hilo principal hasta que respondes; con esto se evita.

### Si no transcribe nada

El panel avisa cuando el dispositivo de entrada no entrega audio. La causa más
común es un auricular Bluetooth: macOS lo mantiene en modo A2DP (solo salida) y su
micrófono no produce ni un buffer. Elige otro micrófono en Ajustes › Audio; vale
para la siguiente vez que enciendas la escucha.

## Ajustes que querrás tocar

`UtteranceSegmenter.Config.silenceGap` (0,9 s) decide cuándo termina una frase. Si
te corta a la mitad, súbelo; si tarda en reaccionar, bájalo. Está en un solo sitio
a propósito.

`ClaudeRequestBuilder.chunkSize` (20) es cuántas frases caben en una petición de
lote. Subirlo ahorra peticiones pero arriesga que la respuesta no quepa en
`batchMaxTokens` y el modelo corte una tarjeta a la mitad.
