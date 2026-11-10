#!/usr/bin/env bash
# genos-fondo: pone un fondo y adapta TODO el diseño a ese fondo.
#   - Modo oscuro o claro según el brillo de la imagen.
#   - Acento tomado del logo (morado, azul, verde). Con logo blanco, negro o café queda gris.
#   - El tema GTK usa la variante de WhiteSur que combina con el acento.
#   - Las pastillas del panel y el lanzador llevan un tinte del color del fondo, y la
#     opacidad sube sola hasta que el texto tenga buen contraste (mínimo 4.5:1).
#   - La terminal toma colores del mismo perfil.
# Uso:
#   genos-fondo              lista los fondos con su perfil
#   genos-fondo --elegir     selector con miniaturas (atajo Ctrl+Alt+F)
#   genos-fondo 7            aplica el fondo número 7 de la lista
#   genos-fondo ruta/imagen  aplica esa imagen
#   genos-fondo --aleatorio  elige uno al azar
#   genos-fondo --analizar X imprime modo y acento de X (sin aplicar)
set -uo pipefail

DIR="$HOME/Pictures/GenOs-Fondos"
ROFI_TPL="$HOME/.config/rofi/launchpad.rasi.tpl"
ROFI_OUT="$HOME/.config/rofi/launchpad.rasi"
GTKCSS="$HOME/.config/gtk-3.0/gtk.css"
ESTADO="$HOME/.config/genos-fondo.estado"
MINIS="$HOME/.cache/genos-fondo/minis"
IM=$(command -v magick || command -v convert || true)
[ -n "$IM" ] || { echo "Falta ImageMagick (sudo apt install imagemagick)"; exit 1; }

lista() {
  find "$DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) 2>/dev/null | sort -V
}

# Imprime "oscuro|claro RRGGBB|neutro"
analizar() {
  local img=$1 brillo modo acento
  brillo=$("$IM" "$img" -resize 64x36! -colorspace Gray -format '%[fx:mean]' info: 2>/dev/null) || return 1
  if awk -v b="$brillo" 'BEGIN{exit !(b<0.5)}'; then modo=oscuro; else modo=claro; fi
  # Se mira la zona del logo (centro, parte alta del hexágono) y se busca el píxel más saturado
  acento=$("$IM" "$img" -resize 960x540! -crop 115x119+422+162 +repage -depth 8 txt:- 2>/dev/null \
    | awk -F'[(),]' 'NR>1 {r=$3+0; g=$4+0; b=$5+0
        mx=(r>g?r:g); mx=(mx>b?mx:b); mn=(r<g?r:g); mn=(mn<b?mn:b); c=mx-mn
        if (c>best) {best=c; br=r; bg=g; bb=b}}
      END { if (best>=45) printf "%02X%02X%02X", br, bg, bb; else printf "neutro" }')
  echo "$modo $acento"
}

# Color medio de una zona: "R G B"
color_medio() { # $1 = imagen ; $2 = "todo" | "arriba"
  local img=$1 zona=$2
  if [ "$zona" = arriba ]; then
    "$IM" "$img" -resize 960x540! -crop 960x22+0+0 +repage -scale 1x1! -depth 8 \
      -format '%[fx:int(255*r)] %[fx:int(255*g)] %[fx:int(255*b)]' info: 2>/dev/null
  else
    "$IM" "$img" -resize 64x36! -scale 1x1! -depth 8 \
      -format '%[fx:int(255*r)] %[fx:int(255*g)] %[fx:int(255*b)]' info: 2>/dev/null
  fi
}

# Del acento (hex) sale la variante de WhiteSur que existe: "" (azul), purple, green o grey
sufijo_acento() {
  local a=$1 r g b
  [ "$a" = neutro ] && { echo grey; return; }
  r=$((16#${a:0:2})); g=$((16#${a:2:2})); b=$((16#${a:4:2}))
  awk -v r="$r" -v g="$g" -v b="$b" 'BEGIN{
    r/=255; g/=255; b/=255
    mx=(r>g?r:g); mx=(mx>b?mx:b); mn=(r<g?r:g); mn=(mn<b?mn:b); d=mx-mn
    if (d<0.12) {print "grey"; exit}
    if (mx==r) {hue=60*((g-b)/d); if (hue<0) hue+=360} else if (mx==g) hue=60*((b-r)/d+2); else hue=60*((r-g)/d+4)
    if (hue<15 || hue>=345) print "red"
    else if (hue<45) print "orange"
    else if (hue<75) print "yellow"
    else if (hue<170) print "green"
    else if (hue<250) print ""
    else if (hue<310) print "purple"
    else print "pink"
  }'
}

elegir_tema() { # $1 = Dark|Light ; $2 = sufijo
  local base=$1 suf=$2 t d
  for t in "WhiteSur-$base-solid${suf:+-$suf}" "WhiteSur-$base-solid" "WhiteSur-$base"; do
    for d in "$HOME/.themes" "$HOME/.local/share/themes" /usr/share/themes; do
      [ -d "$d/$t" ] && { echo "$t"; return; }
    done
  done
  echo "WhiteSur-$base"
}
elegir_iconos() { # $1 = dark|light
  local t=WhiteSur-$1 d
  for d in "$HOME/.icons" "$HOME/.local/share/icons" /usr/share/icons; do
    [ -d "$d/$t" ] && { echo "$t"; return; }
  done
  echo "WhiteSur"
}

hex_a_rgb() { printf '%d,%d,%d' "0x${1:0:2}" "0x${1:2:2}" "0x${1:4:2}"; }

ini_set() { # archivo clave valor
  if grep -q "^$2=" "$1" 2>/dev/null; then sed -i "s|^$2=.*|$2=$3|" "$1"; else echo "$2=$3" >> "$1"; fi
}

# Calcula el perfil completo en variables globales. Ajustes opcionales por entorno:
#   GENOS_MODO=oscuro|claro  GENOS_ACENTO=RRGGBB|neutro  GENOS_OPACIDAD=0.60..0.96
#   GENOS_RADIO=0..24 (esquinas de las pastillas)  GENOS_TEMA=nombre del tema GTK
#   GENOS_TINTE=1 (pastillas teñidas con el acento)
calcular() {
  img=$1
  read -r modo acento < <(analizar "$img") || { echo "No pude leer $img"; exit 1; }
  [ -n "${GENOS_MODO:-}" ] && modo=$GENOS_MODO
  [ -n "${GENOS_ACENTO:-}" ] && acento=${GENOS_ACENTO#\#}
  local mr mg mb tr tg tb
  read -r mr mg mb < <(color_medio "$img" todo)
  read -r tr tg tb < <(color_medio "$img" arriba)

  # Estilo "teñido": las pastillas toman parte del color de acento (GENOS_TINTE=1)
  local ar=0 ag=0 ab=0 tin=0
  if [ -n "${GENOS_TINTE:-}" ] && [ "$acento" != neutro ]; then
    read -r ar ag ab < <(hex_a_rgb "$acento" | tr ',' ' ')
    tin=0.30
  fi

  # --- Perfil de color: tinte del fondo + opacidad que asegura contraste 4.5:1 ---
  read -r PR PG PBL PA FR FG FB < <(awk -v modo="$modo" -v mr="$mr" -v mg="$mg" -v mb="$mb" \
      -v tr="$tr" -v tg="$tg" -v tb="$tb" -v a0="${GENOS_OPACIDAD:-0.72}" \
      -v ar="$ar" -v ag="$ag" -v ab="$ab" -v tin="$tin" '
    function lin(c){c/=255; return (c<=0.03928) ? c/12.92 : ((c+0.055)/1.055)^2.4}
    function lum(r,g,b){return 0.2126*lin(r)+0.7152*lin(g)+0.0722*lin(b)}
    function cr(a,b){hi=(a>b?a:b); lo=(a<b?a:b); return (hi+0.05)/(lo+0.05)}
    BEGIN{
      if (modo=="oscuro") {br=14;bg=14;bb=22;k=0.16;fr=242;fg=242;fb=247}
      else                {br=250;bg=250;bb=252;k=0.14;fr=28;fg=28;fb=34}
      pr=br*(1-k)+mr*k; pg=bg*(1-k)+mg*k; pb=bb*(1-k)+mb*k
      t=tin; if (modo!="oscuro") t=tin*0.6
      pr=pr*(1-t)+ar*t; pg=pg*(1-t)+ag*t; pb=pb*(1-t)+ab*t
      lf=lum(fr,fg,fb)
      for (a=a0; a<=0.96; a+=0.02) {
        er=a*pr+(1-a)*tr; eg=a*pg+(1-a)*tg; eb=a*pb+(1-a)*tb
        if (cr(lum(er,eg,eb), lf) >= 4.5) break
      }
      printf "%d %d %d %.2f %d %d %d\n", pr, pg, pb, a, fr, fg, fb
    }')

  PBG="rgba($PR, $PG, $PBL, $PA)"
  PFG=$(printf '#%02x%02x%02x' "$FR" "$FG" "$FB")
  RBG=$(printf '#%02x%02x%02xdd' "$PR" "$PG" "$PBL")
  if [ "$modo" = oscuro ]; then
    PBORDE="rgba(255, 255, 255, 0.10)"
    PHOVER="rgba($(( PR + 40 )), $(( PG + 40 )), $(( PBL + 50 )), 0.92)"
    RBGSOFT="#ffffff14"; RFG="#f2f2f7"; RFGDIM="#a4a4b8"; RBORDE="#ffffff26"
    PSEL="rgba(255, 255, 255, 0.26)"; PSELFG="#ffffff"; RBGSEL="#ffffff26"
  else
    PBORDE="rgba(0, 0, 0, 0.10)"
    PHOVER="rgba(255, 255, 255, 0.94)"
    RBGSOFT="#00000012"; RFG="#1c1c22"; RFGDIM="#55556a"; RBORDE="#00000022"
    PSEL="rgba(0, 0, 0, 0.16)"; PSELFG="#1c1c22"; RBGSEL="#00000020"
  fi
  if [ "$acento" != neutro ]; then
    local r; r=$(hex_a_rgb "$acento")
    PSEL="rgba($r, 0.88)"; PSELFG="#ffffff"
    RBGSEL="#${acento}55"
  fi

  # --- Lanzador ---
  local base suf
  if [ "$modo" = oscuro ]; then iconos=$(elegir_iconos dark); base=Dark; else iconos=$(elegir_iconos light); base=Light; fi
  suf=$(sufijo_acento "$acento")
  tema=$(elegir_tema "$base" "$suf")
  [ -n "${GENOS_TEMA:-}" ] && tema=$GENOS_TEMA
  RADIO=${GENOS_RADIO:-12}
}

imprimir_perfil() {
  printf 'modo=%s\nacento=%s\ntema=%s\niconos=%s\nopacidad=%s\npastilla=%s,%s,%s\ntexto=%s\nsel=%s\nradio=%s\n' \
    "$modo" "$acento" "$tema" "$iconos" "$PA" "$PR" "$PG" "$PBL" "$PFG" "$PSEL" "$RADIO"
}

aplicar() {
  calcular "$1"
  # --- CSS de la barra (solo se reemplaza el bloque marcado) ---
  mkdir -p "$(dirname "$GTKCSS")"
  [ -f "$GTKCSS" ] && sed -i '\|>>> xfce-estetica >>>|,\|<<< xfce-estetica <<<|d' "$GTKCSS"
  cat >> "$GTKCSS" <<CSS
/* >>> xfce-estetica >>> */
/* Generado por genos-fondo ($modo, acento $acento, opacidad $PA). Selectores: docs.xfce.org/xfce/xfce4-panel/theming */
.xfce4-panel,
.xfce4-panel.background {
    background-color: transparent;
    background-image: none;
    border: 0;
}
.xfce4-panel button {
    background-image: none;
    background-color: $PBG;
    color: $PFG;
    border: 1px solid $PBORDE;
    border-radius: ${RADIO}px;
    box-shadow: none;
    text-shadow: none;
    margin: 4px 3px;
    padding: 0 10px;
    min-height: 0;
}
.xfce4-panel button:hover {
    background-color: $PHOVER;
}
.xfce4-panel button:checked {
    background-color: $PSEL;
    color: $PSELFG;
}
#clock-button {
    padding: 0 16px;
    font-weight: 600;
}
/* Notificaciones (xfce4-notifyd con el tema Default) */
#XfceNotifyWindow .osd,
#XfceNotifyWindow.osd {
    background-color: $PBG;
    color: $PFG;
    border: 1px solid $PBORDE;
    border-radius: $(( RADIO + 4 ))px;
    box-shadow: none;
}
#XfceNotifyWindow .osd:hover {
    background-color: $PHOVER;
}
#XfceNotifyWindow.osd label#summary {
    color: $PFG;
    font-weight: 700;
}
#XfceNotifyWindow.osd label#body {
    color: $PFG;
    opacity: 0.85;
}
#XfceNotifyWindow.osd button {
    background-image: none;
    background-color: $PSEL;
    color: $PSELFG;
    border: 0;
    border-radius: 8px;
    box-shadow: none;
    text-shadow: none;
}
#XfceNotifyWindow.osd progressbar trough {
    background-color: $PBORDE;
    border: 0;
    border-radius: 6px;
}
#XfceNotifyWindow.osd progressbar progress {
    background-color: $PSEL;
    border: 0;
    border-radius: 6px;
}
/* <<< xfce-estetica <<< */
CSS

  if [ -f "$ROFI_TPL" ]; then
    sed -e "s|@@ICONOS@@|$iconos|" -e "s|@@BG@@|$RBG|" -e "s|@@BGSOFT@@|$RBGSOFT|" \
        -e "s|@@BGSEL@@|$RBGSEL|" -e "s|@@FG@@|$RFG|" -e "s|@@FGDIM@@|$RFGDIM|" \
        -e "s|@@BORDE@@|$RBORDE|" "$ROFI_TPL" > "$ROFI_OUT"
  fi

  # --- Terminal: colores del mismo perfil, sin transparencia ---
  local rc="$HOME/.config/xfce4/terminal/terminalrc" tbg tfg tcur
  mkdir -p "$(dirname "$rc")"; [ -f "$rc" ] || echo "[Configuration]" > "$rc"
  tbg=$(printf '#%02x%02x%02x' $(( PR * 70 / 100 )) $(( PG * 70 / 100 )) $(( PBL * 70 / 100 )))
  [ "$modo" = claro ] && tbg=$(printf '#%02x%02x%02x' $(( PR * 98 / 100 )) $(( PG * 98 / 100 )) $(( PBL * 98 / 100 )))
  tfg=$PFG
  if [ "$acento" != neutro ]; then tcur="#$acento"; else tcur=$PFG; fi
  ini_set "$rc" BackgroundMode TERMINAL_BACKGROUND_SOLID
  ini_set "$rc" ColorForeground "$tfg"
  ini_set "$rc" ColorBackground "$tbg"
  ini_set "$rc" ColorCursorUseDefault FALSE
  ini_set "$rc" ColorCursor "$tcur"

  # --- Escritorio (solo dentro de XFCE) ---
  if command -v xfconf-query >/dev/null 2>&1 && { [ "${XDG_CURRENT_DESKTOP:-}" = "XFCE" ] || pgrep -x xfsettingsd >/dev/null 2>&1 || pgrep -x xfce4-session >/dev/null 2>&1; }; then
    xf() { xfconf-query -c "$1" -p "$2" -n -t "$3" -s "$4" 2>/dev/null; }
    xf xsettings /Net/ThemeName     string "$tema"
    xf xsettings /Net/IconThemeName string "$iconos"
    xf xfwm4 /general/theme         string "$tema"
    # También en GTK, para las apps que arrancan sin el demonio de ajustes
    mkdir -p "$HOME/.config/gtk-3.0"
    [ -f "$HOME/.config/gtk-3.0/settings.ini" ] || echo "[Settings]" > "$HOME/.config/gtk-3.0/settings.ini"
    ini_set "$HOME/.config/gtk-3.0/settings.ini" gtk-theme-name "$tema"
    ini_set "$HOME/.config/gtk-3.0/settings.ini" gtk-icon-theme-name "$iconos"
    if command -v gsettings >/dev/null 2>&1; then
      gsettings set org.gnome.desktop.interface gtk-theme "$tema" 2>/dev/null || true
      gsettings set org.gnome.desktop.interface icon-theme "$iconos" 2>/dev/null || true
    fi
    # El nombre del monitor cambia según el equipo (en xrdp suele ser rdp0), así que se
    # escribe el fondo en todos los monitores que existan y en monitor0 por si acaso.
    local mons m o ws
    mons=$(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -oE '^/backdrop/screen[0-9]+/monitor[^/]+' || true)
    for o in $(xrandr --query 2>/dev/null | awk '/ connected/{print $1}'); do
      mons+=$'\n'"/backdrop/screen0/monitor$o"
    done
    mons+=$'\n/backdrop/screen0/monitor0'
    for m in $(printf '%s\n' "$mons" | sort -u); do
      for ws in 0 1 2 3; do
        xf xfce4-desktop "$m/workspace$ws/last-image" string "$img"
        xf xfce4-desktop "$m/workspace$ws/image-style" int 5
      done
    done
    (xfdesktop --reload >/dev/null 2>&1 &)
    (xfce4-panel -r >/dev/null 2>&1 &)
    # El demonio de notificaciones lee el CSS al arrancar; se reinicia solo con la próxima notificación
    pkill -x xfce4-notifyd >/dev/null 2>&1 || true
    echo "Aplicado: $(basename "$img")"
    echo "  modo $modo, acento $acento, tema $tema, opacidad de la barra $PA"
  else
    echo "Guardado: $(basename "$img") (modo $modo, acento $acento, tema $tema)."
    echo "Corre este comando otra vez dentro de XFCE para que se vea."
  fi
  mkdir -p "$(dirname "$ESTADO")"; printf '%s\n' "$img" > "$ESTADO"
  imprimir_perfil > "$HOME/.config/genos-fondo.perfil"
}

# Selector con miniaturas (rofi)
elegir() {
  command -v rofi >/dev/null 2>&1 || { echo "Falta rofi"; exit 1; }
  mkdir -p "$MINIS"
  local f m sel
  sel=$(
    while IFS= read -r f; do
      m="$MINIS/$(printf '%s' "$f" | md5sum | cut -c1-12).jpg"
      [ -f "$m" ] || "$IM" "$f" -resize 480x270^ -gravity center -extent 480x270 -quality 80 "$m" 2>/dev/null
      printf '%s\0icon\x1f%s\n' "$(basename "${f%.*}")" "$m"
    done < <(lista) \
    | rofi -dmenu -i -show-icons -format i -p "" -theme "$ROFI_OUT" \
        -theme-str 'window { width: 74%; height: 76%; } listview { columns: 4; lines: 3; } element-icon { size: 190px; } element-text { font: "Inter 10"; }'
  )
  [ -n "$sel" ] || exit 0
  f=$(lista | sed -n "$((sel+1))p")
  [ -n "$f" ] && aplicar "$f"
}

case "${1:-}" in
  "")
    n=0
    while IFS= read -r f; do
      n=$((n+1))
      read -r m a < <(analizar "$f")
      printf '%2d  %-8s %-8s %s\n' "$n" "$m" "$a" "${f#"$DIR"/}"
    done < <(lista)
    [ "$n" -gt 0 ] || echo "No hay fondos en $DIR"
    echo; echo "Aplica uno con: genos-fondo NUMERO     o el selector con miniaturas: genos-fondo --elegir"
    ;;
  --elegir)
    elegir ;;
  --aleatorio)
    f=$(lista | shuf -n1); [ -n "$f" ] && aplicar "$f" || echo "No hay fondos en $DIR" ;;
  --analizar)
    analizar "${2:?falta la imagen}" ;;
  --perfil)
    calcular "$(readlink -f "${2:?falta la imagen}")"
    imprimir_perfil ;;
  *)
    if [[ "$1" =~ ^[0-9]+$ ]]; then
      f=$(lista | sed -n "${1}p"); [ -n "$f" ] || { echo "No existe el fondo $1"; exit 1; }
    else
      f=$1; [ -f "$f" ] || { echo "No existe $f"; exit 1; }
    fi
    aplicar "$(readlink -f "$f")" ;;
esac
