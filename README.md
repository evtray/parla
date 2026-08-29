# Parla

App de macOS que escucha lo que dices en español y muestra, en una ventana
flotante sobre cualquier aplicación, cómo se diría en inglés **y por qué se dice
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
| Traducción y explicación | API de Anthropic, `claude-opus-5` |
| Historial | SQLite local vía SwiftData |

**Tu audio nunca sale del equipo.** Solo viaja el texto transcrito.

## Requisitos

- macOS 26 o posterior
- Xcode 26 (solo para compilar)
- Una clave de API de Anthropic — se guarda en el Llavero, nunca en disco

## Uso

1. Abre Parla. Vive en la barra de menú, no en el Dock.
2. Ajustes → pega tu clave de API y elige un atajo global.
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

## Compilar

```bash
make test      # 51 tests
make run       # compila y lanza
make install   # deja la app en /Applications
make release   # dist/Parla-X.Y.Z.zip
```

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

### Si no transcribe nada

El panel avisa cuando el dispositivo de entrada no entrega audio. La causa más
común es un auricular Bluetooth: macOS lo mantiene en modo A2DP (solo salida) y su
micrófono no produce ni un buffer. Elige otra entrada en Ajustes del Sistema →
Sonido.

## Ajustes que querrás tocar

`UtteranceSegmenter.Config.silenceGap` (0,9 s) decide cuándo termina una frase. Si
te corta a la mitad, súbelo; si tarda en reaccionar, bájalo. Está en un solo sitio
a propósito.

`ClaudeRequestBuilder.chunkSize` (20) es cuántas frases caben en una petición de
lote. Subirlo ahorra peticiones pero arriesga que la respuesta no quepa en
`batchMaxTokens` y el modelo corte una tarjeta a la mitad.
