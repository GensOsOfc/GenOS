#!/usr/bin/env bash
# xfce-estetica.sh (GenOS: sistema de actualizaciones desde GitHub que conserva tu personalización)
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
@@RASI@@RASI_FIN

# Comando genos-fondo
cat > "$BIN/genos-fondo" <<'GENOS_FIN'
@@GENOS@@GENOS_FIN
chmod +x "$BIN/genos-fondo"

# Traducciones (español, inglés y portugués) que usan las apps de GenOS
mkdir -p "$HOME/.local/lib/genos"
cat > "$HOME/.local/lib/genos/genos_i18n.py" <<'I18N_FIN'
@@I18N@@I18N_FIN

# Actualizaciones desde GitHub
cat > "$BIN/genos-actualizar" <<'ACT_FIN'
@@ACT@@ACT_FIN
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
@@PERS@@PERS_FIN
chmod +x "$BIN/genos-configuracion"
# El nombre anterior sigue funcionando (atajos y lanzadores viejos)
ln -sf "$BIN/genos-configuracion" "$BIN/genos-personalizacion"
rm -f "$HOME/.local/share/applications/genos-personalizacion.desktop"

# Exportar / importar el tema (zip en Descargas de Windows)
cat > "$BIN/genos-exportar" <<'EXPORT_FIN'
@@EXPORT@@EXPORT_FIN
chmod +x "$BIN/genos-exportar"

# Widgets de escritorio (reloj y sistema activos por defecto; el resto se activa en Configuración)
cat > "$BIN/genos-widgets" <<'WIDGETS_FIN'
@@WIDGETS@@WIDGETS_FIN
chmod +x "$BIN/genos-widgets"

# Centro de control (apagar, cerrar sesión, historial de notificaciones, ajustes rápidos)
cat > "$BIN/genos-centro" <<'CENTRO_FIN'
@@CENTRO@@CENTRO_FIN
chmod +x "$BIN/genos-centro"

# Ordena la barra superior: menú y ventanas a la izquierda, reloj al centro, bandeja y botón a la derecha
cat > "$BIN/genos-barra" <<'BARRA_FIN'
@@BARRA@@BARRA_FIN
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
GenOS busca actualizaciones al entrar (una vez al día) y te avisa con una notificación.
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

Redes: YouTube youtube.com/@geniousmods · GitHub github.com/GenOSDev · Telegram t.me/channelgenioushack · TikTok tiktok.com/@gn_dev_logic
FIN
