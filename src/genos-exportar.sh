#!/usr/bin/env bash
# genos-exportar: empaqueta tu tema de GenOs en un .zip y lo deja en Descargas de Windows.
#   genos-exportar [nombre]            exporta (con captura de pantalla si hay escritorio)
#   genos-exportar --importar x.zip    aplica un tema exportado
# El zip trae: captura.png, fondo, perfil de color, ajustes, dock (Plank), CSS de la barra y LEEME.txt.
set -uo pipefail

FONDOS="$HOME/Pictures/GenOs-Fondos"
ESTADO="$HOME/.config/genos-fondo.estado"
AJUSTES="$HOME/.config/genos-personalizacion.json"
GTKCSS="$HOME/.config/gtk-3.0/gtk.css"
ROFI="$HOME/.config/rofi/launchpad.rasi"
BIN="$HOME/.local/bin"
PLANK=/net/launchpad/plank/docks/dock1/

carpeta_descargas() {
  local d
  for d in /mnt/c/Users/*/Downloads; do
    case "$d" in */Public/*|*/Default*/*|*/"All Users"/*) continue ;; esac
    [ -d "$d" ] && { echo "$d"; return; }
  done
  echo "$HOME"
}

importar() {
  local zip=$1 tmp fondo
  [ -f "$zip" ] || { echo "No existe $zip"; exit 1; }
  tmp=$(mktemp -d)
  python3 -I -m zipfile -e "$zip" "$tmp" || { echo "No pude abrir el zip"; exit 1; }
  local raiz; raiz=$(find "$tmp" -name ajustes.json -printf '%h\n' | head -1)
  [ -n "$raiz" ] || { echo "Este zip no parece un tema de GenOs"; exit 1; }
  mkdir -p "$FONDOS" "$(dirname "$AJUSTES")"
  fondo=$(find "$raiz" -maxdepth 1 -name 'fondo.*' | head -1)
  if [ -n "$fondo" ]; then
    cp -f "$fondo" "$FONDOS/importado-$(basename "$raiz").${fondo##*.}"
    fondo="$FONDOS/importado-$(basename "$raiz").${fondo##*.}"
  fi
  cp -f "$raiz/ajustes.json" "$AJUSTES"
  [ -f "$raiz/widgets.json" ] && cp -f "$raiz/widgets.json" "$HOME/.config/genos-widgets.json"
  if [ -f "$raiz/plank.dconf" ] && command -v dconf >/dev/null 2>&1; then
    dconf load "$PLANK" < "$raiz/plank.dconf"
  fi
  # Los ajustes de color viajan como variables para genos-fondo
  eval "$(python3 -I - "$AJUSTES" <<'PY'
import json, shlex, sys
a = json.load(open(sys.argv[1]))
for k, v in (("GENOS_MODO", a.get("modo")), ("GENOS_ACENTO", a.get("acento")), ("GENOS_TEMA", a.get("tema")),
             ("GENOS_OPACIDAD", a.get("opacidad")), ("GENOS_RADIO", a.get("radio"))):
    if v not in (None, ""):
        print("export %s=%s" % (k, shlex.quote(str(v))))
PY
)"
  if [ -n "$fondo" ]; then
    "$BIN/genos-fondo" "$fondo"
  else
    echo "El zip no traía fondo; se guardaron los ajustes."
  fi
  rm -rf "$tmp"
  echo "Tema importado. Abre Configuración para ver el resto de ajustes."
}

if [ "${1:-}" = "--importar" ]; then
  importar "${2:?falta el archivo .zip}"
  exit 0
fi

nombre=${1:-GenOs-Tema-$(date +%Y%m%d-%H%M)}
nombre=${nombre//[^A-Za-z0-9._-]/_}
dest=$(carpeta_descargas)
tmp=$(mktemp -d)
pq="$tmp/$nombre"
mkdir -p "$pq"

# Captura del escritorio (si hay pantalla)
if [ -n "${DISPLAY:-}" ] && command -v import >/dev/null 2>&1; then
  import -window root "$pq/captura.png" 2>/dev/null || echo "No pude sacar la captura."
else
  echo "Sin escritorio a la vista: el zip va sin captura."
fi

# Fondo actual
actual=""
[ -f "$ESTADO" ] && actual=$(head -1 "$ESTADO")
if [ -n "$actual" ] && [ -f "$actual" ]; then
  cp -f "$actual" "$pq/fondo.${actual##*.}"
  "$BIN/genos-fondo" --perfil "$actual" > "$pq/perfil.txt" 2>/dev/null || true
fi

[ -f "$AJUSTES" ] && cp -f "$AJUSTES" "$pq/ajustes.json" || echo '{}' > "$pq/ajustes.json"
[ -f "$HOME/.config/genos-widgets.json" ] && cp -f "$HOME/.config/genos-widgets.json" "$pq/widgets.json"
command -v dconf >/dev/null 2>&1 && dconf dump "$PLANK" > "$pq/plank.dconf" 2>/dev/null
[ -f "$GTKCSS" ] && sed -n '\|>>> xfce-estetica >>>|,\|<<< xfce-estetica <<<|p' "$GTKCSS" > "$pq/barra.css"
[ -f "$ROFI" ] && cp -f "$ROFI" "$pq/lanzador.rasi"
if command -v xfconf-query >/dev/null 2>&1; then
  { xfconf-query -c xfwm4 -lv; xfconf-query -c xsettings -lv; } > "$pq/xfconf.txt" 2>/dev/null
fi

cat > "$pq/LEEME.txt" <<TXT
Tema de GenOs: $nombre
Exportado el $(date '+%Y-%m-%d %H:%M')

captura.png    Cómo se veía el escritorio al exportar.
fondo.*        El fondo que usa el tema.
perfil.txt     Modo, acento, tema GTK y colores calculados para ese fondo.
ajustes.json   Tus ajustes de Configuración (barra, dock, ventanas, texto).
plank.dconf    Configuración del dock.
widgets.json   Qué widgets de escritorio están activos, dónde y a qué tamaño.
barra.css      Estilo de las pastillas de la barra superior.
lanzador.rasi  Estilo del lanzador de aplicaciones.
xfconf.txt     Volcado de ajustes de ventanas y apariencia, solo para consulta.

Para usarlo en otra instalación de GenOs: genos-exportar --importar $nombre.zip
TXT

python3 -I -m zipfile -c "$dest/$nombre.zip" "$pq" >/dev/null 2>&1 || { echo "No pude crear el zip"; rm -rf "$tmp"; exit 1; }
[ -f "$pq/captura.png" ] && cp -f "$pq/captura.png" "$dest/$nombre.png"
rm -rf "$tmp"

echo "Exportado: $dest/$nombre.zip"
[ -f "$dest/$nombre.png" ] && echo "Captura:   $dest/$nombre.png"
