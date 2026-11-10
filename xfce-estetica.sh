#!/usr/bin/env bash
# xfce-estetica.sh (GenOS 1.2: sistema de actualizaciones desde GitHub que conserva tu personalización)
# Estética minimalista para XFCE (Debian en WSL con xrdp): barra superior en pastillas
# translúcidas, dock con zoom, lanzador en cuadrícula (Rofi) y fondos GenOs.
# Con cada fondo el diseño se adapta solo: modo oscuro o claro según la imagen y
# color de acento tomado del logo. Se cambia de fondo con el comando genos-fondo.
#
# Se puede correr varias veces.
#   Fase 1: desde cualquier terminal. Instala paquetes, temas y archivos de configuración.
#   Fase 2: desde una terminal DENTRO de XFCE. Aplica los ajustes y reinicia el panel.
#
# Fondos: baja los diseños de Canva como JPG (Compartir > Descargar > JPG, todas las páginas)
# y deja los .zip o las imágenes en  C:\Users\TU_USUARIO\Downloads\GenOs-Fondos
#
# Créditos
#  - WhiteSur (tema GTK, iconos y cursor): vinceliuice. Se descargan de sus repos oficiales
#    y conservan su licencia (el tema GTK es MIT). Aquí no se copia su código.
#  - Selectores del panel: documentación oficial de XFCE (docs.xfce.org/xfce/xfce4-panel/theming).
#  - La idea del panel transparente con elementos separados viene de una guía de la comunidad
#    (forum.qubes-os.org, "Qubes OS XFCE4-panel customization"). El CSS de este script es propio.

set -uo pipefail

# ---------- Opciones (cámbialas aquí) ----------
FONDO_INICIAL=""       # número (de "genos-fondo") o parte del nombre; vacío = el primero oscuro con color
ALTO_PANEL=34          # alto de la barra de arriba, en píxeles
FUENTE="Inter 10"
TEMA_CURSOR="WhiteSur-cursors"
# -----------------------------------------------

CACHE="$HOME/.cache/xfce-estetica"
FONDOS="$HOME/Pictures/GenOs-Fondos"
BIN="$HOME/.local/bin"
mkdir -p "$CACHE" "$FONDOS" "$BIN"

GENOS_VERSION="1.2"
# Primera instalación o actualización: en una actualización no se toca lo que personalizaste
# (fondo, colores, barra, dock, atajos, terminal). Se fuerza con GENOS_ACTUALIZAR=0 o 1.
if [ -n "${GENOS_ACTUALIZAR:-}" ]; then
  ACTUALIZANDO=$GENOS_ACTUALIZAR
elif [ -f "$HOME/.config/genos-version" ] || [ -f "$HOME/.config/genos-personalizacion.json" ]; then
  ACTUALIZANDO=1
else
  ACTUALIZANDO=0
fi

paso()  { printf '\n==> %s\n' "$*"; }
aviso() { printf '   ! %s\n' "$*"; }
apt_()  { sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get "$@"; }

if [ "$(id -u)" -eq 0 ] && [ -z "${GENOS_PRUEBA:-}" ]; then
  echo "No lo corras como root, usa tu usuario normal."
  exit 1
fi
sudo -v || exit 1

# ---------- 1. Paquetes ----------
paso "1/7 Paquetes"
if [ -d /etc/needrestart/conf.d ]; then
  echo "\$nrconf{restart} = 'a';" | sudo tee /etc/needrestart/conf.d/90-auto.conf >/dev/null
fi
apt_ update -qq
quiero=(git sassc libglib2.0-dev-bin libxml2-utils plank rofi fonts-inter dconf-cli imagemagick unzip python3-gi python3-gi-cairo gir1.2-gtk-3.0 libnotify-bin xfce4-notifyd)
hay=()
for p in "${quiero[@]}"; do
  if apt-cache show "$p" >/dev/null 2>&1; then hay+=("$p"); else aviso "No existe en los repos: $p"; fi
done
apt_ install -y --no-install-recommends "${hay[@]}"
fc-cache -f >/dev/null 2>&1 || true

# ---------- 2. Tema, iconos y cursor ----------
paso "2/7 WhiteSur (tema, iconos y cursor)"
tiene() {
  local d
  for d in "$HOME/.themes" "$HOME/.local/share/themes" "$HOME/.icons" "$HOME/.local/share/icons" /usr/share/themes /usr/share/icons; do
    [ -d "$d/$1" ] && return 0
  done
  return 1
}
bajar_e_instalar() {
  local nombre=$1 url=$2
  shift 2
  local dir="$CACHE/$nombre"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" pull -q --ff-only || true
  else
    git clone -q --depth=1 "$url" "$dir" || { aviso "No pude bajar $nombre"; return 1; }
  fi
  (cd "$dir" && ./install.sh "$@") || aviso "Falló el instalador de $nombre"
}
# Oscuro y claro, porque el tema cambia según el fondo
# y una variante por acento (morado, verde, rosa, naranja, rojo, amarillo, gris) para que el tema combine con cada fondo
if ! tiene WhiteSur-Dark-solid-red || ! tiene WhiteSur-Light-solid-grey || ! tiene WhiteSur-Dark-solid; then
  bajar_e_instalar WhiteSur-gtk-theme https://github.com/vinceliuice/WhiteSur-gtk-theme.git \
    -c Dark -c Light -t purple -t green -t grey -t pink -t orange -t red -t yellow -o solid
  tiene WhiteSur-Dark-solid || bajar_e_instalar WhiteSur-gtk-theme https://github.com/vinceliuice/WhiteSur-gtk-theme.git -c Dark -c Light -o solid
fi
# Las variantes hdpi/xhdpi solo sirven en pantallas con escalado y llenan las listas de temas
rm -rf "$HOME"/.themes/WhiteSur-*-hdpi "$HOME"/.themes/WhiteSur-*-xhdpi 2>/dev/null
if ! tiene WhiteSur-dark || ! tiene WhiteSur-light; then
  bajar_e_instalar WhiteSur-icon-theme https://github.com/vinceliuice/WhiteSur-icon-theme.git
fi
tiene "$TEMA_CURSOR" || bajar_e_instalar WhiteSur-cursors https://github.com/vinceliuice/WhiteSur-cursors.git

# ---------- 3. Archivos de configuración ----------
paso "3/7 Archivos de configuración"
if [ -d "$HOME/.config/xfce4" ] && [ ! -d "$HOME/xfce-respaldo-original" ]; then
  cp -r "$HOME/.config/xfce4" "$HOME/xfce-respaldo-original"
  echo "   Respaldo de tu configuración en ~/xfce-respaldo-original"
fi
[ -f "$HOME/.config/gtk-3.0/gtk.css" ] && cp -n "$HOME/.config/gtk-3.0/gtk.css" "$HOME/.config/gtk-3.0/gtk.css.bak"

# Sesión: evita que XFCE use Wayland (la variable la deja WSLg)
[ -f "$HOME/.xsession" ] && cp -n "$HOME/.xsession" "$HOME/.xsession.bak"
cat > "$HOME/.xsession" <<'EOF'
unset WAYLAND_DISPLAY
export GDK_BACKEND=x11
export XDG_SESSION_TYPE=x11
dbus-update-activation-environment --systemd GDK_BACKEND=x11 XDG_SESSION_TYPE=x11 2>/dev/null
startxfce4
EOF

mkdir -p "$HOME/.config/autostart" "$HOME/.local/share/applications" "$HOME/.config/rofi"

# picom dejaba bloques negros en xrdp: se quita si quedó de antes
pkill -u "$USER" -x picom 2>/dev/null || true
rm -f "$HOME/.config/autostart/picom.desktop"

cat > "$HOME/.config/autostart/plank.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Plank
Exec=plank
X-GNOME-Autostart-enabled=true
EOF

# Plantilla del lanzador (los colores los rellena genos-fondo)
cat > "$HOME/.config/rofi/launchpad.rasi.tpl" <<'RASI_FIN'
/* launchpad.rasi (plantilla de genos-fondo, los colores se rellenan solos)
   Lanzador minimalista: buscador arriba y cuadrícula de apps.
   Deja a la vista el panel de arriba y el dock.
   La transparencia necesita el compositor de xfwm4 activado. */

configuration {
    modi: "drun";
    show-icons: true;
    icon-theme: "@@ICONOS@@";
    drun-display-format: "{name}";
    drun-use-desktop-cache: true;
    drun-reload-desktop-cache: false;
    disable-history: false;
    display-drun: "";
    matching: "fuzzy";
    sorting-method: "fzf";
    kb-row-left: "Left";
    kb-row-right: "Right";
    kb-move-char-back: "Control+b";
    kb-move-char-forward: "Control+f";
}

* {
    bg:      @@BG@@;
    bg-soft: @@BGSOFT@@;
    bg-sel:  @@BGSEL@@;
    fg:      @@FG@@;
    fg-dim:  @@FGDIM@@;
    font: "Inter 11";
    background-color: transparent;
    text-color: @fg;
    margin: 0;
    padding: 0;
    spacing: 0;
}

window {
    location: center;
    anchor: center;
    width: 62%;
    height: 72%;
    background-color: @bg;
    border: 1px;
    border-color: @@BORDE@@;
    border-radius: 24px;
}

mainbox {
    padding: 28px;
    spacing: 24px;
    children: [ inputbar, listview ];
}

inputbar {
    padding: 12px 18px;
    background-color: @bg-soft;
    border-radius: 14px;
    children: [ entry ];
}

entry {
    placeholder: "Buscar";
    placeholder-color: @fg-dim;
}

listview {
    columns: 6;
    lines: 4;
    flow: horizontal;
    fixed-columns: true;
    scrollbar: false;
    cycle: false;
    spacing: 12px;
}

element {
    orientation: vertical;
    padding: 16px 6px;
    spacing: 8px;
    border-radius: 16px;
}

element normal.normal, element alternate.normal {
    background-color: transparent;
    text-color: @fg-dim;
}

element selected.normal {
    background-color: @bg-sel;
    text-color: @fg;
}

element-icon {
    size: 56px;
    horizontal-align: 0.5;
    background-color: transparent;
}

element-text {
    horizontal-align: 0.5;
    vertical-align: 0.5;
    font: "Inter 9";
    background-color: transparent;
    text-color: inherit;
}
RASI_FIN

# Comando genos-fondo
cat > "$BIN/genos-fondo" <<'GENOS_FIN'
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
GENOS_FIN
chmod +x "$BIN/genos-fondo"

# Traducciones (español, inglés y portugués) que usan las apps de GenOS
mkdir -p "$HOME/.local/lib/genos"
cat > "$HOME/.local/lib/genos/genos_i18n.py" <<'I18N_FIN'
"""Traducciones de GenOS: español (base), inglés y portugués.

El texto original de cada app está en español. T() lo busca en el diccionario y devuelve la
versión del idioma elegido; si no la encuentra, deja el texto como está. El idioma se guarda
en ~/.config/genos-idioma (una línea: es, en o pt).
"""
import functools
import os
import re

IDIOMAS = [("es", "Español"), ("en", "English"), ("pt", "Português")]
ARCHIVO_IDIOMA = os.path.join(os.path.expanduser("~"), ".config", "genos-idioma")


def leer_idioma():
    try:
        with open(ARCHIVO_IDIOMA, encoding="utf-8") as f:
            v = f.read().strip().lower()
    except OSError:
        return "es"
    return v if v in ("es", "en", "pt") else "es"


def guardar_idioma(cod):
    os.makedirs(os.path.dirname(ARCHIVO_IDIOMA), exist_ok=True)
    with open(ARCHIVO_IDIOMA, "w", encoding="utf-8") as f:
        f.write(cod + "\n")


LANG = leer_idioma()
_TR = {}
_PLANTILLAS = None
_ESPEC = re.compile(r"%(?:\.\d+)?[sdf]")


def _indice():
    return 0 if LANG == "en" else 1


def _compilar():
    """Prepara las cadenas con %s, %d o %.1f para reconocerlas ya formateadas."""
    global _PLANTILLAS
    _PLANTILLAS = []
    for es, tr in _TR.items():
        if "%" not in es or not _ESPEC.search(es):
            continue
        partes, tipos, pos = [], [], 0
        for m in _ESPEC.finditer(es):
            partes.append(re.escape(es[pos:m.start()]))
            tipos.append(m.group(0)[-1])
            partes.append(r"(-?\d+)" if tipos[-1] == "d" else (r"(-?[\d.]+)" if tipos[-1] == "f" else r"(.*?)"))
            pos = m.end()
        partes.append(re.escape(es[pos:]))
        try:
            rx = re.compile("^" + "".join(partes) + "$", re.S)
        except re.error:
            continue
        _PLANTILLAS.append((rx, tipos, tr))
    _PLANTILLAS.sort(key=lambda p: -len(p[0].pattern))


def T(s):
    """Texto de la interfaz en el idioma elegido."""
    if LANG == "es" or not isinstance(s, str) or not s:
        return s
    r = _TR.get(s)
    if r is not None:
        return r[_indice()]
    base = s.strip()
    if base != s and base in _TR:
        i = s.index(base)
        return s[:i] + _TR[base][_indice()] + s[i + len(base):]
    global _PLANTILLAS
    if _PLANTILLAS is None:
        _compilar()
    for rx, tipos, tr in _PLANTILLAS:
        m = rx.match(s)
        if not m:
            continue
        args = []
        for g, t in zip(m.groups(), tipos):
            if t == "d":
                args.append(int(g))
            elif t == "f":
                try:
                    args.append(float(g))
                except ValueError:
                    args.append(g)
            else:
                args.append(T(g))
        try:
            return tr[_indice()] % tuple(args)
        except (TypeError, ValueError):
            return s
    return s


def TP(es, *args):
    """Traduce la plantilla y la rellena: TP("Hola %s", nombre)."""
    return T(es) % args


def _envolver_init(cls, claves):
    orig = cls.__init__

    @functools.wraps(orig)
    def init(self, *a, **kw):
        for k in claves:
            if isinstance(kw.get(k), str):
                kw[k] = T(kw[k])
        orig(self, *a, **kw)
    cls.__init__ = init


def _envolver_metodo(cls, nombre, posiciones=(0,)):
    orig = getattr(cls, nombre, None)
    if orig is None:
        return

    @functools.wraps(orig)
    def metodo(self, *a, **kw):
        a = list(a)
        for p in posiciones:
            if p < len(a) and isinstance(a[p], str):
                a[p] = T(a[p])
        return orig(self, *a, **kw)
    setattr(cls, nombre, metodo)


def _envolver_clase(cls, nombre, posiciones):
    orig = getattr(cls, nombre, None)
    if orig is None:
        return

    @functools.wraps(orig)
    def metodo(*a, **kw):
        a = list(a)
        for p in posiciones:
            if p < len(a) and isinstance(a[p], str):
                a[p] = T(a[p])
        return orig(*a, **kw)
    setattr(cls, nombre, staticmethod(metodo))


def parchear(Gtk):
    """Hace que los widgets de GTK traduzcan los textos que reciben."""
    if LANG == "es":
        return
    txt = ("label", "title", "subtitle", "placeholder_text", "tooltip_text", "tooltip_markup",
           "secondary_text", "text_label")
    for cls in (Gtk.Label, Gtk.Button, Gtk.CheckButton, Gtk.RadioButton, Gtk.ToggleButton, Gtk.SearchEntry,
                Gtk.Entry, Gtk.HeaderBar, Gtk.Window, Gtk.Dialog, Gtk.Expander, Gtk.Frame, Gtk.LinkButton):
        _envolver_init(cls, txt)
    for cls in (Gtk.MessageDialog, Gtk.FileChooserDialog):
        _envolver_init(cls, txt + ("text",))
    _envolver_metodo(Gtk.Label, "set_text")
    _envolver_metodo(Gtk.Label, "set_label")
    _envolver_metodo(Gtk.Label, "set_markup")
    _envolver_metodo(Gtk.Button, "set_label")
    _envolver_metodo(Gtk.Widget, "set_tooltip_text")
    _envolver_metodo(Gtk.Widget, "set_tooltip_markup")
    _envolver_metodo(Gtk.Window, "set_title")
    _envolver_metodo(Gtk.HeaderBar, "set_title")
    _envolver_metodo(Gtk.HeaderBar, "set_subtitle")
    _envolver_metodo(Gtk.Entry, "set_placeholder_text")
    _envolver_metodo(Gtk.Frame, "set_label")
    _envolver_metodo(Gtk.Expander, "set_label")
    _envolver_metodo(Gtk.ComboBoxText, "append", (1,))
    _envolver_metodo(Gtk.ComboBoxText, "append_text")
    _envolver_metodo(Gtk.ComboBoxText, "prepend", (1,))
    _envolver_metodo(Gtk.Dialog, "add_button")
    _envolver_metodo(Gtk.MessageDialog, "format_secondary_text")
    _envolver_metodo(Gtk.MessageDialog, "set_property", ())
    _envolver_clase(Gtk.RadioButton, "new_with_label_from_widget", (1,))
    _envolver_clase(Gtk.Button, "new_with_label", (0,))
    _envolver_clase(Gtk.CheckButton, "new_with_label", (0,))
    _envolver_clase(Gtk.Label, "new", (0,))


def nombres_fecha():
    """(dias, meses) en el idioma elegido; lunes primero."""
    if LANG == "en":
        return (["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"],
                ["January", "February", "March", "April", "May", "June", "July", "August",
                 "September", "October", "November", "December"])
    if LANG == "pt":
        return (["segunda-feira", "terça-feira", "quarta-feira", "quinta-feira", "sexta-feira", "sábado", "domingo"],
                ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto",
                 "setembro", "outubro", "novembro", "dezembro"])
    return (["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"],
            ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
             "septiembre", "octubre", "noviembre", "diciembre"])


def inicial_semana():
    """Letras de la fila de días del calendario, lunes primero."""
    return {"en": "MTWTFSS", "pt": "STQQSSD"}.get(LANG, "LMXJVSD")


def fecha_larga(dt):
    """Fecha larga en el idioma elegido: 'martes, 3 de junio' / 'Tuesday, June 3'."""
    dias, meses = nombres_fecha()
    d, m = dias[dt.weekday()], meses[dt.month - 1]
    if LANG == "en":
        return "%s, %s %d" % (d, m, dt.day)
    return "%s, %d de %s" % (d, dt.day, m)


_TR_PARTES = []
_TR.update({
    # ---- Presets, palabras del buscador y nombres de página
    "Minimalista": ("Minimal", "Minimalista"),
    "Estilo Mac": ("Mac style", "Estilo Mac"),
    "Compacto": ("Compact", "Compacto"),
    "Flotante grande": ("Large floating", "Flutuante grande"),
    "fondo wallpaper imagen aleatorio": ("background wallpaper image random", "fundo wallpaper imagem aleatório"),
    "color modo claro oscuro acento tema apariencia estilo día noche":
        ("color mode light dark accent theme appearance style day night",
         "cor modo claro escuro destaque tema aparência estilo dia noite"),
    "panel superior pastilla altura esquinas ocultar bloquear iconos":
        ("top panel pill height corners hide lock icons", "painel superior pílula altura cantos ocultar bloquear ícones"),
    "plank zoom iconos tamaño": ("plank zoom icons size", "plank zoom ícones tamanho"),
    "botones sombra compositor foco alt tab imán doble clic ubicación opacidad":
        ("buttons shadow compositor focus alt tab snap double click placement opacity",
         "botões sombra compositor foco alt tab ímã clique duplo posição opacidade"),
    "notificaciones no molestar aviso": ("notifications do not disturb alert", "notificações não perturbe aviso"),
    "reloj calendario pomodoro notas red sistema": ("clock calendar pomodoro notes network system",
                                                    "relógio calendário pomodoro notas rede sistema"),
    "fuente tipografía cursor": ("font typography cursor", "fonte tipografia cursor"),
    "guardar exportar tema": ("save export theme", "salvar exportar tema"),
    "reiniciar barra centro de control": ("restart bar control center", "reiniciar barra central de controle"),
    "iconos escritorio papelera carpeta personal escritorios virtuales espacios de trabajo":
        ("desktop icons trash home folder virtual desktops workspaces",
         "ícones área de trabalho lixeira pasta pessoal áreas de trabalho virtuais espaços de trabalho"),
    "resolución escala dpi tamaño texto monitor xrandr": ("resolution scale dpi text size monitor xrandr",
                                                           "resolução escala dpi tamanho texto monitor xrandr"),
    "distribución idioma repetición teclas atajos": ("layout language key repeat shortcuts",
                                                      "layout idioma repetição teclas atalhos"),
    "autoinicio aplicaciones al iniciar sesión arranque startup guardar sesión cerrar sesión bloquear":
        ("autostart applications at login startup save session log out lock",
         "inicialização automática aplicativos ao entrar login salvar sessão sair bloquear"),
    "iconos tema fuente suavizado antialias hinting sonidos botones menús barra de herramientas monoespaciada":
        ("icons theme font smoothing antialias hinting sounds buttons menus toolbar monospace",
         "ícones tema fonte suavização antialias hinting sons botões menus barra de ferramentas monoespaçada"),
    "ratón mouse touchpad zurdo velocidad aceleración desplazamiento invertir":
        ("mouse touchpad left handed speed acceleration scrolling invert",
         "mouse touchpad canhoto velocidade aceleração rolagem inverter"),
    "volumen audio altavoz micrófono silenciar salida entrada": ("volume audio speaker microphone mute output input",
                                                                  "volume áudio alto-falante microfone silenciar saída entrada"),
    "batería pantalla apagar suspender bloqueo ahorro energía": ("battery screen turn off suspend lock power saving",
                                                                  "bateria tela desligar suspender bloqueio economia energia"),
    "usb extraíbles montar automático cd dvd medios": ("usb removable mount automatic cd dvd media",
                                                       "usb removíveis montar automático cd dvd mídia"),
    "navegador correo terminal predeterminadas portapapeles clipman": ("browser mail terminal default clipboard clipman",
                                                                       "navegador e-mail terminal padrão área de transferência clipman"),
    "thunar carpetas miniaturas vista un clic fecha binario": ("thunar folders thumbnails view single click date binary",
                                                               "thunar pastas miniaturas visualização um clique data binário"),
    "teclas pegajosas lentas rebote ratón con teclado accesibilidad": ("sticky slow bounce keys mouse keyboard accessibility",
                                                                       "teclas de aderência lentas repique mouse teclado acessibilidade"),
    "terminal xfce4-terminal mousepad editor de texto fuente transparencia desplazamiento líneas números ajuste de línea tabulación":
        ("terminal xfce4-terminal mousepad text editor font transparency scrolling lines numbers line wrap tab",
         "terminal xfce4-terminal mousepad editor de texto fonte transparência rolagem linhas números quebra de linha tabulação"),
    "versión debian xfce sistema información interfaces créditos genos": ("version debian xfce system information interfaces credits genos",
                                                                          "versão debian xfce sistema informação interfaces créditos genos"),
    "Modificado": ("Modified", "Modificado"),
    "Original": ("Original", "Original"),
    "Hecho para GenOS": ("Made for GenOS", "Feito para o GenOS"),
    "Automático (del logo)": ("Automatic (from the logo)", "Automático (do logotipo)"),
    "Morado": ("Purple", "Roxo"),
    "Azul": ("Blue", "Azul"),
    "Verde": ("Green", "Verde"),
    "Rosa": ("Pink", "Rosa"),
    "Naranja": ("Orange", "Laranja"),
    "Rojo": ("Red", "Vermelho"),
    "Amarillo": ("Yellow", "Amarelo"),
    "Gris": ("Gray", "Cinza"),
    "Español": ("Spanish", "Espanhol"),
    "Latinoamericano": ("Latin American", "Latino-americano"),
    "Inglés (EE. UU.)": ("English (US)", "Inglês (EUA)"),
    "Inglés (Reino Unido)": ("English (UK)", "Inglês (Reino Unido)"),
    "Portugués": ("Portuguese", "Português"),
    "Portugués (Brasil)": ("Portuguese (Brazil)", "Português (Brasil)"),
    "Francés": ("French", "Francês"),
    "Alemán": ("German", "Alemão"),
    "Italiano": ("Italian", "Italiano"),
    "Estándar": ("Standard", "Padrão"),
    "Internacional (teclas muertas)": ("International (dead keys)", "Internacional (teclas mortas)"),
    "Reloj": ("Clock", "Relógio"),
    "Hora grande y fecha. Activado por defecto.": ("Large time and date. On by default.", "Hora grande e data. Ativado por padrão."),
    "Sistema": ("System", "Sistema"),
    "CPU, memoria y disco en barras. Activado por defecto.": ("CPU, memory and disk as bars. On by default.",
                                                              "CPU, memória e disco em barras. Ativado por padrão."),
    "Red": ("Network", "Rede"),
    "Velocidad de bajada y subida con gráfico. Opcional.": ("Download and upload speed with a graph. Optional.",
                                                            "Velocidade de download e upload com gráfico. Opcional."),
    "Calendario": ("Calendar", "Calendário"),
    "El mes con el día de hoy marcado. Opcional.": ("The month with today highlighted. Optional.",
                                                    "O mês com o dia de hoje marcado. Opcional."),
    "Pomodoro": ("Pomodoro", "Pomodoro"),
    "Foco de 25 minutos y descanso de 5. Clic inicia o pausa, clic derecho reinicia. Opcional.":
        ("25 minutes of focus, 5 of rest. Click to start or pause, right click to reset. Optional.",
         "25 minutos de foco e 5 de descanso. Clique para iniciar ou pausar, clique direito reinicia. Opcional."),
    "Notas": ("Notes", "Notas"),
    "Muestra tu archivo de notas; clic para editarlo. Opcional.": ("Shows your notes file; click to edit it. Optional.",
                                                                    "Mostra seu arquivo de notas; clique para editá-lo. Opcional."),
    "Arriba a la derecha": ("Top right", "Acima à direita"),
    "Arriba a la izquierda": ("Top left", "Acima à esquerda"),
    "Abajo a la derecha": ("Bottom right", "Abaixo à direita"),
    "Abajo a la izquierda": ("Bottom left", "Abaixo à esquerda"),
    "Abajo": ("Bottom", "Abaixo"),
    "Izquierda": ("Left", "Esquerda"),
    "Derecha": ("Right", "Direita"),
    "Arriba": ("Top", "Acima"),
    "Siempre visible": ("Always visible", "Sempre visível"),
    "Inteligente (se oculta si una ventana lo tapa)": ("Smart (hides when a window covers it)",
                                                       "Inteligente (oculta quando uma janela o cobre)"),
    "Automático (aparece al acercar el mouse)": ("Automatic (appears when the mouse gets close)",
                                                 "Automático (aparece ao aproximar o mouse)"),
    "BÁSICO": ("BASIC", "BÁSICO"),
    "Fondos": ("Wallpapers", "Papéis de parede"),
    "Colores": ("Colors", "Cores"),
    "PERSONALIZAR": ("CUSTOMIZE", "PERSONALIZAR"),
    "Barra": ("Bar", "Barra"),
    "Dock": ("Dock", "Dock"),
    "Ventanas": ("Windows", "Janelas"),
    "Notificaciones": ("Notifications", "Notificações"),
    "Widgets": ("Widgets", "Widgets"),
    "Escritorio": ("Desktop", "Área de trabalho"),
    "Apariencia": ("Appearance", "Aparência"),
    "EQUIPO": ("COMPUTER", "COMPUTADOR"),
    "Pantalla": ("Display", "Tela"),
    "Teclado": ("Keyboard", "Teclado"),
    "Ratón": ("Mouse", "Mouse"),
    "Sonido": ("Sound", "Som"),
    "Energía": ("Power", "Energia"),
    "Unidades": ("Drives", "Unidades"),
    "SISTEMA": ("SYSTEM", "SISTEMA"),
    "Inicio": ("Startup", "Inicialização"),
    "Aplicaciones": ("Applications", "Aplicativos"),
    "Archivos": ("Files", "Arquivos"),
    "Terminal y editor": ("Terminal and editor", "Terminal e editor"),
    "Accesibilidad": ("Accessibility", "Acessibilidade"),
    "AVANZADO": ("ADVANCED", "AVANÇADO"),
    "Texto y cursor": ("Text and cursor", "Texto e cursor"),
    "Perfiles": ("Profiles", "Perfis"),
    "Acerca de GenOS": ("About GenOS", "Sobre o GenOS"),

    # ---- Acerca de: interfaces usadas
    "XFCE": ("XFCE", "XFCE"),
    "Escritorio base": ("Base desktop", "Área de trabalho base"),
    "El panel pasó a pastillas flotantes y casi todos sus ajustes viven en Configuración.":
        ("The panel became floating pills and almost all its settings live in Settings.",
         "O painel virou pílulas flutuantes e quase todos os ajustes ficam em Configurações."),
    "Gestor de ventanas y compositor": ("Window manager and compositor", "Gerenciador de janelas e compositor"),
    "Botones estilo Mac, título centrado, sombras y transparencias.":
        ("Mac-style buttons, centered title, shadows and transparency.",
         "Botões estilo Mac, título centralizado, sombras e transparências."),
    "Plank": ("Plank", "Plank"),
    "Centrado y con zoom; tamaño y posición se cambian desde aquí.":
        ("Centered with zoom; size and position are changed from here.",
         "Centralizado e com zoom; tamanho e posição se mudam aqui."),
    "Rofi": ("Rofi", "Rofi"),
    "Lanzador de aplicaciones": ("Application launcher", "Lançador de aplicativos"),
    "Cuadrícula tipo Launchpad con los colores del fondo.": ("Launchpad-style grid using the wallpaper colors.",
                                                              "Grade estilo Launchpad com as cores do fundo."),
    "Tema GTK, iconos y cursores": ("GTK theme, icons and cursors", "Tema GTK, ícones e cursores"),
    "Variante clara u oscura y acento elegidos según el fondo.": ("Light or dark variant and accent picked from the wallpaper.",
                                                                  "Variante clara ou escura e destaque escolhidos a partir do fundo."),
    "Burbujas en forma de pastilla con el diseño de la barra.": ("Pill-shaped bubbles that match the bar design.",
                                                                  "Balões em forma de pílula com o design da barra."),
    "Terminal de XFCE": ("XFCE Terminal", "Terminal do XFCE"),
    "Terminal": ("Terminal", "Terminal"),
    "Fondo translúcido que sigue el modo claro u oscuro.": ("Translucent background that follows light or dark mode.",
                                                              "Fundo translúcido que acompanha o modo claro ou escuro."),
    "Thunar": ("Thunar", "Thunar"),
    "Gestor de archivos": ("File manager", "Gerenciador de arquivos"),
    "Sin cambios; sus preferencias están en Archivos.": ("Unchanged; its preferences are under Files.",
                                                           "Sem alterações; as preferências ficam em Arquivos."),
    "Acceso al escritorio desde Windows": ("Desktop access from Windows", "Acesso à área de trabalho pelo Windows"),
    "Sesión remota por RDP sobre WSL2.": ("Remote session over RDP on WSL2.", "Sessão remota por RDP sobre o WSL2."),
    "Apps de GenOS": ("GenOS apps", "Aplicativos do GenOS"),
    "Configuración, Fondo, Widgets, Centro de control, Barra y Exportar":
        ("Settings, Wallpaper, Widgets, Control center, Bar and Export",
         "Configurações, Fundo, Widgets, Central de controle, Barra e Exportar"),
    "Escritas en Python con GTK 3 para este sistema.": ("Written in Python with GTK 3 for this system.",
                                                         "Escritos em Python com GTK 3 para este sistema."),

    # ---- Atajos
    "Elegir fondo": ("Choose wallpaper", "Escolher fundo"),
    "Configuración": ("Settings", "Configurações"),
    "Widgets (mostrar u ocultar)": ("Widgets (show or hide)", "Widgets (mostrar ou ocultar)"),
    "Centro de control": ("Control center", "Central de controle"),
    "Automática (la principal)": ("Automatic (the primary one)", "Automática (a principal)"),
    "(sin datos de xrandr)": ("(no xrandr data)", "(sem dados do xrandr)"),
    "Base": ("Base", "Base"),
    "Núcleo": ("Kernel", "Kernel"),
    "Equipo": ("Computer", "Computador"),
    "Procesador": ("Processor", "Processador"),
    "Memoria": ("Memory", "Memória"),
    "sí": ("yes", "sim"),
    "Apps": ("Apps", "Apps"),
    "(sin datos)": ("(no data)", "(sem dados)"),
    "oscuro": ("dark", "escuro"),
    "claro": ("light", "claro"),
})
_TR.update({
    # ---- Cabecera y columna lateral
    "GenOs · Configuración": ("GenOs · Settings", "GenOs · Configurações"),
    "de lo básico a lo avanzado": ("from the basics to the advanced", "do básico ao avançado"),
    "Fondo al azar": ("Random wallpaper", "Fundo aleatório"),
    "Buscar": ("Search", "Buscar"),
    "Vista previa": ("Preview", "Pré-visualização"),
    "Todo automático": ("All automatic", "Tudo automático"),
    "Aplicar cambios": ("Apply changes", "Aplicar alterações"),
    "Automático": ("Automatic", "Automático"),
    "Claro": ("Light", "Claro"),
    "Oscuro": ("Dark", "Escuro"),
    "Sólido": ("Solid", "Sólido"),
    "Cristal": ("Glass", "Vidro"),
    "Teñido": ("Tinted", "Colorido"),

    # ---- Fondos y colores
    "Elige un fondo. El modo, el acento y el contraste se calculan solos a partir de la imagen.":
        ("Pick a wallpaper. Mode, accent and contrast are worked out from the image.",
         "Escolha um fundo. O modo, o destaque e o contraste são calculados a partir da imagem."),
    "Todo sale del fondo, pero puedes forzar cualquier parte.":
        ("Everything comes from the wallpaper, but you can force any part.",
         "Tudo vem do fundo, mas você pode forçar qualquer parte."),
    "Automático sigue el fondo; Claro y Oscuro lo fuerzan.":
        ("Automatic follows the wallpaper; Light and Dark force it.",
         "Automático acompanha o fundo; Claro e Escuro o forçam."),
    "Color de acento": ("Accent color", "Cor de destaque"),
    "Selección, cursor de la terminal y variante del tema.": ("Selection, terminal cursor and theme variant.",
                                                                "Seleção, cursor do terminal e variante do tema."),
    "Estilo de las pastillas": ("Pill style", "Estilo das pílulas"),
    "Sólido tapa el fondo, Cristal lo deja ver y Teñido mezcla el acento.":
        ("Solid covers the wallpaper, Glass lets it show through and Tinted mixes in the accent.",
         "Sólido cobre o fundo, Vidro deixa-o aparecer e Colorido mistura o destaque."),
    "Opacidad mínima": ("Minimum opacity", "Opacidade mínima"),
    "La barra y el lanzador suben solos si el texto pierde contraste (mínimo 4.5:1).":
        ("The bar and the launcher raise it on their own if the text loses contrast (minimum 4.5:1).",
         "A barra e o lançador sobem sozinhos se o texto perder contraste (mínimo 4,5:1)."),
    "Tema GTK": ("GTK theme", "Tema GTK"),
    "Automático elige la variante de WhiteSur que combina con el acento.":
        ("Automatic picks the WhiteSur variant that matches the accent.",
         "Automático escolhe a variante do WhiteSur que combina com o destaque."),
    "Cambio automático día y noche": ("Automatic day and night switch", "Troca automática entre dia e noite"),
    "Usa el modo Claro de día y Oscuro de noche con el fondo que tengas puesto.":
        ("Uses Light mode by day and Dark by night with whatever wallpaper you have.",
         "Usa o modo Claro de dia e Escuro à noite com o fundo que estiver ativo."),
    "El día empieza a las": ("Day starts at", "O dia começa às"),
    "La noche empieza a las": ("Night starts at", "A noite começa às"),

    # ---- Barra
    "Barra superior": ("Top bar", "Barra superior"),
    "Pastillas flotantes sobre el fondo, como una barra de macOS.": ("Floating pills over the wallpaper, like a macOS menu bar.",
                                                                      "Pílulas flutuantes sobre o fundo, como a barra do macOS."),
    "Altura de la barra": ("Bar height", "Altura da barra"),
    "En píxeles. Más baja se ve más discreta.": ("In pixels. Lower looks more discreet.", "Em pixels. Mais baixa fica mais discreta."),
    "Esquinas de las pastillas": ("Pill corners", "Cantos das pílulas"),
    "0 es cuadrado; 20 es casi cápsula.": ("0 is square; 20 is almost a capsule.", "0 é quadrado; 20 é quase uma cápsula."),
    "Tamaño de los iconos": ("Icon size", "Tamanho dos ícones"),
    "Los de la bandeja y los lanzadores.": ("Tray and launcher icons.", "Os da bandeja e dos lançadores."),
    "Ocultar automáticamente": ("Hide automatically", "Ocultar automaticamente"),
    "La barra se esconde y aparece al acercar el cursor.": ("The bar hides and shows again when the cursor gets close.",
                                                             "A barra se esconde e reaparece quando o cursor se aproxima."),
    "Nunca": ("Never", "Nunca"),
    "Si una ventana la tapa": ("When a window covers it", "Quando uma janela a cobre"),
    "Siempre": ("Always", "Sempre"),
    "Bloquear la posición": ("Lock the position", "Bloquear a posição"),
    "Evita moverla o cambiarla por accidente.": ("Prevents moving or changing it by accident.",
                                                  "Evita movê-la ou alterá-la sem querer."),
    "Ordenar la barra": ("Tidy the bar", "Organizar a barra"),
    "Menú y ventanas a la izquierda, reloj al centro, bandeja y botón de energía a la derecha.":
        ("Menu and windows on the left, clock in the middle, tray and power button on the right.",
         "Menu e janelas à esquerda, relógio no centro, bandeja e botão de energia à direita."),
    "Reiniciar la barra": ("Restart the bar", "Reiniciar a barra"),
    "Recarga el panel superior.": ("Reloads the top panel.", "Recarrega o painel superior."),
    "Centro de control: añadir a la barra": ("Control center: add to the bar", "Central de controle: adicionar à barra"),
    "Botón de energía y notificaciones arriba a la derecha.": ("Power button and notifications at the top right.",
                                                                 "Botão de energia e notificações no canto superior direito."),
    "Centro de control: quitar de la barra": ("Control center: remove from the bar", "Central de controle: remover da barra"),
    "El atajo Ctrl+Alt+C sigue funcionando.": ("The Ctrl+Alt+C shortcut keeps working.", "O atalho Ctrl+Alt+C continua funcionando."),
    "Ejecutar": ("Run", "Executar"),
    "Longitud": ("Length", "Comprimento"),
    "Largo de la barra": ("Bar length", "Comprimento da barra"),
    "Porcentaje del ancho de la pantalla.": ("Percentage of the screen width.", "Porcentagem da largura da tela."),
    "Crecer automáticamente si hace falta": ("Grow automatically if needed", "Crescer automaticamente se necessário"),

    # ---- Dock
    "Plank, centrado y con zoom. Los cambios se ven en vivo al aplicar.":
        ("Plank, centered with zoom. Changes show live once applied.",
         "Plank, centralizado e com zoom. As alterações aparecem ao vivo ao aplicar."),
    "Zoom al pasar el mouse": ("Zoom on hover", "Zoom ao passar o mouse"),
    "Efecto de ampliación sobre el icono bajo el cursor.": ("Magnifies the icon under the cursor.",
                                                              "Amplia o ícone sob o cursor."),
    "Intensidad del zoom": ("Zoom strength", "Intensidade do zoom"),
    "Porcentaje de ampliación.": ("Magnification percentage.", "Porcentagem de ampliação."),
    "Posición": ("Position", "Posição"),
    "Visibilidad": ("Visibility", "Visibilidade"),

    # ---- Ventanas
    "Aspecto de los marcos. Las animaciones de abrir y minimizar dependen del gestor de ventanas y no se pueden cambiar aquí.":
        ("Look of the window frames. Open and minimize animations depend on the window manager and cannot be changed here.",
         "Aparência das molduras. As animações de abrir e minimizar dependem do gerenciador de janelas e não podem ser alteradas aqui."),
    "Botones de ventana": ("Window buttons", "Botões da janela"),
    "Izquierda es estilo Mac; derecha, estilo Windows.": ("Left is Mac style; right is Windows style.",
                                                            "Esquerda é estilo Mac; direita, estilo Windows."),
    "A la izquierda": ("On the left", "À esquerda"),
    "A la derecha": ("On the right", "À direita"),
    "Título centrado": ("Centered title", "Título centralizado"),
    "Compositor (sombras y transparencias)": ("Compositor (shadows and transparency)", "Compositor (sombras e transparências)"),
    "Apágalo si notas lentitud; se pierden sombras y la transparencia de la barra.":
        ("Turn it off if things feel slow; you lose shadows and the bar transparency.",
         "Desligue se notar lentidão; perdem-se as sombras e a transparência da barra."),
    "Intensidad de las sombras": ("Shadow strength", "Intensidade das sombras"),
    "Fuente del título": ("Title font", "Fonte do título"),
    "Solo la de la barra de título de las ventanas.": ("Only the one in the window title bar.",
                                                        "Apenas a da barra de título das janelas."),
    "Foco y clics": ("Focus and clicks", "Foco e cliques"),
    "Dar foco al hacer clic": ("Focus on click", "Dar foco ao clicar"),
    "Apagado, el foco sigue al cursor.": ("When off, focus follows the cursor.", "Desligado, o foco acompanha o cursor."),
    "Traer al frente al hacer clic": ("Raise on click", "Trazer para a frente ao clicar"),
    "Dar foco a las ventanas nuevas": ("Focus new windows", "Dar foco às janelas novas"),
    "Evitar que las ventanas roben el foco": ("Prevent windows from stealing focus", "Impedir que as janelas roubem o foco"),
    "Doble clic en el título": ("Double click on the title", "Clique duplo no título"),
    "Maximizar": ("Maximize", "Maximizar"),
    "Enrollar": ("Shade", "Enrolar"),
    "Minimizar": ("Minimize", "Minimizar"),
    "Rellenar": ("Fill", "Preencher"),
    "Nada": ("Nothing", "Nada"),
    "Imán y tamaño": ("Snapping and size", "Ímã e tamanho"),
    "Dónde aparecen las ventanas nuevas": ("Where new windows appear", "Onde as janelas novas aparecem"),
    "Al centro": ("In the center", "No centro"),
    "Bajo el cursor": ("Under the cursor", "Sob o cursor"),
    "Pegarse a los bordes de la pantalla": ("Snap to screen edges", "Grudar nas bordas da tela"),
    "Pegarse a otras ventanas": ("Snap to other windows", "Grudar em outras janelas"),
    "Maximizar sin marcos": ("Maximize without borders", "Maximizar sem bordas"),
    "Las ventanas maximizadas pierden el borde.": ("Maximized windows lose their border.", "As janelas maximizadas perdem a borda."),
    "Alt+Tab": ("Alt+Tab", "Alt+Tab"),
    "Estilo": ("Style", "Estilo"),
    "Iconos en una ventana": ("Icons in a window", "Ícones em uma janela"),
    "Lista de ventanas": ("Window list", "Lista de janelas"),
    "Incluir ventanas minimizadas": ("Include minimized windows", "Incluir janelas minimizadas"),
    "Incluir ventanas de otros escritorios": ("Include windows from other desktops", "Incluir janelas de outras áreas de trabalho"),
    "Marcar la ventana elegida": ("Highlight the selected window", "Destacar a janela escolhida"),
    "Transparencia": ("Transparency", "Transparência"),
    "Ventanas sin foco": ("Windows without focus", "Janelas sem foco"),
    "100 es opaco. Necesita el compositor.": ("100 is opaque. Needs the compositor.", "100 é opaco. Precisa do compositor."),
    "Ventanas mientras las mueves": ("Windows while you move them", "Janelas enquanto você as move"),
    "Marcos de las ventanas": ("Window frames", "Molduras das janelas"),
    "Menús y avisos emergentes": ("Menus and pop-ups", "Menus e avisos pop-up"),
    "Foco: más opciones": ("Focus: more options", "Foco: mais opções"),
    "Respetar las peticiones de foco de las apps": ("Respect focus requests from apps", "Respeitar os pedidos de foco dos aplicativos"),
    "Traer al frente al recibir foco": ("Raise when focused", "Trazer para a frente ao receber foco"),
    "Útil si el foco sigue al cursor.": ("Useful if focus follows the cursor.", "Útil se o foco acompanha o cursor."),
    "Traer al frente con cualquier botón del ratón": ("Raise with any mouse button", "Trazer para a frente com qualquer botão do mouse"),
    "Retardo del foco": ("Focus delay", "Atraso do foco"),
    "Milisegundos; solo cuenta si el foco sigue al cursor.": ("Milliseconds; only applies if focus follows the cursor.",
                                                                "Milissegundos; só conta se o foco acompanha o cursor."),
    "Al activar una ventana desde otro escritorio": ("When activating a window from another desktop",
                                                      "Ao ativar uma janela de outra área de trabalho"),
    "Traerla aquí": ("Bring it here", "Trazê-la para cá"),
    "Ir a su escritorio": ("Go to its desktop", "Ir para a área de trabalho dela"),
    "No hacer nada": ("Do nothing", "Não fazer nada"),
    "Comportamiento": ("Behavior", "Comportamento"),
    "Tamaño mínimo para centrar": ("Minimum size to center", "Tamanho mínimo para centralizar"),
    "Porcentaje de pantalla que debe ocupar una ventana para centrarse.":
        ("Share of the screen a window must fill to be centered.", "Porcentagem da tela que uma janela deve ocupar para ser centralizada."),
    "Distancia del imán": ("Snap distance", "Distância do ímã"),
    "Píxeles.": ("Pixels.", "Pixels."),
    "Resistencia al acercarse a otras ventanas": ("Resistance near other windows", "Resistência ao se aproximar de outras janelas"),
    "Mover solo el contorno": ("Move only the outline", "Mover apenas o contorno"),
    "Más rápido en equipos lentos.": ("Faster on slow computers.", "Mais rápido em computadores lentos."),
    "Cambiar el tamaño solo con contorno": ("Resize with outline only", "Redimensionar apenas com contorno"),
    "Parpadear cuando una ventana pide atención": ("Blink when a window asks for attention", "Piscar quando uma janela pede atenção"),
    "Enrollar la ventana con la rueda sobre el título": ("Shade the window with the wheel over the title",
                                                          "Enrolar a janela com a roda sobre o título"),
    "Cambiar de escritorio con la rueda sobre el escritorio": ("Switch desktops with the wheel over the desktop",
                                                                 "Trocar de área de trabalho com a roda sobre ela"),
    "Pulsar otra vez el atajo vuelve al escritorio anterior": ("Pressing the shortcut again returns to the previous desktop",
                                                                 "Pressionar o atalho de novo volta à área de trabalho anterior"),
    "Dar la vuelta al llevar una ventana al borde": ("Wrap around when dragging a window to the edge",
                                                      "Dar a volta ao arrastar uma janela até a borda"),
    "Compositor": ("Compositor", "Compositor"),
    "Apagada": ("Off", "Desligada"),
    "Automática": ("Automatic", "Automática"),
    "Sombra en las ventanas": ("Shadow on windows", "Sombra nas janelas"),
    "Sombra en menús y avisos": ("Shadow on menus and pop-ups", "Sombra em menus e avisos"),
    "Sombra en el dock y la barra": ("Shadow on the dock and bar", "Sombra no dock e na barra"),
    "Zoom del escritorio con Alt y la rueda": ("Desktop zoom with Alt and the wheel", "Zoom da área de trabalho com Alt e a roda"),
    "Sincronía vertical": ("Vertical sync", "Sincronia vertical"),
    "Evita cortes en la imagen; en escritorio remoto déjalo en automático.":
        ("Avoids screen tearing; on a remote desktop leave it on automatic.",
         "Evita cortes na imagem; em área de trabalho remota deixe em automático."),

    # ---- Notificaciones
    "Las burbujas toman el diseño de la barra: pastilla con el color del fondo y botones con tu acento.":
        ("Bubbles use the bar design: a pill in the wallpaper color and buttons in your accent.",
         "Os balões seguem o design da barra: pílula na cor do fundo e botões com o seu destaque."),
    "No molestar": ("Do not disturb", "Não perturbe"),
    "No muestra ninguna burbuja mientras esté activado.": ("Shows no bubbles while it is on.", "Não mostra nenhum balão enquanto estiver ativo."),
    "Duración": ("Duration", "Duração"),
    "Segundos en pantalla antes de desvanecerse.": ("Seconds on screen before fading out.", "Segundos na tela antes de desaparecer."),
    "Opacidad": ("Opacity", "Opacidade"),
    "Se suma a la transparencia de la pastilla.": ("Adds to the pill transparency.", "Soma-se à transparência da pílula."),
    "Desvanecer al cerrar": ("Fade out on close", "Desvanecer ao fechar"),
    "Deslizar al cerrar": ("Slide out on close", "Deslizar ao fechar"),
    "Mostrar el valor de las barras de volumen y brillo": ("Show the value on volume and brightness bars",
                                                            "Mostrar o valor nas barras de volume e brilho"),
    "Pantalla de las burbujas": ("Screen for bubbles", "Tela dos balões"),
    "La del cursor": ("The one with the cursor", "A do cursor"),
    "La principal": ("The primary one", "A principal"),
    "Probar": ("Try", "Testar"),
    "Enviar notificaciones de prueba": ("Send test notifications", "Enviar notificações de teste"),
    "Aplica estos ajustes y muestra tres burbujas de ejemplo.": ("Applies these settings and shows three sample bubbles.",
                                                                  "Aplica estes ajustes e mostra três balões de exemplo."),
    "Historial y aplicaciones": ("History and applications", "Histórico e aplicativos"),
    "El diálogo de XFCE: historial de avisos y apps silenciadas.": ("The XFCE dialog: notification history and muted apps.",
                                                                      "O diálogo do XFCE: histórico de avisos e aplicativos silenciados."),
    "Abrir": ("Open", "Abrir"),

    # ---- Widgets
    "Tarjetas flotantes en el escritorio con los colores del fondo. Reloj y Sistema vienen activados; el resto son opcionales.":
        ("Floating cards on the desktop in the wallpaper colors. Clock and System are on; the rest are optional.",
         "Cartões flutuantes na área de trabalho com as cores do fundo. Relógio e Sistema vêm ativados; o resto é opcional."),
    "Mostrar widgets": ("Show widgets", "Mostrar widgets"),
    "Atajo para ocultarlos o mostrarlos al instante: Ctrl+Alt+W.": ("Shortcut to hide or show them instantly: Ctrl+Alt+W.",
                                                                      "Atalho para ocultá-los ou mostrá-los na hora: Ctrl+Alt+W."),
    "Dónde se colocan. Si se salen de tu pantalla, elige otra de la lista.":
        ("Where they sit. If they fall off your screen, pick another one from the list.",
         "Onde ficam. Se saírem da sua tela, escolha outra da lista."),
    "Tamaño": ("Size", "Tamanho"),
    "Opacidad de las tarjetas": ("Card opacity", "Opacidade dos cartões"),
    "Por defecto se calcula sola para que el texto se lea bien.": ("By default it is calculated so the text stays readable.",
                                                                    "Por padrão é calculada para que o texto fique legível."),

    # ---- Escritorio
    "Iconos sobre el fondo y escritorios virtuales.": ("Icons on the wallpaper and virtual desktops.",
                                                       "Ícones sobre o fundo e áreas de trabalho virtuais."),
    "Iconos del escritorio": ("Desktop icons", "Ícones da área de trabalho"),
    "Ninguno": ("None", "Nenhum"),
    "Ventanas minimizadas": ("Minimized windows", "Janelas minimizadas"),
    "Archivos y carpetas": ("Files and folders", "Arquivos e pastas"),
    "Mostrar Carpeta personal": ("Show Home folder", "Mostrar Pasta pessoal"),
    "Mostrar Sistema de archivos": ("Show File system", "Mostrar Sistema de arquivos"),
    "Mostrar Papelera": ("Show Trash", "Mostrar Lixeira"),
    "Mostrar unidades extraíbles": ("Show removable drives", "Mostrar unidades removíveis"),
    "Escritorios virtuales": ("Virtual desktops", "Áreas de trabalho virtuais"),
    "Cantidad": ("Number", "Quantidade"),
    "Los cuadritos del selector de la barra salen de aquí.": ("The squares in the bar switcher come from this.",
                                                                "Os quadradinhos do seletor da barra vêm daqui."),
    "Dar la vuelta al llegar al último": ("Wrap around after the last one", "Dar a volta ao chegar na última"),
    "Nombres de los escritorios": ("Desktop names", "Nomes das áreas de trabalho"),
    "Escritorio %d": ("Desktop %d", "Área de trabalho %d"),
    "Márgenes de pantalla": ("Screen margins", "Margens da tela"),
    "Espacio que las ventanas maximizadas no ocupan.": ("Space that maximized windows leave free.",
                                                         "Espaço que as janelas maximizadas não ocupam."),
})
_TR.update({
    # ---- Pantalla y teclado
    "Resolución y tamaño de la interfaz. En escritorio remoto, la ventana de mstsc manda.":
        ("Resolution and interface size. On a remote desktop, the mstsc window decides.",
         "Resolução e tamanho da interface. Em área de trabalho remota, a janela do mstsc manda."),
    "Resolución": ("Resolution", "Resolução"),
    "Aplicar resolución": ("Apply resolution", "Aplicar resolução"),
    "Cambiar ahora": ("Change now", "Mudar agora"),
    "Se aplica al instante; si no se ve bien, vuelve a elegir la anterior.":
        ("Applies instantly; if it looks wrong, pick the previous one again.",
         "Aplica na hora; se não ficar bom, escolha a anterior de novo."),
    "Tamaño de la interfaz (DPI)": ("Interface size (DPI)", "Tamanho da interface (DPI)"),
    "96 es lo normal; sube a 120 o 144 si todo se ve pequeño.": ("96 is normal; raise it to 120 or 144 if everything looks small.",
                                                                   "96 é o normal; suba para 120 ou 144 se tudo parecer pequeno."),
    "<span size='small'>El DPI se aplica con el botón Aplicar de abajo; algunas apps lo toman al reabrirse.</span>":
        ("<span size='small'>DPI is applied with the Apply button below; some apps pick it up when reopened.</span>",
         "<span size='small'>O DPI é aplicado com o botão Aplicar abaixo; alguns aplicativos só o adotam ao reabrir.</span>"),
    "Distribución, velocidad de repetición y atajos de GenOs.": ("Layout, key repeat speed and GenOs shortcuts.",
                                                                  "Layout, velocidade de repetição e atalhos do GenOs."),
    "Distribución": ("Layout", "Layout"),
    "En escritorio remoto, Windows también envía su propia distribución; si las teclas salen mal, prueba otra.":
        ("On a remote desktop Windows also sends its own layout; if keys come out wrong, try another one.",
         "Em área de trabalho remota o Windows também envia o próprio layout; se as teclas saírem erradas, tente outro."),
    "Variante": ("Variant", "Variante"),
    "Retardo de repetición": ("Repeat delay", "Atraso de repetição"),
    "Milisegundos antes de que una tecla empiece a repetirse.": ("Milliseconds before a key starts repeating.",
                                                                   "Milissegundos antes de uma tecla começar a repetir."),
    "Velocidad de repetición": ("Repeat speed", "Velocidade de repetição"),
    "Repeticiones por segundo.": ("Repeats per second.", "Repetições por segundo."),
    "Repetir teclas al mantenerlas": ("Repeat keys when held", "Repetir teclas ao mantê-las pressionadas"),
    "Recordar el estado de Bloq Num": ("Remember the Num Lock state", "Lembrar o estado do Num Lock"),
    "Al iniciar sesión.": ("At login.", "Ao entrar."),
    "Atajos de GenOs": ("GenOs shortcuts", "Atalhos do GenOs"),
    "Sin atajo": ("No shortcut", "Sem atalho"),
    "Nuevo atajo": ("New shortcut", "Novo atalho"),
    "Pulsa la combinación nueva (con Ctrl, Alt o Super).": ("Press the new combination (with Ctrl, Alt or Super).",
                                                              "Pressione a nova combinação (com Ctrl, Alt ou Super)."),
    "Ese atajo no existe todavía; corre otra vez el instalador dentro de XFCE.":
        ("That shortcut does not exist yet; run the installer again inside XFCE.",
         "Esse atalho ainda não existe; execute o instalador de novo dentro do XFCE."),
    "Cancelar": ("Cancel", "Cancelar"),

    # ---- Inicio
    "Aplicaciones que se abren al entrar en la sesión.": ("Applications that open when you log in.",
                                                           "Aplicativos que abrem ao entrar na sessão."),
    "Sesión": ("Session", "Sessão"),
    "Guardar la sesión al cerrar": ("Save the session on logout", "Salvar a sessão ao sair"),
    "Reabre las ventanas que tenías.": ("Reopens the windows you had.", "Reabre as janelas que você tinha."),
    "Preguntar antes de cerrar sesión": ("Ask before logging out", "Perguntar antes de sair"),
    "Bloquear la pantalla antes de suspender": ("Lock the screen before suspending", "Bloquear a tela antes de suspender"),
    "Elegir la sesión al entrar": ("Choose the session at login", "Escolher a sessão ao entrar"),
    "Aplicaciones que se abren al iniciar": ("Applications that open at startup", "Aplicativos que abrem na inicialização"),
    "Añadir aplicación…": ("Add application…", "Adicionar aplicativo…"),
    "No hay aplicaciones de inicio": ("No startup applications", "Não há aplicativos de inicialização"),

    # ---- Apariencia
    "Iconos, suavizado de letras y detalles de la interfaz. El tema de colores sale de Colores.":
        ("Icons, font smoothing and interface details. The color theme comes from Colors.",
         "Ícones, suavização de fontes e detalhes da interface. O tema de cores vem de Cores."),
    "Iconos": ("Icons", "Ícones"),
    "Tema de iconos": ("Icon theme", "Tema de ícones"),
    "WhiteSur es el que usa el diseño.": ("WhiteSur is the one the design uses.", "O WhiteSur é o que o design usa."),
    "Suavizado de letras": ("Font smoothing", "Suavização de fontes"),
    "Suavizar los bordes": ("Smooth the edges", "Suavizar as bordas"),
    "Ajustar las letras a la rejilla": ("Snap letters to the pixel grid", "Ajustar as letras à grade de pixels"),
    "Intensidad del ajuste": ("Hinting strength", "Intensidade do ajuste"),
    "Suave": ("Slight", "Suave"),
    "Medio": ("Medium", "Médio"),
    "Completo": ("Full", "Completo"),
    "Orden de subpíxeles": ("Subpixel order", "Ordem dos subpixels"),
    "Para pantallas LCD; en escritorio remoto déjalo en ninguno.": ("For LCD screens; on a remote desktop leave it on none.",
                                                                      "Para telas LCD; em área de trabalho remota deixe em nenhum."),
    "Interfaz": ("Interface", "Interface"),
    "Barras de herramientas": ("Toolbars", "Barras de ferramentas"),
    "Solo iconos": ("Icons only", "Apenas ícones"),
    "Solo texto": ("Text only", "Apenas texto"),
    "Texto bajo los iconos": ("Text below icons", "Texto abaixo dos ícones"),
    "Texto al lado": ("Text beside icons", "Texto ao lado"),
    "Iconos en los botones": ("Icons on buttons", "Ícones nos botões"),
    "Iconos en los menús": ("Icons in menus", "Ícones nos menus"),
    "Sonidos de eventos": ("Event sounds", "Sons de eventos"),
    "Sonido al pulsar teclas y botones": ("Sound when pressing keys and buttons", "Som ao pressionar teclas e botões"),

    # ---- Ratón
    "Ratón y touchpad": ("Mouse and touchpad", "Mouse e touchpad"),
    "Velocidad y botones del dispositivo que elijas.": ("Speed and buttons for the device you choose.",
                                                          "Velocidade e botões do dispositivo escolhido."),
    "Dispositivo": ("Device", "Dispositivo"),
    "Botones y desplazamiento": ("Buttons and scrolling", "Botões e rolagem"),
    "Botones para zurdos": ("Left-handed buttons", "Botões para canhotos"),
    "Intercambia el botón principal y el secundario.": ("Swaps the primary and secondary buttons.",
                                                          "Troca o botão principal e o secundário."),
    "Invertir el sentido del desplazamiento": ("Reverse the scrolling direction", "Inverter o sentido da rolagem"),
    "Velocidad": ("Speed", "Velocidade"),
    "Aceleración": ("Acceleration", "Aceleração"),
    "Más alta, el cursor llega más lejos con el mismo gesto.": ("Higher, and the cursor goes farther with the same movement.",
                                                                  "Mais alta, o cursor vai mais longe com o mesmo movimento."),
    "Sensibilidad para arrastrar": ("Drag sensitivity", "Sensibilidade para arrastar"),
    "Píxeles que hay que mover antes de arrastrar.": ("Pixels to move before a drag starts.",
                                                        "Pixels a mover antes de começar a arrastar."),
    "Cambia al instante; no hace falta pulsar Aplicar.": ("Changes instantly; no need to press Apply.",
                                                            "Muda na hora; não precisa pressionar Aplicar."),

    # ---- Sonido
    "Salida": ("Output", "Saída"),
    "Entrada": ("Input", "Entrada"),
    "Volumen": ("Volume", "Volume"),
    "Pasar de 100 puede distorsionar.": ("Going above 100 can distort.", "Passar de 100 pode distorcer."),
    "Silenciar": ("Mute", "Silenciar"),
    "No encuentro pactl. Instala pulseaudio-utils para controlar el volumen desde aquí.":
        ("I cannot find pactl. Install pulseaudio-utils to control the volume from here.",
         "Não encontro o pactl. Instale o pulseaudio-utils para controlar o volume daqui."),

    # ---- Energía
    "Pantalla, avisos y bloqueo. En WSL no hay suspensión, así que solo salen las opciones que sirven.":
        ("Display, alerts and lock. WSL has no suspend, so only the options that work are shown.",
         "Tela, avisos e bloqueio. No WSL não há suspensão, então só aparecem as opções que funcionam."),
    "Avisos": ("Alerts", "Avisos"),
    "Notificaciones de estado": ("Status notifications", "Notificações de estado"),
    "Batería baja, cable conectado, etc.": ("Low battery, cable plugged in, and so on.", "Bateria baixa, cabo conectado, etc."),
    "Icono de energía en la bandeja": ("Power icon in the tray", "Ícone de energia na bandeja"),
    "Apagar la pantalla por inactividad": ("Turn off the screen when idle", "Desligar a tela por inatividade"),
    "Con corriente": ("On AC power", "Com energia elétrica"),
    "Minutos hasta apagar la pantalla; 0 es nunca.": ("Minutes until the screen turns off; 0 means never.",
                                                        "Minutos até desligar a tela; 0 é nunca."),
    "Con batería": ("On battery", "Com bateria"),
    "Bloquear la pantalla al suspender": ("Lock the screen on suspend", "Bloquear a tela ao suspender"),

    # ---- Unidades
    "Unidades extraíbles": ("Removable drives", "Unidades removíveis"),
    "Qué hacer cuando conectas una memoria USB, un disco o un CD.": ("What to do when you plug in a USB stick, a disk or a CD.",
                                                                       "O que fazer ao conectar um pendrive, um disco ou um CD."),
    "Almacenamiento": ("Storage", "Armazenamento"),
    "Montar al conectar": ("Mount on connect", "Montar ao conectar"),
    "Montar los medios al insertarlos": ("Mount media when inserted", "Montar as mídias ao inserir"),
    "Abrirlos en el explorador de archivos": ("Open them in the file manager", "Abri-las no gerenciador de arquivos"),
    "Ejecutar los programas automáticos": ("Run autorun programs", "Executar os programas automáticos"),
    "Abrir sus archivos al conectar": ("Open their files on connect", "Abrir os arquivos ao conectar"),
    "Discos vacíos": ("Blank discs", "Discos vazios"),
    "Grabar un CD o DVD al insertar uno vacío": ("Burn a CD or DVD when a blank one is inserted",
                                                   "Gravar um CD ou DVD ao inserir um vazio"),

    # ---- Aplicaciones y portapapeles
    "Qué programa se abre por defecto y cómo se comporta el portapapeles.": ("Which program opens by default and how the clipboard behaves.",
                                                                                "Qual programa abre por padrão e como a área de transferência se comporta."),
    "Navegador web": ("Web browser", "Navegador web"),
    "Correo": ("Mail", "E-mail"),
    "(sin elegir)": ("(not chosen)", "(não escolhido)"),
    "Portapapeles": ("Clipboard", "Área de transferência"),
    "Guardar el historial al cerrar sesión": ("Save the history on logout", "Salvar o histórico ao sair"),
    "Sincronizar la selección del ratón con Ctrl+C": ("Sync the mouse selection with Ctrl+C",
                                                        "Sincronizar a seleção do mouse com Ctrl+C"),
    "Textos en el historial": ("Texts in the history", "Textos no histórico"),
    "Elementos en el menú": ("Items in the menu", "Itens no menu"),
    "Abrir el menú bajo el cursor": ("Open the menu under the cursor", "Abrir o menu sob o cursor"),
    "Solo con el atajo de xfce4-popup-clipman.": ("Only with the xfce4-popup-clipman shortcut.",
                                                    "Só com o atalho do xfce4-popup-clipman."),
    "Al elegir un elemento": ("When picking an item", "Ao escolher um item"),
    "Solo copiarlo": ("Only copy it", "Apenas copiar"),
    "Pegarlo con Ctrl+V": ("Paste it with Ctrl+V", "Colar com Ctrl+V"),
    "Pegarlo con Shift+Insertar": ("Paste it with Shift+Insert", "Colar com Shift+Insert"),

    # ---- Archivos (Thunar)
    "Preferencias de Thunar, el gestor de archivos.": ("Preferences for Thunar, the file manager.",
                                                         "Preferências do Thunar, o gerenciador de arquivos."),
    "Vista": ("View", "Visualização"),
    "Vista para las carpetas nuevas": ("View for new folders", "Visualização para pastas novas"),
    "La última usada": ("The last one used", "A última usada"),
    "Lista detallada": ("Detailed list", "Lista detalhada"),
    "Lista compacta": ("Compact list", "Lista compacta"),
    "Carpetas antes que archivos": ("Folders before files", "Pastas antes dos arquivos"),
    "Tamaños en formato binario (KiB, MiB)": ("Sizes in binary format (KiB, MiB)", "Tamanhos em formato binário (KiB, MiB)"),
    "Nombre al lado de los iconos": ("Name beside the icons", "Nome ao lado dos ícones"),
    "Recordar el tamaño de la ventana": ("Remember the window size", "Lembrar o tamanho da janela"),
    "Formato de fecha": ("Date format", "Formato de data"),
    "Hoy y ayer": ("Today and yesterday", "Hoje e ontem"),
    "Corto": ("Short", "Curto"),
    "Largo": ("Long", "Longo"),
    "Miniaturas": ("Thumbnails", "Miniaturas"),
    "Mostrar miniaturas": ("Show thumbnails", "Mostrar miniaturas"),
    "Solo en archivos locales": ("Local files only", "Apenas em arquivos locais"),
    "Marco alrededor de las miniaturas": ("Frame around thumbnails", "Moldura ao redor das miniaturas"),
    "Navegación": ("Navigation", "Navegação"),
    "Abrir con un solo clic": ("Open with a single click", "Abrir com um único clique"),
    "Se guardan al instante, sin pulsar Aplicar.": ("Saved instantly, without pressing Apply.",
                                                      "Salvos na hora, sem pressionar Aplicar."),

    # ---- Accesibilidad
    "Ayudas de teclado y ratón para quien las necesite.": ("Keyboard and mouse aids for anyone who needs them.",
                                                             "Ajudas de teclado e mouse para quem precisar."),
    "Teclas especiales": ("Sticky keys", "Teclas de aderência"),
    "Ctrl, Alt y Mayús se pulsan de una en una.": ("Ctrl, Alt and Shift are pressed one at a time.",
                                                     "Ctrl, Alt e Shift são pressionadas uma de cada vez."),
    "Teclas lentas": ("Slow keys", "Teclas lentas"),
    "Hay que mantener la tecla un momento.": ("The key has to be held for a moment.", "É preciso manter a tecla por um instante."),
    "Teclas de rebote": ("Bounce keys", "Teclas de repique"),
    "Ignora pulsaciones repetidas muy rápido.": ("Ignores very fast repeated presses.", "Ignora pressionamentos repetidos muito rápidos."),
    "Mover el cursor con el teclado numérico": ("Move the cursor with the numeric keypad", "Mover o cursor com o teclado numérico"),

    # ---- Terminal y editor
    "Fuente": ("Font", "Fonte"),
    "Se aplica a las terminales nuevas.": ("Applies to new terminals.", "Aplica-se aos terminais novos."),
    "Opacidad del fondo": ("Background opacity", "Opacidade do fundo"),
    "Más bajo se ve más transparente.": ("Lower looks more transparent.", "Mais baixo fica mais transparente."),
    "Líneas guardadas al desplazar": ("Lines kept for scrolling", "Linhas guardadas para rolagem"),
    "Forma del cursor": ("Cursor shape", "Formato do cursor"),
    "Bloque": ("Block", "Bloco"),
    "Subrayado": ("Underline", "Sublinhado"),
    "Cursor parpadeante": ("Blinking cursor", "Cursor piscante"),
    "Sonido de campana": ("Bell sound", "Som de sino"),
    "Ancho de tabulación": ("Tab width", "Largura da tabulação"),
    "Editor de texto (Mousepad)": ("Text editor (Mousepad)", "Editor de texto (Mousepad)"),
    "Mousepad no está instalado": ("Mousepad is not installed", "O Mousepad não está instalado"),
    "Cuando lo instales, sus opciones saldrán aquí.": ("Once you install it, its options will show up here.",
                                                         "Quando você o instalar, as opções aparecerão aqui."),
    "Mostrar números de línea": ("Show line numbers", "Mostrar números de linha"),
    "Ajustar las líneas largas": ("Wrap long lines", "Quebrar linhas longas"),
    "Resaltar la línea actual": ("Highlight the current line", "Destacar a linha atual"),
    "Sangría automática": ("Auto indent", "Recuo automático"),

    # ---- Texto y cursor
    "Tipografía general y tamaño del cursor.": ("General typography and cursor size.", "Tipografia geral e tamanho do cursor."),
    "Fuente de la interfaz": ("Interface font", "Fonte da interface"),
    "Inter 10 es la que usa el diseño.": ("Inter 10 is the one the design uses.", "A Inter 10 é a que o design usa."),
    "Tamaño del cursor": ("Cursor size", "Tamanho do cursor"),
    "Tema del cursor": ("Cursor theme", "Tema do cursor"),
    "Se aplica al volver a entrar en la sesión.": ("Applies the next time you log in.", "Aplica-se ao entrar de novo na sessão."),
    "Fuente de texto monoespaciado": ("Monospace font", "Fonte monoespaçada"),
    "Terminales y editores.": ("Terminals and editors.", "Terminais e editores."),
    "Cursor de texto parpadeante": ("Blinking text cursor", "Cursor de texto piscante"),
    "Velocidad del parpadeo": ("Blink speed", "Velocidade da piscada"),
    "Milisegundos por ciclo.": ("Milliseconds per cycle.", "Milissegundos por ciclo."),
})
_TR.update({
    # ---- Perfiles
    "Guarda tu combinación (fondo, colores, barra, dock y ventanas) y vuelve a ella cuando quieras.":
        ("Save your combination (wallpaper, colors, bar, dock and windows) and return to it whenever you like.",
         "Salve sua combinação (fundo, cores, barra, dock e janelas) e volte a ela quando quiser."),
    "Incluidos": ("Included", "Incluídos"),
    "Cargar": ("Load", "Carregar"),
    "Tus perfiles": ("Your profiles", "Seus perfis"),
    "Nombre del perfil": ("Profile name", "Nome do perfil"),
    "Guardar el actual": ("Save the current one", "Salvar o atual"),
    "Compartir": ("Share", "Compartilhar"),
    "Exportar": ("Export", "Exportar"),
    "Exportar mi tema a Windows": ("Export my theme to Windows", "Exportar meu tema para o Windows"),
    "Crea un .zip con el fondo, los colores y el dock, más una captura, en tu carpeta Descargas.":
        ("Creates a .zip with the wallpaper, colors and dock, plus a screenshot, in your Downloads folder.",
         "Cria um .zip com o fundo, as cores e o dock, mais uma captura, na pasta Downloads."),
    "Importar": ("Import", "Importar"),
    "Importar un tema": ("Import a theme", "Importar um tema"),
    "Aplica un .zip exportado desde otro GenOS.": ("Applies a .zip exported from another GenOS.",
                                                    "Aplica um .zip exportado de outro GenOS."),
    "Importar un tema de GenOS": ("Import a GenOS theme", "Importar um tema do GenOS"),
    "Temas exportados (.zip)": ("Exported themes (.zip)", "Temas exportados (.zip)"),
    "Todavía no guardas ninguno.": ("You have not saved any yet.", "Você ainda não salvou nenhum."),
    "Borrar": ("Delete", "Apagar"),
    "Ponle un nombre al perfil.": ("Give the profile a name.", "Dê um nome ao perfil."),
    "Perfil «%s» guardado.": ("Profile “%s” saved.", "Perfil “%s” salvo."),
    "<b>%s</b>\nmodo %s · acento %s · tema %s": ("<b>%s</b>\nmode %s · accent %s · theme %s",
                                                  "<b>%s</b>\nmodo %s · destaque %s · tema %s"),
    "Exportando…": ("Exporting…", "Exportando…"),
    "Exportado": ("Exported", "Exportado"),
    "No pude exportar. Corre genos-exportar en la terminal.": ("I could not export. Run genos-exportar in the terminal.",
                                                                 "Não consegui exportar. Execute genos-exportar no terminal."),
    "Importando…": ("Importing…", "Importando…"),
    "Tema importado.": ("Theme imported.", "Tema importado."),
    "No pude importarlo. Prueba: genos-exportar --importar archivo.zip":
        ("I could not import it. Try: genos-exportar --importar file.zip",
         "Não consegui importar. Tente: genos-exportar --importar arquivo.zip"),

    # ---- Sistema
    "Utilidades para cuando algo no se ve como debe.": ("Tools for when something does not look right.",
                                                         "Utilitários para quando algo não aparece como deveria."),
    "Reiniciar el dock": ("Restart the dock", "Reiniciar o dock"),
    "Cierra Plank y lo vuelve a abrir.": ("Closes Plank and opens it again.", "Fecha o Plank e o abre de novo."),
    "Abrir la carpeta de fondos": ("Open the wallpapers folder", "Abrir a pasta de fundos"),
    "Reiniciar el escritorio": ("Restart the desktop", "Reiniciar a área de trabalho"),
    "Recarga los iconos y el fondo del escritorio.": ("Reloads the desktop icons and wallpaper.",
                                                        "Recarrega os ícones e o fundo da área de trabalho."),
    "Volver a lo automático": ("Back to automatic", "Voltar ao automático"),
    "Quita todos los ajustes manuales de color, tema y opacidad.": ("Removes all manual color, theme and opacity settings.",
                                                                      "Remove todos os ajustes manuais de cor, tema e opacidade."),
    "Idioma": ("Language", "Idioma"),
    "Idioma del programa": ("Program language", "Idioma do programa"),
    "Configuración se reabre sola. El Centro de control y los widgets lo toman la próxima vez que se abran.":
        ("Settings reopens by itself. The Control center and widgets pick it up the next time they open.",
         "A Configuração reabre sozinha. A Central de controle e os widgets adotam o idioma na próxima abertura."),
    "Gestor de ajustes de XFCE": ("XFCE Settings Manager", "Gerenciador de ajustes do XFCE"),
    "Reemplazar el Gestor de ajustes de XFCE": ("Replace the XFCE Settings Manager", "Substituir o Gerenciador de ajustes do XFCE"),
    "Configuración ocupa su lugar en el menú, el dock y la línea de comandos. Se esconden las entradas que ya tiene.":
        ("Settings takes its place in the menu, the dock and the command line. The entries it already covers are hidden.",
         "A Configuração assume o lugar dele no menu, no dock e na linha de comando. As entradas que ela já cobre ficam ocultas."),
    "Abrir el gestor original": ("Open the original manager", "Abrir o gerenciador original"),
    "El de XFCE, por si falta algo en Configuración.": ("The XFCE one, in case something is missing in Settings.",
                                                          "O do XFCE, caso falte algo na Configuração."),
    "Diálogos originales de XFCE (avanzado)": ("Original XFCE dialogs (advanced)", "Diálogos originais do XFCE (avançado)"),
    "Elementos de la barra": ("Bar items", "Itens da barra"),
    "Pantalla completa": ("Full display", "Tela completa"),
    "Teclado y atajos": ("Keyboard and shortcuts", "Teclado e atalhos"),
    "Escritorio y fondo": ("Desktop and wallpaper", "Área de trabalho e fundo"),
    "Gestor de ventanas": ("Window manager", "Gerenciador de janelas"),
    "Ajustes extra de ventanas": ("Extra window tweaks", "Ajustes extras de janelas"),
    "Sesión e inicio": ("Session and startup", "Sessão e inicialização"),
    "Aplicaciones predeterminadas": ("Default applications", "Aplicativos padrão"),
    "Preferencias de Thunar": ("Thunar preferences", "Preferências do Thunar"),
    "Mezclador de sonido": ("Sound mixer", "Mixer de som"),
    "Perfiles de color": ("Color profiles", "Perfis de cor"),
    "Terminal (diálogo original)": ("Terminal (original dialog)", "Terminal (diálogo original)"),
    "Editor de ajustes": ("Settings editor", "Editor de ajustes"),
    "<span size='small'>Comandos útiles:  <tt>genos-fondo</tt> lista los fondos,  <tt>genos-fondo 7</tt> aplica el 7,  <tt>genos-fondo --elegir</tt> abre el selector rápido.</span>":
        ("<span size='small'>Handy commands:  <tt>genos-fondo</tt> lists the wallpapers,  <tt>genos-fondo 7</tt> applies number 7,  <tt>genos-fondo --elegir</tt> opens the quick picker.</span>",
         "<span size='small'>Comandos úteis:  <tt>genos-fondo</tt> lista os fundos,  <tt>genos-fondo 7</tt> aplica o 7,  <tt>genos-fondo --elegir</tt> abre o seletor rápido.</span>"),

    # ---- Acerca de
    "Un escritorio minimalista y ligero, hecho a mano sobre XFCE.": ("A minimal, light desktop built by hand on top of XFCE.",
                                                                       "Uma área de trabalho minimalista e leve, feita à mão sobre o XFCE."),
    "<span size='11000'>Versión %s  ·  basado en %s</span>": ("<span size='11000'>Version %s  ·  based on %s</span>",
                                                              "<span size='11000'>Versão %s  ·  baseado em %s</span>"),
    "Este equipo": ("This computer", "Este computador"),
    "Interfaces usadas y modificadas": ("Interfaces used and modified", "Interfaces usadas e modificadas"),
    "Copiar información": ("Copy information", "Copiar informações"),
    "Información copiada.": ("Information copied.", "Informações copiadas."),
    "Créditos": ("Credits", "Créditos"),
    "Proyecto de Duvan Esteban Chaparro Castro.": ("A project by Duvan Esteban Chaparro Castro.",
                                                   "Projeto de Duvan Esteban Chaparro Castro."),
    "Diseñado y programado con la ayuda de Claude, de Anthropic.": ("Designed and programmed with the help of Claude, by Anthropic.",
                                                                      "Projetado e programado com a ajuda do Claude, da Anthropic."),
    "Se apoya en software libre: Debian, XFCE, Plank, Rofi, xrdp, Thunar, Mousepad y el tema WhiteSur. Cada proyecto es de sus autores y conserva su licencia.":
        ("It builds on free software: Debian, XFCE, Plank, Rofi, xrdp, Thunar, Mousepad and the WhiteSur theme. Each project belongs to its authors and keeps its license.",
         "Usa software livre: Debian, XFCE, Plank, Rofi, xrdp, Thunar, Mousepad e o tema WhiteSur. Cada projeto pertence aos seus autores e mantém a sua licença."),
    "Cerrar": ("Close", "Fechar"),
    "%s  ·  %s": ("%s  ·  %s", "%s  ·  %s"),
    "GenOS %s": ("GenOS %s", "GenOS %s"),
    "Ajustes de GenOS": ("GenOS settings", "Ajustes do GenOS"),

    # ---- Mensajes de estado
    "Enviando pruebas…": ("Sending tests…", "Enviando testes…"),
    "Listo, mira la esquina de la pantalla.": ("Done, look at the corner of the screen.", "Pronto, olhe o canto da tela."),
    "Falta notify-send (sudo apt install libnotify-bin).": ("notify-send is missing (sudo apt install libnotify-bin).",
                                                              "Falta o notify-send (sudo apt install libnotify-bin)."),
    "GenOs": ("GenOs", "GenOs"),
    "Así se ven las notificaciones con tu tema.": ("This is how notifications look with your theme.",
                                                     "É assim que as notificações ficam com o seu tema."),
    "Mensaje nuevo": ("New message", "Nova mensagem"),
    "Esteban: la ventana de Configuración ya quedó.": ("Esteban: the Settings window is done.",
                                                         "Esteban: a janela de Configurações ficou pronta."),
    "Batería baja": ("Low battery", "Bateria baixa"),
    "Conecta el cargador.": ("Plug in the charger.", "Conecte o carregador."),
    "Aplicando…": ("Applying…", "Aplicando…"),
    "Listo, aplicado.": ("Done, applied.", "Pronto, aplicado."),
    "Algo falló: %s\nDetalle en ~/.cache/genos-fondo/error.log": ("Something failed: %s\nDetails in ~/.cache/genos-fondo/error.log",
                                                                    "Algo falhou: %s\nDetalhes em ~/.cache/genos-fondo/error.log"),
    "no encuentro la sesión de XFCE; abre Configuración desde el escritorio":
        ("I cannot find the XFCE session; open Settings from the desktop",
         "não encontro a sessão do XFCE; abra a Configuração pela área de trabalho"),
    "No sé cuál es el fondo actual.": ("I do not know which wallpaper is current.", "Não sei qual é o fundo atual."),
    "Resolución cambiada a %s.": ("Resolution changed to %s.", "Resolução alterada para %s."),
    "xrandr no pudo: %s": ("xrandr could not: %s", "o xrandr não conseguiu: %s"),
    "Pantalla %d: %dx%d en %d,%d": ("Display %d: %dx%d at %d,%d", "Tela %d: %dx%d em %d,%d"),
    "Configuración reemplaza al Gestor de ajustes. Entradas escondidas: %d.":
        ("Settings now replaces the Settings Manager. Entries hidden: %d.",
         "A Configuração agora substitui o Gerenciador de ajustes. Entradas ocultas: %d."),
    "Gestor de ajustes de XFCE restaurado. Entradas devueltas: %d.":
        ("XFCE Settings Manager restored. Entries returned: %d.",
         "Gerenciador de ajustes do XFCE restaurado. Entradas devolvidas: %d."),
    "No encuentro %s": ("I cannot find %s", "Não encontro %s"),

    # ---- Centro de control
    "GenOs Centro": ("GenOs Control center", "GenOs Central de controle"),
    "Modo oscuro": ("Dark mode", "Modo escuro"),
    "Fondos y colores": ("Wallpapers and colors", "Fundos e cores"),
    "Ajustes": ("Settings", "Ajustes"),
    "Captura": ("Screenshot", "Captura"),
    "NOTIFICACIONES": ("NOTIFICATIONS", "NOTIFICAÇÕES"),
    "Borrar todo": ("Clear all", "Limpar tudo"),
    "Sin notificaciones": ("No notifications", "Sem notificações"),
    "Notificación": ("Notification", "Notificação"),
    "Reproduciendo": ("Playing", "Reproduzindo"),
    "Activado": ("On", "Ativado"),
    "Desactivado": ("Off", "Desativado"),
    "Bloquear": ("Lock", "Bloquear"),
    "Apagar": ("Shut down", "Desligar"),
    "¿Cerrar sesión?": ("Log out?", "Sair da sessão?"),
    "Se cerrarán las ventanas abiertas.": ("Open windows will be closed.", "As janelas abertas serão fechadas."),
    "Cerrar sesión": ("Log out", "Sair"),
    "¿Apagar GenOs?": ("Shut down GenOs?", "Desligar o GenOs?"),
    "Se cierra la sesión y se apaga la máquina WSL. Guarda tu trabajo antes.":
        ("The session closes and the WSL machine shuts down. Save your work first.",
         "A sessão é encerrada e a máquina WSL é desligada. Salve seu trabalho antes."),
    "Para apagar, en PowerShell de Windows escribe:  wsl --shutdown":
        ("To shut down, type this in Windows PowerShell:  wsl --shutdown",
         "Para desligar, digite no PowerShell do Windows:  wsl --shutdown"),
    "No encuentro wsl.exe": ("I cannot find wsl.exe", "Não encontro o wsl.exe"),
    "ahora": ("now", "agora"),
    "hace %s min": ("%s min ago", "há %s min"),
    "hace %s h": ("%s h ago", "há %s h"),
    "hace %s d": ("%s d ago", "há %s d"),
    "Reparé la lista de paneles: ahora carga %s.": ("I repaired the panel list: it now loads %s.",
                                                    "Reparei a lista de painéis: agora carrega %s."),
    "Botón del centro de control añadido a la barra (%s).": ("Control center button added to the bar (%s).",
                                                              "Botão da central de controle adicionado à barra (%s)."),
    "Barra ordenada (%s): %d elementos, quité %d (escritorios, separadores viejos, etc.).":
        ("Bar tidied (%s): %d items, removed %d (desktops, old separators, etc.).",
         "Barra organizada (%s): %d itens, removi %d (áreas de trabalho, separadores antigos, etc.)."),
    "Si algo no te gusta, el respaldo está en %s": ("If you dislike something, the backup is at %s",
                                                      "Se algo não agradar, o backup está em %s"),
    "Actualizaciones": ("Updates", "Atualizações"),
    "Tienes la versión %s.": ("You have version %s.", "Você tem a versão %s."),
    "Buscar": ("Check", "Verificar"),
    "Buscar actualizaciones": ("Check for updates", "Verificar atualizações"),
    "Tu personalización se conserva y antes se guarda un respaldo.": ("Your customization is kept, and a backup is saved first.",
                                                                       "Sua personalização é mantida e antes se salva um backup."),
    "Avisarme cuando haya una versión nueva": ("Tell me when there is a new version", "Avisar quando houver uma versão nova"),
    "Revisa una vez al día al entrar en la sesión.": ("Checks once a day when you log in.", "Verifica uma vez por dia ao entrar na sessão."),
    "Lista de cambios": ("Changelog", "Lista de mudanças"),
    "Qué trae cada versión.": ("What each version brings.", "O que cada versão traz."),
    "Historial": ("History", "Histórico"),
    "Actualizaciones instaladas en este equipo.": ("Updates installed on this computer.", "Atualizações instaladas neste computador."),
    "Volver al respaldo": ("Restore the backup", "Voltar ao backup"),
    "Deja tu configuración como estaba antes de la última actualización.": ("Puts your settings back as they were before the last update.",
                                                                              "Deixa sua configuração como estava antes da última atualização."),
    "Restaurar": ("Restore", "Restaurar"),
    "Buscando…": ("Checking…", "Verificando…"),
    "Versión %s disponible.": ("Version %s available.", "Versão %s disponível."),
    "Actualizar": ("Update", "Atualizar"),
    "Tienes la última versión (%s).": ("You have the latest version (%s).", "Você tem a versão mais recente (%s)."),
    "Sin conexión con GitHub.": ("No connection to GitHub.", "Sem conexão com o GitHub."),
    "¿Volver al respaldo?": ("Restore the backup?", "Voltar ao backup?"),
    "Se restaura tu configuración de antes de la última actualización.": ("Your settings from before the last update are restored.",
                                                                            "Sua configuração de antes da última atualização é restaurada."),
    "Sin datos.": ("No data.", "Sem dados."),
    "Todavía no hay actualizaciones instaladas.": ("No updates installed yet.", "Ainda não há atualizações instaladas."),
    "No hay respaldos todavía.": ("No backups yet.", "Ainda não há backups."),
    "Botón quitado.": ("Button removed.", "Botão removido."),
    "No hay botón que quitar.": ("There is no button to remove.", "Não há botão para remover."),
    "El botón del centro de control ya está en la barra.": ("The control center button is already on the bar.",
                                                             "O botão da central de controle já está na barra."),
    "No pude leer la barra (¿estás dentro de la sesión XFCE?).": ("I could not read the bar (are you inside the XFCE session?).",
                                                                    "Não consegui ler a barra (você está dentro da sessão XFCE?)."),
    "No pude escribir la barra.": ("I could not write the bar.", "Não consegui escrever a barra."),
    "No pude escribir el orden de la barra.": ("I could not write the bar order.", "Não consegui escrever a ordem da barra."),
    "No puedo hablar con la barra. Corre esto dentro del escritorio XFCE.":
        ("I cannot talk to the bar. Run this inside the XFCE desktop.",
         "Não consigo falar com a barra. Execute isto dentro da área de trabalho XFCE."),

    # ---- Widgets
    "Hora": ("Time", "Hora"),
    "CPU": ("CPU", "CPU"),
    "RAM": ("RAM", "RAM"),
    "Disco": ("Disk", "Disco"),
    "Foco": ("Focus", "Foco"),
    "Descanso": ("Rest", "Descanso"),
    " · en marcha": (" · running", " · em andamento"),
    " · en pausa": (" · paused", " · em pausa"),
    "Hora de descansar 5 minutos.": ("Time for a 5 minute break.", "Hora de descansar 5 minutos."),
    "Vuelve al foco, 25 minutos.": ("Back to focus for 25 minutes.", "Volte ao foco por 25 minutos."),
    "clic para editar": ("click to edit", "clique para editar"),
    "Haz clic aquí para escribir tus notas.\n": ("Click here to write your notes.\n", "Clique aqui para escrever suas notas.\n"),
    "genos-widgets ya está corriendo.": ("genos-widgets is already running.", "O genos-widgets já está em execução."),
})
I18N_FIN

# Actualizaciones desde GitHub
cat > "$BIN/genos-actualizar" <<'ACT_FIN'
#!/usr/bin/env bash
# genos-actualizar: busca, muestra e instala versiones nuevas de GenOS desde GitHub.
#
#   genos-actualizar              dice si hay una versión nueva
#   genos-actualizar --aviso      lo mismo, pero en silencio y con notificación (una vez al día)
#   genos-actualizar --cambios    lista de cambios desde tu versión
#   genos-actualizar --instalar   respalda tu configuración e instala la versión nueva
#   genos-actualizar --revertir   vuelve a la configuración del último respaldo
#   genos-actualizar --historial  actualizaciones instaladas en este equipo
#
# La actualización conserva tu personalización: fondo, colores, barra, dock, atajos y
# todo lo que cambiaste en Configuración. Solo se renuevan los programas de GenOS.

set -uo pipefail

REPO="${GENOS_REPO:-GensOsOfc/GenOS}"
RAMA="${GENOS_RAMA:-main}"
BASE="${GENOS_BASE_URL:-https://raw.githubusercontent.com/$REPO/$RAMA}"
CONF="$HOME/.config"
DATOS="$HOME/.local/share/genos"
CACHE="$HOME/.cache/genos-actualizar"
VERSION_LOCAL="$CONF/genos-version"
HISTORIAL="$DATOS/actualizaciones.log"
RESPALDOS="$DATOS/respaldos"
mkdir -p "$DATOS" "$CACHE" "$RESPALDOS"

local_v() { [ -f "$VERSION_LOCAL" ] && tr -d ' \n' < "$VERSION_LOCAL" || echo "0"; }

bajar() { # url destino
  curl -fsSL --connect-timeout 8 --max-time 120 "$1" -o "$2"
}

remota_v() {
  local t="$CACHE/VERSION"
  bajar "$BASE/VERSION" "$t" 2>/dev/null || return 1
  tr -d ' \n' < "$t"
}

mas_nueva() { # $1 nueva, $2 actual: verdadero si $1 > $2
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
}

# Secciones del CHANGELOG con versión mayor que $1 (formato "## 1.2 (fecha)")
cambios_desde() {
  local desde=$1 f="$CACHE/CHANGELOG.md"
  bajar "$BASE/CHANGELOG.md" "$f" 2>/dev/null || return 1
  awk -v desde="$desde" '
    function mayor(a, b,   x, y, n, i) {
      n = split(a, x, "."); split(b, y, ".")
      for (i = 1; i <= (n > 3 ? n : 3); i++) { if (x[i] + 0 > y[i] + 0) return 1; if (x[i] + 0 < y[i] + 0) return 0 }
      return 0
    }
    /^## / { v = $2; mostrar = mayor(v, desde) }
    mostrar { print }
  ' "$f"
}

notificar() { # titulo cuerpo
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a GenOS -i system-software-update "$1" "$2" 2>/dev/null || true
}

abrir_en_terminal() { # comando...
  if [ -t 0 ]; then "$@"; return; fi
  if command -v xfce4-terminal >/dev/null 2>&1; then
    xfce4-terminal --title "Actualizar GenOS" -x bash -c '"$@"; echo; read -rp "Pulsa Enter para cerrar." _' _ "$@"
  elif command -v x-terminal-emulator >/dev/null 2>&1; then
    x-terminal-emulator -e bash -c '"$@"; echo; read -rp "Pulsa Enter para cerrar." _' _ "$@"
  else
    "$@"
  fi
}

comprobar() {
  local r l
  l=$(local_v)
  if ! r=$(remota_v); then
    echo "sin-conexion $l"
    return 2
  fi
  if mas_nueva "$r" "$l"; then echo "disponible $l $r"; return 0; fi
  echo "al-dia $l $r"
  return 1
}

aviso() {
  # Una vez al día como máximo
  local marca="$CACHE/ultima-comprobacion" hoy
  hoy=$(date +%F)
  [ "$(cat "$marca" 2>/dev/null)" = "$hoy" ] && [ "${1:-}" != "--forzar" ] && return 0
  echo "$hoy" > "$marca"
  local estado l r
  read -r estado l r < <(comprobar)
  [ "$estado" = disponible ] || return 0
  if command -v notify-send >/dev/null 2>&1 && notify-send --help 2>&1 | grep -q -- '--action'; then
    local resp
    resp=$(notify-send -a GenOS -i system-software-update -w \
      --action=instalar="Actualizar" --action=cambios="Ver cambios" \
      "GenOS $r disponible" "Tienes la $l. Tu personalización se conserva." 2>/dev/null)
    case "$resp" in
      instalar) abrir_en_terminal "$0" --instalar ;;
      cambios)  ver_cambios_gui ;;
    esac
  else
    notificar "GenOS $r disponible" "Tienes la $l. Para instalarla: genos-actualizar --instalar"
  fi
}

ver_cambios_gui() {
  local txt
  txt=$(cambios_desde "$(local_v)") || txt="No pude bajar la lista de cambios."
  if command -v zenity >/dev/null 2>&1; then
    printf '%s\n' "$txt" | zenity --text-info --title "Cambios de GenOS" --width 560 --height 460 2>/dev/null
  else
    abrir_en_terminal bash -c 'printf "%s\n" "$1" | less' _ "$txt"
  fi
}

respaldar() {
  local destino
  destino="$RESPALDOS/$(date +%Y%m%d-%H%M%S)-v$(local_v).tar.gz"
  # dconf (dock) no vive en archivos de texto: se guarda aparte
  command -v dconf >/dev/null 2>&1 && dconf dump /net/launchpad/plank/ > "$CONF/genos-plank.dconf" 2>/dev/null
  (cd "$HOME" && tar -czf "$destino" --ignore-failed-read \
      .config/genos-*.json .config/genos-perfiles .config/genos-idioma .config/genos-version \
      .config/genos-plank.dconf .config/xfce4/xfconf/xfce-perchannel-xml \
      .config/xfce4/terminal .config/xfce4/helpers.rc .config/plank .config/autostart \
      .local/bin/genos-* .local/lib/genos 2>/dev/null)
  # Se guardan los tres últimos
  ls -1t "$RESPALDOS"/*.tar.gz 2>/dev/null | tail -n +4 | xargs -r rm -f
  echo "$destino"
}

revertir() {
  local ult
  ult=$(ls -1t "$RESPALDOS"/*.tar.gz 2>/dev/null | head -n1)
  [ -n "$ult" ] || { echo "No hay respaldos todavía."; return 1; }
  echo "Restaurando $(basename "$ult")…"
  tar -xzf "$ult" -C "$HOME" || return 1
  if [ -f "$CONF/genos-plank.dconf" ] && command -v dconf >/dev/null 2>&1; then
    dconf load /net/launchpad/plank/ < "$CONF/genos-plank.dconf"
  fi
  echo "Listo. Cierra sesión y vuelve a entrar para que todo se vea como antes."
  printf '%s  revertido a %s\n' "$(date '+%F %R')" "$(basename "$ult")" >> "$HISTORIAL"
}

instalar() {
  local estado l r
  read -r estado l r < <(comprobar)
  case "$estado" in
    sin-conexion) echo "No pude conectarme con GitHub. Revisa la conexión e inténtalo otra vez."; return 1 ;;
    al-dia) [ "${1:-}" = "--forzar" ] || { echo "Ya tienes la última versión ($l)."; return 0; } ;;
  esac
  echo "==> GenOS $l → $r"
  echo
  cambios_desde "$l" || true
  echo
  local sh="$CACHE/xfce-estetica.sh" sum="$CACHE/xfce-estetica.sh.sha256"
  echo "==> Bajando la versión $r"
  bajar "$BASE/xfce-estetica.sh" "$sh" && bajar "$BASE/xfce-estetica.sh.sha256" "$sum" \
    || { echo "La descarga falló. No se cambió nada."; return 1; }
  local esperado real
  esperado=$(awk '{print $1}' "$sum")
  real=$(sha256sum "$sh" | awk '{print $1}')
  if [ -z "$esperado" ] || [ "$esperado" != "$real" ]; then
    echo "El archivo bajado no coincide con su huella SHA-256. No se instaló nada."
    return 1
  fi
  bash -n "$sh" || { echo "El instalador nuevo tiene errores de sintaxis. No se instaló nada."; return 1; }

  echo "==> Respaldando tu configuración"
  local resp
  resp=$(respaldar)
  echo "   $resp"

  echo "==> Instalando"
  if GENOS_ACTUALIZAR=1 bash "$sh"; then
    {
      printf '%s  %s → %s\n' "$(date '+%F %R')" "$l" "$r"
      cambios_desde "$l" | sed 's/^/    /'
    } >> "$HISTORIAL"
    notificar "GenOS actualizado a $r" "Cierra sesión y vuelve a entrar para terminar."
    echo
    echo "GenOS $r instalado. Si algo no te gusta: genos-actualizar --revertir"
  else
    echo
    echo "La instalación terminó con errores. Tu configuración anterior está en:"
    echo "   $resp"
    echo "Para volver a ella: genos-actualizar --revertir"
    return 1
  fi
}

case "${1:-}" in
  ""|--comprobar)
    read -r estado l r < <(comprobar)
    case "$estado" in
      disponible)   echo "Hay una versión nueva: $r (tienes la $l). Instálala con: genos-actualizar --instalar" ;;
      al-dia)       echo "Tienes la última versión ($l)." ;;
      sin-conexion) echo "No pude conectarme con GitHub (tienes la $l)." ;;
    esac ;;
  --estado)    comprobar ;;
  --aviso)     aviso "${2:-}" ;;
  --cambios)   cambios_desde "${2:-$(local_v)}" ;;
  --ver-cambios) ver_cambios_gui ;;
  --instalar)  instalar "${2:-}" ;;
  --terminal)  abrir_en_terminal "$0" --instalar ;;
  --revertir)  revertir ;;
  --historial) [ -f "$HISTORIAL" ] && cat "$HISTORIAL" || echo "Todavía no hay actualizaciones instaladas." ;;
  -h|--help)   sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) echo "Opción desconocida: $1 (mira genos-actualizar --help)"; exit 1 ;;
esac
ACT_FIN
chmod +x "$BIN/genos-actualizar"
mkdir -p "$HOME/.config/autostart"
if [ ! -f "$HOME/.config/autostart/genos-actualizar.desktop" ]; then
  cat > "$HOME/.config/autostart/genos-actualizar.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Buscar actualizaciones de GenOS
Exec=sh -c "sleep 90; $BIN/genos-actualizar --aviso"
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
fi

# Ventana gráfica de configuración
cat > "$BIN/genos-configuracion" <<'PERS_FIN'
#!/usr/bin/env python3
"""GenOs Configuración: ajustes del escritorio con barra lateral, de lo básico a lo avanzado.

  BÁSICO        Fondos, Colores
  PERSONALIZAR  Barra, Dock, Ventanas
  AVANZADO      Texto y cursor, Perfiles, Sistema

La vista previa de la derecha refleja cada ajuste. "Aplicar" escribe todo de una vez:
fondo, tema y colores con genos-fondo; dock con dconf; barra, ventanas y texto con xfconf.
"""
import glob
import hashlib
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import threading
import time

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk  # noqa: E402

sys.path[:0] = [os.path.join(os.path.expanduser("~"), ".local", "lib", "genos"),
                os.path.dirname(os.path.abspath(__file__))]
try:
    import genos_i18n as i18n  # noqa: E402
    i18n.parchear(Gtk)
    T = i18n.T
except ImportError:  # sin el módulo todo queda en español
    i18n = None

    def T(s):
        return s

HOME = os.path.expanduser("~")
GENOS_VERSION = "1.2"
DIR = os.path.join(HOME, "Pictures", "GenOs-Fondos")
CACHE = os.path.join(HOME, ".cache", "genos-fondo")
MINIS = os.path.join(CACHE, "minis")
ANALISIS = os.path.join(CACHE, "analisis.json")
ESTADO = os.path.join(HOME, ".config", "genos-fondo.estado")
AJUSTES = os.path.join(HOME, ".config", "genos-personalizacion.json")
PERFILES = os.path.join(HOME, ".config", "genos-perfiles")
BIN = os.environ.get("GENOS_FONDO_BIN", os.path.join(HOME, ".local", "bin", "genos-fondo"))
PLANK = "/net/launchpad/plank/docks/dock1"

ACENTOS = [
    ("auto", "Automático (del logo)", None),
    ("9B6BFF", "Morado", "#9B6BFF"),
    ("3478F6", "Azul", "#3478F6"),
    ("30B050", "Verde", "#30B050"),
    ("FF5C93", "Rosa", "#FF5C93"),
    ("FF9500", "Naranja", "#FF9500"),
    ("FF453A", "Rojo", "#FF453A"),
    ("FFD60A", "Amarillo", "#FFD60A"),
    ("neutro", "Gris", "#8E8E93"),
]

# Valores por defecto de cada ajuste (None = automático)
DEFECTO = {
    "modo": None, "acento": None, "opacidad": None, "tema": None, "estilo": None,
    "dn_activo": False, "dn_dia": "07:00", "dn_noche": "19:00",
    "alto": 34, "radio": 12,
    "dock_tam": 48, "dock_zoom": True, "dock_zoomp": 150, "dock_pos": "bottom", "dock_ocultar": "none",
    "botones": "izq", "centrado": True, "sombra": 50, "compositor": True,
    "fuente": "Inter 10", "cursor": 24,
    # Notificaciones (xfce4-notifyd)
    "notif_dnd": False, "notif_pos": "2", "notif_tiempo": 5, "notif_opac": 1.0, "notif_fade": True,
    # Widgets: activos por defecto Reloj y Sistema; el resto son opcionales
    "w_maestro": True, "w_reloj": True, "w_sistema": True, "w_red": False, "w_calendario": False,
    "w_notas": False, "w_pomodoro": False,
    "w_pos_reloj": "arriba-der", "w_pos_sistema": "arriba-der", "w_pos_red": "arriba-der",
    "w_pos_calendario": "abajo-der", "w_pos_pomodoro": "abajo-izq", "w_pos_notas": "abajo-izq",
    "w_escala": 1.0, "w_opac": None, "w_monitor": "auto",
}

# Ajustes que van directo a xfconf: clave -> (canal, propiedad, tipo, valor por defecto de XFCE)
XF_MAP = {
    # Ventanas: foco y comportamiento
    "foco_clic": ("xfwm4", "/general/click_to_focus", "bool", True),
    "raise_clic": ("xfwm4", "/general/raise_on_click", "bool", True),
    "foco_nuevas": ("xfwm4", "/general/focus_new", "bool", True),
    "evitar_robo": ("xfwm4", "/general/prevent_focus_stealing", "bool", False),
    "doble_clic": ("xfwm4", "/general/double_click_action", "string", "maximize"),
    "ubicacion": ("xfwm4", "/general/placement_mode", "string", "center"),
    "iman_bordes": ("xfwm4", "/general/snap_to_border", "bool", True),
    "iman_ventanas": ("xfwm4", "/general/snap_to_windows", "bool", False),
    "max_sin_bordes": ("xfwm4", "/general/borderless_maximize", "bool", True),
    "op_inactiva": ("xfwm4", "/general/inactive_opacity", "int", 100),
    "op_mover": ("xfwm4", "/general/move_opacity", "int", 100),
    "titulo_fuente": ("xfwm4", "/general/title_font", "string", "Sans Bold 9"),
    # Alt+Tab
    "tab_ocultas": ("xfwm4", "/general/cycle_hidden", "bool", True),
    "tab_escritorios": ("xfwm4", "/general/cycle_workspaces", "bool", False),
    "tab_marco": ("xfwm4", "/general/cycle_draw_frame", "bool", True),
    "tab_lista": ("xfwm4", "/general/cycle_tabwin_mode", "int", 0),
    # Escritorios virtuales e iconos del escritorio
    "escritorios": ("xfwm4", "/general/workspace_count", "int", 4),
    "ciclar_esc": ("xfwm4", "/general/wrap_workspaces", "bool", False),
    "esc_iconos": ("xfce4-desktop", "/desktop-icons/style", "int", 2),
    "esc_tam": ("xfce4-desktop", "/desktop-icons/icon-size", "int", 48),
    "esc_casa": ("xfce4-desktop", "/desktop-icons/file-icons/show-home", "bool", True),
    "esc_sistema": ("xfce4-desktop", "/desktop-icons/file-icons/show-filesystem", "bool", True),
    "esc_papelera": ("xfce4-desktop", "/desktop-icons/file-icons/show-trash", "bool", True),
    "esc_extraibles": ("xfce4-desktop", "/desktop-icons/file-icons/show-removable", "bool", True),
    # Pantalla y teclado
    "dpi": ("xsettings", "/Xft/DPI", "int", 96),
    "tec_retardo": ("keyboards", "/Default/KeyRepeat/Delay", "int", 500),
    "tec_velocidad": ("keyboards", "/Default/KeyRepeat/Rate", "int", 20),
    "tec_repetir": ("keyboards", "/Default/KeyRepeat", "bool", True),
    "tec_numlock": ("keyboards", "/Default/RestoreNumlock", "bool", True),
    # Ventanas: foco, comportamiento y compositor
    "cycle_min": ("xfwm4", "/general/cycle_minimized", "bool", False),
    "tab_raise": ("xfwm4", "/general/cycle_raise", "bool", False),
    "tab_vista": ("xfwm4", "/general/cycle_preview", "bool", True),
    "foco_retardo": ("xfwm4", "/general/focus_delay", "int", 250),
    "raise_foco": ("xfwm4", "/general/raise_on_focus", "bool", False),
    "raise_cualquier": ("xfwm4", "/general/raise_with_any_button", "bool", True),
    "foco_hint": ("xfwm4", "/general/focus_hint", "bool", True),
    "activar": ("xfwm4", "/general/activate_action", "string", "bring"),
    "rueda_esc": ("xfwm4", "/general/scroll_workspaces", "bool", True),
    "alternar_esc": ("xfwm4", "/general/toggle_workspaces", "bool", False),
    "vuelta_vent": ("xfwm4", "/general/wrap_windows", "bool", True),
    "colocar_ratio": ("xfwm4", "/general/placement_ratio", "int", 20),
    "snap_ancho": ("xfwm4", "/general/snap_width", "int", 10),
    "snap_resist": ("xfwm4", "/general/snap_resist", "bool", False),
    "caja_mover": ("xfwm4", "/general/box_move", "bool", False),
    "caja_redim": ("xfwm4", "/general/box_resize", "bool", False),
    "urgente_parp": ("xfwm4", "/general/urgent_blink", "bool", True),
    "rueda_enrollar": ("xfwm4", "/general/mousewheel_rollup", "bool", True),
    "sombra_marco": ("xfwm4", "/general/show_frame_shadow", "bool", True),
    "sombra_popup": ("xfwm4", "/general/show_popup_shadow", "bool", False),
    "sombra_dock": ("xfwm4", "/general/show_dock_shadow", "bool", True),
    "op_marco": ("xfwm4", "/general/frame_opacity", "int", 100),
    "op_popup": ("xfwm4", "/general/popup_opacity", "int", 100),
    "zoom_esc": ("xfwm4", "/general/zoom_desktop", "bool", True),
    "vblank": ("xfwm4", "/general/vblank_mode", "string", "auto"),
    "margen_izq": ("xfwm4", "/general/margin_left", "int", 0),
    "margen_der": ("xfwm4", "/general/margin_right", "int", 0),
    "margen_arr": ("xfwm4", "/general/margin_top", "int", 0),
    "margen_aba": ("xfwm4", "/general/margin_bottom", "int", 0),
    # Apariencia
    "tema_cursor": ("xsettings", "/Gtk/CursorThemeName", "string", "WhiteSur-cursors"),
    "tema_iconos": ("xsettings", "/Net/IconThemeName", "string", "WhiteSur"),
    "fuente_mono": ("xsettings", "/Gtk/MonospaceFontName", "string", "Monospace 10"),
    "xft_aa": ("xsettings", "/Xft/Antialias", "intbool", True),
    "xft_hint": ("xsettings", "/Xft/Hinting", "intbool", True),
    "xft_estilo": ("xsettings", "/Xft/HintStyle", "string", "hintslight"),
    "xft_rgba": ("xsettings", "/Xft/RGBA", "string", "none"),
    "sonidos_ev": ("xsettings", "/Net/EnableEventSounds", "bool", False),
    "sonidos_in": ("xsettings", "/Net/EnableInputFeedbackSounds", "bool", False),
    "img_botones": ("xsettings", "/Gtk/ButtonImages", "bool", True),
    "img_menus": ("xsettings", "/Gtk/MenuImages", "bool", True),
    "barra_herr": ("xsettings", "/Gtk/ToolbarStyle", "string", "icons"),
    "cursor_parpadeo": ("xsettings", "/Net/CursorBlink", "bool", True),
    "cursor_tiempo": ("xsettings", "/Net/CursorBlinkTime", "int", 1200),
    # Notificaciones (extra)
    "notif_slide": ("xfce4-notifyd", "/do-slideout", "bool", False),
    "notif_gauge": ("xfce4-notifyd", "/show-text-with-gauge", "bool", True),
    "notif_monitor": ("xfce4-notifyd", "/primary-monitor", "uint", 0),
    # Energía
    "pw_tray": ("xfce4-power-manager", "/xfce4-power-manager/show-tray-icon", "bool", False),
    "pw_notif": ("xfce4-power-manager", "/xfce4-power-manager/general-notification", "bool", True),
    "pw_dpms": ("xfce4-power-manager", "/xfce4-power-manager/dpms-enabled", "bool", True),
    "pw_blank_ca": ("xfce4-power-manager", "/xfce4-power-manager/blank-on-ac", "int", 10),
    "pw_blank_bat": ("xfce4-power-manager", "/xfce4-power-manager/blank-on-battery", "int", 5),
    "pw_bloqueo": ("xfce4-power-manager", "/xfce4-power-manager/lock-screen-suspend-hibernate", "bool", True),
    # Unidades extraíbles
    "rm_montar": ("thunar-volman", "/automount-drives/enabled", "bool", False),
    "rm_medios": ("thunar-volman", "/automount-media/enabled", "bool", False),
    "rm_explorar": ("thunar-volman", "/autobrowse/enabled", "bool", False),
    "rm_autorun": ("thunar-volman", "/autorun/enabled", "bool", False),
    "rm_autoabrir": ("thunar-volman", "/autoopen/enabled", "bool", False),
    "rm_grabar": ("thunar-volman", "/autoburn/enabled", "bool", False),
    # Gestor de archivos (Thunar)
    "th_vista": ("thunar", "/default-view", "string", "void"),
    "th_carpetas": ("thunar", "/misc-folders-first", "bool", True),
    "th_binario": ("thunar", "/misc-file-size-binary", "bool", True),
    "th_texto_lado": ("thunar", "/misc-text-beside-icons", "bool", False),
    "th_un_clic": ("thunar", "/misc-single-click", "bool", False),
    "th_marcos": ("thunar", "/misc-thumbnail-draw-frames", "bool", False),
    "th_miniaturas": ("thunar", "/misc-thumbnail-mode", "string", "THUNAR_THUMBNAIL_MODE_ONLY_LOCAL"),
    "th_fecha": ("thunar", "/misc-date-style", "string", "THUNAR_DATE_STYLE_SIMPLE"),
    "th_geometria": ("thunar", "/misc-remember-geometry", "bool", True),
    # Portapapeles (Clipman)
    "cl_sync": ("xfce4-panel", "/plugins/clipman/settings/add-primary-clipboard", "bool", False),
    "cl_guardar": ("xfce4-panel", "/plugins/clipman/settings/save-on-quit", "bool", True),
    "cl_max": ("xfce4-panel", "/plugins/clipman/settings/max-texts-in-history", "uint", 10),
    "cl_puntero": ("xfce4-panel", "/plugins/clipman/tweaks/popup-at-pointer", "bool", False),
    "cl_menu": ("xfce4-panel", "/plugins/clipman/tweaks/max-menu-items", "uint", 15),
    "cl_pegar": ("xfce4-panel", "/plugins/clipman/tweaks/paste-on-activate", "uint", 0),
    # Sesión
    "se_guardar": ("xfce4-session", "/general/AutoSave", "bool", False),
    "se_pregunta": ("xfce4-session", "/general/PromptOnLogout", "bool", True),
    "se_bloquear": ("xfce4-session", "/shutdown/LockScreen", "bool", False),
    "se_selector": ("xfce4-session", "/chooser/AlwaysDisplay", "bool", False),
    # Accesibilidad
    "ac_pegajosas": ("accessibility", "/StickyKeys", "bool", False),
    "ac_lentas": ("accessibility", "/SlowKeys", "bool", False),
    "ac_rebote": ("accessibility", "/BounceKeys", "bool", False),
    "ac_raton": ("accessibility", "/MouseKeys", "bool", False),
}
DEFECTO.update({k: v[3] for k, v in XF_MAP.items()})
DEFECTO.update({"panel_oculta": 0, "panel_bloq": True, "panel_iconos": 16,
                "tec_layout": "es", "tec_variante": "", "pantalla_salida": "", "pantalla_modo": "",
                "panel_largo": 100, "panel_crecer": True, "esc_nombres": [],
                "rat_disp": "", "rat_zurdo": False, "rat_invertir": False, "rat_umbral": 4, "rat_aceler": 2.0})

DISTRIBUCIONES = [("es", "Español"), ("latam", "Latinoamericano"), ("us", "Inglés (EE. UU.)"), ("gb", "Inglés (Reino Unido)"),
                  ("pt", "Portugués"), ("br", "Portugués (Brasil)"), ("fr", "Francés"), ("de", "Alemán"), ("it", "Italiano")]
SIN_VISTA = set(XF_MAP) | {"panel_oculta", "panel_bloq", "panel_iconos", "tec_layout", "tec_variante",
                          "pantalla_salida", "pantalla_modo", "panel_largo", "panel_crecer",
                          "esc_nombres", "rat_disp", "rat_zurdo", "rat_invertir", "rat_umbral", "rat_aceler"}
VARIANTES = [("", "Estándar"), ("intl", "Internacional (teclas muertas)"), ("dvorak", "Dvorak")]

WIDGETS = [
    ("reloj", "Reloj", "Hora grande y fecha. Activado por defecto."),
    ("sistema", "Sistema", "CPU, memoria y disco en barras. Activado por defecto."),
    ("red", "Red", "Velocidad de bajada y subida con gráfico. Opcional."),
    ("calendario", "Calendario", "El mes con el día de hoy marcado. Opcional."),
    ("pomodoro", "Pomodoro", "Foco de 25 minutos y descanso de 5. Clic inicia o pausa, clic derecho reinicia. Opcional."),
    ("notas", "Notas", "Muestra tu archivo de notas; clic para editarlo. Opcional."),
]
ESQUINAS = [("arriba-der", "Arriba a la derecha"), ("arriba-izq", "Arriba a la izquierda"),
            ("abajo-der", "Abajo a la derecha"), ("abajo-izq", "Abajo a la izquierda")]
NOTIF_POS = [("2", "Arriba a la derecha"), ("0", "Arriba a la izquierda"),
             ("3", "Abajo a la derecha"), ("1", "Abajo a la izquierda")]
CONF_WIDGETS = os.path.join(HOME, ".config", "genos-widgets.json")
# xfce4-notifyd guarda la posición como número en unas versiones y como texto en otras
NOMBRES_POS = {"0": "top-left", "1": "bottom-left", "2": "top-right", "3": "bottom-right"}
IDS_POS = {v: k for k, v in NOMBRES_POS.items()}
NOTIF_POS_TEXTO = [False]


def pos_id(v):
    v = str(v).strip()
    return v if v in NOMBRES_POS else IDS_POS.get(v, "2")

PRESETS = {
    "Minimalista": {"alto": 34, "radio": 12, "dock_tam": 44, "dock_zoom": True, "dock_ocultar": "none", "botones": "izq"},
    "Estilo Mac": {"alto": 30, "radio": 14, "dock_tam": 52, "dock_zoom": True, "dock_zoomp": 170, "dock_ocultar": "none", "botones": "izq", "centrado": True},
    "Compacto": {"alto": 28, "radio": 8, "dock_tam": 36, "dock_zoom": False, "dock_ocultar": "intelligent", "botones": "der"},
    "Flotante grande": {"alto": 42, "radio": 20, "dock_tam": 64, "dock_zoom": True, "dock_zoomp": 160, "dock_ocultar": "none", "botones": "izq"},
}

# Palabras extra para el buscador lateral
PALABRAS = {
    "fondos": "fondo wallpaper imagen aleatorio", "colores": "color modo claro oscuro acento tema apariencia estilo día noche",
    "barra": "panel superior pastilla altura esquinas ocultar bloquear iconos", "dock": "plank zoom iconos tamaño",
    "ventanas": "botones sombra compositor foco alt tab imán doble clic ubicación opacidad", "notif": "notificaciones no molestar aviso",
    "widgets": "reloj calendario pomodoro notas red sistema", "texto": "fuente tipografía cursor",
    "perfiles": "guardar exportar tema", "sistema": "reiniciar barra centro de control",
    "escritorio": "iconos escritorio papelera carpeta personal escritorios virtuales espacios de trabajo",
    "pantalla": "resolución escala dpi tamaño texto monitor xrandr",
    "teclado": "distribución idioma repetición teclas atajos",
    "inicio": "autoinicio aplicaciones al iniciar sesión arranque startup guardar sesión cerrar sesión bloquear",
    "apariencia": "iconos tema fuente suavizado antialias hinting sonidos botones menús barra de herramientas monoespaciada",
    "raton": "ratón mouse touchpad zurdo velocidad aceleración desplazamiento invertir",
    "sonido": "volumen audio altavoz micrófono silenciar salida entrada",
    "energia": "batería pantalla apagar suspender bloqueo ahorro energía",
    "unidades": "usb extraíbles montar automático cd dvd medios",
    "apps": "navegador correo terminal predeterminadas portapapeles clipman",
    "archivos": "thunar carpetas miniaturas vista un clic fecha binario",
    "accesib": "teclas pegajosas lentas rebote ratón con teclado accesibilidad",
    "terminal": "terminal xfce4-terminal mousepad editor de texto fuente transparencia desplazamiento líneas números ajuste de línea tabulación",
    "acerca": "versión debian xfce sistema información interfaces créditos genos",
}

POSICIONES = [("bottom", "Abajo"), ("left", "Izquierda"), ("right", "Derecha"), ("top", "Arriba")]
OCULTAR = [("none", "Siempre visible"), ("intelligent", "Inteligente (se oculta si una ventana lo tapa)"),
           ("auto", "Automático (aparece al acercar el mouse)")]

PAGINAS = [
    ("BÁSICO", None, None),
    ("Fondos", "fondos", "preferences-desktop-wallpaper-symbolic"),
    ("Colores", "colores", "applications-graphics-symbolic"),
    ("PERSONALIZAR", None, None),
    ("Barra", "barra", "view-more-horizontal-symbolic"),
    ("Dock", "dock", "view-app-grid-symbolic"),
    ("Ventanas", "ventanas", "window-new-symbolic"),
    ("Notificaciones", "notif", "preferences-system-notifications-symbolic"),
    ("Widgets", "widgets", "view-grid-symbolic"),
    ("Escritorio", "escritorio", "user-desktop-symbolic"),
    ("Apariencia", "apariencia", "preferences-desktop-theme-symbolic"),
    ("EQUIPO", None, None),
    ("Pantalla", "pantalla", "video-display-symbolic"),
    ("Teclado", "teclado", "input-keyboard-symbolic"),
    ("Ratón", "raton", "input-mouse-symbolic"),
    ("Sonido", "sonido", "audio-volume-high-symbolic"),
    ("Energía", "energia", "battery-full-symbolic"),
    ("Unidades", "unidades", "drive-removable-media-symbolic"),
    ("SISTEMA", None, None),
    ("Inicio", "inicio", "system-run-symbolic"),
    ("Aplicaciones", "apps", "emblem-system-symbolic"),
    ("Archivos", "archivos", "folder-symbolic"),
    ("Terminal y editor", "terminal", "utilities-terminal-symbolic"),
    ("Accesibilidad", "accesib", "preferences-desktop-accessibility-symbolic"),
    ("AVANZADO", None, None),
    ("Texto y cursor", "texto", "preferences-desktop-font-symbolic"),
    ("Perfiles", "perfiles", "emblem-favorite-symbolic"),
    ("Sistema", "sistema", "preferences-system-symbolic"),
    ("Acerca de GenOS", "acerca", "help-about-symbolic"),
]

CSS = b"""
.tarjeta { border-radius: 10px; padding: 6px; }
.tarjeta-nombre { font-size: 9pt; }
.sub { opacity: 0.65; font-size: 9pt; }
.titulo-pagina { font-size: 15pt; font-weight: 700; }
.cabecera { font-size: 8pt; font-weight: 700; opacity: 0.55; margin: 14px 12px 4px 12px; }
.lateral row { padding: 7px 12px; border-radius: 8px; margin: 1px 6px; }
.fila-ajuste { padding: 10px 12px; }
.muestra { min-width: 26px; min-height: 26px; border-radius: 15px; padding: 0; margin: 2px; border: 3px solid transparent; box-shadow: none; }
.muestra:checked { border-color: @theme_fg_color; }
.tarjeta-modo { padding: 6px 6px 4px 6px; border-radius: 14px; border: 2px solid transparent; background: none; box-shadow: none; }
.tarjeta-modo:checked { border-color: @theme_selected_bg_color; background: alpha(@theme_selected_bg_color, 0.12); }
.ic { min-width: 22px; min-height: 22px; border-radius: 6px; }
.ic image { color: #ffffff; }
.ic-fondos { background: #3478F6; } .ic-colores { background: #AF52DE; } .ic-barra { background: #8E8E93; }
.ic-dock { background: #30B0C7; } .ic-ventanas { background: #5E5CE6; } .ic-notif { background: #FF453A; }
.ic-widgets { background: #FF9F0A; } .ic-texto { background: #636366; } .ic-perfiles { background: #FF2D55; }
.ic-sistema { background: #8E8E93; } .ic-escritorio { background: #34C759; } .ic-pantalla { background: #0A84FF; }
.ic-teclado { background: #A2845E; } .ic-inicio { background: #64D2FF; }
.ic-apariencia { background: #FF375F; } .ic-raton { background: #98989D; } .ic-sonido { background: #FF6482; }
.ic-energia { background: #32D74B; } .ic-unidades { background: #5AC8FA; } .ic-apps { background: #BF5AF2; }
.ic-terminal { background: #30303A; } .ic-archivos { background: #0A84FF; } .ic-accesib { background: #007AFF; } .ic-acerca { background: #3478F6; }
.etiqueta { background: alpha(@theme_selected_bg_color, 0.20); border-radius: 8px; padding: 1px 8px; font-size: 8pt; }
.valor { opacity: 0.8; }
button.minimo { padding: 0 6px; min-height: 0; }
.chip { padding: 3px 11px; border-radius: 12px; background-color: alpha(@theme_fg_color, 0.07); font-size: 9pt; }
.chip-mod { background-color: alpha(#3478f6, 0.16); }
button.minimo label { font-size: 8pt; opacity: 0.55; }
list.frame { border-radius: 12px; }
.buscador { margin: 10px 10px 4px 10px; }
.muestra-auto { background-image: linear-gradient(135deg, #9B6BFF, #3478F6 50%, #30B050); }
"""


# ---------------------------------------------------------------- utilidades
def lista_fondos():
    out = []
    for raiz, _, archivos in os.walk(DIR):
        for a in archivos:
            if a.lower().endswith((".jpg", ".jpeg", ".png")):
                out.append(os.path.join(raiz, a))

    def clave(p):
        return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", p)]

    return sorted(out, key=clave)


def miniatura(ruta):
    os.makedirs(MINIS, exist_ok=True)
    m = os.path.join(MINIS, hashlib.md5(ruta.encode()).hexdigest()[:12] + ".jpg")
    if not os.path.exists(m):
        try:
            pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(ruta, 480, 270, False)
            pb.savev(m, "jpeg", ["quality"], ["80"])
        except Exception:
            return None
    return m


def correr(cmd, env=None, timeout=20):
    try:
        return subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=timeout).stdout.strip()
    except Exception:
        return ""


def dconf_leer(clave, defecto):
    v = correr(["dconf", "read", "%s/%s" % (PLANK, clave)], timeout=5).replace("uint32 ", "").strip("'")
    if not v:
        return defecto
    if isinstance(defecto, bool):
        return v == "true"
    try:
        return type(defecto)(v)
    except ValueError:
        return defecto


def xf_leer(canal, prop, defecto):
    if not shutil.which("xfconf-query"):
        return defecto
    v = correr(["xfconf-query", "-c", canal, "-p", prop], timeout=5)
    if not v:
        return defecto
    if isinstance(defecto, bool):
        return v == "true"
    try:
        return type(defecto)(v)
    except ValueError:
        return defecto


def paneles():
    """Ids de panel que existen en xfconf (panel-0, panel-1...)."""
    if not shutil.which("xfconf-query"):
        return []
    out = correr(["xfconf-query", "-c", "xfce4-panel", "-l"], timeout=5)
    return sorted(set(re.findall(r"^/panels/(panel-\d+)", out, re.M)))


def xf_poner(canal, prop, tipo, valor):
    if shutil.which("xfconf-query"):
        subprocess.run(["xfconf-query", "-c", canal, "-p", prop, "-n", "-t", tipo, "-s", str(valor)],
                       capture_output=True, timeout=10)


def pantallas():
    """[(id, etiqueta)] de las pantallas que ve GTK, para elegir dónde van los widgets."""
    out = [("auto", "Automática (la principal)")]
    try:
        disp = Gdk.Display.get_default()
        for i in range(disp.get_n_monitors()):
            g = disp.get_monitor(i).get_geometry()
            out.append((str(i), "Pantalla %d: %dx%d en %d,%d" % (i + 1, g.width, g.height, g.x, g.y)))
    except Exception:
        pass
    return out


def xf_poner_v(canal, prop, tipo, valor):
    if tipo == "bool":
        valor = "true" if valor in (True, "true", "True", "1", 1) else "false"
    elif tipo == "intbool":
        tipo, valor = "int", 1 if valor in (True, "true", "True", "1", 1) else 0
    elif tipo == "double":
        valor = "%.2f" % float(valor)
    elif tipo in ("int", "uint"):
        valor = int(float(valor))
    xf_poner(canal, prop, tipo, valor)


def xf_canal(canal):
    """{propiedad: valor} de un canal de xfconf, con una sola llamada."""
    d = {}
    for ln in correr(["xfconf-query", "-c", canal, "-lv"], timeout=8).splitlines():
        m = re.match(r"^(/\S+)\s+(.*)$", ln)
        if m:
            d.setdefault(m.group(1), m.group(2).strip())
    return d


def convertir_xf(v, tipo, defecto):
    try:
        if tipo in ("bool", "intbool"):
            return v in ("true", "1")
        if tipo in ("int", "uint"):
            return int(float(v))
        if tipo == "double":
            return float(v)
        return v
    except ValueError:
        return defecto


def panel_principal():
    """El panel con más elementos: el que ve el usuario aunque /panels apunte a otro."""
    if not shutil.which("xfconf-query"):
        return ""
    mejor, n = "", 0
    for ln in correr(["xfconf-query", "-c", "xfce4-panel", "-l"], timeout=5).splitlines():
        m = re.match(r"^/panels/(panel-\d+)/plugin-ids$", ln.strip())
        if m:
            c = len([x for x in correr(["xfconf-query", "-c", "xfce4-panel", "-p", ln.strip()], timeout=5).splitlines()
                     if x.strip().isdigit()])
            if c > n:
                mejor, n = m.group(1), c
    return mejor


def modos_pantalla():
    """({salida: [modos]}, salida principal, {salida: modo actual}), leídos de xrandr."""
    out, actual, principal, ahora = {}, None, "", {}
    if not shutil.which("xrandr"):
        return out, principal, ahora
    for ln in correr(["xrandr", "--query"], timeout=5).splitlines():
        m = re.match(r"^(\S+) connected( primary)?", ln)
        if m:
            actual = m.group(1)
            out[actual] = []
            if m.group(2) or not principal:
                principal = actual
            continue
        m = re.match(r"^\s+(\d+x\d+)\s(.*)", ln)
        if m and actual:
            out[actual].append(m.group(1))
            if "*" in m.group(2):
                ahora[actual] = m.group(1)
    return out, principal, ahora


def distribucion_actual():
    lay, var = "es", ""
    for ln in correr(["setxkbmap", "-query"], timeout=5).splitlines() if shutil.which("setxkbmap") else []:
        if ln.startswith("layout:"):
            lay = ln.split(":", 1)[1].strip().split(",")[0]
        elif ln.startswith("variant:"):
            var = ln.split(":", 1)[1].strip().split(",")[0]
    return lay, var


def leer_desktop(ruta):
    d = {}
    try:
        with open(ruta, encoding="utf-8", errors="replace") as f:
            en = False
            for ln in f:
                ln = ln.strip()
                if ln.startswith("["):
                    en = ln == "[Desktop Entry]"
                elif en and "=" in ln:
                    k, v = ln.split("=", 1)
                    d.setdefault(k.strip(), v.strip())
    except OSError:
        pass
    return d


def apps_de_inicio():
    """[(archivo, nombre, comentario, activo)] de las apps que arrancan con la sesión."""
    vistos = {}
    for carpeta in (os.path.join(HOME, ".config", "autostart"), "/etc/xdg/autostart"):
        for f in sorted(glob.glob(os.path.join(carpeta, "*.desktop"))):
            vistos.setdefault(os.path.basename(f), f)
    out = []
    for base, ruta in sorted(vistos.items()):
        d = leer_desktop(ruta)
        if d.get("NoDisplay", "").lower() == "true" and not ruta.startswith(HOME):
            continue
        solo = d.get("OnlyShowIn")
        if solo and "XFCE" not in solo:
            continue
        activo = d.get("Hidden", "false").lower() != "true" and \
            d.get("X-GNOME-Autostart-enabled", "true").lower() != "false"
        out.append((base, d.get("Name", base[:-8]), d.get("Comment", ""), activo))
    return out


def poner_inicio(base, activo):
    """Activa o desactiva una app de inicio escribiendo su copia en ~/.config/autostart."""
    carpeta = os.path.join(HOME, ".config", "autostart")
    os.makedirs(carpeta, exist_ok=True)
    destino = os.path.join(carpeta, base)
    origen = destino if os.path.isfile(destino) else os.path.join("/etc/xdg/autostart", base)
    try:
        with open(origen, encoding="utf-8", errors="replace") as f:
            lineas = [l.rstrip("\n") for l in f]
    except OSError:
        return
    nuevas, visto = [], False
    for ln in lineas:
        if ln.startswith(("Hidden=", "X-GNOME-Autostart-enabled=")):
            continue
        nuevas.append(ln)
        if ln.strip() == "[Desktop Entry]" and not visto:
            visto = True
            nuevas.append("X-GNOME-Autostart-enabled=%s" % ("true" if activo else "false"))
            nuevas.append("Hidden=%s" % ("false" if activo else "true"))
    with open(destino, "w", encoding="utf-8") as f:
        f.write("\n".join(nuevas) + "\n")



def nombres_escritorios():
    out = []
    for ln in correr(["xfconf-query", "-c", "xfwm4", "-p", "/general/workspace_names"], timeout=5).splitlines() \
            if shutil.which("xfconf-query") else []:
        if ln.strip() and not ln.startswith("Value is an array"):
            out.append(ln.strip())
    return out


def clave_dispositivo(nombre):
    return re.sub(r"[^A-Za-z0-9]", "_", nombre)


def dispositivos_raton():
    """Nombres de punteros: los que ya conoce xfconf, o los que lista xinput."""
    res = []
    if shutil.which("xfconf-query"):
        for ln in correr(["xfconf-query", "-c", "pointers", "-l"], timeout=5).splitlines():
            m = re.match(r"^/([^/]+)/(RightHanded|Acceleration|Threshold)$", ln.strip())
            if m and m.group(1) not in res:
                res.append(m.group(1))
    if not res and shutil.which("xinput"):
        for ln in correr(["xinput", "list", "--name-only"], timeout=5).splitlines():
            n = ln.strip()
            if n and not re.search(r"Virtual core|XTEST|[Kk]eyboard|Button|Sleep|Video Bus", n):
                res.append(clave_dispositivo(n))
    return res or ["xrdpMouse"]


def leer_raton(disp, aj):
    base = "/%s/" % disp
    c = xf_canal("pointers") if shutil.which("xfconf-query") else {}
    return {"rat_zurdo": c.get(base + "RightHanded", "true") == "false",
            "rat_invertir": c.get(base + "ReverseScrolling", "false") == "true",
            "rat_umbral": int(float(c.get(base + "Threshold", aj.get("rat_umbral", 4)))),
            "rat_aceler": float(c.get(base + "Acceleration", aj.get("rat_aceler", 2.0)))}


def helpers_de(cat):
    """[(id, nombre)] de las aplicaciones preferidas de XFCE para una categoría."""
    res = {}
    for d in ("/usr/share/xfce4/helpers", os.path.join(HOME, ".local", "share", "xfce4", "helpers")):
        for f in sorted(glob.glob(os.path.join(d, "*.desktop"))):
            dd = leer_desktop(f)
            if dd.get("X-XFCE-Category") == cat and dd.get("NoDisplay", "").lower() != "true":
                res[os.path.basename(f)[:-8]] = dd.get("Name", os.path.basename(f)[:-8])
    return sorted(res.items(), key=lambda x: x[1].lower())


RC_HELPERS = os.path.join(HOME, ".config", "xfce4", "helpers.rc")


def helper_actual(clave):
    try:
        with open(RC_HELPERS, encoding="utf-8") as f:
            for ln in f:
                if ln.startswith(clave + "="):
                    return ln.split("=", 1)[1].strip()
    except OSError:
        pass
    return ""


def poner_helper(clave, valor):
    lineas = []
    try:
        with open(RC_HELPERS, encoding="utf-8") as f:
            lineas = [l.rstrip("\n") for l in f if not l.startswith(clave + "=")]
    except OSError:
        pass
    lineas.append("%s=%s" % (clave, valor))
    os.makedirs(os.path.dirname(RC_HELPERS), exist_ok=True)
    with open(RC_HELPERS, "w", encoding="utf-8") as f:
        f.write("\n".join(lineas) + "\n")


def temas_de_iconos():
    res = set()
    for d in ("/usr/share/icons", os.path.join(HOME, ".icons"), os.path.join(HOME, ".local", "share", "icons")):
        if os.path.isdir(d):
            for n in os.listdir(d):
                idx = os.path.join(d, n, "index.theme")
                if os.path.isfile(idx) and n not in ("default", "hicolor", "locolor") \
                        and "Directories=" in open(idx, encoding="utf-8", errors="replace").read():
                    res.add(n)
    return sorted(res)


def temas_de_cursor():
    res = set()
    for d in ("/usr/share/icons", os.path.join(HOME, ".icons"), os.path.join(HOME, ".local", "share", "icons")):
        if os.path.isdir(d):
            for n in os.listdir(d):
                if os.path.isdir(os.path.join(d, n, "cursors")):
                    res.add(n)
    return sorted(res)


RC_TERMINAL = os.path.join(HOME, ".config", "xfce4", "terminal", "terminalrc")


def ini_leer(ruta, clave, defecto=""):
    try:
        with open(ruta, encoding="utf-8", errors="replace") as f:
            for ln in f:
                if ln.startswith(clave + "="):
                    return ln.split("=", 1)[1].strip()
    except OSError:
        pass
    return defecto


def ini_poner(ruta, pares):
    try:
        with open(ruta, encoding="utf-8", errors="replace") as f:
            lineas = [l.rstrip("\n") for l in f]
    except OSError:
        lineas = ["[Configuration]"]
    for k, v in pares.items():
        for i, ln in enumerate(lineas):
            if ln.startswith(k + "="):
                lineas[i] = "%s=%s" % (k, v)
                break
        else:
            lineas.append("%s=%s" % (k, v))
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    with open(ruta, "w", encoding="utf-8") as f:
        f.write("\n".join(lineas) + "\n")


MOUSEPAD = "org.xfce.mousepad.preferences"


def mousepad_leer(sub, clave, defecto):
    if not shutil.which("gsettings"):
        return defecto
    v = correr(["gsettings", "get", "%s.%s" % (MOUSEPAD, sub), clave], timeout=5)
    if not v:
        return defecto
    v = v.strip("'")
    if isinstance(defecto, bool):
        return v == "true"
    try:
        return type(defecto)(v)
    except ValueError:
        return defecto


def mousepad_poner(sub, clave, valor):
    if shutil.which("gsettings"):
        if isinstance(valor, bool):
            valor = "true" if valor else "false"
        elif isinstance(valor, str):
            valor = "'%s'" % valor
        subprocess.run(["gsettings", "set", "%s.%s" % (MOUSEPAD, sub), clave, str(valor)], capture_output=True, timeout=5)


def audio_pactl(*args):
    return correr(["pactl"] + list(args), timeout=5) if shutil.which("pactl") else ""


def audio_dispositivos(tipo):
    """[(nombre, descripción)] de salidas (sinks) o entradas (sources)."""
    out = []
    for ln in audio_pactl("list", "short", tipo + "s").splitlines():
        parts = ln.split("\t")
        if len(parts) > 1 and not parts[1].endswith(".monitor"):
            out.append((parts[1], parts[1]))
    return out


def audio_volumen(tipo):
    m = re.search(r"(\d+)%", audio_pactl("get-%s-volume" % tipo, "@DEFAULT_%s@" % tipo.upper()))
    return int(m.group(1)) if m else 0


def audio_silencio(tipo):
    return "yes" in audio_pactl("get-%s-mute" % tipo, "@DEFAULT_%s@" % tipo.upper()).lower() \
        or "sí" in audio_pactl("get-%s-mute" % tipo, "@DEFAULT_%s@" % tipo.upper()).lower()


def info_sistema():
    d = {}
    try:
        with open("/etc/os-release", encoding="utf-8") as f:
            for ln in f:
                if "=" in ln:
                    k, v = ln.strip().split("=", 1)
                    d[k] = v.strip('"')
    except OSError:
        pass
    xf = ""
    if shutil.which("xfce4-session"):
        m = re.search(r"Xfce (\d+\.\d+)", correr(["xfce4-session", "--version"], timeout=5))
        xf = m.group(1) if m else ""
    cpu = ""
    try:
        with open("/proc/cpuinfo", encoding="utf-8") as f:
            for ln in f:
                if ln.startswith("model name"):
                    cpu = re.sub(r"\s+", " ", ln.split(":", 1)[1]).strip()
                    break
    except OSError:
        pass
    mem = ""
    try:
        with open("/proc/meminfo", encoding="utf-8") as f:
            kb = int(f.readline().split()[1])
            mem = "%.1f GiB" % (kb / 1048576.0)
    except (OSError, ValueError, IndexError):
        pass
    return [("Sistema", "GenOS %s" % GENOS_VERSION),
            ("Base", d.get("PRETTY_NAME", "Debian GNU/Linux")),
            ("Escritorio", ("XFCE " + xf) if xf else "XFCE"),
            ("GTK", "%d.%d.%d" % (Gtk.get_major_version(), Gtk.get_minor_version(), Gtk.get_micro_version())),
            ("Núcleo", os.uname().release),
            ("Equipo", socket.gethostname()),
            ("Procesador", cpu or "(sin datos)"),
            ("Memoria", mem or "(sin datos)")]


INTERFACES = [
    ("XFCE", "Escritorio base", "mod", "El panel pasó a pastillas flotantes y casi todos sus ajustes viven en Configuración.", None),
    ("Xfwm4", "Gestor de ventanas y compositor", "mod", "Botones estilo Mac, título centrado, sombras y transparencias.", None),
    ("Plank", "Dock", "mod", "Centrado y con zoom; tamaño y posición se cambian desde aquí.", "plank"),
    ("Rofi", "Lanzador de aplicaciones", "mod", "Cuadrícula tipo Launchpad con los colores del fondo.", "rofi"),
    ("WhiteSur", "Tema GTK, iconos y cursores", "mod", "Variante clara u oscura y acento elegidos según el fondo.", None),
    ("xfce4-notifyd", "Notificaciones", "mod", "Burbujas en forma de pastilla con el diseño de la barra.", None),
    ("Terminal de XFCE", "Terminal", "mod", "Fondo translúcido que sigue el modo claro u oscuro.", "xfce4-terminal"),
    ("Thunar", "Gestor de archivos", "orig", "Sin cambios; sus preferencias están en Archivos.", "thunar"),
    ("xrdp", "Acceso al escritorio desde Windows", "orig", "Sesión remota por RDP sobre WSL2.", "xrdp"),
    ("Apps de GenOS", "Configuración, Fondo, Widgets, Centro de control, Barra y Exportar", "gen",
     "Escritas en Python con GTK 3 para este sistema.", None),
]
ETIQUETAS = {"mod": "Modificado", "orig": "Original", "gen": "Hecho para GenOS"}


# ---- Entradas originales del Gestor de ajustes de XFCE que Configuración ya cubre
AJUSTES_CUBIERTOS = {"xfce4-appearance-settings", "xfdesktop-settings", "xfce4-notifyd-config", "xfwm4-settings",
                     "xfwm4-tweaks-settings", "xfwm4-workspace-settings", "xfce4-display-settings",
                     "xfce4-keyboard-settings", "xfce4-session-settings", "xfce4-panel", "xfce4-mouse-settings",
                     "xfce4-power-manager-settings", "thunar-volman-settings", "xfce4-accessibility-settings",
                     "xfce4-mime-settings", "thunar-settings", "xfce4-clipman-settings", "pavucontrol", "xfce4-about",
                     "xfce4-settings-manager"}
AJUSTES_POR_ARCHIVO = {"xfce4-terminal-settings.desktop", "org.xfce.mousepad-settings.desktop"}
MARCA_OCULTO = "X-GenOs-Oculto"
APPS_USUARIO = os.path.join(HOME, ".local", "share", "applications")


def carpetas_apps():
    dirs = [d for d in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":") if d]
    return [os.path.join(d, "applications") for d in dirs]


def entradas_cubiertas():
    """[(archivo, ruta)] de las entradas del Gestor de ajustes que ya tienen su página aquí."""
    out = {}
    for carpeta in carpetas_apps():
        for f in sorted(glob.glob(os.path.join(carpeta, "*.desktop"))):
            base = os.path.basename(f)
            if base in out:
                continue
            d = leer_desktop(f)
            cats = d.get("Categories", "")
            if "X-XFCE-SettingsDialog" not in cats and "Settings" not in cats:
                continue
            ej = d.get("Exec", "").split()
            if base in AJUSTES_POR_ARCHIVO or (ej and os.path.basename(ej[0]) in AJUSTES_CUBIERTOS):
                out[base] = f
    return sorted(out.items())


def ajustes_ocultos():
    for f in glob.glob(os.path.join(APPS_USUARIO, "*.desktop")):
        if leer_desktop(f).get(MARCA_OCULTO) == "true":
            return True
    return False


def ocultar_ajustes():
    """Esconde del Gestor de ajustes lo que ya está dentro de Configuración. Devuelve cuántas."""
    os.makedirs(APPS_USUARIO, exist_ok=True)
    n = 0
    for base, ruta in entradas_cubiertas():
        destino = os.path.join(APPS_USUARIO, base)
        if os.path.isfile(destino) and leer_desktop(destino).get(MARCA_OCULTO) != "true":
            continue  # una copia propia del usuario: no se toca
        try:
            with open(ruta, encoding="utf-8", errors="replace") as f:
                lineas = [l.rstrip("\n") for l in f]
        except OSError:
            continue
        nuevas, visto = [], False
        for ln in lineas:
            if ln.startswith(("Hidden=", "NoDisplay=", "OnlyShowIn=", MARCA_OCULTO + "=")):
                continue
            nuevas.append(ln)
            if ln.strip() == "[Desktop Entry]" and not visto:
                visto = True
                nuevas += ["Hidden=true", "NoDisplay=true", "OnlyShowIn=GenOs-oculto;", MARCA_OCULTO + "=true"]
        with open(destino, "w", encoding="utf-8") as f:
            f.write("\n".join(nuevas) + "\n")
        n += 1
    instalar_envoltorio()
    refrescar_gestor()
    return n


RUTA_GESTOR = os.path.join(HOME, ".local", "bin", "xfce4-settings-manager")
MARCA_GESTOR = "# GenOs: reemplaza el Gestor de ajustes de XFCE por Configuración"


AUTO_ACT = os.path.join(HOME, ".config", "autostart", "genos-actualizar.desktop")


def aviso_activo():
    try:
        with open(AUTO_ACT, encoding="utf-8") as f:
            return "Hidden=true" not in f.read()
    except OSError:
        return False


def poner_aviso(activo):
    act = os.path.join(os.path.dirname(BIN), "genos-actualizar")
    os.makedirs(os.path.dirname(AUTO_ACT), exist_ok=True)
    with open(AUTO_ACT, "w", encoding="utf-8") as f:
        f.write("[Desktop Entry]\nType=Application\nName=Buscar actualizaciones de GenOS\n"
                'Exec=sh -c "sleep 90; %s --aviso"\nNoDisplay=true\n%s' % (act, "" if activo else "Hidden=true\n"))


def gestor_original():
    """Ruta del Gestor de ajustes de XFCE de verdad (no el envoltorio de GenOs)."""
    for r in ("/usr/bin/xfce4-settings-manager", "/usr/local/bin/xfce4-settings-manager"):
        if os.path.isfile(r):
            return r
    return None


def _es_envoltorio(ruta):
    try:
        with open(ruta, encoding="utf-8", errors="replace") as f:
            return MARCA_GESTOR in f.read(400)
    except OSError:
        return False


def instalar_envoltorio():
    """~/.local/bin/xfce4-settings-manager abre Configuración. No pisa un archivo ajeno."""
    if os.path.lexists(RUTA_GESTOR) and not _es_envoltorio(RUTA_GESTOR):
        return False
    os.makedirs(os.path.dirname(RUTA_GESTOR), exist_ok=True)
    with open(RUTA_GESTOR, "w", encoding="utf-8") as f:
        f.write('#!/bin/sh\n%s\nexec "%s/.local/bin/genos-configuracion"\n' % (MARCA_GESTOR, HOME))
    os.chmod(RUTA_GESTOR, 0o755)
    return True


def quitar_envoltorio():
    if os.path.lexists(RUTA_GESTOR) and _es_envoltorio(RUTA_GESTOR):
        try:
            os.remove(RUTA_GESTOR)
        except OSError:
            pass


def mostrar_ajustes():
    quitar_envoltorio()
    n = 0
    for f in glob.glob(os.path.join(APPS_USUARIO, "*.desktop")):
        if leer_desktop(f).get(MARCA_OCULTO) == "true":
            try:
                os.remove(f)
                n += 1
            except OSError:
                pass
    refrescar_gestor()
    return n


def refrescar_gestor():
    if shutil.which("update-desktop-database"):
        subprocess.run(["update-desktop-database", APPS_USUARIO], capture_output=True, timeout=10)
    subprocess.run(["pkill", "-u", str(os.getuid()), "-f", "xfce4-settings-manager"], capture_output=True, timeout=5)


# ---- Atajos de teclado de GenOs
CANAL_ATAJOS = "xfce4-keyboard-shortcuts"
ATAJOS = [("Lanzador de aplicaciones", "launchpad.rasi"), ("Elegir fondo", "genos-fondo --elegir"),
          ("Configuración", "genos-configuracion"), ("Widgets (mostrar u ocultar)", "genos-widgets --alternar"),
          ("Centro de control", "genos-centro")]


def atajos_actuales():
    """{fragmento_del_comando: (tecla_xfconf, comando)} para los atajos de GenOs."""
    res = {}
    for ln in correr(["xfconf-query", "-c", CANAL_ATAJOS, "-lv"], timeout=8).splitlines():
        m = re.match(r"^/commands/custom/(\S+)\s+(.+)$", ln.strip())
        if not m:
            continue
        for _n, frag in ATAJOS:
            if frag in m.group(2) and frag not in res:
                res[frag] = (m.group(1), m.group(2))
    return res


def etiqueta_tecla(t):
    return (t.replace("<Primary>", "Ctrl+").replace("<Control>", "Ctrl+").replace("<Alt>", "Alt+")
             .replace("<Shift>", "Shift+").replace("<Super>", "Super+").replace("<", "").replace(">", ""))


def temas_instalados():
    nombres = set()
    for d in (os.path.join(HOME, ".themes"), os.path.join(HOME, ".local/share/themes"), "/usr/share/themes"):
        if os.path.isdir(d):
            for n in os.listdir(d):
                if n.startswith("WhiteSur") and "hdpi" not in n:
                    nombres.add(n)
    return sorted(nombres)


def modo_por_hora(aj, ahora=None):
    """'claro' entre la hora de día y la de noche; 'oscuro' el resto."""
    def minutos(t, defecto):
        try:
            h, m = t.split(":")
            return int(h) * 60 + int(m)
        except Exception:
            return defecto
    ahora = ahora or time.localtime()
    n = ahora.tm_hour * 60 + ahora.tm_min
    dia, noche = minutos(aj.get("dn_dia", "07:00"), 420), minutos(aj.get("dn_noche", "19:00"), 1140)
    return "claro" if dia <= n < noche else "oscuro"


def entorno(aj):
    env = dict(os.environ)
    modo = modo_por_hora(aj) if aj.get("dn_activo") else aj["modo"]
    for k, v in (("GENOS_MODO", modo), ("GENOS_ACENTO", aj["acento"]),
                 ("GENOS_TEMA", aj["tema"])):
        if v:
            env[k] = v
    est = aj.get("estilo")
    if aj["opacidad"]:
        env["GENOS_OPACIDAD"] = "%.2f" % aj["opacidad"]
    elif est == "solido":
        env["GENOS_OPACIDAD"] = "0.95"
    elif est == "cristal":
        env["GENOS_OPACIDAD"] = "0.60"
    if est == "tenido":
        env["GENOS_TINTE"] = "1"
    env["GENOS_RADIO"] = str(int(aj["radio"]))
    return env


def perfil(ruta, aj):
    d = {}
    for linea in correr([BIN, "--perfil", ruta], env=entorno(aj)).splitlines():
        if "=" in linea:
            k, v = linea.split("=", 1)
            d[k] = v
    return d


def rgba(texto, defecto=(0.1, 0.1, 0.15, 0.8)):
    n = [float(x) for x in re.findall(r"[\d.]+", texto or "")]
    if len(n) >= 4:
        return (n[0] / 255, n[1] / 255, n[2] / 255, n[3])
    if len(n) == 3:
        return (n[0] / 255, n[1] / 255, n[2] / 255, 1.0)
    return defecto


def hex_color(h, defecto=(0.6, 0.6, 0.7)):
    m = re.fullmatch(r"#?([0-9a-fA-F]{6})", h or "")
    if not m:
        return defecto
    v = m.group(1)
    return tuple(int(v[i:i + 2], 16) / 255 for i in (0, 2, 4))


def rect_redondo(cr, x, y, w, h, r):
    r = max(0, min(r, w / 2, h / 2))
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -1.5708, 0)
    cr.arc(x + w - r, y + h - r, r, 0, 1.5708)
    cr.arc(x + r, y + h - r, r, 1.5708, 3.1416)
    cr.arc(x + r, y + r, r, 3.1416, 4.7124)
    cr.close_path()


# ---------------------------------------------------------------- vista previa
def dibuja_mini(cr, w, h, tipo):
    """Miniatura de escritorio para el selector Automático / Claro / Oscuro."""
    def escena(oscuro):
        fondo = (0.10, 0.11, 0.18) if oscuro else (0.80, 0.86, 0.95)
        ventana = (0.17, 0.18, 0.24) if oscuro else (0.98, 0.98, 1.0)
        linea = (0.40, 0.42, 0.52) if oscuro else (0.72, 0.74, 0.82)
        cr.set_source_rgb(*fondo)
        cr.paint()
        rect_redondo(cr, 0, 3, w, 6, 3)
        cr.set_source_rgba(1, 1, 1, 0.25) if oscuro else cr.set_source_rgba(1, 1, 1, 0.7)
        cr.fill()
        rect_redondo(cr, 16, 16, w - 32, h - 34, 5)
        cr.set_source_rgb(*ventana)
        cr.fill()
        for i, col in enumerate(((1, 0.37, 0.34), (1, 0.74, 0.18), (0.16, 0.8, 0.25))):
            cr.arc(23 + i * 7, 23, 2, 0, 6.2832)
            cr.set_source_rgb(*col)
            cr.fill()
        cr.set_source_rgb(*linea)
        for y, ancho in ((32, 44), (38, 30)):
            rect_redondo(cr, 22, y, ancho, 3, 1.5)
            cr.fill()
        rect_redondo(cr, w / 2 - 20, h - 11, 40, 7, 3.5)
        cr.set_source_rgba(1, 1, 1, 0.3) if oscuro else cr.set_source_rgba(1, 1, 1, 0.8)
        cr.fill()

    cr.save()
    rect_redondo(cr, 0, 0, w, h, 9)
    cr.clip()
    if tipo == "auto":
        escena(False)
        cr.move_to(w, 0)
        cr.line_to(w, h)
        cr.line_to(0, h)
        cr.close_path()
        cr.clip()
        escena(True)
    else:
        escena(tipo == "oscuro")
    cr.restore()


class Vista(Gtk.DrawingArea):
    """Maqueta del escritorio con los colores y medidas reales de los ajustes."""

    def __init__(self):
        super().__init__()
        self.set_size_request(440, 262)
        self.pb = None
        self.p = {}
        self.aj = dict(DEFECTO)
        self.connect("draw", self.dibujar)

    def poner(self, ruta, p, aj):
        try:
            if getattr(self, "ruta", None) != ruta:
                self.pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(ruta, 880, 495, False)
                self.ruta = ruta
        except Exception:
            self.pb = None
        self.p, self.aj = p, dict(aj)
        self.queue_draw()

    def dibujar(self, w, cr):
        W, H = self.get_allocated_width(), self.get_allocated_height()
        rect_redondo(cr, 0, 0, W, H, 12)
        cr.clip()
        if self.pb:
            esc = max(W / self.pb.get_width(), H / self.pb.get_height())
            cr.save()
            cr.scale(esc, esc)
            Gdk.cairo_set_source_pixbuf(cr, self.pb, 0, 0)
            cr.paint()
            cr.restore()
        else:
            cr.set_source_rgb(0.1, 0.1, 0.14)
            cr.paint()
        p, aj = self.p, self.aj
        if not p:
            return False
        pr, pg, pb_ = [int(x) / 255 for x in p.get("pastilla", "20,20,28").split(",")]
        alfa = float(p.get("opacidad", "0.72"))
        texto = hex_color(p.get("texto", "#f2f2f7"))
        sel = rgba(p.get("sel", ""))
        k = W / 440.0
        radio = aj["radio"] * 0.5 * k

        def pastilla(x, y, ancho, alto, etiqueta, seleccion=False):
            rect_redondo(cr, x, y, ancho, alto, radio)
            cr.set_source_rgba(*(sel if seleccion else (pr, pg, pb_, alfa)))
            cr.fill()
            cr.set_source_rgb(*(hex_color("#ffffff") if seleccion else texto))
            cr.select_font_face("Sans")
            cr.set_font_size(8.5 * k)
            ext = cr.text_extents(etiqueta)
            cr.move_to(x + (ancho - ext.width) / 2 - ext.x_bearing, y + alto / 2 + ext.height / 2)
            cr.show_text(etiqueta)

        # Barra superior
        alto = 18 * k * (aj["alto"] / 34.0)
        y = 5 * k
        pastilla(8 * k, y, 74 * k, alto, "Apps")
        pastilla(88 * k, y, 70 * k, alto, "Terminal", True)
        pastilla(W / 2 - 30 * k, y, 60 * k, alto, "12:00")
        pastilla(W - 8 * k - 70 * k, y, 70 * k, alto, "· ·  ▮")

        # Ventana con botones a la izquierda o a la derecha
        tx, ty, tw, th = W * 0.28, H * 0.27, W * 0.44, H * 0.36
        sombra = aj["sombra"] / 100.0
        if aj["compositor"] and sombra > 0:
            for i in range(4):
                rect_redondo(cr, tx - i * 2 * k, ty - i * 2 * k + 3 * k, tw + i * 4 * k, th + i * 4 * k, 9 * k)
                cr.set_source_rgba(0, 0, 0, 0.07 * sombra)
                cr.fill()
        rect_redondo(cr, tx, ty, tw, th, 8 * k)
        cr.set_source_rgba(pr * 0.7, pg * 0.7, pb_ * 0.7, 0.97)
        cr.fill()
        cr.set_source_rgba(1, 1, 1, 0.06)
        rect_redondo(cr, tx, ty, tw, 16 * k, 8 * k)
        cr.fill()
        cols = [(1.0, 0.37, 0.34), (1.0, 0.74, 0.18), (0.16, 0.8, 0.25)]
        for i, c in enumerate(cols):
            cx = tx + (12 + i * 12) * k if aj["botones"] == "izq" else tx + tw - (12 + (2 - i) * 12) * k
            cr.arc(cx, ty + 8 * k, 3.6 * k, 0, 6.2832)
            cr.set_source_rgb(*c)
            cr.fill()
        cr.set_source_rgb(*texto)
        cr.set_font_size(7.2 * k)
        titulo = "Terminal"
        ext = cr.text_extents(titulo)
        if aj["centrado"]:
            cr.move_to(tx + (tw - ext.width) / 2, ty + 11 * k)
        else:
            cr.move_to(tx + (50 if aj["botones"] == "izq" else 10) * k, ty + 11 * k)
        cr.show_text(titulo)
        cr.set_font_size(8 * k)
        cr.move_to(tx + 10 * k, ty + 32 * k)
        cr.show_text("duvan@genos:~$ genos-fondo")
        cr.set_source_rgba(*sel[:3], 1)
        cr.rectangle(tx + 10 * k, ty + 40 * k, 7 * k, 11 * k)
        cr.fill()

        # Dock (abajo, izquierda, derecha o arriba)
        n = 6
        ic = aj["dock_tam"] * 0.5 * k * 0.85
        sep = 5 * k
        largo = n * ic + (n - 1) * sep + 14 * k
        pos = aj["dock_pos"]
        horizontal = pos in ("bottom", "top")
        zoom = 1 + (aj["dock_zoomp"] - 100) / 100.0 * 0.5 if aj["dock_zoom"] else 1.0
        if horizontal:
            dx = (W - largo) / 2
            dy = H - ic - 18 * k if pos == "bottom" else 5 * k + alto + 8 * k
            rect_redondo(cr, dx, dy - 5 * k, largo, ic + 10 * k, radio + 2 * k)
        else:
            dx = 12 * k if pos == "left" else W - ic - 12 * k
            dy = (H - largo) / 2
            rect_redondo(cr, dx - 5 * k, dy, ic + 10 * k, largo, radio + 2 * k)
        cr.set_source_rgba(pr, pg, pb_, alfa)
        cr.fill()
        for i in range(n):
            s = ic * (zoom if i == 2 else 1.0)
            if horizontal:
                x = dx + 7 * k + i * (ic + sep)
                x0, y0 = x - (s - ic) / 2, (dy - (s - ic)) if pos == "bottom" else dy
            else:
                yy = dy + 7 * k + i * (ic + sep)
                y0 = yy - (s - ic) / 2
                x0 = dx if pos == "left" else dx - (s - ic)
            rect_redondo(cr, x0, y0, s, s, radio * 0.7 + 2 * k)
            cr.set_source_rgba(*(sel if i == 0 else (texto[0], texto[1], texto[2], 0.22)))
            cr.fill()
        return False


# ---------------------------------------------------------------- ventana
class Ventana(Gtk.Window):
    def __init__(self):
        super().__init__(title="GenOs · Configuración")
        try:
            disp = Gdk.Display.get_default()
            mon = disp.get_primary_monitor() or disp.get_monitor(0)
            wa = mon.get_workarea()
            self.set_default_size(min(1280, wa.width - 40), min(760, wa.height - 60))
            self.estrecho = wa.width < 1250
        except Exception:
            self.set_default_size(1100, 680)
            self.estrecho = True
        self.set_position(Gtk.WindowPosition.CENTER)
        self.fondos = lista_fondos()
        self.analisis = {}
        try:
            with open(ANALISIS) as f:
                self.analisis = json.load(f)
        except Exception:
            pass
        self.aj = self.leer_actual()
        self.sel = None
        self.pendiente = 0
        self.tarjetas = {}
        self.w = {}  # controles por clave, para poder cargarles valores
        self.bloqueo = False
        self.tocado = set()   # claves cambiadas desde la última vez que se aplicó

        prov = Gtk.CssProvider()
        prov.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        hb = Gtk.HeaderBar(title="Configuración", subtitle="de lo básico a lo avanzado", show_close_button=True)
        self.set_titlebar(hb)
        b = Gtk.Button(label="Fondo al azar")
        b.connect("clicked", self.al_azar)
        hb.pack_start(b)

        raiz = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        self.add(raiz)

        # Barra lateral con tres niveles
        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE, transition_duration=120)
        lat = Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE)
        lat.get_style_context().add_class("lateral")
        self.filas = {}
        self.consulta = ""
        for nombre, clave, icono in PAGINAS:
            fila = Gtk.ListBoxRow()
            if clave is None:
                fila.set_selectable(False)
                fila.set_activatable(False)
                l = Gtk.Label(label=nombre, xalign=0)
                l.get_style_context().add_class("cabecera")
                fila.add(l)
            else:
                caja = Gtk.Box(spacing=10)
                cuadro = Gtk.Box()
                cuadro.get_style_context().add_class("ic")
                cuadro.get_style_context().add_class("ic-" + clave)
                cuadro.set_center_widget(Gtk.Image.new_from_icon_name(icono, Gtk.IconSize.MENU))
                caja.pack_start(cuadro, False, False, 0)
                caja.pack_start(Gtk.Label(label=nombre, xalign=0), True, True, 0)
                fila.add(caja)
                fila.clave = clave
                pal = PALABRAS.get(clave, "")
                fila.nombre = " ".join((nombre, T(nombre), pal, T(pal))).lower()
                self.filas[clave] = fila
            lat.add(fila)
        lat.connect("row-selected", lambda _l, r: r and getattr(r, "clave", None) and self.stack.set_visible_child_name(r.clave))

        def filtrar(fila):
            q = self.consulta
            if not q:
                return True
            return getattr(fila, "clave", None) is not None and q in fila.nombre
        lat.set_filter_func(filtrar)

        def buscar(entrada):
            self.consulta = entrada.get_text().strip().lower()
            lat.invalidate_filter()
            if self.consulta:
                for _n, clave, _i in PAGINAS:
                    f = self.filas.get(clave) if clave else None
                    if f is not None and self.consulta in f.nombre:
                        lat.select_row(f)
                        break
        izq = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        izq.set_size_request(190 if self.estrecho else 220, -1)
        busq = Gtk.SearchEntry(placeholder_text="Buscar")
        busq.get_style_context().add_class("buscador")
        busq.connect("search-changed", buscar)
        izq.pack_start(busq, False, False, 0)
        scl = Gtk.ScrolledWindow()
        scl.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scl.add(lat)
        izq.pack_start(scl, True, True, 0)
        raiz.pack_start(izq, False, False, 0)
        raiz.pack_start(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL), False, False, 0)

        self.construir_paginas()
        raiz.pack_start(self.stack, True, True, 0)
        raiz.pack_start(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL), False, False, 0)

        # Columna fija: vista previa y botón de aplicar
        der = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        der.set_border_width(14)
        der.set_size_request(380 if self.estrecho else 470, -1)
        t = Gtk.Label(label="Vista previa", xalign=0)
        t.get_style_context().add_class("titulo-pagina")
        der.pack_start(t, False, False, 0)
        self.vista = Vista()
        if self.estrecho:
            self.vista.set_size_request(350, 208)
        der.pack_start(self.vista, False, False, 4)
        self.info = Gtk.Label(xalign=0, wrap=True)
        self.info.get_style_context().add_class("sub")
        der.pack_start(self.info, False, False, 0)
        der.pack_start(Gtk.Box(), True, True, 0)
        self.estado = Gtk.Label(xalign=0, wrap=True)
        self.estado.get_style_context().add_class("sub")
        der.pack_start(self.estado, False, False, 0)
        fila = Gtk.Box(spacing=8)
        rest = Gtk.Button(label="Todo automático")
        rest.connect("clicked", self.todo_auto)
        fila.pack_start(rest, False, False, 0)
        self.btn_ok = Gtk.Button(label="Aplicar cambios")
        self.btn_ok.get_style_context().add_class("suggested-action")
        self.btn_ok.connect("clicked", self.aplicar)
        fila.pack_end(self.btn_ok, False, False, 0)
        der.pack_start(fila, False, False, 0)
        raiz.pack_start(der, False, False, 0)

        self.cargar_tarjetas()
        self.sincronizar_controles()
        inicial = os.environ.get("GENOS_PAGINA", "fondos")
        fila_inicial = self.filas.get(inicial, self.filas["fondos"])
        # Se elige después de mostrar la ventana: el Stack solo cambia a páginas ya visibles
        GLib.idle_add(lambda: (lat.select_row(fila_inicial), lat.grab_focus(), False)[2])
        threading.Thread(target=self.analizar_todo, daemon=True).start()

    # ------------------------------------------------ estado
    def leer_actual(self):
        aj = dict(DEFECTO)
        try:
            with open(AJUSTES) as f:
                aj.update(json.load(f))
        except Exception:
            pass
        aj["dock_tam"] = dconf_leer("icon-size", aj["dock_tam"])
        aj["dock_zoom"] = dconf_leer("zoom-enabled", aj["dock_zoom"])
        aj["dock_zoomp"] = dconf_leer("zoom-percent", aj["dock_zoomp"])
        aj["dock_pos"] = dconf_leer("position", aj["dock_pos"])
        aj["dock_ocultar"] = dconf_leer("hide-mode", aj["dock_ocultar"])
        ps = paneles()
        if ps:
            aj["alto"] = xf_leer("xfce4-panel", "/panels/%s/size" % ps[0], aj["alto"])
        bl = xf_leer("xfwm4", "/general/button_layout", "CHM|")
        aj["botones"] = "der" if bl.startswith("|") else "izq"
        aj["compositor"] = xf_leer("xfwm4", "/general/use_compositing", aj["compositor"])
        aj["sombra"] = xf_leer("xfwm4", "/general/shadow_opacity", aj["sombra"])
        aj["fuente"] = xf_leer("xsettings", "/Gtk/FontName", aj["fuente"])
        aj["cursor"] = xf_leer("xsettings", "/Gtk/CursorThemeSize", aj["cursor"])
        try:
            with open(CONF_WIDGETS) as f:
                w = json.load(f)
            aj["w_maestro"] = bool(w.get("maestro", aj["w_maestro"]))
            for n, _t, _d in WIDGETS:
                aj["w_" + n] = bool(w.get("activos", {}).get(n, aj["w_" + n]))
                aj["w_pos_" + n] = w.get("pos", {}).get(n, aj["w_pos_" + n])
            aj["w_escala"] = float(w.get("escala", aj["w_escala"]))
            aj["w_opac"] = w.get("opacidad", aj["w_opac"])
            aj["w_monitor"] = str(w.get("monitor", aj["w_monitor"]))
        except Exception:
            pass
        cache = {}
        for k, (canal, prop, tipo, _d) in XF_MAP.items():
            if canal not in cache:
                cache[canal] = xf_canal(canal) if shutil.which("xfconf-query") else {}
            v = cache[canal].get(prop)
            if v is not None:
                aj[k] = convertir_xf(v, tipo, aj[k])
        aj["esc_nombres"] = nombres_escritorios()
        disp = dispositivos_raton()
        aj["rat_disp"] = disp[0] if disp else ""
        aj.update(leer_raton(aj["rat_disp"], aj))
        pp = panel_principal()
        if pp:
            base = "/panels/%s/" % pp
            aj["panel_oculta"] = xf_leer("xfce4-panel", base + "autohide-behavior", aj["panel_oculta"])
            aj["panel_bloq"] = xf_leer("xfce4-panel", base + "position-locked", aj["panel_bloq"])
            aj["panel_iconos"] = xf_leer("xfce4-panel", base + "icon-size", aj["panel_iconos"]) or 16
            aj["panel_largo"] = xf_leer("xfce4-panel", base + "length", aj["panel_largo"])
            aj["panel_crecer"] = xf_leer("xfce4-panel", base + "length-adjust", aj["panel_crecer"])
        aj["tec_layout"], aj["tec_variante"] = distribucion_actual()
        aj["notif_dnd"] = xf_leer("xfce4-notifyd", "/do-not-disturb", aj["notif_dnd"])
        crudo = str(xf_leer("xfce4-notifyd", "/notify-location", aj["notif_pos"]))
        NOTIF_POS_TEXTO[0] = not crudo.strip().isdigit() and crudo.strip() in IDS_POS
        aj["notif_pos"] = pos_id(crudo)
        aj["notif_tiempo"] = xf_leer("xfce4-notifyd", "/expire-timeout", aj["notif_tiempo"])
        aj["notif_fade"] = xf_leer("xfce4-notifyd", "/do-fadeout", aj["notif_fade"])
        return aj

    def poner(self, clave, valor):
        self.aj[clave] = valor
        if not self.bloqueo:
            self.tocado.add(clave)
            if clave not in SIN_VISTA:
                self.refrescar()

    def sincronizar_controles(self):
        """Lleva self.aj a los controles (al cargar un perfil o al restablecer)."""
        self.bloqueo = True
        for clave, w in self.w.items():
            v = self.aj.get(clave)
            if isinstance(w, Gtk.Scale):
                w.set_value(float(v if v is not None else 0.72))
            elif isinstance(w, Gtk.Switch):
                w.set_active(bool(v))
            elif isinstance(w, Gtk.ComboBoxText):
                w.set_active_id(str(v) if v is not None else "auto")
            elif isinstance(w, Gtk.FontButton):
                w.set_font(str(v))
            elif isinstance(w, dict):  # grupos de botones de radio
                clave_b = "auto" if v is None else v
                if clave_b in w:
                    w[clave_b].set_active(True)
        self.bloqueo = False
        self.refrescar()

    # ------------------------------------------------ construcción de páginas
    def pagina(self, clave, titulo, descripcion):
        sc = Gtk.ScrolledWindow()
        sc.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        caja.set_border_width(18)
        t = Gtk.Label(label=titulo, xalign=0)
        t.get_style_context().add_class("titulo-pagina")
        caja.pack_start(t, False, False, 0)
        d = Gtk.Label(label=descripcion, xalign=0, wrap=True)
        d.get_style_context().add_class("sub")
        caja.pack_start(d, False, False, 6)
        sc.add(caja)
        self.stack.add_named(sc, clave)
        return caja

    def grupo(self, caja):
        lb = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        lb.get_style_context().add_class("frame")
        caja.pack_start(lb, False, False, 6)
        return lb

    def fila(self, lb, titulo, desc, control):
        f = Gtk.ListBoxRow(activatable=False)
        h = Gtk.Box(spacing=12)
        h.get_style_context().add_class("fila-ajuste")
        v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        v.pack_start(Gtk.Label(label=titulo, xalign=0), False, False, 0)
        if desc:
            d = Gtk.Label(label=desc, xalign=0, wrap=True)
            d.get_style_context().add_class("sub")
            v.pack_start(d, False, False, 0)
        h.pack_start(v, True, True, 0)
        control.set_valign(Gtk.Align.CENTER)
        h.pack_end(control, False, False, 0)
        f.add(h)
        lb.add(f)

    def escala(self, clave, lo, hi, paso, ancho=210):
        e = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, lo, hi, paso)
        e.set_draw_value(True)
        e.set_value_pos(Gtk.PositionType.RIGHT)
        e.set_size_request(ancho, -1)
        e.connect("value-changed", lambda s: self.poner(clave, s.get_value() if paso < 1 else int(s.get_value())))
        self.w[clave] = e
        return e

    def interruptor(self, clave):
        s = Gtk.Switch()
        s.connect("notify::active", lambda sw, _p: self.poner(clave, sw.get_active()))
        self.w[clave] = s
        return s

    def combo(self, clave, opciones, auto=None):
        c = Gtk.ComboBoxText()
        if auto:
            c.append("auto", auto)
        for i, n in opciones:
            c.append(i, n)
        c.connect("changed", lambda cb: self.poner(clave, None if cb.get_active_id() == "auto" else cb.get_active_id()))
        self.w[clave] = c
        return c

    def construir_paginas(self):
        # ---- Fondos
        c = self.pagina("fondos", "Fondos", "Elige un fondo. El modo, el acento y el contraste se calculan solos a partir de la imagen.")
        sc = Gtk.ScrolledWindow(vexpand=True)
        sc.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sc.set_min_content_height(480)
        self.flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.SINGLE, homogeneous=True,
                                min_children_per_line=2, max_children_per_line=4, row_spacing=8, column_spacing=8)
        self.flow.connect("selected-children-changed", self.cambio_seleccion)
        sc.add(self.flow)
        c.pack_start(sc, True, True, 0)

        # ---- Colores
        c = self.pagina("colores", "Colores", "Todo sale del fondo, pero puedes forzar cualquier parte.")
        g = self.grupo(c)
        caja = Gtk.Box(spacing=8)
        self.w["modo"] = {}
        grupo = None
        for clave, nombre in (("auto", "Automático"), ("claro", "Claro"), ("oscuro", "Oscuro")):
            r = Gtk.RadioButton.new_from_widget(grupo)
            grupo = grupo or r
            r.set_mode(False)
            r.get_style_context().add_class("tarjeta-modo")
            v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            area = Gtk.DrawingArea()
            area.set_size_request(104, 66)
            area.connect("draw", lambda _w, cr, cl=clave: dibuja_mini(cr, 104, 66, cl))
            v.pack_start(area, False, False, 0)
            et = Gtk.Label(label=nombre)
            et.get_style_context().add_class("sub")
            v.pack_start(et, False, False, 0)
            r.add(v)
            r.connect("toggled", lambda rb, cl=clave: rb.get_active() and self.poner("modo", None if cl == "auto" else cl))
            caja.pack_start(r, False, False, 0)
            self.w["modo"][clave] = r
        self.fila(g, "Apariencia", "Automático sigue el fondo; Claro y Oscuro lo fuerzan.", caja)

        col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        caja = Gtk.Box(spacing=2)
        self.w["acento"] = {}
        gr = None
        nombre_acento = Gtk.Label(label="Automático", xalign=1)
        nombre_acento.get_style_context().add_class("sub")
        for clave, nombre, color in ACENTOS:
            b = Gtk.RadioButton.new_from_widget(gr)
            gr = gr or b
            b.set_mode(False)
            b.set_tooltip_text(nombre)
            b.get_style_context().add_class("muestra")
            if color is None:
                b.get_style_context().add_class("muestra-auto")
            else:
                pv = Gtk.CssProvider()
                pv.load_from_data(("button { background-image: none; background-color: %s; }" % color).encode())
                b.get_style_context().add_provider(pv, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)

            def cambio(bt, cl=clave, nom=nombre):
                if bt.get_active():
                    nombre_acento.set_text(nom)
                    self.poner("acento", None if cl == "auto" else cl)
            b.connect("toggled", cambio)
            caja.pack_start(b, False, False, 0)
            self.w["acento"][clave] = b
        col.pack_start(caja, False, False, 0)
        col.pack_start(nombre_acento, False, False, 0)
        self.fila(g, "Color de acento", "Selección, cursor de la terminal y variante del tema.", col)

        caja = Gtk.Box()
        caja.get_style_context().add_class("linked")
        self.w["estilo"] = {}
        gr = None
        for clave, nombre in (("auto", "Automático"), ("solido", "Sólido"), ("cristal", "Cristal"), ("tenido", "Teñido")):
            r = Gtk.RadioButton.new_with_label_from_widget(gr, nombre)
            gr = gr or r
            r.set_mode(False)

            def cambio_estilo(rb, cl=clave):
                if rb.get_active():
                    if not self.bloqueo:
                        self.aj["opacidad"] = None
                    self.poner("estilo", None if cl == "auto" else cl)
            r.connect("toggled", cambio_estilo)
            caja.pack_start(r, False, False, 0)
            self.w["estilo"][clave] = r
        self.fila(g, "Estilo de las pastillas", "Sólido tapa el fondo, Cristal lo deja ver y Teñido mezcla el acento.", caja)

        self.fila(g, "Opacidad mínima", "La barra y el lanzador suben solos si el texto pierde contraste (mínimo 4.5:1).",
                  self.escala("opacidad", 0.55, 0.96, 0.02))
        temas = [(t, t) for t in temas_instalados()]
        self.fila(g, "Tema GTK", "Automático elige la variante de WhiteSur que combina con el acento.",
                  self.combo("tema", temas, "Automático"))

        g2 = self.grupo(c)
        self.fila(g2, "Cambio automático día y noche",
                  "Usa el modo Claro de día y Oscuro de noche con el fondo que tengas puesto.",
                  self.interruptor("dn_activo"))
        self.fila(g2, "El día empieza a las", None,
                  self.combo("dn_dia", [("%02d:00" % h, "%02d:00" % h) for h in range(4, 12)]))
        self.fila(g2, "La noche empieza a las", None,
                  self.combo("dn_noche", [("%02d:00" % h, "%02d:00" % h) for h in range(15, 24)]))

        # ---- Barra
        c = self.pagina("barra", "Barra superior", "Pastillas flotantes sobre el fondo, como una barra de macOS.")
        g = self.grupo(c)
        self.fila(g, "Altura de la barra", "En píxeles. Más baja se ve más discreta.", self.escala("alto", 24, 48, 2))
        self.fila(g, "Esquinas de las pastillas", "0 es cuadrado; 20 es casi cápsula.", self.escala("radio", 0, 20, 1))
        self.fila(g, "Tamaño de los iconos", "Los de la bandeja y los lanzadores.", self.escala("panel_iconos", 12, 32, 2))
        self.fila(g, "Ocultar automáticamente", "La barra se esconde y aparece al acercar el cursor.",
                  self.combo("panel_oculta", [("0", "Nunca"), ("1", "Si una ventana la tapa"), ("2", "Siempre")]))
        self.fila(g, "Bloquear la posición", "Evita moverla o cambiarla por accidente.", self.interruptor("panel_bloq"))
        g = self.grupo(c)
        for titulo, desc, cmd in (
                ("Ordenar la barra", "Menú y ventanas a la izquierda, reloj al centro, bandeja y botón de energía a la derecha.",
                 [os.path.join(HOME, ".local", "bin", "genos-barra")]),
                ("Reiniciar la barra", "Recarga el panel superior.", ["xfce4-panel", "-r"]),
                ("Centro de control: añadir a la barra", "Botón de energía y notificaciones arriba a la derecha.",
                 [os.path.join(HOME, ".local", "bin", "genos-centro"), "--boton"]),
                ("Centro de control: quitar de la barra", "El atajo Ctrl+Alt+C sigue funcionando.",
                 [os.path.join(HOME, ".local", "bin", "genos-centro"), "--quitar-boton"])):
            b = Gtk.Button(label="Ejecutar")
            b.connect("clicked", lambda _b, cm=cmd: subprocess.Popen(cm))
            self.fila(g, titulo, desc, b)

        self.seccion(c, "Longitud", [
            ("esc", "panel_largo", "Largo de la barra", "Porcentaje del ancho de la pantalla.", 10, 100, 5),
            ("sw", "panel_crecer", "Crecer automáticamente si hace falta", None),
        ])

        # ---- Dock
        c = self.pagina("dock", "Dock", "Plank, centrado y con zoom. Los cambios se ven en vivo al aplicar.")
        g = self.grupo(c)
        self.fila(g, "Tamaño de los iconos", None, self.escala("dock_tam", 32, 72, 2))
        self.fila(g, "Zoom al pasar el mouse", "Efecto de ampliación sobre el icono bajo el cursor.", self.interruptor("dock_zoom"))
        self.fila(g, "Intensidad del zoom", "Porcentaje de ampliación.", self.escala("dock_zoomp", 110, 200, 10))
        self.fila(g, "Posición", None, self.combo("dock_pos", POSICIONES))
        self.fila(g, "Visibilidad", None, self.combo("dock_ocultar", OCULTAR))

        # ---- Ventanas
        c = self.pagina("ventanas", "Ventanas", "Aspecto de los marcos. Las animaciones de abrir y minimizar dependen del gestor de ventanas y no se pueden cambiar aquí.")
        g = self.grupo(c)
        self.fila(g, "Botones de ventana", "Izquierda es estilo Mac; derecha, estilo Windows.",
                  self.combo("botones", [("izq", "A la izquierda"), ("der", "A la derecha")]))
        self.fila(g, "Título centrado", None, self.interruptor("centrado"))
        self.fila(g, "Compositor (sombras y transparencias)", "Apágalo si notas lentitud; se pierden sombras y la transparencia de la barra.",
                  self.interruptor("compositor"))
        self.fila(g, "Intensidad de las sombras", None, self.escala("sombra", 0, 100, 5))
        self.fila(g, "Fuente del título", "Solo la de la barra de título de las ventanas.", self.fuente_titulo())

        t = Gtk.Label(label="Foco y clics", xalign=0)
        t.get_style_context().add_class("sub")
        c.pack_start(t, False, False, 6)
        g = self.grupo(c)
        self.fila(g, "Dar foco al hacer clic", "Apagado, el foco sigue al cursor.", self.interruptor("foco_clic"))
        self.fila(g, "Traer al frente al hacer clic", None, self.interruptor("raise_clic"))
        self.fila(g, "Dar foco a las ventanas nuevas", None, self.interruptor("foco_nuevas"))
        self.fila(g, "Evitar que las ventanas roben el foco", None, self.interruptor("evitar_robo"))
        self.fila(g, "Doble clic en el título", None,
                  self.combo("doble_clic", [("maximize", "Maximizar"), ("shade", "Enrollar"), ("hide", "Minimizar"),
                                            ("fill", "Rellenar"), ("none", "Nada")]))
        self.fila(g, "Dónde aparecen las ventanas nuevas", None,
                  self.combo("ubicacion", [("center", "Al centro"), ("mouse", "Bajo el cursor")]))

        t = Gtk.Label(label="Imán y tamaño", xalign=0)
        t.get_style_context().add_class("sub")
        c.pack_start(t, False, False, 6)
        g = self.grupo(c)
        self.fila(g, "Pegarse a los bordes de la pantalla", None, self.interruptor("iman_bordes"))
        self.fila(g, "Pegarse a otras ventanas", None, self.interruptor("iman_ventanas"))
        self.fila(g, "Maximizar sin marcos", "Las ventanas maximizadas pierden el borde.", self.interruptor("max_sin_bordes"))

        t = Gtk.Label(label="Alt+Tab", xalign=0)
        t.get_style_context().add_class("sub")
        c.pack_start(t, False, False, 6)
        g = self.grupo(c)
        self.fila(g, "Estilo", None, self.combo("tab_lista", [("0", "Iconos en una ventana"), ("1", "Lista de ventanas")]))
        self.fila(g, "Incluir ventanas minimizadas", None, self.interruptor("tab_ocultas"))
        self.fila(g, "Incluir ventanas de otros escritorios", None, self.interruptor("tab_escritorios"))
        self.fila(g, "Marcar la ventana elegida", None, self.interruptor("tab_marco"))

        t = Gtk.Label(label="Transparencia", xalign=0)
        t.get_style_context().add_class("sub")
        c.pack_start(t, False, False, 6)
        g = self.grupo(c)
        self.fila(g, "Ventanas sin foco", "100 es opaco. Necesita el compositor.", self.escala("op_inactiva", 40, 100, 5))
        self.fila(g, "Ventanas mientras las mueves", None, self.escala("op_mover", 40, 100, 5))
        self.fila(g, "Marcos de las ventanas", None, self.escala("op_marco", 40, 100, 5))
        self.fila(g, "Menús y avisos emergentes", None, self.escala("op_popup", 40, 100, 5))

        self.seccion(c, "Foco: más opciones", [
            ("sw", "foco_hint", "Respetar las peticiones de foco de las apps", None),
            ("sw", "raise_foco", "Traer al frente al recibir foco", "Útil si el foco sigue al cursor."),
            ("sw", "raise_cualquier", "Traer al frente con cualquier botón del ratón", None),
            ("esc", "foco_retardo", "Retardo del foco", "Milisegundos; solo cuenta si el foco sigue al cursor.", 0, 1000, 50),
            ("cb", "activar", "Al activar una ventana desde otro escritorio",
             None, [("bring", "Traerla aquí"), ("switch", "Ir a su escritorio"), ("none", "No hacer nada")]),
        ])
        self.seccion(c, "Comportamiento", [
            ("esc", "colocar_ratio", "Tamaño mínimo para centrar", "Porcentaje de pantalla que debe ocupar una ventana para centrarse.", 0, 100, 5),
            ("esc", "snap_ancho", "Distancia del imán", "Píxeles.", 0, 50, 1),
            ("sw", "snap_resist", "Resistencia al acercarse a otras ventanas", None),
            ("sw", "caja_mover", "Mover solo el contorno", "Más rápido en equipos lentos.", ),
            ("sw", "caja_redim", "Cambiar el tamaño solo con contorno", None),
            ("sw", "urgente_parp", "Parpadear cuando una ventana pide atención", None),
            ("sw", "rueda_enrollar", "Enrollar la ventana con la rueda sobre el título", None),
            ("sw", "rueda_esc", "Cambiar de escritorio con la rueda sobre el escritorio", None),
            ("sw", "alternar_esc", "Pulsar otra vez el atajo vuelve al escritorio anterior", None),
            ("sw", "vuelta_vent", "Dar la vuelta al llevar una ventana al borde", None),
        ])
        self.seccion(c, "Compositor", [
            ("sw", "sombra_marco", "Sombra en las ventanas", None),
            ("sw", "sombra_popup", "Sombra en menús y avisos", None),
            ("sw", "sombra_dock", "Sombra en el dock y la barra", None),
            ("sw", "zoom_esc", "Zoom del escritorio con Alt y la rueda", None),
            ("cb", "vblank", "Sincronía vertical", "Evita cortes en la imagen; en escritorio remoto déjalo en automático.",
             [("off", "Apagada"), ("auto", "Automática"), ("glx", "GLX"), ("xpresent", "XPresent")]),
        ])

        # ---- Notificaciones
        c = self.pagina("notif", "Notificaciones", "Las burbujas toman el diseño de la barra: pastilla con el color del fondo y botones con tu acento.")
        g = self.grupo(c)
        self.fila(g, "No molestar", "No muestra ninguna burbuja mientras esté activado.", self.interruptor("notif_dnd"))
        self.fila(g, "Posición", None, self.combo("notif_pos", NOTIF_POS))
        self.fila(g, "Duración", "Segundos en pantalla antes de desvanecerse.", self.escala("notif_tiempo", 2, 15, 1))
        self.fila(g, "Opacidad", "Se suma a la transparencia de la pastilla.", self.escala("notif_opac", 0.6, 1.0, 0.05))
        self.fila(g, "Desvanecer al cerrar", None, self.interruptor("notif_fade"))
        self.fila(g, "Deslizar al cerrar", None, self.interruptor("notif_slide"))
        self.fila(g, "Mostrar el valor de las barras de volumen y brillo", None, self.interruptor("notif_gauge"))
        self.fila(g, "Pantalla de las burbujas", None,
                  self.combo("notif_monitor", [("0", "La del cursor"), ("1", "La principal")]))
        g = self.grupo(c)
        b = Gtk.Button(label="Probar")
        b.connect("clicked", self.probar_notif)
        self.fila(g, "Enviar notificaciones de prueba", "Aplica estos ajustes y muestra tres burbujas de ejemplo.", b)
        b = Gtk.Button(label="Abrir")
        b.connect("clicked", lambda *_: subprocess.Popen(["xfce4-notifyd-config"]))
        self.fila(g, "Historial y aplicaciones", "El diálogo de XFCE: historial de avisos y apps silenciadas.", b)

        # ---- Widgets
        c = self.pagina("widgets", "Widgets", "Tarjetas flotantes en el escritorio con los colores del fondo. Reloj y Sistema vienen activados; el resto son opcionales.")
        g = self.grupo(c)
        self.fila(g, "Mostrar widgets", "Atajo para ocultarlos o mostrarlos al instante: Ctrl+Alt+W.", self.interruptor("w_maestro"))
        self.fila(g, "Pantalla", "Dónde se colocan. Si se salen de tu pantalla, elige otra de la lista.",
                  self.combo("w_monitor", pantallas()))
        self.fila(g, "Tamaño", None, self.escala("w_escala", 0.8, 1.4, 0.1))
        self.fila(g, "Opacidad de las tarjetas", "Por defecto se calcula sola para que el texto se lea bien.", self.escala("w_opac", 0.4, 0.96, 0.02))
        g = self.grupo(c)
        for clave, nombre, desc in WIDGETS:
            caja = Gtk.Box(spacing=10)
            caja.pack_start(self.combo("w_pos_" + clave, ESQUINAS), False, False, 0)
            caja.pack_start(self.interruptor("w_" + clave), False, False, 0)
            self.fila(g, nombre, desc, caja)

        # ---- Escritorio
        c = self.pagina("escritorio", "Escritorio", "Iconos sobre el fondo y escritorios virtuales.")
        g = self.grupo(c)
        self.fila(g, "Iconos del escritorio", None,
                  self.combo("esc_iconos", [("0", "Ninguno"), ("1", "Ventanas minimizadas"), ("2", "Archivos y carpetas")]))
        self.fila(g, "Tamaño de los iconos", None, self.escala("esc_tam", 24, 96, 4))
        self.fila(g, "Mostrar Carpeta personal", None, self.interruptor("esc_casa"))
        self.fila(g, "Mostrar Sistema de archivos", None, self.interruptor("esc_sistema"))
        self.fila(g, "Mostrar Papelera", None, self.interruptor("esc_papelera"))
        self.fila(g, "Mostrar unidades extraíbles", None, self.interruptor("esc_extraibles"))
        t = Gtk.Label(label="Escritorios virtuales", xalign=0)
        t.get_style_context().add_class("sub")
        c.pack_start(t, False, False, 6)
        g = self.grupo(c)
        self.fila(g, "Cantidad", "Los cuadritos del selector de la barra salen de aquí.", self.escala("escritorios", 1, 8, 1))
        self.fila(g, "Dar la vuelta al llegar al último", None, self.interruptor("ciclar_esc"))
        t = Gtk.Label(label="Nombres de los escritorios", xalign=0)
        t.get_style_context().add_class("sub")
        c.pack_start(t, False, False, 6)
        g = self.grupo(c)
        self.ent_esc = []
        for i in range(8):
            e = Gtk.Entry()
            e.set_width_chars(22)
            e.set_placeholder_text("Escritorio %d" % (i + 1))
            if i < len(self.aj["esc_nombres"]):
                e.set_text(self.aj["esc_nombres"][i])
            e.connect("changed", self.cambio_nombre_esc)
            self.ent_esc.append(e)
            self.fila(g, "Escritorio %d" % (i + 1), None, e)
        self.seccion(c, "Márgenes de pantalla", [
            ("esc", "margen_izq", "Izquierda", "Espacio que las ventanas maximizadas no ocupan.", 0, 300, 5),
            ("esc", "margen_der", "Derecha", None, 0, 300, 5),
            ("esc", "margen_arr", "Arriba", None, 0, 300, 5),
            ("esc", "margen_aba", "Abajo", None, 0, 300, 5),
        ])

        # ---- Pantalla
        c = self.pagina("pantalla", "Pantalla", "Resolución y tamaño de la interfaz. En escritorio remoto, la ventana de mstsc manda.")
        g = self.grupo(c)
        self.modos, self.salida_p, self.modo_ahora = modos_pantalla()
        salidas = [(o, o) for o in self.modos] or [("", "(sin datos de xrandr)")]
        self.cb_salida = Gtk.ComboBoxText()
        for i, n in salidas:
            self.cb_salida.append(i, n)
        self.cb_salida.set_active_id(self.salida_p or salidas[0][0])
        self.cb_salida.connect("changed", self.llenar_modos)
        self.fila(g, "Pantalla", None, self.cb_salida)
        self.cb_modo = Gtk.ComboBoxText()
        self.fila(g, "Resolución", None, self.cb_modo)
        self.llenar_modos()
        b = Gtk.Button(label="Aplicar resolución")
        b.connect("clicked", self.aplicar_resolucion)
        self.fila(g, "Cambiar ahora", "Se aplica al instante; si no se ve bien, vuelve a elegir la anterior.", b)
        g = self.grupo(c)
        self.fila(g, "Tamaño de la interfaz (DPI)", "96 es lo normal; sube a 120 o 144 si todo se ve pequeño.",
                  self.escala("dpi", 72, 192, 6))
        n = Gtk.Label(xalign=0, wrap=True)
        n.set_markup("<span size='small'>El DPI se aplica con el botón Aplicar de abajo; algunas apps lo toman al reabrirse.</span>")
        n.get_style_context().add_class("sub")
        c.pack_start(n, False, False, 4)

        # ---- Teclado
        c = self.pagina("teclado", "Teclado", "Distribución, velocidad de repetición y atajos de GenOs.")
        g = self.grupo(c)
        self.fila(g, "Distribución", "En escritorio remoto, Windows también envía su propia distribución; si las teclas salen mal, prueba otra.",
                  self.combo("tec_layout", DISTRIBUCIONES))
        self.fila(g, "Variante", None, self.combo("tec_variante", VARIANTES))
        self.fila(g, "Retardo de repetición", "Milisegundos antes de que una tecla empiece a repetirse.",
                  self.escala("tec_retardo", 150, 1000, 50))
        self.fila(g, "Velocidad de repetición", "Repeticiones por segundo.", self.escala("tec_velocidad", 5, 80, 5))
        self.fila(g, "Repetir teclas al mantenerlas", None, self.interruptor("tec_repetir"))
        self.fila(g, "Recordar el estado de Bloq Num", "Al iniciar sesión.", self.interruptor("tec_numlock"))
        t = Gtk.Label(label="Atajos de GenOs", xalign=0)
        t.get_style_context().add_class("sub")
        c.pack_start(t, False, False, 6)
        self.g_atajos = self.grupo(c)
        self.llenar_atajos()

        # ---- Inicio
        c = self.pagina("inicio", "Inicio", "Aplicaciones que se abren al entrar en la sesión.")
        self.seccion(c, "Sesión", [
            ("sw", "se_guardar", "Guardar la sesión al cerrar", "Reabre las ventanas que tenías."),
            ("sw", "se_pregunta", "Preguntar antes de cerrar sesión", None),
            ("sw", "se_bloquear", "Bloquear la pantalla antes de suspender", None),
            ("sw", "se_selector", "Elegir la sesión al entrar", None),
        ])
        t = Gtk.Label(label="Aplicaciones que se abren al iniciar", xalign=0)
        t.get_style_context().add_class("sub")
        c.pack_start(t, False, False, 6)
        self.g_inicio = self.grupo(c)
        self.llenar_inicio()
        b = Gtk.Button(label="Añadir aplicación…")
        b.connect("clicked", self.anadir_inicio)
        c.pack_start(b, False, False, 6)
        b.set_halign(Gtk.Align.START)

        # ---- Apariencia
        c = self.pagina("apariencia", "Apariencia", "Iconos, suavizado de letras y detalles de la interfaz. El tema de colores sale de Colores.")
        self.seccion(c, "Iconos", [
            ("cb", "tema_iconos", "Tema de iconos", "WhiteSur es el que usa el diseño.", [(n, n) for n in temas_de_iconos()]),
        ])
        self.seccion(c, "Suavizado de letras", [
            ("sw", "xft_aa", "Suavizar los bordes", None),
            ("sw", "xft_hint", "Ajustar las letras a la rejilla", None),
            ("cb", "xft_estilo", "Intensidad del ajuste", None,
             [("hintnone", "Ninguno"), ("hintslight", "Suave"), ("hintmedium", "Medio"), ("hintfull", "Completo")]),
            ("cb", "xft_rgba", "Orden de subpíxeles", "Para pantallas LCD; en escritorio remoto déjalo en ninguno.",
             [("none", "Ninguno"), ("rgb", "RGB"), ("bgr", "BGR"), ("vrgb", "VRGB"), ("vbgr", "VBGR")]),
        ])
        self.seccion(c, "Interfaz", [
            ("cb", "barra_herr", "Barras de herramientas", None,
             [("icons", "Solo iconos"), ("text", "Solo texto"), ("both", "Texto bajo los iconos"), ("both-horiz", "Texto al lado")]),
            ("sw", "img_botones", "Iconos en los botones", None),
            ("sw", "img_menus", "Iconos en los menús", None),
            ("sw", "sonidos_ev", "Sonidos de eventos", None),
            ("sw", "sonidos_in", "Sonido al pulsar teclas y botones", None),
        ])

        # ---- Ratón
        c = self.pagina("raton", "Ratón y touchpad", "Velocidad y botones del dispositivo que elijas.")
        g = self.grupo(c)
        disp = dispositivos_raton()
        self.cb_raton = Gtk.ComboBoxText()
        for d_ in disp:
            self.cb_raton.append(d_, d_.replace("_", " "))
        self.cb_raton.set_active_id(self.aj["rat_disp"] if self.aj["rat_disp"] in disp else disp[0])
        self.cb_raton.connect("changed", self.cambio_raton)
        self.fila(g, "Dispositivo", None, self.cb_raton)
        self.seccion(c, "Botones y desplazamiento", [
            ("sw", "rat_zurdo", "Botones para zurdos", "Intercambia el botón principal y el secundario."),
            ("sw", "rat_invertir", "Invertir el sentido del desplazamiento", None),
        ])
        self.seccion(c, "Velocidad", [
            ("esc", "rat_aceler", "Aceleración", "Más alta, el cursor llega más lejos con el mismo gesto.", 0.5, 10.0, 0.5),
            ("esc", "rat_umbral", "Sensibilidad para arrastrar", "Píxeles que hay que mover antes de arrastrar.", 1, 30, 1),
        ])

        # ---- Sonido
        c = self.pagina("sonido", "Sonido", "Cambia al instante; no hace falta pulsar Aplicar.")
        self.construir_sonido(c)

        # ---- Energía
        c = self.pagina("energia", "Energía", "Pantalla, avisos y bloqueo. En WSL no hay suspensión, así que solo salen las opciones que sirven.")
        self.seccion(c, "Avisos", [
            ("sw", "pw_notif", "Notificaciones de estado", "Batería baja, cable conectado, etc."),
            ("sw", "pw_tray", "Icono de energía en la bandeja", None),
        ])
        self.seccion(c, "Pantalla", [
            ("sw", "pw_dpms", "Apagar la pantalla por inactividad", None),
            ("esc", "pw_blank_ca", "Con corriente", "Minutos hasta apagar la pantalla; 0 es nunca.", 0, 60, 1),
            ("esc", "pw_blank_bat", "Con batería", None, 0, 60, 1),
            ("sw", "pw_bloqueo", "Bloquear la pantalla al suspender", None),
        ])

        # ---- Unidades
        c = self.pagina("unidades", "Unidades extraíbles", "Qué hacer cuando conectas una memoria USB, un disco o un CD.")
        self.seccion(c, "Almacenamiento", [
            ("sw", "rm_montar", "Montar al conectar", None),
            ("sw", "rm_medios", "Montar los medios al insertarlos", None),
            ("sw", "rm_explorar", "Abrirlos en el explorador de archivos", None),
            ("sw", "rm_autorun", "Ejecutar los programas automáticos", None),
            ("sw", "rm_autoabrir", "Abrir sus archivos al conectar", None),
        ])
        self.seccion(c, "Discos vacíos", [("sw", "rm_grabar", "Grabar un CD o DVD al insertar uno vacío", None)])

        # ---- Aplicaciones
        c = self.pagina("apps", "Aplicaciones", "Qué programa se abre por defecto y cómo se comporta el portapapeles.")
        g = self.grupo(c)
        for clave, titulo, cat in (("WebBrowser", "Navegador web", "WebBrowser"), ("MailReader", "Correo", "MailReader"),
                                   ("FileManager", "Gestor de archivos", "FileManager"),
                                   ("TerminalEmulator", "Terminal", "TerminalEmulator")):
            cb = Gtk.ComboBoxText()
            cb.append("", "(sin elegir)")
            for i_, n_ in helpers_de(cat):
                cb.append(i_, n_)
            cb.set_active_id(helper_actual(clave))
            cb.connect("changed", lambda w, cl=clave: w.get_active_id() and poner_helper(cl, w.get_active_id()))
            self.fila(g, titulo, None, cb)
        self.seccion(c, "Portapapeles", [
            ("sw", "cl_guardar", "Guardar el historial al cerrar sesión", None),
            ("sw", "cl_sync", "Sincronizar la selección del ratón con Ctrl+C", None),
            ("esc", "cl_max", "Textos en el historial", None, 5, 100, 5),
            ("esc", "cl_menu", "Elementos en el menú", None, 5, 50, 1),
            ("sw", "cl_puntero", "Abrir el menú bajo el cursor", "Solo con el atajo de xfce4-popup-clipman."),
            ("cb", "cl_pegar", "Al elegir un elemento", None,
             [("0", "Solo copiarlo"), ("1", "Pegarlo con Ctrl+V"), ("2", "Pegarlo con Shift+Insertar")]),
        ])

        # ---- Archivos
        c = self.pagina("archivos", "Archivos", "Preferencias de Thunar, el gestor de archivos.")
        self.seccion(c, "Vista", [
            ("cb", "th_vista", "Vista para las carpetas nuevas", None,
             [("void", "La última usada"), ("ThunarIconView", "Iconos"), ("ThunarDetailsView", "Lista detallada"),
              ("ThunarCompactView", "Lista compacta")]),
            ("sw", "th_carpetas", "Carpetas antes que archivos", None),
            ("sw", "th_binario", "Tamaños en formato binario (KiB, MiB)", None),
            ("sw", "th_texto_lado", "Nombre al lado de los iconos", None),
            ("sw", "th_geometria", "Recordar el tamaño de la ventana", None),
            ("cb", "th_fecha", "Formato de fecha", None,
             [("THUNAR_DATE_STYLE_SIMPLE", "Hoy y ayer"), ("THUNAR_DATE_STYLE_SHORT", "Corto"),
              ("THUNAR_DATE_STYLE_LONG", "Largo"), ("THUNAR_DATE_STYLE_ISO", "ISO")]),
        ])
        self.seccion(c, "Miniaturas", [
            ("cb", "th_miniaturas", "Mostrar miniaturas", None,
             [("THUNAR_THUMBNAIL_MODE_NEVER", "Nunca"), ("THUNAR_THUMBNAIL_MODE_ONLY_LOCAL", "Solo en archivos locales"),
              ("THUNAR_THUMBNAIL_MODE_ALWAYS", "Siempre")]),
            ("sw", "th_marcos", "Marco alrededor de las miniaturas", None),
        ])
        self.seccion(c, "Navegación", [("sw", "th_un_clic", "Abrir con un solo clic", None)])

        # ---- Terminal y editor
        c = self.pagina("terminal", "Terminal y editor", "Se guardan al instante, sin pulsar Aplicar.")
        self.construir_terminal(c)

        # ---- Accesibilidad
        c = self.pagina("accesib", "Accesibilidad", "Ayudas de teclado y ratón para quien las necesite.")
        self.seccion(c, "Teclado", [
            ("sw", "ac_pegajosas", "Teclas especiales", "Ctrl, Alt y Mayús se pulsan de una en una."),
            ("sw", "ac_lentas", "Teclas lentas", "Hay que mantener la tecla un momento."),
            ("sw", "ac_rebote", "Teclas de rebote", "Ignora pulsaciones repetidas muy rápido."),
        ])
        self.seccion(c, "Ratón", [("sw", "ac_raton", "Mover el cursor con el teclado numérico", None)])

        # ---- Acerca de
        c = self.pagina("acerca", "Acerca de GenOS", "")
        self.construir_acerca(c)

        # ---- Texto y cursor
        c = self.pagina("texto", "Texto y cursor", "Tipografía general y tamaño del cursor.")
        g = self.grupo(c)
        fb = Gtk.FontButton()
        fb.set_font(self.aj["fuente"])
        fb.connect("font-set", lambda b: self.poner("fuente", b.get_font()))
        self.w["fuente"] = fb
        self.fila(g, "Fuente de la interfaz", "Inter 10 es la que usa el diseño.", fb)
        self.fila(g, "Tamaño del cursor", None, self.escala("cursor", 16, 48, 2))
        self.fila(g, "Tema del cursor", "Se aplica al volver a entrar en la sesión.",
                  self.combo("tema_cursor", [(n, n) for n in temas_de_cursor()]))
        self.fila(g, "Fuente de texto monoespaciado", "Terminales y editores.", self.selector_fuente("fuente_mono"))
        self.fila(g, "Cursor de texto parpadeante", None, self.interruptor("cursor_parpadeo"))
        self.fila(g, "Velocidad del parpadeo", "Milisegundos por ciclo.", self.escala("cursor_tiempo", 200, 2000, 100))

        # ---- Perfiles
        c = self.pagina("perfiles", "Perfiles", "Guarda tu combinación (fondo, colores, barra, dock y ventanas) y vuelve a ella cuando quieras.")
        t = Gtk.Label(label="Incluidos", xalign=0)
        t.get_style_context().add_class("sub")
        c.pack_start(t, False, False, 0)
        g = self.grupo(c)
        for nombre, vals in PRESETS.items():
            b = Gtk.Button(label="Cargar")
            b.connect("clicked", lambda _b, v=vals: self.cargar_perfil(v))
            self.fila(g, nombre, None, b)
        t = Gtk.Label(label="Tus perfiles", xalign=0)
        t.get_style_context().add_class("sub")
        c.pack_start(t, False, False, 6)
        self.caja_perfiles = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        c.pack_start(self.caja_perfiles, False, False, 0)
        fila = Gtk.Box(spacing=8)
        self.nombre_perfil = Gtk.Entry(placeholder_text="Nombre del perfil")
        fila.pack_start(self.nombre_perfil, True, True, 0)
        bg = Gtk.Button(label="Guardar el actual")
        bg.connect("clicked", self.guardar_perfil)
        fila.pack_start(bg, False, False, 0)
        c.pack_start(fila, False, False, 10)
        t = Gtk.Label(label="Compartir", xalign=0)
        t.get_style_context().add_class("sub")
        c.pack_start(t, False, False, 6)
        g = self.grupo(c)
        b = Gtk.Button(label="Exportar")
        b.connect("clicked", self.exportar)
        self.fila(g, "Exportar mi tema a Windows",
                  "Crea un .zip con el fondo, los colores y el dock, más una captura, en tu carpeta Descargas.", b)
        b = Gtk.Button(label="Importar")
        b.connect("clicked", self.importar_tema)
        self.fila(g, "Importar un tema", "Aplica un .zip exportado desde otro GenOS.", b)
        self.listar_perfiles()

        # ---- Sistema
        c = self.pagina("sistema", "Sistema", "Utilidades para cuando algo no se ve como debe.")
        if i18n:
            t = Gtk.Label(label="Idioma", xalign=0)
            t.get_style_context().add_class("sub")
            c.pack_start(t, False, False, 0)
            g = self.grupo(c)
            almacen = Gtk.ListStore(str, str)
            for cod, nom in i18n.IDIOMAS:
                almacen.append([cod, nom])
            cb = Gtk.ComboBox.new_with_model(almacen)
            rend = Gtk.CellRendererText()
            cb.pack_start(rend, True)
            cb.add_attribute(rend, "text", 1)
            cb.set_id_column(0)
            cb.set_active_id(i18n.LANG)
            cb.connect("changed", self.cambio_idioma)
            self.fila(g, "Idioma del programa",
                      "Configuración se reabre sola. El Centro de control y los widgets lo toman la próxima vez que se abran.", cb)
        g = self.grupo(c)
        for titulo, desc, cb in (
            ("Reiniciar la barra", "Recarga el panel superior.", lambda *_: subprocess.Popen(["xfce4-panel", "-r"])),
            ("Reiniciar el dock", "Cierra Plank y lo vuelve a abrir.", self.reiniciar_dock),
            ("Abrir la carpeta de fondos", DIR, lambda *_: subprocess.Popen(["xdg-open", DIR])),
            ("Reiniciar el escritorio", "Recarga los iconos y el fondo del escritorio.",
             lambda *_: subprocess.Popen(["xfdesktop", "--reload"])),
            ("Volver a lo automático", "Quita todos los ajustes manuales de color, tema y opacidad.", self.todo_auto),
        ):
            b = Gtk.Button(label="Ejecutar")
            b.connect("clicked", cb)
            self.fila(g, titulo, desc, b)

        t = Gtk.Label(label="Gestor de ajustes de XFCE", xalign=0)
        t.get_style_context().add_class("sub")
        c.pack_start(t, False, False, 6)
        g = self.grupo(c)
        self.sw_ocultar = Gtk.Switch()
        self.sw_ocultar.set_active(ajustes_ocultos())
        self.sw_ocultar.connect("notify::active", self.cambio_ocultar)
        self.fila(g, "Reemplazar el Gestor de ajustes de XFCE",
                  "Configuración ocupa su lugar en el menú, el dock y la línea de comandos. Se esconden las entradas que ya tiene.",
                  self.sw_ocultar)
        if gestor_original():
            b = Gtk.Button(label="Abrir")
            b.connect("clicked", lambda *_: subprocess.Popen([gestor_original()], start_new_session=True))
            self.fila(g, "Abrir el gestor original", "El de XFCE, por si falta algo en Configuración.", b)

        self.construir_actualizaciones(c)

        orig = [(t_, cm) for t_, cm in (("Elementos de la barra", ["xfce4-panel", "--preferences"]),
                            ("Pantalla completa", ["xfce4-display-settings"]),
                            ("Teclado y atajos", ["xfce4-keyboard-settings"]),
                            ("Escritorio y fondo", ["xfdesktop-settings"]),
                            ("Gestor de ventanas", ["xfwm4-settings"]),
                            ("Ajustes extra de ventanas", ["xfwm4-tweaks-settings"]),
                            ("Escritorios virtuales", ["xfwm4-workspace-settings"]),
                            ("Sesión e inicio", ["xfce4-session-settings"]),
                            ("Apariencia", ["xfce4-appearance-settings"]),
                            ("Ratón y touchpad", ["xfce4-mouse-settings"]),
                            ("Energía", ["xfce4-power-manager-settings"]),
                            ("Unidades extraíbles", ["thunar-volman-settings"]),
                            ("Accesibilidad", ["xfce4-accessibility-settings"]),
                            ("Aplicaciones predeterminadas", ["xfce4-mime-settings"]),
                            ("Preferencias de Thunar", ["thunar-settings"]),
                            ("Portapapeles", ["xfce4-clipman-settings"]),
                            ("Mezclador de sonido", ["pavucontrol"]),
                            ("Perfiles de color", ["xfce4-color-settings"]),
                            ("Terminal (diálogo original)", ["xfce4-terminal", "--preferences"]),
                            ("Editor de ajustes", ["xfce4-settings-editor"])) if shutil.which(cm[0])]
        if orig:
            t = Gtk.Label(label="Diálogos originales de XFCE (avanzado)", xalign=0)
            t.get_style_context().add_class("sub")
            c.pack_start(t, False, False, 6)
            g = self.grupo(c)
        for titulo, cmd in orig:
            b = Gtk.Button(label="Abrir")
            b.connect("clicked", lambda _b, cm=cmd: subprocess.Popen(cm))
            self.fila(g, titulo, None, b)
        n = Gtk.Label(xalign=0, wrap=True)
        n.set_markup("<span size='small'>Comandos útiles:  <tt>genos-fondo</tt> lista los fondos,  <tt>genos-fondo 7</tt> aplica el 7,  "
                     "<tt>genos-fondo --elegir</tt> abre el selector rápido.</span>")
        n.get_style_context().add_class("sub")
        c.pack_start(n, False, False, 10)

    def seccion(self, c, titulo, filas):
        """Agrega una sección: filas = (tipo, clave, título, descripción[, extra...])."""
        if titulo:
            t = Gtk.Label(label=titulo, xalign=0)
            t.get_style_context().add_class("sub")
            c.pack_start(t, False, False, 6)
        g = self.grupo(c)
        for f in filas:
            tipo, clave, tit, desc = f[:4]
            if tipo == "sw":
                ctl = self.interruptor(clave)
            elif tipo == "esc":
                ctl = self.escala(clave, f[4], f[5], f[6])
            elif tipo == "cb":
                ctl = self.combo(clave, f[4])
            else:
                continue
            self.fila(g, tit, desc, ctl)
        return g

    def selector_fuente(self, clave):
        fb = Gtk.FontButton()
        fb.set_font(str(self.aj.get(clave, "Sans 10")))
        fb.connect("font-set", lambda b: self.poner(clave, b.get_font()))
        self.w[clave] = fb
        return fb

    def cambio_nombre_esc(self, *_):
        self.aj["esc_nombres"] = [e.get_text().strip() for e in self.ent_esc]
        if not self.bloqueo:
            self.tocado.add("esc_nombres")

    def cambio_raton(self, cb):
        disp = cb.get_active_id()
        if not disp:
            return
        self.aj["rat_disp"] = disp
        self.aj.update(leer_raton(disp, self.aj))
        self.tocado.add("rat_disp")
        self.sincronizar_controles()

    def construir_sonido(self, c):
        if not shutil.which("pactl"):
            n = Gtk.Label(label="No encuentro pactl. Instala pulseaudio-utils para controlar el volumen desde aquí.", xalign=0)
            n.get_style_context().add_class("sub")
            c.pack_start(n, False, False, 6)
            return
        for tipo, titulo in (("sink", "Salida"), ("source", "Entrada")):
            t = Gtk.Label(label=titulo, xalign=0)
            t.get_style_context().add_class("sub")
            c.pack_start(t, False, False, 6)
            g = self.grupo(c)
            devs = audio_dispositivos(tipo)
            actual = audio_pactl("get-default-" + tipo).strip()
            cb = Gtk.ComboBoxText()
            for nom, desc in devs:
                cb.append(nom, desc)
            cb.set_active_id(actual if actual else (devs[0][0] if devs else None))
            cb.connect("changed", lambda w, tp=tipo: w.get_active_id() and audio_pactl("set-default-" + tp, w.get_active_id()))
            self.fila(g, "Dispositivo", None, cb)
            esc = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 150, 1)
            esc.set_value_pos(Gtk.PositionType.RIGHT)
            esc.set_size_request(230, -1)
            esc.set_value(audio_volumen(tipo))
            esc.connect("value-changed", lambda w, tp=tipo: audio_pactl("set-%s-volume" % tp, "@DEFAULT_%s@" % tp.upper(),
                                                                       "%d%%" % int(w.get_value())))
            self.fila(g, "Volumen", "Pasar de 100 puede distorsionar.", esc)
            sw = Gtk.Switch()
            sw.set_active(audio_silencio(tipo))
            sw.connect("notify::active", lambda w, _p, tp=tipo: audio_pactl("set-%s-mute" % tp, "@DEFAULT_%s@" % tp.upper(),
                                                                           "1" if w.get_active() else "0"))
            self.fila(g, "Silenciar", None, sw)

    def construir_terminal(self, c):
        def fila_ini(g, titulo, desc, ctl):
            self.fila(g, titulo, desc, ctl)

        t = Gtk.Label(label="Terminal de XFCE", xalign=0)
        t.get_style_context().add_class("sub")
        c.pack_start(t, False, False, 6)
        g = self.grupo(c)
        fb = Gtk.FontButton()
        fb.set_font(ini_leer(RC_TERMINAL, "FontName", "Monospace 11"))
        fb.connect("font-set", lambda b: ini_poner(RC_TERMINAL, {"FontName": b.get_font()}))
        self.fila(g, "Fuente", "Se aplica a las terminales nuevas.", fb)
        esc = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0.3, 1.0, 0.05)
        esc.set_value_pos(Gtk.PositionType.RIGHT)
        esc.set_size_request(210, -1)
        try:
            esc.set_value(float(ini_leer(RC_TERMINAL, "BackgroundDarkness", "0.9")))
        except ValueError:
            esc.set_value(0.9)
        esc.connect("value-changed", lambda w: ini_poner(RC_TERMINAL, {"BackgroundMode": "TERMINAL_BACKGROUND_TRANSPARENT",
                                                                       "BackgroundDarkness": "%.2f" % w.get_value()}))
        self.fila(g, "Opacidad del fondo", "Más bajo se ve más transparente.", esc)
        sc = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 1000, 50000, 1000)
        sc.set_value_pos(Gtk.PositionType.RIGHT)
        sc.set_size_request(210, -1)
        try:
            sc.set_value(float(ini_leer(RC_TERMINAL, "ScrollingLines", "10000")))
        except ValueError:
            sc.set_value(10000)
        sc.connect("value-changed", lambda w: ini_poner(RC_TERMINAL, {"ScrollingLines": str(int(w.get_value()))}))
        self.fila(g, "Líneas guardadas al desplazar", None, sc)
        cb = Gtk.ComboBoxText()
        for i_, n_ in (("TERMINAL_CURSOR_SHAPE_BLOCK", "Bloque"), ("TERMINAL_CURSOR_SHAPE_IBEAM", "Barra"),
                       ("TERMINAL_CURSOR_SHAPE_UNDERLINE", "Subrayado")):
            cb.append(i_, n_)
        cb.set_active_id(ini_leer(RC_TERMINAL, "MiscCursorShape", "TERMINAL_CURSOR_SHAPE_BLOCK"))
        cb.connect("changed", lambda w: w.get_active_id() and ini_poner(RC_TERMINAL, {"MiscCursorShape": w.get_active_id()}))
        self.fila(g, "Forma del cursor", None, cb)
        for clave, titulo, def_ in (("MiscCursorBlinks", "Cursor parpadeante", "false"), ("MiscBell", "Sonido de campana", "false")):
            sw = Gtk.Switch()
            sw.set_active(ini_leer(RC_TERMINAL, clave, def_) == "TRUE" or ini_leer(RC_TERMINAL, clave, def_).lower() == "true")
            sw.connect("notify::active", lambda w, _p, cl=clave: ini_poner(RC_TERMINAL, {cl: "TRUE" if w.get_active() else "FALSE"}))
            self.fila(g, titulo, None, sw)

        t = Gtk.Label(label="Editor de texto (Mousepad)", xalign=0)
        t.get_style_context().add_class("sub")
        c.pack_start(t, False, False, 6)
        g = self.grupo(c)
        if not shutil.which("gsettings") or not correr(["gsettings", "list-schemas"], timeout=5).count("org.xfce.mousepad"):
            self.fila(g, "Mousepad no está instalado", "Cuando lo instales, sus opciones saldrán aquí.", Gtk.Label(label=""))
            return
        for sub, clave, titulo in (("view", "show-line-numbers", "Mostrar números de línea"),
                                   ("view", "word-wrap", "Ajustar las líneas largas"),
                                   ("view", "highlight-current-line", "Resaltar la línea actual"),
                                   ("view", "auto-indent", "Sangría automática")):
            sw = Gtk.Switch()
            sw.set_active(mousepad_leer(sub, clave, False))
            sw.connect("notify::active", lambda w, _p, sb=sub, cl=clave: mousepad_poner(sb, cl, w.get_active()))
            self.fila(g, titulo, None, sw)
        ancho = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 2, 8, 1)
        ancho.set_value_pos(Gtk.PositionType.RIGHT)
        ancho.set_size_request(210, -1)
        ancho.set_value(mousepad_leer("view", "tab-width", 8))
        ancho.connect("value-changed", lambda w: mousepad_poner("view", "tab-width", int(w.get_value())))
        self.fila(g, "Ancho de tabulación", None, ancho)

    def construir_acerca(self, c):
        # Emblema del wallpaper de GenOs (hexágono y G), mismos trazados que en Canva
        HEX = "M104.8,0.0 L209.5,60.5 L209.5,181.5 L104.8,242.0 L0.0,181.5 L0.0,60.5 Z M104.8,12.0 L10.4,66.5 L10.3,175.5 L104.8,230.0 L199.2,175.5 L199.2,66.5 Z"
        GE = ("M67.2,0.0 L137.2,40.4 L129.7,53.3 L123.2,49.6 L67.2,17.3 L15.0,47.4 L14.9,107.8 L67.2,138.0 "
              "L119.5,107.8 L119.5,85.1 L66.7,85.1 L66.7,70.2 L74.1,70.2 L134.5,70.2 L134.5,116.4 L67.2,155.3 "
              "L0.0,116.4 L0.0,38.8 Z")
        logo = Gtk.DrawingArea()
        logo.set_size_request(140, 150)
        logo.set_halign(Gtk.Align.CENTER)

        def trazar(cr, d, dx, dy, k):
            for cmd, x, y in re.findall(r"([MLZ])\s*([-\d.]*),?([-\d.]*)", d):
                if cmd == "Z":
                    cr.close_path()
                elif cmd == "M":
                    cr.move_to(dx + float(x) * k, dy + float(y) * k)
                else:
                    cr.line_to(dx + float(x) * k, dy + float(y) * k)

        def dibuja(w, cr):
            fg = w.get_style_context().get_color(Gtk.StateFlags.NORMAL)
            cr.set_source_rgba(fg.red, fg.green, fg.blue, 1)
            k = 140.0 / 242.0
            x0, y0 = (w.get_allocated_width() - 209.5 * k) / 2, (w.get_allocated_height() - 242 * k) / 2
            cr.set_fill_rule(1)  # even-odd: el aro queda hueco
            trazar(cr, HEX, x0, y0, k)
            cr.fill()
            trazar(cr, GE, x0 + 37.6 * k, y0 + 43.4 * k, k)
            cr.fill()
            return False

        logo.connect("draw", dibuja)
        c.pack_start(logo, False, False, 14)
        t = Gtk.Label()
        t.set_markup("<span size='28000' weight='bold'>GenOS</span>")
        c.pack_start(t, False, False, 0)
        base = dict(info_sistema()).get("Base", "Debian GNU/Linux")
        sub = Gtk.Label()
        sub.set_markup("<span size='11000'>Versión %s  ·  basado en %s</span>" % (GENOS_VERSION, GLib.markup_escape_text(base)))
        sub.get_style_context().add_class("sub")
        c.pack_start(sub, False, False, 4)

        info = info_sistema()
        g = self.grupo(c)
        g.set_margin_top(22)
        for k, val in info:
            if k in ("Escritorio", "Núcleo", "Procesador", "Memoria", "Equipo"):
                l = Gtk.Label(label=val, xalign=1)
                l.get_style_context().add_class("valor")
                l.set_line_wrap(True)
                l.set_max_width_chars(40)
                self.fila(g, k, None, l)

        ex = Gtk.Expander(label="Interfaces usadas y modificadas")
        ex.set_margin_top(14)
        fb = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, homogeneous=False, row_spacing=6, column_spacing=6,
                         min_children_per_line=2, max_children_per_line=8)
        fb.set_margin_top(10)
        for nombre, rol, tipo, nota, binario in INTERFACES:
            if binario and not shutil.which(binario):
                continue
            chip = Gtk.Label(label=nombre)
            chip.get_style_context().add_class("chip")
            if tipo != "orig":
                chip.get_style_context().add_class("chip-mod")
            chip.set_tooltip_text("%s: %s" % (T(rol), T(nota)))
            fb.add(chip)
        for hijo in fb.get_children():
            hijo.set_can_focus(False)
        ex.add(fb)
        c.pack_start(ex, False, False, 0)

        pie = Gtk.Box(spacing=12)
        pie.set_halign(Gtk.Align.CENTER)
        b = Gtk.Button(label="Copiar información")

        def copiar(*_):
            txt = "\n".join("%s: %s" % kv for kv in info)
            Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(txt, -1)
            self.estado.set_text("Información copiada.")
            GLib.timeout_add_seconds(4, lambda: (self.estado.set_text(""), False)[1])

        b.connect("clicked", copiar)
        pie.pack_start(b, False, False, 0)
        cr = Gtk.Button(label="Créditos")
        cr.set_relief(Gtk.ReliefStyle.NONE)
        cr.get_style_context().add_class("minimo")
        cr.connect("clicked", self.mostrar_creditos)
        pie.pack_start(cr, False, False, 0)
        c.pack_start(pie, False, False, 18)

    def mostrar_creditos(self, *_):
        d = Gtk.Dialog(title="Créditos", transient_for=self, modal=True)
        d.add_button("Cerrar", Gtk.ResponseType.CLOSE)
        caja = d.get_content_area()
        caja.set_spacing(10)
        for lado in ("top", "bottom", "start", "end"):
            getattr(caja, "set_margin_" + lado)(20)
        t = Gtk.Label(xalign=0)
        t.set_markup("<span size='16000' weight='bold'>GenOS %s</span>" % GENOS_VERSION)
        caja.pack_start(t, False, False, 0)
        for linea in ("Proyecto de Duvan Esteban Chaparro Castro.",
                      "Diseñado y programado con la ayuda de Claude, de Anthropic.",
                      "Se apoya en software libre: Debian, XFCE, Plank, Rofi, xrdp, Thunar, Mousepad y el tema WhiteSur. "
                      "Cada proyecto es de sus autores y conserva su licencia."):
            caja.pack_start(Gtk.Label(label=linea, xalign=0, wrap=True, width_chars=46, max_width_chars=46), False, False, 0)
        d.show_all()
        d.run()
        d.destroy()

    def fuente_titulo(self):
        fb = Gtk.FontButton()
        fb.set_font(str(self.aj.get("titulo_fuente", "Sans Bold 9")))
        fb.connect("font-set", lambda b: self.poner("titulo_fuente", b.get_font()))
        self.w["titulo_fuente"] = fb
        return fb

    def llenar_modos(self, *_):
        self.cb_modo.remove_all()
        o = self.cb_salida.get_active_id() or ""
        for m in self.modos.get(o, []):
            self.cb_modo.append(m, m)
        self.cb_modo.set_active_id(self.modo_ahora.get(o, ""))

    def aplicar_resolucion(self, *_):
        o, m = self.cb_salida.get_active_id(), self.cb_modo.get_active_id()
        if not (o and m and shutil.which("xrandr")):
            return
        r = subprocess.run(["xrandr", "--output", o, "--mode", m], capture_output=True, text=True)
        self.estado.set_text("Resolución cambiada a %s." % m if r.returncode == 0 else "xrandr no pudo: %s" % r.stderr.strip()[:120])
        GLib.timeout_add_seconds(6, lambda: (self.estado.set_text(""), False)[1])

    # ------------------------------------------------ actualizaciones
    def construir_actualizaciones(self, c):
        t = Gtk.Label(label="Actualizaciones", xalign=0)
        t.get_style_context().add_class("sub")
        c.pack_start(t, False, False, 0)
        g = self.grupo(c)
        self.lbl_act = Gtk.Label(label="Tienes la versión %s." % GENOS_VERSION, xalign=1)
        self.lbl_act.get_style_context().add_class("valor")
        self.btn_act = Gtk.Button(label="Buscar")
        self.btn_act.connect("clicked", self.buscar_actualizacion)
        caja = Gtk.Box(spacing=8)
        caja.pack_start(self.lbl_act, False, False, 0)
        caja.pack_start(self.btn_act, False, False, 0)
        self.fila(g, "Buscar actualizaciones", "Tu personalización se conserva y antes se guarda un respaldo.", caja)
        sw = Gtk.Switch(valign=Gtk.Align.CENTER)
        sw.set_active(aviso_activo())
        sw.connect("notify::active", lambda w, _p: poner_aviso(w.get_active()))
        self.fila(g, "Avisarme cuando haya una versión nueva", "Revisa una vez al día al entrar en la sesión.", sw)
        for nombre, desc, arg in (("Lista de cambios", "Qué trae cada versión.", "--ver-cambios"),
                                  ("Historial", "Actualizaciones instaladas en este equipo.", "--historial"),
                                  ("Volver al respaldo", "Deja tu configuración como estaba antes de la última actualización.", "--revertir")):
            b = Gtk.Button(label="Abrir" if arg != "--revertir" else "Restaurar")
            b.connect("clicked", lambda _b, a=arg: self.accion_actualizar(a))
            self.fila(g, nombre, desc, b)

    def buscar_actualizacion(self, *_):
        act = os.path.join(os.path.dirname(BIN), "genos-actualizar")
        if getattr(self, "version_nueva", None):
            subprocess.Popen([act, "--terminal"], start_new_session=True)
            return
        self.lbl_act.set_text("Buscando…")
        self.btn_act.set_sensitive(False)

        def trabajo():
            partes = correr([act, "--estado"], timeout=30).split()
            GLib.idle_add(self.fin_buscar, partes)

        threading.Thread(target=trabajo, daemon=True).start()

    def fin_buscar(self, partes):
        self.btn_act.set_sensitive(True)
        estado = partes[0] if partes else "sin-conexion"
        if estado == "disponible" and len(partes) >= 3:
            self.version_nueva = partes[2]
            self.lbl_act.set_text(T("Versión %s disponible.") % partes[2])
            self.btn_act.set_label("Actualizar")
            self.btn_act.get_style_context().add_class("suggested-action")
        elif estado == "al-dia":
            self.lbl_act.set_text(T("Tienes la última versión (%s).") % GENOS_VERSION)
        else:
            self.lbl_act.set_text("Sin conexión con GitHub.")
        return False

    def accion_actualizar(self, arg):
        act = os.path.join(os.path.dirname(BIN), "genos-actualizar")
        if arg == "--ver-cambios":
            subprocess.Popen([act, arg], start_new_session=True)
            return
        if arg == "--revertir":
            d = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.QUESTION,
                                  buttons=Gtk.ButtonsType.OK_CANCEL, text="¿Volver al respaldo?")
            d.format_secondary_text("Se restaura tu configuración de antes de la última actualización.")
            ok = d.run() == Gtk.ResponseType.OK
            d.destroy()
            if not ok:
                return
        salida = correr([act, arg], timeout=60) or "Sin datos."
        d = Gtk.Dialog(title="Historial" if arg == "--historial" else "Volver al respaldo", transient_for=self, modal=True)
        d.add_button("Cerrar", Gtk.ResponseType.CLOSE)
        d.set_default_size(520, 360)
        tv = Gtk.TextView(editable=False, monospace=True, wrap_mode=Gtk.WrapMode.WORD)
        tv.get_buffer().set_text(T(salida.strip()))
        sc = Gtk.ScrolledWindow(vexpand=True)
        sc.add(tv)
        d.get_content_area().pack_start(sc, True, True, 0)
        d.show_all()
        d.run()
        d.destroy()

    def cambio_idioma(self, cb):
        cod = cb.get_active_id()
        if not cod or not i18n or cod == i18n.LANG:
            return
        i18n.guardar_idioma(cod)
        os.environ["GENOS_PAGINA"] = "sistema"
        os.execv(sys.executable, [sys.executable] + sys.argv)

    def cambio_ocultar(self, sw, _p):
        n = ocultar_ajustes() if sw.get_active() else mostrar_ajustes()
        self.estado.set_text(("Configuración reemplaza al Gestor de ajustes. Entradas escondidas: %d." if sw.get_active()
                              else "Gestor de ajustes de XFCE restaurado. Entradas devueltas: %d.") % n)
        GLib.timeout_add_seconds(6, lambda: (self.estado.set_text(""), False)[1])

    def llenar_atajos(self):
        for h in self.g_atajos.get_children():
            self.g_atajos.remove(h)
        act = atajos_actuales()
        for nombre, frag in ATAJOS:
            tecla, cmd = act.get(frag, ("", ""))
            b = Gtk.Button(label=etiqueta_tecla(tecla) if tecla else "Sin atajo")
            b.connect("clicked", lambda _b, fr=frag, tk=tecla, cm=cmd: self.capturar_atajo(fr, tk, cm))
            self.fila(self.g_atajos, nombre, None, b)
        self.g_atajos.show_all()

    def capturar_atajo(self, frag, vieja, cmd):
        if not cmd:
            self.estado.set_text("Ese atajo no existe todavía; corre otra vez el instalador dentro de XFCE.")
            return
        d = Gtk.Dialog(title="Nuevo atajo", transient_for=self, modal=True)
        d.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        l = Gtk.Label(label="Pulsa la combinación nueva (con Ctrl, Alt o Super).")
        l.set_margin_top(18); l.set_margin_bottom(18); l.set_margin_start(24); l.set_margin_end(24)
        d.get_content_area().add(l)
        elegido = {}

        def tecla(_w, ev):
            kv = Gdk.keyval_to_lower(ev.keyval)
            mods = ev.state & Gtk.accelerator_get_default_mod_mask()
            if kv in (Gdk.KEY_Escape,):
                d.response(Gtk.ResponseType.CANCEL)
                return True
            if not mods or Gdk.keyval_name(kv) in ("Control_L", "Control_R", "Alt_L", "Alt_R", "Shift_L", "Shift_R",
                                                    "Super_L", "Super_R", "Meta_L", "Meta_R", "ISO_Level3_Shift"):
                return True
            elegido["k"] = Gtk.accelerator_name(kv, mods).replace("<Control>", "<Primary>")
            d.response(Gtk.ResponseType.OK)
            return True

        d.connect("key-press-event", tecla)
        d.show_all()
        r = d.run()
        d.destroy()
        if r == Gtk.ResponseType.OK and elegido.get("k") and elegido["k"] != vieja:
            xf_poner(CANAL_ATAJOS, "/commands/custom/" + elegido["k"], "string", cmd)
            if vieja:
                subprocess.run(["xfconf-query", "-c", CANAL_ATAJOS, "-p", "/commands/custom/" + vieja, "-r"],
                               capture_output=True, timeout=10)
            self.llenar_atajos()

    def llenar_inicio(self):
        for h in self.g_inicio.get_children():
            self.g_inicio.remove(h)
        apps = apps_de_inicio()
        if not apps:
            self.fila(self.g_inicio, "No hay aplicaciones de inicio", None, Gtk.Label(label=""))
        for base, nombre, com, activo in apps:
            sw = Gtk.Switch()
            sw.set_active(activo)
            sw.connect("notify::active", lambda w, _p, b=base: poner_inicio(b, w.get_active()))
            self.fila(self.g_inicio, nombre, com or None, sw)
        self.g_inicio.show_all()

    def anadir_inicio(self, *_):
        d = Gtk.AppChooserDialog(transient_for=self, modal=True)
        if d.run() == Gtk.ResponseType.OK:
            info = d.get_app_info()
            ruta = info.get_filename() if info else None
            if ruta and os.path.isfile(ruta):
                os.makedirs(os.path.join(HOME, ".config", "autostart"), exist_ok=True)
                shutil.copy(ruta, os.path.join(HOME, ".config", "autostart", os.path.basename(ruta)))
                self.llenar_inicio()
        d.destroy()

    # ------------------------------------------------ fondos
    def cargar_tarjetas(self):
        actual = ""
        try:
            with open(ESTADO) as f:
                actual = f.read().strip()
        except Exception:
            pass
        for ruta in self.fondos:
            caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            caja.get_style_context().add_class("tarjeta")
            m = miniatura(ruta)
            img = Gtk.Image()
            if m:
                img.set_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_scale(m, 200, 112, True))
            caja.pack_start(img, False, False, 0)
            nombre = os.path.splitext(os.path.basename(ruta))[0]
            nombre = re.sub(r"^\d+[-_ ]*", "", nombre).replace("-", " ").replace("_", " ").strip() or nombre
            lbl = Gtk.Label(label=nombre, xalign=0, ellipsize=3, max_width_chars=22)
            lbl.get_style_context().add_class("tarjeta-nombre")
            caja.pack_start(lbl, False, False, 0)
            sub = Gtk.Label(label="", xalign=0, use_markup=True)
            sub.get_style_context().add_class("sub")
            caja.pack_start(sub, False, False, 0)
            self.flow.add(caja)
            hijo = caja.get_parent()
            hijo.ruta = ruta
            self.tarjetas[ruta] = sub
            self.pon_etiqueta(ruta)
            if ruta == actual:
                self.flow.select_child(hijo)
        self.flow.show_all()
        if self.sel is None and self.fondos:
            self.flow.select_child(self.flow.get_child_at_index(0))

    def pon_etiqueta(self, ruta):
        a = self.analisis.get(ruta)
        if not a:
            return
        modo, acento = a.split()
        punto = "<span foreground='#%s'>●</span> " % acento if acento != "neutro" else "○ "
        self.tarjetas[ruta].set_markup("%s%s" % (punto, modo))

    def analizar_todo(self):
        cambio = False
        for ruta in self.fondos:
            if ruta in self.analisis:
                continue
            r = correr([BIN, "--analizar", ruta])
            if r:
                self.analisis[ruta] = r
                cambio = True
                GLib.idle_add(self.pon_etiqueta, ruta)
        if cambio:
            try:
                os.makedirs(CACHE, exist_ok=True)
                with open(ANALISIS, "w") as f:
                    json.dump(self.analisis, f)
            except Exception:
                pass

    def cambio_seleccion(self, flow):
        h = flow.get_selected_children()
        if h:
            self.sel = h[0].ruta
            self.refrescar()

    def al_azar(self, *_):
        import random
        if self.fondos:
            r = random.choice(self.fondos)
            for h in self.flow.get_children():
                if h.ruta == r:
                    self.flow.select_child(h)
                    h.grab_focus()

    # ------------------------------------------------ vista previa
    def refrescar(self):
        if not self.sel:
            return
        self.pendiente += 1
        n = self.pendiente
        ruta, aj = self.sel, dict(self.aj)

        def trabajo():
            GLib.idle_add(self.mostrar, n, ruta, perfil(ruta, aj), aj)

        GLib.timeout_add(120, lambda: (threading.Thread(target=trabajo, daemon=True).start(), False)[1])

    def mostrar(self, n, ruta, p, aj):
        if n != self.pendiente or not p:
            return False
        self.vista.poner(ruta, p, aj)
        self.info.set_markup("<b>%s</b>\nmodo %s · acento %s · tema %s" % (
            GLib.markup_escape_text(os.path.basename(ruta)), p.get("modo", "?"), p.get("acento", "?"), p.get("tema", "?")))
        return False

    # ------------------------------------------------ perfiles
    def cargar_perfil(self, vals):
        self.aj.update(vals)
        self.tocado.update(vals.keys())
        self.sincronizar_controles()

    def listar_perfiles(self):
        for h in self.caja_perfiles.get_children():
            self.caja_perfiles.remove(h)
        g = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        g.get_style_context().add_class("frame")
        os.makedirs(PERFILES, exist_ok=True)
        nombres = sorted(f[:-5] for f in os.listdir(PERFILES) if f.endswith(".json"))
        if not nombres:
            l = Gtk.Label(label="Todavía no guardas ninguno.", xalign=0)
            l.get_style_context().add_class("sub")
            self.caja_perfiles.pack_start(l, False, False, 0)
        for nombre in nombres:
            caja = Gtk.Box(spacing=6)
            b1 = Gtk.Button(label="Cargar")
            b1.connect("clicked", lambda _b, nm=nombre: self.cargar_guardado(nm))
            b2 = Gtk.Button(label="Borrar")
            b2.connect("clicked", lambda _b, nm=nombre: self.borrar_perfil(nm))
            caja.pack_start(b1, False, False, 0)
            caja.pack_start(b2, False, False, 0)
            self.fila(g, nombre, None, caja)
        if nombres:
            self.caja_perfiles.pack_start(g, False, False, 0)
        self.caja_perfiles.show_all()

    def guardar_perfil(self, *_):
        nombre = re.sub(r"[^\w .-]", "", self.nombre_perfil.get_text()).strip()
        if not nombre:
            self.estado.set_text("Ponle un nombre al perfil.")
            return
        os.makedirs(PERFILES, exist_ok=True)
        with open(os.path.join(PERFILES, nombre + ".json"), "w") as f:
            json.dump(dict(self.aj, fondo=self.sel), f, indent=1)
        self.nombre_perfil.set_text("")
        self.estado.set_text("Perfil «%s» guardado." % nombre)
        self.listar_perfiles()

    def cargar_guardado(self, nombre):
        try:
            with open(os.path.join(PERFILES, nombre + ".json")) as f:
                d = json.load(f)
        except Exception:
            return
        fondo = d.pop("fondo", None)
        self.aj.update(d)
        if fondo:
            for h in self.flow.get_children():
                if h.ruta == fondo:
                    self.flow.select_child(h)
        self.sincronizar_controles()

    def borrar_perfil(self, nombre):
        try:
            os.remove(os.path.join(PERFILES, nombre + ".json"))
        except OSError:
            pass
        self.listar_perfiles()

    # ------------------------------------------------ acciones
    def todo_auto(self, *_):
        for k in ("modo", "acento", "opacidad", "tema"):
            self.aj[k] = None
        self.sincronizar_controles()

    def probar_notif(self, *_):
        aj = dict(self.aj)
        self.estado.set_text("Enviando pruebas…")

        def trabajo():
            self.aplicar_notif(aj)
            if shutil.which("notify-send"):
                import time
                subprocess.run(["notify-send", "GenOs", T("Así se ven las notificaciones con tu tema.")])
                time.sleep(0.6)
                subprocess.run(["notify-send", "-i", "mail-unread-symbolic", T("Mensaje nuevo"),
                                T("Esteban: la ventana de Configuración ya quedó.")])
                time.sleep(0.6)
                subprocess.run(["notify-send", "-u", "critical", T("Batería baja"), T("Conecta el cargador.")])
                msg = "Listo, mira la esquina de la pantalla."
            else:
                msg = "Falta notify-send (sudo apt install libnotify-bin)."
            GLib.idle_add(self.estado.set_text, msg)

        threading.Thread(target=trabajo, daemon=True).start()

    @staticmethod
    def aplicar_notif(aj):
        nx = "xfce4-notifyd"
        xf_poner(nx, "/theme", "string", "Default")
        xf_poner(nx, "/do-not-disturb", "bool", "true" if aj["notif_dnd"] else "false")
        if NOTIF_POS_TEXTO[0]:
            xf_poner(nx, "/notify-location", "string", NOMBRES_POS[pos_id(aj["notif_pos"])])
        else:
            xf_poner(nx, "/notify-location", "uint", int(pos_id(aj["notif_pos"])))
        xf_poner(nx, "/expire-timeout", "int", int(aj["notif_tiempo"]))
        xf_poner(nx, "/initial-opacity", "double", "%.2f" % float(aj["notif_opac"]))
        xf_poner(nx, "/do-fadeout", "bool", "true" if aj["notif_fade"] else "false")

    @staticmethod
    def aplicar_teclado(aj):
        lay, var = aj["tec_layout"], aj["tec_variante"]
        if shutil.which("setxkbmap"):
            subprocess.run(["setxkbmap", "-layout", lay] + (["-variant", var] if var else []), timeout=10)
        xf_poner("keyboards", "/Default/XkbDisable", "bool", "false")
        xf_poner("keyboards", "/Default/XkbLayout", "string", lay)
        xf_poner("keyboards", "/Default/XkbVariant", "string", var)

    @staticmethod
    def aplicar_widgets(aj):
        d = {
            "maestro": bool(aj["w_maestro"]),
            "activos": {n: bool(aj["w_" + n]) for n, _t, _d in WIDGETS},
            "pos": {n: aj["w_pos_" + n] for n, _t, _d in WIDGETS},
            "escala": float(aj["w_escala"]),
            "opacidad": aj["w_opac"],
            "monitor": str(aj["w_monitor"]),
        }
        with open(CONF_WIDGETS, "w") as f:
            json.dump(d, f, indent=1)
        gw = os.path.join(os.path.dirname(BIN), "genos-widgets")
        if d["maestro"] and os.path.isfile(gw):
            subprocess.Popen([gw], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def exportar(self, *_):
        """Minimiza la ventana para que salga el escritorio en la captura y exporta."""
        exp = os.path.join(os.path.dirname(BIN), "genos-exportar")
        self.estado.set_text("Exportando…")
        self.iconify()

        def trabajo():
            import time
            time.sleep(2)
            salida = correr([exp], timeout=60)
            GLib.idle_add(self.fin_exportar, salida)

        threading.Thread(target=trabajo, daemon=True).start()

    def fin_exportar(self, salida):
        self.deiconify()
        self.present()
        linea = [l for l in salida.splitlines() if l.startswith("Exportado")]
        self.estado.set_text(linea[0] if linea else "No pude exportar. Corre genos-exportar en la terminal.")
        return False

    def importar_tema(self, *_):
        d = Gtk.FileChooserDialog(title="Importar un tema de GenOS", transient_for=self, action=Gtk.FileChooserAction.OPEN)
        d.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        d.add_button("Importar", Gtk.ResponseType.OK)
        f = Gtk.FileFilter()
        f.set_name(T("Temas exportados (.zip)"))
        f.add_pattern("*.zip")
        d.add_filter(f)
        ruta = d.get_filename() if d.run() == Gtk.ResponseType.OK else None
        d.destroy()
        if not ruta:
            return
        exp = os.path.join(os.path.dirname(BIN), "genos-exportar")
        self.estado.set_text("Importando…")

        def trabajo():
            salida = correr([exp, "--importar", ruta], timeout=120)
            GLib.idle_add(self.estado.set_text, "Tema importado." if "importado" in salida.lower() else
                          "No pude importarlo. Prueba: genos-exportar --importar archivo.zip")

        threading.Thread(target=trabajo, daemon=True).start()

    def reiniciar_dock(self, *_):
        subprocess.run(["pkill", "-x", "plank"])
        GLib.timeout_add(700, lambda: (subprocess.Popen(["plank"], start_new_session=True), False)[1])

    def aplicar(self, *_):
        if not self.sel:
            return
        self.btn_ok.set_sensitive(False)
        self.estado.set_text("Aplicando…")
        ruta, aj = self.sel, dict(self.aj)

        def trabajo():
            ok, msg = True, ""
            try:
                r = subprocess.run([BIN, ruta], env=entorno(aj), timeout=240, capture_output=True, text=True)
                if r.returncode != 0:
                    salida = (r.stdout + r.stderr).strip().splitlines()
                    raise RuntimeError("genos-fondo: " + (salida[-1] if salida else "terminó con error"))
                aviso = ("no encuentro la sesión de XFCE; abre Configuración desde el escritorio"
                         if "Corre este comando otra vez dentro de XFCE" in r.stdout else "")
                with open(AJUSTES, "w") as f:
                    json.dump(aj, f, indent=1)
                # ajustes sueltos: van después del tema para que no los pise
                d = PLANK
                subprocess.run(["dconf", "write", d + "/icon-size", str(int(aj["dock_tam"]))], timeout=10)
                subprocess.run(["dconf", "write", d + "/zoom-enabled", "true" if aj["dock_zoom"] else "false"], timeout=10)
                subprocess.run(["dconf", "write", d + "/zoom-percent", "uint32 %d" % int(aj["dock_zoomp"])], timeout=10)
                subprocess.run(["dconf", "write", d + "/position", "'%s'" % aj["dock_pos"]], timeout=10)
                subprocess.run(["dconf", "write", d + "/hide-mode", "'%s'" % aj["dock_ocultar"]], timeout=10)
                for pn in paneles():
                    xf_poner("xfce4-panel", "/panels/%s/size" % pn, "uint", int(aj["alto"]))
                xf_poner("xfwm4", "/general/button_layout", "string", "CHM|" if aj["botones"] == "izq" else "|HMC")
                xf_poner("xfwm4", "/general/title_alignment", "string", "center" if aj["centrado"] else "left")
                xf_poner("xfwm4", "/general/use_compositing", "bool", "true" if aj["compositor"] else "false")
                xf_poner("xfwm4", "/general/shadow_opacity", "int", int(aj["sombra"]))
                xf_poner("xsettings", "/Gtk/FontName", "string", aj["fuente"])
                xf_poner("xsettings", "/Gtk/CursorThemeSize", "int", int(aj["cursor"]))
                tocado = set(self.tocado)
                for k, (canal, prop, tipo, _d) in XF_MAP.items():
                    if k in tocado:
                        xf_poner_v(canal, prop, tipo, aj[k])
                pp = panel_principal()
                if pp and tocado & {"panel_oculta", "panel_bloq", "panel_iconos"}:
                    base = "/panels/%s/" % pp
                    xf_poner("xfce4-panel", base + "autohide-behavior", "uint", int(aj["panel_oculta"]))
                    xf_poner("xfce4-panel", base + "position-locked", "bool", "true" if aj["panel_bloq"] else "false")
                    xf_poner("xfce4-panel", base + "icon-size", "uint", int(aj["panel_iconos"]))
                if tocado & {"panel_largo", "panel_crecer"} and pp:
                    base = "/panels/%s/" % pp
                    xf_poner("xfce4-panel", base + "length", "uint", int(aj["panel_largo"]))
                    xf_poner("xfce4-panel", base + "length-adjust", "bool", "true" if aj["panel_crecer"] else "false")
                if "esc_nombres" in tocado:
                    n = max(1, int(aj["escritorios"]))
                    nombres = [(aj["esc_nombres"][i] if i < len(aj["esc_nombres"]) and aj["esc_nombres"][i]
                                else "Escritorio %d" % (i + 1)) for i in range(min(n, 8))]
                    cmd = ["xfconf-query", "-c", "xfwm4", "-p", "/general/workspace_names", "-n", "-a"]
                    for nm in nombres:
                        cmd += ["-t", "string", "-s", nm]
                    subprocess.run(cmd, capture_output=True, timeout=10)
                if tocado & {"rat_disp", "rat_zurdo", "rat_invertir", "rat_umbral", "rat_aceler"} and aj["rat_disp"]:
                    b = "/%s/" % aj["rat_disp"]
                    xf_poner("pointers", b + "RightHanded", "bool", "false" if aj["rat_zurdo"] else "true")
                    xf_poner("pointers", b + "ReverseScrolling", "bool", "true" if aj["rat_invertir"] else "false")
                    xf_poner("pointers", b + "Threshold", "int", int(aj["rat_umbral"]))
                    xf_poner("pointers", b + "Acceleration", "double", "%.2f" % float(aj["rat_aceler"]))
                if tocado & {"tec_layout", "tec_variante"}:
                    Ventana.aplicar_teclado(aj)
                if tocado & {"tec_retardo", "tec_velocidad"} and shutil.which("xset"):
                    subprocess.run(["xset", "r", "rate", str(int(aj["tec_retardo"])), str(int(aj["tec_velocidad"]))],
                                   timeout=10)
                if any(k.startswith("esc_") for k in tocado) and shutil.which("xfdesktop"):
                    subprocess.run(["xfdesktop", "--reload"], timeout=15)
                Ventana.aplicar_notif(aj)
                Ventana.aplicar_widgets(aj)
                self.tocado.clear()
                if aviso:
                    raise RuntimeError(T(aviso))
            except Exception as e:
                ok = False
                msg = str(e) if isinstance(e, RuntimeError) else "%s: %s" % (type(e).__name__, e)
                try:
                    import traceback
                    os.makedirs(CACHE, exist_ok=True)
                    with open(os.path.join(CACHE, "error.log"), "a") as lg:
                        lg.write(time.strftime("%F %T") + "\n" + traceback.format_exc() + "\n")
                except OSError:
                    pass
            GLib.idle_add(self.fin_aplicar, ok, msg)

        threading.Thread(target=trabajo, daemon=True).start()

    def fin_aplicar(self, ok, msg=""):
        self.btn_ok.set_sensitive(True)
        self.estado.set_text("Listo, aplicado." if ok else "Algo falló: %s\nDetalle en ~/.cache/genos-fondo/error.log" % msg[:160])
        GLib.timeout_add_seconds(5 if ok else 25, lambda: (self.estado.set_text(""), False)[1])
        return False


def reaplicar(argv):
    """Vuelve a aplicar el fondo actual sin abrir la ventana.
    --modo claro|oscuro  fija el modo (y apaga el cambio automático)
    --auto               solo si el cambio día/noche está activo y la hora pide otro modo"""
    aj = dict(DEFECTO)
    try:
        with open(AJUSTES) as f:
            aj.update(json.load(f))
    except Exception:
        pass
    if "--modo" in argv:
        aj["modo"] = argv[argv.index("--modo") + 1]
        aj["dn_activo"] = False
    elif "--auto" in argv:
        if not aj.get("dn_activo"):
            return 0
        actual = ""
        try:
            with open(os.path.join(HOME, ".config", "genos-fondo.perfil")) as f:
                for ln in f:
                    if ln.startswith("modo="):
                        actual = ln.strip().split("=", 1)[1]
        except OSError:
            pass
        if actual == modo_por_hora(aj):
            return 0
    try:
        with open(ESTADO) as f:
            ruta = f.read().strip()
    except OSError:
        ruta = ""
    if not ruta or not os.path.isfile(ruta):
        print("No sé cuál es el fondo actual.")
        return 1
    rc = subprocess.run([BIN, ruta], env=entorno(aj), timeout=180).returncode
    if rc == 0:
        with open(AJUSTES, "w") as f:
            json.dump(aj, f, indent=1)
    return rc


def main():
    if "--ocultar-ajustes" in sys.argv:
        print(T("Configuración reemplaza al Gestor de ajustes. Entradas escondidas: %d.") % ocultar_ajustes())
        return 0
    if "--mostrar-ajustes" in sys.argv:
        print(T("Gestor de ajustes de XFCE restaurado. Entradas devueltas: %d.") % mostrar_ajustes())
        return 0
    if not os.path.isfile(BIN):
        print(T("No encuentro %s") % BIN)
        return 1
    if "--reaplicar" in sys.argv:
        return reaplicar(sys.argv)
    w = Ventana()
    w.connect("destroy", Gtk.main_quit)
    w.show_all()
    Gtk.main()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PERS_FIN
chmod +x "$BIN/genos-configuracion"
# El nombre anterior sigue funcionando (atajos y lanzadores viejos)
ln -sf "$BIN/genos-configuracion" "$BIN/genos-personalizacion"
rm -f "$HOME/.local/share/applications/genos-personalizacion.desktop"

# Exportar / importar el tema (zip en Descargas de Windows)
cat > "$BIN/genos-exportar" <<'EXPORT_FIN'
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
EXPORT_FIN
chmod +x "$BIN/genos-exportar"

# Widgets de escritorio (reloj y sistema activos por defecto; el resto se activa en Configuración)
cat > "$BIN/genos-widgets" <<'WIDGETS_FIN'
#!/usr/bin/env python3
"""GenOs Widgets: tarjetas flotantes en el escritorio con los colores del perfil del fondo.

Por defecto están activos Reloj y Sistema. Opcionales: Red, Calendario, Notas y Pomodoro.
Se configuran desde Configuración (guarda ~/.config/genos-widgets.json); este proceso
vigila ese archivo y el perfil de color, así que no hace falta reiniciarlo.

  genos-widgets              arranca (una sola instancia)
  genos-widgets --alternar   muestra u oculta todos los widgets
"""
import calendar
import datetime
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

sys.path[:0] = [os.path.join(os.path.expanduser("~"), ".local", "lib", "genos"),
                os.path.dirname(os.path.abspath(__file__))]
try:
    import genos_i18n as i18n
    i18n.parchear(Gtk)
    T = i18n.T
except ImportError:  # sin el módulo todo queda en español
    i18n = None

    def T(s):
        return s

HOME = os.path.expanduser("~")
CONF = os.path.join(HOME, ".config", "genos-widgets.json")
PERFIL = os.path.join(HOME, ".config", "genos-fondo.perfil")
NOTAS = os.path.join(HOME, ".config", "genos-notas.txt")
AJUSTES = os.path.join(HOME, ".config", "genos-personalizacion.json")
LOCK = os.path.join(HOME, ".cache", "genos-widgets.lock")
HIST = os.path.join(HOME, ".local", "share", "genos", "notificaciones.jsonl")

ORDEN = ["reloj", "sistema", "red", "calendario", "pomodoro", "notas"]
DEFECTO = {
    "maestro": True,
    "activos": {"reloj": True, "sistema": True, "red": False, "calendario": False, "notas": False, "pomodoro": False},
    "pos": {"reloj": "arriba-der", "sistema": "arriba-der", "red": "arriba-der",
            "calendario": "abajo-der", "pomodoro": "abajo-izq", "notas": "abajo-izq"},
    "escala": 1.0,
    "opacidad": None,
    "margen_sup": 20,
    "monitor": "auto",
}
DIAS = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]
MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
         "septiembre", "octubre", "noviembre", "diciembre"]
if i18n:
    DIAS, MESES = i18n.nombres_fecha()


def leer_conf():
    c = json.loads(json.dumps(DEFECTO))
    try:
        with open(CONF) as f:
            d = json.load(f)
        for k, v in d.items():
            if isinstance(v, dict) and isinstance(c.get(k), dict):
                c[k].update(v)
            else:
                c[k] = v
    except Exception:
        pass
    return c


def mtime(ruta):
    try:
        return os.path.getmtime(ruta)
    except OSError:
        return 0


def hex_rgb(h, defecto=(0.95, 0.95, 0.97)):
    m = re.fullmatch(r"#?([0-9a-fA-F]{6})", h or "")
    return tuple(int(m.group(1)[i:i + 2], 16) / 255 for i in (0, 2, 4)) if m else defecto


class Tema:
    """Colores del perfil que calcula genos-fondo (se relee si cambia el archivo)."""

    def __init__(self):
        self.firma = None
        self.cargar()

    def cargar(self):
        d = {}
        try:
            with open(PERFIL) as f:
                for linea in f:
                    if "=" in linea:
                        k, v = linea.strip().split("=", 1)
                        d[k] = v
        except OSError:
            pass
        try:
            self.pastilla = tuple(int(x) / 255 for x in d.get("pastilla", "14,14,22").split(","))
            self.alfa = float(d.get("opacidad", "0.72"))
            self.radio = float(d.get("radio", "12"))
        except ValueError:
            self.pastilla, self.alfa, self.radio = (0.06, 0.06, 0.09), 0.72, 12.0
        self.texto = hex_rgb(d.get("texto", "#f2f2f7"))
        n = [float(x) for x in re.findall(r"[\d.]+", d.get("sel", ""))]
        self.acento = tuple(x / 255 for x in n[:3]) if len(n) >= 3 else (0.48, 0.36, 1.0)
        self.firma = mtime(PERFIL)


def rect_redondo(cr, x, y, w, h, r):
    r = max(0, min(r, w / 2, h / 2))
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -1.5708, 0)
    cr.arc(x + w - r, y + h - r, r, 0, 1.5708)
    cr.arc(x + r, y + h - r, r, 1.5708, 3.1416)
    cr.arc(x + r, y + r, r, 3.1416, 4.7124)
    cr.close_path()


def texto(cr, x, y, s, tam, color, alfa=1.0, negrita=False, ancla="i"):
    import cairo
    cr.select_font_face("Inter", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD if negrita else cairo.FONT_WEIGHT_NORMAL)
    cr.set_font_size(tam)
    s = T(s)
    ext = cr.text_extents(s)
    if ancla == "d":
        x -= ext.x_advance
    elif ancla == "c":
        x -= ext.x_advance / 2
    cr.set_source_rgba(color[0], color[1], color[2], alfa)
    cr.move_to(x, y)
    cr.show_text(s)


def barra(cr, x, y, w, h, frac, tema):
    rect_redondo(cr, x, y, w, h, h / 2)
    cr.set_source_rgba(*tema.texto, 0.14)
    cr.fill()
    frac = max(0.0, min(1.0, frac))
    if frac > 0:
        rect_redondo(cr, x, y, max(h, w * frac), h, h / 2)
        cr.set_source_rgba(*tema.acento, 1)
        cr.fill()


# ---------------------------------------------------------------- tarjeta base
class Tarjeta(Gtk.Window):
    nombre = ""
    titulo = ""
    ancho = 300
    alto = 130
    periodo = 2  # segundos entre actualizaciones

    def __init__(self, app):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self.app = app
        self.ultimo = 0
        self.set_decorated(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_type_hint(Gdk.WindowTypeHint.DESKTOP)
        self.set_keep_below(True)
        self.set_accept_focus(False)
        self.stick()
        self.set_app_paintable(True)
        vis = self.get_screen().get_rgba_visual()
        if vis:
            self.set_visual(vis)
        self.connect("draw", self.limpiar)
        self.area = Gtk.DrawingArea()
        self.area.connect("draw", self.dibujar)
        self.add(self.area)
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
        self.connect("button-press-event", self.click)
        self.tamano()

    def tamano(self):
        e = self.app.conf["escala"]
        w, h = int(self.ancho * e), int(self.alto * e)
        self.area.set_size_request(w, h)
        self.set_default_size(w, h)
        self.resize(w, h)

    def limpiar(self, _w, cr):
        import cairo
        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.set_source_rgba(0, 0, 0, 0)
        cr.paint()
        cr.set_operator(cairo.OPERATOR_OVER)
        return False

    def dibujar(self, _a, cr):
        t = self.app.tema
        e = self.app.conf["escala"]
        cr.scale(e, e)
        alfa = self.app.conf.get("opacidad") or t.alfa
        if not self.get_screen().is_composited():
            alfa = 1.0  # sin compositor no hay transparencia real
        rect_redondo(cr, 0.5, 0.5, self.ancho - 1, self.alto - 1, t.radio * 1.4)
        cr.set_source_rgba(*t.pastilla, alfa)
        cr.fill_preserve()
        cr.set_source_rgba(*t.texto, 0.10)
        cr.set_line_width(1)
        cr.stroke()
        texto(cr, 20, 28, T(self.titulo).upper(), 9, t.texto, 0.55, True)
        self.contenido(cr, t)
        return False

    def contenido(self, cr, t):
        pass

    def actualizar(self):
        """Devuelve True si hay que redibujar."""
        return True

    def click(self, _w, ev):
        return False

    def tick(self, ahora):
        if ahora - self.ultimo >= self.periodo:
            self.ultimo = ahora
            if self.actualizar():
                self.area.queue_draw()


# ---------------------------------------------------------------- widgets
class Reloj(Tarjeta):
    nombre, titulo, alto, periodo = "reloj", "Hora", 140, 5

    def contenido(self, cr, t):
        ahora = datetime.datetime.now()
        texto(cr, 20, 90, ahora.strftime("%H:%M"), 56, t.texto, 1.0, True)
        fecha = i18n.fecha_larga(ahora) if i18n else "%s, %d de %s" % (DIAS[ahora.weekday()], ahora.day, MESES[ahora.month - 1])
        texto(cr, 22, 120, fecha[:1].upper() + fecha[1:], 14, t.texto, 0.8)
        cr.arc(272, 36, 5, 0, 6.2832)
        cr.set_source_rgba(*t.acento, 1)
        cr.fill()


class Sistema(Tarjeta):
    nombre, titulo, alto, periodo = "sistema", "Sistema", 158, 2

    def __init__(self, app):
        self.cpu = 0.0
        self.prev = self.leer_cpu()
        super().__init__(app)

    @staticmethod
    def leer_cpu():
        try:
            with open("/proc/stat") as f:
                v = [int(x) for x in f.readline().split()[1:]]
            return sum(v), v[3] + (v[4] if len(v) > 4 else 0)
        except Exception:
            return 0, 0

    def actualizar(self):
        tot, idle = self.leer_cpu()
        dt, di = tot - self.prev[0], idle - self.prev[1]
        self.prev = (tot, idle)
        self.cpu = 1 - di / dt if dt > 0 else 0.0
        return True

    def contenido(self, cr, t):
        mem = {}
        try:
            with open("/proc/meminfo") as f:
                for linea in f:
                    k, v = linea.split(":")
                    mem[k] = int(v.split()[0])
        except Exception:
            pass
        total = mem.get("MemTotal", 1)
        usada = total - mem.get("MemAvailable", 0)
        try:
            du = shutil.disk_usage("/")
            disco = du.used / du.total
        except Exception:
            disco = 0
        filas = (("CPU", self.cpu, "%d%%" % round(self.cpu * 100)),
                 ("RAM", usada / total, "%.1f / %.1f GB" % (usada / 1048576, total / 1048576)),
                 ("Disco", disco, "%d%%" % round(disco * 100)))
        y = 60
        for nombre, frac, etiqueta in filas:
            texto(cr, 20, y, nombre, 12, t.texto, 0.9, True)
            texto(cr, 280, y, etiqueta, 12, t.texto, 0.75, False, "d")
            barra(cr, 20, y + 8, 260, 7, frac, t)
            y += 34


class Red(Tarjeta):
    nombre, titulo, alto, periodo = "red", "Red", 130, 2

    def __init__(self, app):
        self.hist = [0.0] * 40
        self.bajada = self.subida = 0.0
        self.prev = (self.leer(), time.time())
        super().__init__(app)

    @staticmethod
    def leer():
        rx = tx = 0
        try:
            with open("/proc/net/dev") as f:
                for linea in f.readlines()[2:]:
                    nom, datos = linea.split(":", 1)
                    if nom.strip() == "lo":
                        continue
                    v = datos.split()
                    rx += int(v[0])
                    tx += int(v[8])
        except Exception:
            pass
        return rx, tx

    def actualizar(self):
        rx, tx = self.leer()
        (prx, ptx), pt = self.prev
        ahora = time.time()
        dt = max(ahora - pt, 0.1)
        self.bajada, self.subida = max(0, rx - prx) / dt, max(0, tx - ptx) / dt
        self.prev = ((rx, tx), ahora)
        self.hist = self.hist[1:] + [self.bajada]
        return True

    @staticmethod
    def fmt(b):
        for u in ("B/s", "KB/s", "MB/s"):
            if b < 1024 or u == "MB/s":
                return "%.0f %s" % (b, u) if u == "B/s" else "%.1f %s" % (b, u)
            b /= 1024

    def contenido(self, cr, t):
        texto(cr, 20, 60, "↓ " + self.fmt(self.bajada), 15, t.texto, 1.0, True)
        texto(cr, 280, 60, "↑ " + self.fmt(self.subida), 13, t.texto, 0.75, False, "d")
        mx = max(self.hist) or 1
        base, alto = 112, 38
        cr.move_to(20, base)
        for i, v in enumerate(self.hist):
            cr.line_to(20 + i * (260 / (len(self.hist) - 1)), base - alto * v / mx)
        cr.line_to(280, base)
        cr.close_path()
        cr.set_source_rgba(*t.acento, 0.35)
        cr.fill()


class Calendario(Tarjeta):
    nombre, titulo, alto, periodo = "calendario", "Calendario", 275, 600

    def contenido(self, cr, t):
        hoy = datetime.date.today()
        texto(cr, 20, 58, "%s %d" % (MESES[hoy.month - 1].capitalize(), hoy.year), 16, t.texto, 1.0, True)
        ancho = 260 / 7
        for i, d in enumerate(i18n.inicial_semana() if i18n else "LMXJVSD"):
            texto(cr, 20 + ancho * i + ancho / 2, 88, d, 10, t.texto, 0.5, True, "c")
        y = 114
        for semana in calendar.Calendar(0).monthdayscalendar(hoy.year, hoy.month):
            for i, dia in enumerate(semana):
                if not dia:
                    continue
                cx = 20 + ancho * i + ancho / 2
                if dia == hoy.day:
                    cr.arc(cx, y - 4, 12, 0, 6.2832)
                    cr.set_source_rgba(*t.acento, 1)
                    cr.fill()
                    texto(cr, cx, y, str(dia), 12, (1, 1, 1), 1.0, True, "c")
                else:
                    texto(cr, cx, y, str(dia), 12, t.texto, 0.85, False, "c")
            y += 26


class Notas(Tarjeta):
    nombre, titulo, alto, periodo = "notas", "Notas", 200, 4

    def __init__(self, app):
        self.lineas = []
        if not os.path.exists(NOTAS):
            try:
                with open(NOTAS, "w") as f:
                    f.write(T("Haz clic aquí para escribir tus notas.\n"))
            except OSError:
                pass
        super().__init__(app)
        self.actualizar()

    def actualizar(self):
        try:
            with open(NOTAS) as f:
                bruto = f.read().splitlines()
        except OSError:
            bruto = []
        out = []
        import textwrap
        for l in bruto:
            out.extend(textwrap.wrap(l, 34) or [""])
        nuevo = out[:7]
        cambio = nuevo != self.lineas
        self.lineas = nuevo
        return cambio

    def contenido(self, cr, t):
        y = 56
        for l in self.lineas:
            texto(cr, 20, y, l, 12, t.texto, 0.9)
            y += 19
        texto(cr, 280, 190, "clic para editar", 9, t.texto, 0.4, False, "d")

    def click(self, _w, ev):
        for ed in ("mousepad", "xdg-open"):
            if shutil.which(ed):
                subprocess.Popen([ed, NOTAS])
                break
        return True


class Pomodoro(Tarjeta):
    nombre, titulo, alto, periodo = "pomodoro", "Pomodoro", 130, 1
    FOCO, PAUSA = 25 * 60, 5 * 60

    def __init__(self, app):
        self.fase = "foco"
        self.resta = self.FOCO
        self.corre = False
        self.t0 = 0.0
        super().__init__(app)

    def actualizar(self):
        if self.corre:
            ahora = time.time()
            self.resta -= ahora - self.t0
            self.t0 = ahora
            if self.resta <= 0:
                nuevo = "pausa" if self.fase == "foco" else "foco"
                msg = ("Hora de descansar 5 minutos." if nuevo == "pausa" else "Vuelve al foco, 25 minutos.")
                if shutil.which("notify-send"):
                    subprocess.Popen(["notify-send", "-i", "alarm-symbolic", "Pomodoro", T(msg)])
                self.fase = nuevo
                self.resta = self.PAUSA if nuevo == "pausa" else self.FOCO
        return True

    def contenido(self, cr, t):
        m, s = divmod(max(0, int(self.resta)), 60)
        texto(cr, 20, 84, "%02d:%02d" % (m, s), 46, t.texto, 1.0, True)
        estado = T("Foco" if self.fase == "foco" else "Descanso") + T(" · en marcha" if self.corre else " · en pausa")
        texto(cr, 22, 112, estado, 12, t.texto, 0.75)
        total = self.FOCO if self.fase == "foco" else self.PAUSA
        barra(cr, 190, 100, 90, 6, 1 - self.resta / total, t)

    def click(self, _w, ev):
        if ev.button == 1:
            self.corre = not self.corre
            self.t0 = time.time()
        elif ev.button == 3:
            self.corre = False
            self.fase, self.resta = "foco", self.FOCO
        self.area.queue_draw()
        return True


CLASES = {c.nombre: c for c in (Reloj, Sistema, Red, Calendario, Notas, Pomodoro)}


# ------------------------------------------------ historial de notificaciones
def guardar_notificacion(app, icono, titulo, cuerpo):
    os.makedirs(os.path.dirname(HIST), exist_ok=True)
    with open(HIST, "a") as f:
        f.write(json.dumps({"t": time.time(), "app": app, "icono": icono,
                            "titulo": titulo, "cuerpo": cuerpo}, ensure_ascii=False) + "\n")
    try:
        with open(HIST) as f:
            lineas = f.readlines()
        if len(lineas) > 300:
            with open(HIST, "w") as f:
                f.writelines(lineas[-200:])
    except OSError:
        pass


def vigilar_notificaciones():
    """Escucha las llamadas Notify del bus de sesión y las apunta para el centro de control."""
    if not shutil.which("dbus-monitor"):
        return
    regla = "type='method_call',interface='org.freedesktop.Notifications',member='Notify'"
    while True:
        try:
            p = subprocess.Popen(["dbus-monitor", "--session", regla], stdout=subprocess.PIPE,
                                 stderr=subprocess.DEVNULL, text=True, errors="replace")
        except OSError:
            return
        cadenas, parcial, hecho = [], None, True
        for linea in p.stdout:
            linea = linea.rstrip("\n")
            if parcial is not None:
                # Cadena de varias líneas: las siguientes líneas no llevan sangría
                parcial += "\n" + linea
                if linea.endswith('"'):
                    cadenas.append(parcial[:-1])
                    parcial = None
            elif linea and not linea[0].isspace():
                cadenas, hecho = [], not linea.startswith("method call")
                continue
            elif hecho or len(cadenas) >= 4:
                continue
            else:
                m = re.match(r'^\s+string "(.*)$', linea)
                if m:
                    if m.group(1).endswith('"'):
                        cadenas.append(m.group(1)[:-1])
                    else:
                        parcial = m.group(1)
            if len(cadenas) == 4:
                hecho = True
                try:
                    guardar_notificacion(*cadenas)
                except OSError:
                    pass
        time.sleep(10)


# ---------------------------------------------------------------- aplicación
class App:
    def __init__(self):
        self.conf = leer_conf()
        self.tema = Tema()
        self.vistas = {}
        self.firma_conf = mtime(CONF)
        self.sincronizar()
        GLib.timeout_add(1000, self.tick)
        self.dn = None
        GLib.timeout_add_seconds(15, lambda: (self.dianoche(), False)[1])
        GLib.timeout_add_seconds(60, self.dianoche)

    def dianoche(self):
        """Cambio automático Claro/Oscuro: si está activo en Configuración, lo aplica a su hora."""
        try:
            with open(AJUSTES) as f:
                activo = bool(json.load(f).get("dn_activo"))
        except Exception:
            return True
        exe = os.path.join(HOME, ".local", "bin", "genos-configuracion")
        if activo and os.path.exists(exe) and (self.dn is None or self.dn.poll() is not None):
            self.dn = subprocess.Popen([exe, "--reaplicar", "--auto"], stdout=subprocess.DEVNULL,
                                       stderr=subprocess.DEVNULL)
        return True

    def tick(self):
        if mtime(CONF) != self.firma_conf:
            self.firma_conf = mtime(CONF)
            self.conf = leer_conf()
            self.sincronizar()
        if mtime(PERFIL) != self.tema.firma:
            self.tema.cargar()
            for w in self.vistas.values():
                w.area.queue_draw()
        ahora = time.time()
        for w in self.vistas.values():
            w.tick(ahora)
        return True

    def sincronizar(self):
        c = self.conf
        for n in ORDEN:
            quiere = c["maestro"] and c["activos"].get(n, False)
            if quiere and n not in self.vistas:
                self.vistas[n] = CLASES[n](self)
            elif not quiere and n in self.vistas:
                self.vistas.pop(n).destroy()
        self.colocar()

    def elegir_monitor(self):
        """La pantalla elegida; en automático, la principal, o la que está en el origen (0,0)."""
        disp = Gdk.Display.get_default()
        n = disp.get_n_monitors()
        sel = str(self.conf.get("monitor", "auto"))
        if sel != "auto":
            try:
                idx = int(sel)
                if 0 <= idx < n:
                    return disp.get_monitor(idx)
            except ValueError:
                pass
        mon = disp.get_primary_monitor()
        if mon:
            return mon
        for i in range(n):
            g = disp.get_monitor(i).get_geometry()
            if g.x == 0 and g.y == 0:
                return disp.get_monitor(i)
        return disp.get_monitor(0)

    def colocar(self):
        area = self.elegir_monitor().get_workarea()
        m, hueco, e = 20, 14, self.conf["escala"]
        cursores = {}   # esquina -> alto ocupado en la columna actual
        columnas = {}   # esquina -> columnas ya llenas
        for n in ORDEN:
            w = self.vistas.get(n)
            if not w:
                continue
            w.tamano()
            ancho, alto = int(w.ancho * e), int(w.alto * e)
            esq = self.conf["pos"].get(n, "arriba-der")
            vert, horiz = esq.split("-")
            usado = cursores.get(esq, 0)
            # Si la columna no cabe en la pantalla, se abre otra hacia el centro
            if usado and usado + alto > area.height - 2 * m:
                columnas[esq] = columnas.get(esq, 0) + 1
                usado = cursores[esq] = 0
            desp = columnas.get(esq, 0) * (ancho + hueco)
            x = area.x + (m + desp if horiz == "izq" else area.width - ancho - m - desp)
            y = area.y + m + usado if vert == "arriba" else area.y + area.height - alto - m - usado
            # Nunca fuera del área visible
            x = max(area.x, min(x, area.x + area.width - ancho))
            y = max(area.y, min(y, area.y + area.height - alto))
            cursores[esq] = usado + alto + hueco
            w.move(x, y)
            w.show_all()
            w.move(x, y)
            w.set_keep_below(True)


def alternar():
    c = leer_conf()
    d = {}
    try:
        with open(CONF) as f:
            d = json.load(f)
    except Exception:
        pass
    d["maestro"] = not c["maestro"]
    os.makedirs(os.path.dirname(CONF), exist_ok=True)
    with open(CONF, "w") as f:
        json.dump(d, f, indent=1)
    print("Widgets", "visibles" if d["maestro"] else "ocultos")


def main():
    if "--alternar" in sys.argv:
        alternar()
        return 0
    os.makedirs(os.path.dirname(LOCK), exist_ok=True)
    cerrojo = open(LOCK, "w")
    try:
        fcntl.flock(cerrojo, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print(T("genos-widgets ya está corriendo."))
        return 0
    threading.Thread(target=vigilar_notificaciones, daemon=True).start()
    App()
    Gtk.main()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
WIDGETS_FIN
chmod +x "$BIN/genos-widgets"

# Centro de control (apagar, cerrar sesión, historial de notificaciones, ajustes rápidos)
cat > "$BIN/genos-centro" <<'CENTRO_FIN'
#!/usr/bin/python3
# genos-centro: centro de control de GenOs (energía, notificaciones y ajustes rápidos).
#   genos-centro                abre o cierra el panel
#   genos-centro --boton        añade el botón a la barra superior
#   genos-centro --quitar-boton lo quita
import datetime
import getpass
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
PERFIL = os.path.join(HOME, ".config", "genos-fondo.perfil")
WCONF = os.path.join(HOME, ".config", "genos-widgets.json")
HIST = os.path.join(HOME, ".local", "share", "genos", "notificaciones.jsonl")
PID = os.path.join(HOME, ".cache", "genos-centro.pid")
MARCA = os.path.join(HOME, ".config", "genos-centro.plugin")
PANEL_XML = os.path.join(HOME, ".config", "xfce4", "xfconf", "xfce-perchannel-xml", "xfce4-panel.xml")
BIN = os.path.join(HOME, ".local", "bin")

sys.path[:0] = [os.path.join(os.path.expanduser("~"), ".local", "lib", "genos"),
                os.path.dirname(os.path.abspath(__file__))]
try:
    import genos_i18n as i18n
    T = i18n.T
except ImportError:  # sin el módulo todo queda en español
    i18n = None

    def T(s):
        return s

DIAS = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]
MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
         "septiembre", "octubre", "noviembre", "diciembre"]


def correr(cmd, **kw):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10, **kw)
    except Exception:
        return None


# ------------------------------------------------------------ botón en la barra
def xfp(*args):
    r = correr(["xfconf-query", "-c", "xfce4-panel", *args])
    return r.stdout if r and r.returncode == 0 else ""


def numeros(texto):
    """Enteros de la salida de xfconf-query (ignora 'Value is an array with N items')."""
    return [int(x.strip()) for x in texto.splitlines() if x.strip().isdigit()]


def ids_de(panel):
    return numeros(xfp("-p", f"/panels/{panel}/plugin-ids"))


def escribir_ids(panel, ids):
    cmd = ["xfconf-query", "-c", "xfce4-panel", "-p", f"/panels/{panel}/plugin-ids", "-n", "-a"]
    for i in ids:
        cmd += ["-t", "int", "-s", str(i)]
    return subprocess.run(cmd, capture_output=True).returncode == 0


def panel_principal():
    """La barra con más elementos (la lista /panels no siempre coincide con los panel-N reales)."""
    if os.environ.get("GENOS_PANEL"):
        return os.environ["GENOS_PANEL"]
    mejor, cuantos = "panel-1", 0
    for linea in xfp("-l").splitlines():
        m = re.match(r"^/panels/(panel-\d+)/plugin-ids$", linea.strip())
        if m:
            n = len(ids_de(m.group(1)))
            if n > cuantos:
                mejor, cuantos = m.group(1), n
    return mejor


def reiniciar_barra():
    subprocess.Popen(["xfce4-panel", "-r"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def poner_boton():
    panel = panel_principal()
    ids = ids_de(panel)
    if not ids:
        print(T("No pude leer la barra (¿estás dentro de la sesión XFCE?)."))
        return 1
    try:
        marca = open(MARCA).read().split()
        if len(marca) == 2 and marca[0] == panel and int(marca[1]) in ids:
            print(T("El botón del centro de control ya está en la barra."))
            return 0
    except (OSError, ValueError):
        pass
    # Si la barra con elementos no está en la lista de paneles, XFCE no la carga: se agrega
    num_panel = int(panel.split("-")[1])
    if num_panel not in numeros(xfp("-p", "/panels")):
        cmd = ["xfconf-query", "-c", "xfce4-panel", "-p", "/panels", "-n", "-a", "-t", "int", "-s", str(num_panel)]
        subprocess.run(cmd, capture_output=True)
        print(T("Reparé la lista de paneles: ahora carga %s.") % panel)
    if os.path.isfile(PANEL_XML) and not os.path.exists(PANEL_XML + ".bak-genos"):
        shutil.copy2(PANEL_XML, PANEL_XML + ".bak-genos")
    existentes = [int(m.group(1)) for m in
                  (re.match(r"^/plugins/plugin-(\d+)", p) for p in xfp("-l").splitlines()) if m]
    nuevo = max(existentes + ids + [0]) + 1
    carpeta = os.path.join(HOME, ".config", "xfce4", "panel", f"launcher-{nuevo}")
    os.makedirs(carpeta, exist_ok=True)
    escritorio = f"{int(time.time())}.desktop"
    with open(os.path.join(carpeta, escritorio), "w") as f:
        f.write("[Desktop Entry]\nVersion=1.0\nType=Application\nName=Centro de control\n"
                f"Comment=Notificaciones, ajustes rápidos y apagado\nExec={BIN}/genos-centro\n"
                "Icon=system-shutdown-symbolic\nTerminal=false\nStartupNotify=false\n")
    base = ["xfconf-query", "-c", "xfce4-panel"]
    subprocess.run(base + ["-p", f"/plugins/plugin-{nuevo}", "-n", "-t", "string", "-s", "launcher"],
                   capture_output=True)
    subprocess.run(base + ["-p", f"/plugins/plugin-{nuevo}/items", "-n", "-a", "-t", "string", "-s", escritorio],
                   capture_output=True)
    if not escribir_ids(panel, ids + [nuevo]):
        print(T("No pude escribir la barra."))
        return 1
    with open(MARCA, "w") as f:
        f.write(f"{panel} {nuevo}\n")
    reiniciar_barra()
    print(T("Botón del centro de control añadido a la barra (%s).") % panel)
    return 0


def quitar_boton():
    try:
        panel, num = open(MARCA).read().split()
        num = int(num)
    except (OSError, ValueError):
        print(T("No hay botón que quitar."))
        return 0
    ids = [i for i in ids_de(panel) if i != num]
    escribir_ids(panel, ids)
    subprocess.run(["xfconf-query", "-c", "xfce4-panel", "-p", f"/plugins/plugin-{num}", "-r", "-R"],
                   capture_output=True)
    shutil.rmtree(os.path.join(HOME, ".config", "xfce4", "panel", f"launcher-{num}"), ignore_errors=True)
    os.remove(MARCA)
    reiniciar_barra()
    print(T("Botón quitado."))
    return 0


# ------------------------------------------------------------------ utilidades
def perfil():
    d = {}
    try:
        with open(PERFIL) as f:
            for linea in f:
                if "=" in linea:
                    k, v = linea.strip().split("=", 1)
                    d[k] = v
    except OSError:
        pass
    return d


def hex_a_rgb(h, defecto):
    m = re.fullmatch(r"#?([0-9a-fA-F]{6})", h or "")
    return tuple(int(m.group(1)[i:i + 2], 16) for i in (0, 2, 4)) if m else defecto


def hace(t):
    s = max(0, int(time.time() - t))
    if s < 60:
        return T("ahora")
    if s < 3600:
        return T("hace %s min") % (s // 60)
    if s < 86400:
        return T("hace %s h") % (s // 3600)
    return T("hace %s d") % (s // 86400)


def leer_historial(n=8):
    try:
        with open(HIST) as f:
            lineas = f.readlines()[-n:]
    except OSError:
        return []
    out = []
    for ln in reversed(lineas):
        try:
            out.append(json.loads(ln))
        except ValueError:
            pass
    return out


def no_molestar():
    r = correr(["xfconf-query", "-c", "xfce4-notifyd", "-p", "/do-not-disturb"])
    return bool(r and r.returncode == 0 and r.stdout.strip() == "true")


def poner_no_molestar(v):
    subprocess.run(["xfconf-query", "-c", "xfce4-notifyd", "-p", "/do-not-disturb", "-n",
                    "-t", "bool", "-s", "true" if v else "false"], capture_output=True)


def widgets_activos():
    try:
        with open(WCONF) as f:
            return bool(json.load(f).get("maestro", True))
    except Exception:
        return True


def volumen():
    if shutil.which("pactl"):
        r = correr(["pactl", "get-sink-volume", "@DEFAULT_SINK@"])
        m = re.search(r"(\d+)%", r.stdout) if r and r.returncode == 0 else None
        if m:
            return int(m.group(1)), "pactl"
    if shutil.which("amixer"):
        r = correr(["amixer", "sget", "Master"])
        m = re.search(r"\[(\d+)%\]", r.stdout) if r and r.returncode == 0 else None
        if m:
            return int(m.group(1)), "amixer"
    return None, None


def poner_volumen(v, via):
    if via == "pactl":
        subprocess.run(["pactl", "set-sink-volume", "@DEFAULT_SINK@", f"{v}%"], capture_output=True)
    elif via == "amixer":
        subprocess.run(["amixer", "sset", "Master", f"{v}%"], capture_output=True)


def medio():
    """(título, artista, estado) del reproductor activo, si hay playerctl y algo sonando."""
    if not shutil.which("playerctl"):
        return None
    r = correr(["playerctl", "metadata", "--format", "{{title}}\t{{artist}}\t{{status}}"])
    if not r or r.returncode != 0 or not r.stdout.strip():
        return None
    partes = (r.stdout.rstrip("\n").split("\t") + ["", "", ""])[:3]
    return tuple(partes)


def buscar_wsl():
    for c in (shutil.which("wsl.exe"), "/mnt/c/Windows/System32/wsl.exe"):
        if c and os.path.exists(c):
            return c
    return None


# ------------------------------------------------------------------ interfaz
def abrir():
    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    from gi.repository import Gdk, GLib, Gtk

    if i18n:
        i18n.parchear(Gtk)
    p = perfil()
    bg = hex_a_rgb(None, (14, 14, 22))
    try:
        bg = tuple(int(x) for x in p.get("pastilla", "14,14,22").split(","))
    except ValueError:
        pass
    fg = hex_a_rgb(p.get("texto"), (242, 242, 247))
    n = [float(x) for x in re.findall(r"[\d.]+", p.get("sel", ""))]
    ac = tuple(int(x) for x in n[:3]) if len(n) >= 3 else (123, 92, 255)
    try:
        radio = int(float(p.get("radio", "12"))) + 6
        alfa = max(0.9, float(p.get("opacidad", "0.72")))
    except ValueError:
        radio, alfa = 18, 0.92
    # Las tarjetas se aclaran u oscurecen un poco respecto al fondo, según el texto
    claro = sum(fg) < 380
    tono = "0,0,0" if claro else "255,255,255"
    css = f"""
    window {{ background: transparent; }}
    #centro {{ background: rgba({bg[0]},{bg[1]},{bg[2]},{alfa:.2f}); color: rgb({fg[0]},{fg[1]},{fg[2]});
              border-radius: {radio}px; border: 1px solid rgba({fg[0]},{fg[1]},{fg[2]},0.14); padding: 16px; }}
    #centro label {{ color: rgb({fg[0]},{fg[1]},{fg[2]}); }}
    .nota .titulo {{ font-size: 13px; }}
    .card {{ background: rgba({tono},0.08); border-radius: {max(10, radio - 4)}px; padding: 8px; }}
    #centro button.fila {{ background: none; padding: 5px 4px; border-radius: 10px; }}
    #centro button.fila:hover {{ background: rgba({tono},0.08); }}
    #centro button.fila:checked {{ background: none; }}
    #centro button.fila:checked label {{ color: rgb({fg[0]},{fg[1]},{fg[2]}); }}
    .circ {{ background: rgba({tono},0.16); border-radius: 18px; min-width: 36px; min-height: 36px; }}
    .circ image {{ color: rgb({fg[0]},{fg[1]},{fg[2]}); }}
    .circ.on {{ background: rgb({ac[0]},{ac[1]},{ac[2]}); }}
    .circ.on image {{ color: #ffffff; }}
    .peligro-circ {{ background: rgba(220,60,60,0.85); }}
    .peligro-circ image {{ color: #ffffff; }}
    #centro button.cuadro {{ background: rgba({tono},0.08); border-radius: {max(10, radio - 4)}px; padding: 10px 4px; }}
    #centro button.cuadro:hover {{ background: rgba({tono},0.16); }}
    .pequeno {{ font-size: 11px; opacity: 0.62; }}
    .tenue {{ opacity: 0.62; font-size: 11px; }}
    .titulo {{ font-weight: 700; font-size: 15px; }}
    .seccion {{ font-weight: 700; font-size: 11px; opacity: 0.62; }}
    #centro button {{ background: rgba({tono},0.08); border: none; box-shadow: none; text-shadow: none;
                     border-radius: {max(8, radio - 6)}px; padding: 9px 10px; color: rgb({fg[0]},{fg[1]},{fg[2]}); }}
    #centro button:hover {{ background: rgba({tono},0.16); }}
    #centro button:checked {{ background: rgb({ac[0]},{ac[1]},{ac[2]}); }}
    #centro button:checked label {{ color: #ffffff; }}
    #centro button.peligro {{ background: rgba(220,60,60,0.22); }}
    #centro button.peligro:hover {{ background: rgba(220,60,60,0.45); }}
    #centro button.mini {{ padding: 3px 9px; font-size: 11px; }}
    .nota {{ background: rgba({tono},0.08); border-radius: {max(8, radio - 6)}px; padding: 8px 10px; }}
    #centro scale trough {{ background: rgba({tono},0.16); min-height: 6px; border-radius: 3px; }}
    #centro scale highlight {{ background: rgb({ac[0]},{ac[1]},{ac[2]}); border-radius: 3px; }}
    #centro scale slider {{ background: #ffffff; min-width: 16px; min-height: 16px; border-radius: 8px; border: none; }}
    #centro separator {{ background: rgba({fg[0]},{fg[1]},{fg[2]},0.12); min-height: 1px; }}
    scrolledwindow undershoot, scrolledwindow overshoot {{ background: none; }}
    """

    class Centro(Gtk.Window):
        def __init__(self):
            super().__init__(type=Gtk.WindowType.TOPLEVEL)
            self.set_decorated(False)
            self.set_skip_taskbar_hint(True)
            self.set_skip_pager_hint(True)
            self.set_keep_above(True)
            self.set_resizable(False)
            self.set_type_hint(Gdk.WindowTypeHint.UTILITY)
            self.set_title("GenOs Centro")
            scr = self.get_screen()
            vis = scr.get_rgba_visual()
            if vis:
                self.set_visual(vis)
            self.set_app_paintable(True)
            prov = Gtk.CssProvider()
            prov.load_from_data(css.encode())
            Gtk.StyleContext.add_provider_for_screen(scr, prov, Gtk.STYLE_PROVIDER_PRIORITY_USER)
            self.bloqueo = False
            self.t0 = time.time()
            self.via_vol = None
            self.vol_id = 0
            self.construir()
            self.connect("key-press-event", self.tecla)
            self.connect("focus-out-event", self.perdio_foco)
            self.connect("destroy", Gtk.main_quit)
            self.show_all()
            self.colocar()
            self.present()

        def colocar(self):
            disp = Gdk.Display.get_default()
            mon = disp.get_primary_monitor() or disp.get_monitor(0)
            area = mon.get_workarea()
            ancho, alto = self.get_size()
            self.move(area.x + area.width - ancho - 12, area.y + 8)

        # --- piezas
        def tarjeta(self, icono, texto, accion, interruptor=False, activo=False, clase=None):
            b = Gtk.ToggleButton() if interruptor else Gtk.Button()
            caja = Gtk.Box(spacing=8)
            if icono:
                caja.pack_start(Gtk.Image.new_from_icon_name(icono, Gtk.IconSize.BUTTON), False, False, 0)
            et = Gtk.Label(label=texto, xalign=0)
            et.set_ellipsize(3)
            caja.pack_start(et, True, True, 0)
            b.add(caja)
            b.set_relief(Gtk.ReliefStyle.NONE)
            if clase:
                b.get_style_context().add_class(clase)
            if interruptor:
                b.set_active(activo)
                b.connect("toggled", lambda w: accion(w.get_active()))
            else:
                b.connect("clicked", lambda _w: accion())
            return b

        def lanzar(self, *cmd):
            try:
                subprocess.Popen(list(cmd), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                 start_new_session=True)
            except OSError:
                pass
            self.destroy()

        def circulo(self, icono, activo=False, clase=None):
            c = Gtk.Box()
            c.set_halign(Gtk.Align.CENTER)
            c.set_valign(Gtk.Align.CENTER)
            ctx = c.get_style_context()
            ctx.add_class("circ")
            if activo:
                ctx.add_class("on")
            if clase:
                ctx.add_class(clase)
            im = Gtk.Image.new_from_icon_name(icono, Gtk.IconSize.BUTTON)
            im.set_halign(Gtk.Align.CENTER)
            c.set_center_widget(im)
            return c

        def fila(self, icono, titulo, sub, accion, interruptor=False, activo=False):
            """Fila estilo macOS: círculo con icono, título y una línea pequeña debajo."""
            b = Gtk.ToggleButton() if interruptor else Gtk.Button()
            b.get_style_context().add_class("fila")
            b.set_relief(Gtk.ReliefStyle.NONE)
            caja = Gtk.Box(spacing=10)
            circ = self.circulo(icono, activo and interruptor)
            caja.pack_start(circ, False, False, 0)
            col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            col.set_valign(Gtk.Align.CENTER)
            t = Gtk.Label(label=titulo, xalign=0)
            t.set_ellipsize(3)
            col.pack_start(t, False, False, 0)
            sl = Gtk.Label(label=sub if not interruptor else ("Activado" if activo else "Desactivado"), xalign=0)
            sl.get_style_context().add_class("pequeno")
            sl.set_ellipsize(3)
            col.pack_start(sl, False, False, 0)
            caja.pack_start(col, True, True, 0)
            b.add(caja)
            if interruptor:
                b.set_active(activo)

                def cambio(w):
                    on = w.get_active()
                    sl.set_text("Activado" if on else "Desactivado")
                    cx = circ.get_style_context()
                    cx.add_class("on") if on else cx.remove_class("on")
                    accion(on)
                b.connect("toggled", cambio)
            else:
                b.connect("clicked", lambda _w: accion())
            return b

        def cuadro(self, icono, texto, accion):
            b = Gtk.Button()
            b.get_style_context().add_class("cuadro")
            b.set_relief(Gtk.ReliefStyle.NONE)
            col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            circ = self.circulo(icono)
            col.pack_start(circ, False, False, 0)
            t = Gtk.Label(label=texto)
            t.get_style_context().add_class("pequeno")
            col.pack_start(t, False, False, 0)
            b.add(col)
            b.connect("clicked", lambda _w: accion())
            return b

        def card(self, *hijos, espacio=0):
            c = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=espacio)
            c.get_style_context().add_class("card")
            for h in hijos:
                c.pack_start(h, False, False, 0)
            return c

        def construir(self):
            raiz = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
            raiz.set_name("centro")
            raiz.set_size_request(350, -1)
            self.add(raiz)

            ahora = datetime.datetime.now()
            cab = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            t = Gtk.Label(label=f"{getpass.getuser()}@{socket.gethostname()}", xalign=0)
            t.get_style_context().add_class("titulo")
            fecha = (i18n.fecha_larga(ahora)[:1].upper() + i18n.fecha_larga(ahora)[1:] if i18n
                     else f"{DIAS[ahora.weekday()].capitalize()} {ahora.day} de {MESES[ahora.month - 1]}")
            f = Gtk.Label(label=f"{fecha} · {ahora:%H:%M}", xalign=0)
            f.get_style_context().add_class("tenue")
            cab.pack_start(t, False, False, 0)
            cab.pack_start(f, False, False, 0)
            raiz.pack_start(cab, False, False, 2)

            # Bloque superior, como el de macOS: tarjeta grande a la izquierda, dos a la derecha
            rej = Gtk.Grid(column_spacing=10, row_spacing=10, column_homogeneous=True)
            izq = self.card(
                self.fila("weather-clear-night-symbolic", "Modo oscuro", "", self.cambiar_modo, True,
                          perfil().get("modo", "oscuro") == "oscuro"),
                self.fila("view-app-grid-symbolic", "Widgets", "", self.cambiar_widgets, True, widgets_activos()),
                self.fila("applications-graphics-symbolic", "Configuración", "Fondos y colores",
                          lambda: self.lanzar(os.path.join(BIN, "genos-configuracion"))),
                espacio=4)
            rej.attach(izq, 0, 0, 1, 2)
            rej.attach(self.card(self.fila("notifications-disabled-symbolic", "No molestar", "",
                                           self.cambiar_dnd, True, no_molestar())), 1, 0, 1, 1)
            cuadros = Gtk.Box(spacing=10, homogeneous=True)
            cuadros.pack_start(self.cuadro("preferences-system-symbolic", "Ajustes",
                                           lambda: self.lanzar(os.path.join(BIN, "genos-configuracion"))), True, True, 0)
            if shutil.which("xfce4-screenshooter"):
                cuadros.pack_start(self.cuadro("applets-screenshooter-symbolic", "Captura",
                                               lambda: self.lanzar("xfce4-screenshooter")), True, True, 0)
            else:
                cuadros.pack_start(self.cuadro("input-keyboard-symbolic", "Teclado",
                                               lambda: self.lanzar("env", "GENOS_PAGINA=teclado", os.path.join(BIN, "genos-configuracion"))), True, True, 0)
            rej.attach(cuadros, 1, 1, 1, 1)
            raiz.pack_start(rej, False, False, 0)

            v, via = volumen()
            if v is not None:
                self.via_vol = via
                et = Gtk.Label(label="Sonido", xalign=0)
                et.get_style_context().add_class("seccion")
                fila = Gtk.Box(spacing=10)
                fila.pack_start(Gtk.Image.new_from_icon_name("audio-volume-high-symbolic", Gtk.IconSize.BUTTON),
                                False, False, 0)
                esc = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1)
                esc.set_draw_value(False)
                esc.set_value(v)
                esc.connect("value-changed", self.cambiar_volumen)
                fila.pack_start(esc, True, True, 0)
                raiz.pack_start(self.card(et, fila, espacio=4), False, False, 0)

            med = medio()
            if med:
                self.medio_estado = med[2]
                tl = Gtk.Label(label=med[0] or "Reproduciendo", xalign=0)
                tl.set_ellipsize(3)
                tl.get_style_context().add_class("titulo")
                ar = Gtk.Label(label=med[1], xalign=0)
                ar.set_ellipsize(3)
                ar.get_style_context().add_class("pequeno")
                col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
                col.pack_start(tl, False, False, 0)
                col.pack_start(ar, False, False, 0)
                fila = Gtk.Box(spacing=6)
                fila.pack_start(col, True, True, 0)
                for ic, cmd in (("media-skip-backward-symbolic", "previous"),
                                ("media-playback-start-symbolic", "play-pause"),
                                ("media-skip-forward-symbolic", "next")):
                    bt = Gtk.Button()
                    bt.get_style_context().add_class("fila")
                    bt.set_relief(Gtk.ReliefStyle.NONE)
                    bt.add(Gtk.Image.new_from_icon_name(ic, Gtk.IconSize.BUTTON))
                    bt.connect("clicked", lambda _w, c=cmd: subprocess.run(["playerctl", c], capture_output=True))
                    fila.pack_start(bt, False, False, 0)
                raiz.pack_start(self.card(fila), False, False, 0)

            enc = Gtk.Box()
            s = Gtk.Label(label="NOTIFICACIONES", xalign=0)
            s.get_style_context().add_class("seccion")
            enc.pack_start(s, True, True, 0)
            borrar = Gtk.Button(label="Borrar todo")
            borrar.get_style_context().add_class("mini")
            borrar.connect("clicked", self.borrar_historial)
            enc.pack_end(borrar, False, False, 0)

            self.lista = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            sc = Gtk.ScrolledWindow()
            sc.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
            sc.set_propagate_natural_height(True)
            sc.set_max_content_height(230)
            sc.add(self.lista)
            raiz.pack_start(self.card(enc, sc, espacio=6), False, False, 0)
            self.llenar_lista()

            pie = Gtk.Box(spacing=10, homogeneous=True)
            pie.pack_start(self.cuadro("system-lock-screen-symbolic", "Bloquear",
                                       lambda: self.lanzar("xflock4")), True, True, 0)
            pie.pack_start(self.cuadro("system-log-out-symbolic", "Cerrar sesión", self.cerrar_sesion), True, True, 0)
            ap = self.cuadro("system-shutdown-symbolic", "Apagar", self.apagar)
            ap.get_child().get_children()[0].get_style_context().add_class("peligro-circ")
            pie.pack_start(ap, True, True, 0)
            raiz.pack_start(pie, False, False, 0)

        def llenar_lista(self):
            for h in self.lista.get_children():
                self.lista.remove(h)
            items = leer_historial()
            if not items:
                vacio = Gtk.Label(label="Sin notificaciones", xalign=0)
                vacio.get_style_context().add_class("tenue")
                self.lista.pack_start(vacio, False, False, 4)
            for it in items:
                caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
                caja.get_style_context().add_class("nota")
                cab = Gtk.Label(label=it.get("titulo") or it.get("app") or "Notificación", xalign=0)
                cab.set_ellipsize(3)
                cab.get_style_context().add_class("titulo")
                caja.pack_start(cab, False, False, 0)
                if it.get("cuerpo"):
                    cu = Gtk.Label(label=re.sub(r"<[^>]+>", "", it["cuerpo"]), xalign=0)
                    cu.set_line_wrap(True)
                    cu.set_lines(2)
                    cu.set_ellipsize(3)
                    cu.set_max_width_chars(44)
                    caja.pack_start(cu, False, False, 0)
                pie = Gtk.Label(label=f"{it.get('app') or ''} · {hace(it.get('t', 0))}".strip(" ·"), xalign=0)
                pie.get_style_context().add_class("tenue")
                caja.pack_start(pie, False, False, 0)
                self.lista.pack_start(caja, False, False, 0)
            self.lista.show_all()

        # --- acciones
        def cambiar_dnd(self, v):
            poner_no_molestar(v)

        def cambiar_modo(self, oscuro):
            """Claro u oscuro al instante: reaplica el fondo actual con ese modo (apaga el cambio automático)."""
            self.lanzar(os.path.join(BIN, "genos-configuracion"), "--reaplicar", "--modo",
                        "oscuro" if oscuro else "claro")

        def cambiar_widgets(self, _v):
            subprocess.run([os.path.join(BIN, "genos-widgets"), "--alternar"], capture_output=True)

        def cambiar_volumen(self, esc):
            if self.vol_id:
                GLib.source_remove(self.vol_id)
            val = int(esc.get_value())

            def poner():
                self.vol_id = 0
                poner_volumen(val, self.via_vol)
                return False
            self.vol_id = GLib.timeout_add(120, poner)

        def borrar_historial(self, _b):
            try:
                open(HIST, "w").close()
            except OSError:
                pass
            self.llenar_lista()
            self.resize(1, 1)

        def confirmar(self, titulo, texto, boton):
            self.bloqueo = True
            d = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.QUESTION,
                                  text=titulo)
            d.format_secondary_text(texto)
            d.add_button("Cancelar", Gtk.ResponseType.CANCEL)
            d.add_button(boton, Gtk.ResponseType.OK)
            r = d.run()
            d.destroy()
            self.bloqueo = False
            return r == Gtk.ResponseType.OK

        def cerrar_sesion(self):
            if self.confirmar("¿Cerrar sesión?", "Se cerrarán las ventanas abiertas.", "Cerrar sesión"):
                self.lanzar("xfce4-session-logout", "--logout")

        def apagar(self):
            wsl = buscar_wsl()
            if not wsl:
                self.bloqueo = True
                d = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.INFO,
                                      buttons=Gtk.ButtonsType.OK, text="No encuentro wsl.exe")
                d.format_secondary_text("Para apagar, en PowerShell de Windows escribe:  wsl --shutdown")
                d.run()
                d.destroy()
                self.bloqueo = False
                return
            if self.confirmar("¿Apagar GenOs?", "Se cierra la sesión y se apaga la máquina WSL. "
                              "Guarda tu trabajo antes.", "Apagar"):
                self.lanzar(wsl, "--shutdown")

        # --- cierre
        def tecla(self, _w, ev):
            if ev.keyval == Gdk.KEY_Escape:
                self.destroy()
            return False

        def perdio_foco(self, _w, _ev):
            if os.environ.get("GENOS_CENTRO_FIJO"):
                return False
            if time.time() - self.t0 < 0.4:
                return False

            def revisar():
                if not self.bloqueo and not self.is_active():
                    self.destroy()
                return False
            GLib.timeout_add(150, revisar)
            return False

    Centro()
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, Gtk.main_quit)
    Gtk.main()


def main():
    if "--boton" in sys.argv:
        return poner_boton()
    if "--quitar-boton" in sys.argv:
        return quitar_boton()
    os.makedirs(os.path.dirname(PID), exist_ok=True)
    # Alternar: si ya hay uno abierto, se cierra
    try:
        viejo = int(open(PID).read().strip())
        os.kill(viejo, 0)
        if "genos-centro" in open(f"/proc/{viejo}/cmdline").read():
            os.kill(viejo, signal.SIGTERM)
            return 0
    except (OSError, ValueError):
        pass
    with open(PID, "w") as f:
        f.write(str(os.getpid()))
    try:
        abrir()
    finally:
        try:
            os.remove(PID)
        except OSError:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
CENTRO_FIN
chmod +x "$BIN/genos-centro"

# Ordena la barra superior: menú y ventanas a la izquierda, reloj al centro, bandeja y botón a la derecha
cat > "$BIN/genos-barra" <<'BARRA_FIN'
#!/usr/bin/env python3
# genos-barra: deja la barra superior limpia. Menú y ventanas a la izquierda, reloj al centro,
# bandeja y botón del centro de control a la derecha. Sin cuadritos de escritorios.
import os
import re
import shutil
import subprocess
import sys

sys.path[:0] = [os.path.join(os.path.expanduser("~"), ".local", "lib", "genos"),
                os.path.dirname(os.path.abspath(__file__))]
try:
    import genos_i18n as i18n
    T = i18n.T
except ImportError:  # sin el módulo todo queda en español
    i18n = None

    def T(s):
        return s

HOME = os.path.expanduser("~")
XML = os.path.join(HOME, ".config", "xfce4", "xfconf", "xfce-perchannel-xml", "xfce4-panel.xml")


def xf(*a):
    r = subprocess.run(["xfconf-query", "-c", "xfce4-panel", *a], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


def enteros(t):
    return [int(x.strip()) for x in t.splitlines() if x.strip().isdigit()]


def elegir_panel():
    mejor, n = "panel-1", 0
    for ln in xf("-l").splitlines():
        m = re.match(r"^/panels/(panel-\d+)/plugin-ids$", ln.strip())
        if m:
            c = len(enteros(xf("-p", ln.strip())))
            if c > n:
                mejor, n = m.group(1), c
    return mejor


def main():
    if not xf("-l"):
        print(T("No puedo hablar con la barra. Corre esto dentro del escritorio XFCE."))
        return 1
    panel = elegir_panel()
    ids = enteros(xf("-p", f"/panels/{panel}/plugin-ids"))
    tipos = {i: xf("-p", f"/plugins/plugin-{i}").strip() for i in ids}
    if os.path.isfile(XML) and not os.path.exists(XML + ".bak-genos-barra"):
        shutil.copy2(XML, XML + ".bak-genos-barra")

    def de(*nombres):
        return [i for i in ids if tipos[i] in nombres]

    menu = de("whiskermenu", "applicationsmenu")
    ventanas = de("tasklist")
    reloj = de("clock")
    bandeja = de("systray", "statusnotifier", "pulseaudio", "power-manager-plugin", "notification-plugin")
    lanzadores = de("launcher")
    quitar = de("pager", "separator", "actions", "showdesktop", "windowmenu", "directorymenu")
    conocidos = set(menu + ventanas + reloj + bandeja + lanzadores + quitar)
    otros = [i for i in ids if i not in conocidos]

    todos = [int(m.group(1)) for m in (re.match(r"^/plugins/plugin-(\d+)", p) for p in xf("-l").splitlines()) if m]
    nuevo = max(todos + ids + [0]) + 1
    sep = []
    for k in range(2):
        i = nuevo + k
        subprocess.run(["xfconf-query", "-c", "xfce4-panel", "-p", f"/plugins/plugin-{i}", "-n", "-t", "string",
                        "-s", "separator"], capture_output=True)
        subprocess.run(["xfconf-query", "-c", "xfce4-panel", "-p", f"/plugins/plugin-{i}/expand", "-n", "-t", "bool",
                        "-s", "true"], capture_output=True)
        subprocess.run(["xfconf-query", "-c", "xfce4-panel", "-p", f"/plugins/plugin-{i}/style", "-n", "-t", "uint",
                        "-s", "0"], capture_output=True)
        sep.append(i)

    orden = menu + ventanas + [sep[0]] + reloj + [sep[1]] + otros + bandeja + lanzadores
    cmd = ["xfconf-query", "-c", "xfce4-panel", "-p", f"/panels/{panel}/plugin-ids", "-n", "-a"]
    for i in orden:
        cmd += ["-t", "int", "-s", str(i)]
    if subprocess.run(cmd, capture_output=True).returncode != 0:
        print(T("No pude escribir el orden de la barra."))
        return 1
    for i in quitar:
        subprocess.run(["xfconf-query", "-c", "xfce4-panel", "-p", f"/plugins/plugin-{i}", "-r", "-R"],
                       capture_output=True)

    # Reloj en una sola línea: dom 08 nov  17:37
    for i in reloj:
        for prop, tipo, val in (("digital-layout", "uint", "1"), ("digital-time-format", "string", "%a %d %b  %H:%M")):
            subprocess.run(["xfconf-query", "-c", "xfce4-panel", "-p", f"/plugins/plugin-{i}/{prop}", "-n", "-t",
                            tipo, "-s", val], capture_output=True)

    subprocess.Popen(["xfce4-panel", "-r"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(T("Barra ordenada (%s): %d elementos, quité %d (escritorios, separadores viejos, etc.).") % (panel, len(orden), len(quitar)))
    print(T("Si algo no te gusta, el respaldo está en %s") % (XML + ".bak-genos-barra"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
BARRA_FIN
chmod +x "$BIN/genos-barra"
cat > "$HOME/.config/autostart/genos-widgets.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=GenOs Widgets
Exec=sh -c "sleep 4 && $BIN/genos-widgets"
X-GNOME-Autostart-enabled=true
EOF
cat > "$HOME/.local/share/applications/genos-configuracion.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Configuración
Comment=Todos los ajustes de GenOS
Exec=$BIN/genos-configuracion
Icon=preferences-desktop-wallpaper
Terminal=false
Categories=XFCE;GTK;Settings;DesktopSettings;X-XFCE;X-XFCE-SettingsDialog;X-XFCE-PersonalSettings;
OnlyShowIn=XFCE;
EOF

cat > "$HOME/.local/share/applications/launchpad.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Apps
Comment=Lanzador de aplicaciones
Exec=rofi -show drun -theme $HOME/.config/rofi/launchpad.rasi
Icon=view-app-grid
Terminal=false
Categories=Utility;
EOF
# Que el propio rofi no salga dentro de la lista de apps
for n in rofi rofi-theme-selector; do
  printf '[Desktop Entry]\nType=Application\nName=%s\nNoDisplay=true\n' "$n" > "$HOME/.local/share/applications/$n.desktop"
done

# ---------- 4. Fondos GenOs ----------
paso "4/7 Fondos"
for o in /mnt/c/Users/*/Downloads/GenOs-Fondos "$HOME/GenOs-Fondos"; do
  [ -d "$o" ] || continue
  echo "   Buscando fondos en $o"
  while IFS= read -r -d '' z; do
    sub="$FONDOS/$(basename "${z%.*}")"
    mkdir -p "$sub"
    unzip -o -q "$z" -d "$sub" || aviso "No pude abrir $z"
  done < <(find "$o" -maxdepth 1 -type f -iname '*.zip' -print0)
  (cd "$o" && find . -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -print0 \
     | xargs -0 -r cp -n --parents -t "$FONDOS")
done
nfondos=$(find "$FONDOS" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) | wc -l)
if [ "$nfondos" -eq 0 ]; then
  aviso "No encontré fondos. Se crea un degradado morado de reserva."
  aviso "Para usar los de Canva, deja los .zip o las imágenes en Descargas\\GenOs-Fondos y corre el script otra vez."
  IM=$(command -v magick || command -v convert || true)
  if [ -n "$IM" ]; then
    "$IM" -size 2560x1440 radial-gradient:'#3b2e8a-#07070d' -attenuate 0.25 +noise Gaussian -quality 90 \
      "$FONDOS/00-degradado-morado.jpg" || aviso "No pude crear el degradado"
  fi
else
  echo "   $nfondos fondos en ~/Pictures/GenOs-Fondos"
fi

elegido=""
if [ -n "$FONDO_INICIAL" ]; then
  if [[ "$FONDO_INICIAL" =~ ^[0-9]+$ ]]; then
    elegido=$(find "$FONDOS" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) | sort -V | sed -n "${FONDO_INICIAL}p")
  else
    elegido=$(find "$FONDOS" -type f -iname "*$FONDO_INICIAL*" | sort -V | head -n1)
  fi
fi
if [ -z "$elegido" ]; then
  while IFS= read -r f; do
    read -r m a < <("$BIN/genos-fondo" --analizar "$f")
    if [ "$m" = oscuro ] && [ "$a" != neutro ]; then elegido=$f; break; fi
  done < <(find "$FONDOS" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) ! -name '00-degradado*' | sort -V)
fi
[ -n "$elegido" ] || elegido=$(find "$FONDOS" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) ! -name '00-degradado*' | sort -V | head -n1)
[ -n "$elegido" ] || elegido="$FONDOS/00-degradado-morado.jpg"
echo "   Fondo inicial: ${elegido:-ninguno}"

# ---------- 5. Arranque más liviano ----------
paso "5/7 Arranque más liviano"
for n in xfce4-power-manager blueman print-applet nm-applet xfce4-screensaver light-locker geoclue-demo-agent; do
  if [ -f "/etc/xdg/autostart/$n.desktop" ]; then
    printf '[Desktop Entry]\nHidden=true\n' > "$HOME/.config/autostart/$n.desktop"
    echo "   Oculto en el arranque: $n"
  fi
done

# ---------- 6. Ajustes (solo dentro de XFCE) ----------
paso "6/7 Ajustes de apariencia"
en_xfce() {
  [ "${XDG_CURRENT_DESKTOP:-}" = "XFCE" ] \
    && command -v xfconf-query >/dev/null 2>&1 \
    && xfconf-query -c xsettings -l >/dev/null 2>&1
}
if en_xfce; then
  xf() { xfconf-query -c "$1" -p "$2" -n -t "$3" -s "$4" 2>/dev/null || aviso "No pude fijar $1 $2"; }

  if [ "$ACTUALIZANDO" = 1 ]; then
    echo "   Actualización: se conservan tu fuente, cursor, ventanas, barra y dock"
  else
  xf xsettings /Gtk/CursorThemeName string "$TEMA_CURSOR"
  xf xsettings /Gtk/FontName        string "$FUENTE"
  xf xsettings /Xft/Antialias       int 1
  xf xsettings /Xft/Hinting         int 1
  xf xsettings /Xft/HintStyle       string hintslight

  xf xfwm4 /general/button_layout    string "CHM|"
  xf xfwm4 /general/title_alignment  string center
  xf xfwm4 /general/use_compositing  bool true
  xf xfwm4 /general/show_dock_shadow bool false

  # El panel puede llamarse panel-0, panel-1... según la instalación: se toman todos los que existan
  paneles=$(xfconf-query -c xfce4-panel -l 2>/dev/null | grep -oE '^/panels/panel-[0-9]+' | sort -u)
  if [ -n "$paneles" ]; then
    for pn in $paneles; do
      xf xfce4-panel "$pn/size" uint "$ALTO_PANEL"
      xf xfce4-panel "$pn/background-style" uint 1
      xfconf-query -c xfce4-panel -p "$pn/background-rgba" -n -a \
        -t double -s 0 -t double -s 0 -t double -s 0 -t double -s 0 2>/dev/null \
        || aviso "No pude dejar $pn transparente"
    done
  else
    aviso "No encontré el panel, ajústalo a mano"
  fi

  if command -v dconf >/dev/null 2>&1; then
    d=/net/launchpad/plank/docks/dock1
    dconf write "$d/theme" "'Transparent'"
    dconf write "$d/icon-size" 48
    dconf write "$d/zoom-enabled" true
    dconf write "$d/zoom-percent" 150
  else
    aviso "No encontré dconf, configura Plank a mano"
  fi
  fi

  # Dock: solo con apps que sí existen (un lanzador sin app instalada sale como engranaje)
  if [ "$ACTUALIZANDO" != 1 ]; then
  LDIR="$HOME/.config/plank/dock1/launchers"
  [ -d "$LDIR" ] && [ ! -d "$LDIR.bak" ] && cp -r "$LDIR" "$LDIR.bak"
  mkdir -p "$LDIR"
  rm -f "$LDIR"/*.dockitem
  items=()
  agregar() { # $1 = nombre del .dockitem ; resto = candidatos .desktop (el primero que exista)
    local nombre=$1 c ruta; shift
    for c in "$@"; do
      for ruta in "$HOME/.local/share/applications/$c" "/usr/share/applications/$c"; do
        if [ -f "$ruta" ]; then
          printf '[PlankDockItemPreferences]\nLauncher=file://%s\n' "$ruta" > "$LDIR/$nombre.dockitem"
          items+=("'$nombre.dockitem'"); return
        fi
      done
    done
  }
  agregar apps       launchpad.desktop
  agregar archivos   thunar.desktop org.xfce.thunar.desktop org.xfce.Thunar.desktop
  agregar terminal   org.xfce.terminal.desktop xfce4-terminal.desktop
  agregar navegador  firefox-esr.desktop firefox.desktop chromium.desktop brave-browser.desktop google-chrome.desktop
  agregar editor     code.desktop org.xfce.mousepad.desktop mousepad.desktop
  agregar personal   genos-configuracion.desktop
  if command -v dconf >/dev/null 2>&1 && [ "${#items[@]}" -gt 0 ]; then
    dconf write /net/launchpad/plank/docks/dock1/dock-items "[$(IFS=,; echo "${items[*]}")]"
  fi
  fi
  pkill -u "$USER" -x plank 2>/dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -u "$USER" -x plank >/dev/null || break; sleep 0.5; done
  pkill -9 -u "$USER" -x plank 2>/dev/null
  (nohup plank >/dev/null 2>&1 &)
  if [ "$ACTUALIZANDO" = 1 ]; then echo "   Dock reiniciado con tus apps"; else echo "   Dock con ${#items[@]} apps"; fi

  # Atajos: si ya existe uno con ese comando (aunque le cambiaras la tecla), se deja como está
  atajos_v=$(xfconf-query -c xfce4-keyboard-shortcuts -l -v 2>/dev/null)
  atajo() { # tecla comando fragmento mensaje
    if [ "$ACTUALIZANDO" = 1 ] && grep -qF -- "$3" <<< "$atajos_v"; then return 0; fi
    xfconf-query -c xfce4-keyboard-shortcuts -n -t string -p "/commands/custom/$1" -s "$2" && echo "   $4"
  }
  atajo "<Primary><Alt>a" "rofi -show drun -theme $HOME/.config/rofi/launchpad.rasi" "launchpad.rasi" "Atajo del lanzador: Ctrl+Alt+A"
  atajo "<Primary><Alt>f" "$BIN/genos-fondo --elegir" "genos-fondo --elegir" "Atajo para elegir fondo: Ctrl+Alt+F"
  atajo "<Primary><Alt>p" "$BIN/genos-configuracion" "genos-configuracion" "Atajo de Configuración: Ctrl+Alt+P"
  atajo "<Primary><Alt>w" "$BIN/genos-widgets --alternar" "genos-widgets --alternar" "Atajo de widgets: Ctrl+Alt+W"
  atajo "<Primary><Alt>c" "$BIN/genos-centro" "genos-centro" "Atajo del centro de control: Ctrl+Alt+C"

  # Lo que Configuración ya cubre se esconde del Gestor de ajustes (se devuelve con: genos-configuracion --mostrar-ajustes)
  if [ "$ACTUALIZANDO" != 1 ] || [ -f "$BIN/xfce4-settings-manager" ]; then
    "$BIN/genos-configuracion" --ocultar-ajustes || true
  fi

  # Notificaciones: el tema Default toma el diseño de la barra (CSS de genos-fondo).
  # Los demás valores solo se fijan si todavía no existen, para no pisar lo que elijas.
  xf xfce4-notifyd /theme string Default
  for par in "/notify-location uint 2" "/expire-timeout int 5" "/do-fadeout bool true" "/initial-opacity double 1.0"; do
    read -r np nt nv <<< "$par"
    xfconf-query -c xfce4-notifyd -p "$np" >/dev/null 2>&1 || xf xfce4-notifyd "$np" "$nt" "$nv"
  done
  echo "   Notificaciones con el diseño GenOs"

  rc="$HOME/.config/xfce4/terminal/terminalrc"
  mkdir -p "$(dirname "$rc")"
  [ -f "$rc" ] || echo "[Configuration]" > "$rc"
  ini_set() {
    if grep -q "^$2=" "$1"; then sed -i "s|^$2=.*|$2=$3|" "$1"; else echo "$2=$3" >> "$1"; fi
  }
  if [ "$ACTUALIZANDO" != 1 ]; then
    ini_set "$rc" BackgroundMode TERMINAL_BACKGROUND_TRANSPARENT
    ini_set "$rc" BackgroundDarkness 0.900000
  fi
else
  aviso "Estás fuera de la sesión de XFCE, así que estos ajustes no se aplicaron."
  aviso "Abre una terminal dentro del escritorio remoto y corre otra vez: bash \"$0\""
fi

# Fondo + tema oscuro/claro + CSS de la barra + lanzador. Fuera de XFCE solo escribe los archivos.
# El lanzador guarda en caché la lista de apps para abrir rápido; se renueva al correr este script
rm -f "$HOME/.cache/rofi3.druncache"
if [ "$ACTUALIZANDO" = 1 ] && [ -f "$HOME/.config/genos-personalizacion.json" ]; then
  # Tu fondo, modo, acento y estilo de siempre, con los programas nuevos
  "$BIN/genos-configuracion" --reaplicar || aviso "No pude reaplicar tu tema; ábrelo en Configuración y pulsa Aplicar"
  pgrep -u "$USER" -f genos-widgets >/dev/null || (nohup "$BIN/genos-widgets" >/dev/null 2>&1 &)
elif [ -n "$elegido" ]; then
  "$BIN/genos-fondo" "$elegido" || aviso "genos-fondo falló"
  # Widgets por defecto (reloj y sistema): aparecen ya, sin esperar al próximo inicio de sesión
  (nohup "$BIN/genos-widgets" >/dev/null 2>&1 &)
  # Botón del centro de control en la barra (una sola vez; se quita desde Configuración > Sistema)
  if en_xfce && [ ! -f "$HOME/.config/genos-centro.plugin" ]; then
    "$BIN/genos-centro" --boton || aviso "No pude añadir el botón del centro de control (abre con Ctrl+Alt+C)"
  fi
fi

# ---------- 7. Limpieza ----------
paso "7/7 Limpieza"
echo "$GENOS_VERSION" > "$HOME/.config/genos-version"
apt_ autoremove -y -qq
apt_ clean

cat <<'FIN'

Listo. Cierra sesión (Applications > Log Out) y vuelve a entrar.
Para cambiar fondo y colores: Ctrl+Alt+P (ventana de Configuración) o su icono en el dock.
Selector rápido con miniaturas: Ctrl+Alt+F. Por terminal: genos-fondo NUMERO. Cada fondo trae su
propio tema (modo, acento, pastillas, lanzador, notificaciones y terminal).
Colores > Apariencia: Automático, Claro u Oscuro, color de acento, estilo (Sólido, Cristal, Teñido) y
cambio automático día y noche. Si la barra se ve desordenada, corre: genos-barra
GenOS 1.2 busca actualizaciones al entrar (una vez al día) y te avisa con una notificación.
Por terminal: genos-actualizar, genos-actualizar --cambios, genos-actualizar --instalar.
Las actualizaciones conservan tu personalización y guardan un respaldo (genos-actualizar --revertir).
Configuración reemplaza al Gestor de ajustes de XFCE. Reúne la barra, las ventanas, el
escritorio, la apariencia, la pantalla, el teclado, el ratón, el sonido, la energía, las unidades, el inicio,
las aplicaciones, los archivos y la accesibilidad, y trae su página Acerca de GenOS con los créditos.
El idioma (español, inglés o portugués) se elige en Configuración > Sistema.
Para devolver el Gestor de ajustes original: genos-configuracion --mostrar-ajustes
Centro de control (botón arriba a la derecha o Ctrl+Alt+C): apagar, cerrar sesión, historial de
notificaciones, No molestar y ajustes rápidos.
Widgets en el escritorio: reloj y sistema vienen activos; Calendario, Red, Notas y Pomodoro se activan en
Configuración > Widgets. Ctrl+Alt+W los oculta o los muestra. Exporta tu tema con genos-exportar.
Para que la barra quede como pastillas, en Panel Preferences > Items deja: el menú, la lista de
ventanas, un Separator con Expand a cada lado del reloj, y la bandeja a la derecha.
FIN
