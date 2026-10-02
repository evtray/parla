#!/bin/bash
# Regenera las capturas de muestra a partir de las páginas de fuentes/.
# Escala 2 para que se parezcan a una captura de una pantalla Retina.
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for html in fuentes/*.html; do
  name=$(basename "$html" .html)
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=2 --window-size=900,500 \
    --screenshot="$PWD/$name.png" "file://$PWD/$html" >/dev/null 2>&1
  echo "$name.png"
done
