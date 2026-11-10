#!/usr/bin/env bash
# Pruebas de GenOS: sintaxis, versiones, actualizador y modo actualización del instalador.
# No toca tu sistema: todo corre en carpetas temporales con programas simulados.
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
PY=${PY:-python3}
fallos=0
bien() { printf '  ok    %s\n' "$*"; }
mal()  { printf '  FALLA %s\n' "$*"; fallos=$((fallos + 1)); }
revisa() { local d=$1; shift; if "$@" >/dev/null 2>&1; then bien "$d"; else mal "$d"; fi; }

echo "== Construir"
"$PY" "$RAIZ/herramientas/construir.py" || { echo "No se pudo construir"; exit 1; }
SH="$RAIZ/xfce-estetica.sh"
V=$(tr -d ' \n' < "$RAIZ/VERSION")

echo "== Sintaxis"
revisa "bash -n xfce-estetica.sh" bash -n "$SH"
revisa "bash -n genos-actualizar.sh" bash -n "$RAIZ/src/genos-actualizar.sh"
revisa "bash -n genos-fondo.sh" bash -n "$RAIZ/src/genos-fondo.sh"
for f in "$RAIZ"/src/*.py; do revisa "python $(basename "$f")" "$PY" -m py_compile "$f"; done
if command -v shellcheck >/dev/null 2>&1; then
  revisa "shellcheck (avisos)" shellcheck -S warning "$SH" "$RAIZ/src/genos-actualizar.sh"
fi

echo "== Versiones"
grep -q "^GENOS_VERSION=\"$V\"$" "$SH" && bien "instalador dice $V" || mal "el instalador no dice $V"
grep -q "^GENOS_VERSION = \"$V\"$" "$SH" && bien "Configuración dice $V" || mal "Configuración no dice $V"
grep -q "^## $V " "$RAIZ/CHANGELOG.md" && bien "CHANGELOG tiene la $V" || mal "falta '## $V' en CHANGELOG.md"
(cd "$RAIZ" && sha256sum -c --quiet xfce-estetica.sh.sha256) && bien "huella sha256" || mal "huella sha256"

echo "== Actualizador"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
SRV="$T/servidor"; H="$T/casa"; mkdir -p "$SRV" "$H/.config" "$H/bin"
ACT="$RAIZ/src/genos-actualizar.sh"
corre() { env HOME="$H" GENOS_BASE_URL="file://$SRV" PATH="$H/bin:$PATH" bash "$ACT" "$@" </dev/null; }
printf 'notify-send %s\n' '"$@"' > /dev/null
cat > "$H/bin/notify-send" <<'EOF'
#!/bin/sh
echo "$*" >> "$HOME/notificaciones"
EOF
chmod +x "$H/bin/notify-send"
cat > "$SRV/CHANGELOG.md" <<'EOF'
# Cambios
## 2.1 (2030-01-02)
- cambio dos punto uno
## 2.0 (2030-01-01)
- cambio dos
## 1.0 (2029-01-01)
- viejo
EOF
echo "2.1" > "$SRV/VERSION"
cat > "$SRV/xfce-estetica.sh" <<'EOF'
#!/usr/bin/env bash
[ "${GENOS_ACTUALIZAR:-}" = 1 ] || { echo "no vino en modo actualización"; exit 3; }
echo "2.1" > "$HOME/.config/genos-version"
echo instalado > "$HOME/marca"
EOF
(cd "$SRV" && sha256sum xfce-estetica.sh > xfce-estetica.sh.sha256)
echo "1.0" > "$H/.config/genos-version"
echo '{"fondo": "mio.jpg", "modo": "claro"}' > "$H/.config/genos-personalizacion.json"

[ "$(corre --estado)" = "disponible 1.0 2.1" ] && bien "detecta la versión nueva" || mal "no detecta la versión nueva: $(corre --estado)"
c=$(corre --cambios)
grep -q "dos punto uno" <<< "$c" && grep -q "cambio dos$" <<< "$c" && ! grep -q viejo <<< "$c" \
  && bien "lista solo los cambios nuevos" || mal "lista de cambios: $c"
corre --aviso >/dev/null; grep -q "2.1 disponible" "$H/notificaciones" 2>/dev/null && bien "avisa con notificación" || mal "no avisó"
: > "$H/notificaciones"; corre --aviso >/dev/null; [ ! -s "$H/notificaciones" ] && bien "avisa una sola vez al día" || mal "avisó dos veces"

cp "$SRV/xfce-estetica.sh.sha256" "$T/buena"; echo "0000  xfce-estetica.sh" > "$SRV/xfce-estetica.sh.sha256"
corre --instalar >/dev/null; [ ! -f "$H/marca" ] && bien "rechaza una huella que no coincide" || mal "instaló con huella mala"
cp "$T/buena" "$SRV/xfce-estetica.sh.sha256"

corre --instalar > "$T/salida" 2>&1
[ -f "$H/marca" ] && bien "instala la versión nueva en modo actualización" || mal "no instaló: $(tail -3 "$T/salida")"
grep -q '"modo": "claro"' "$H/.config/genos-personalizacion.json" && bien "conserva la personalización" || mal "tocó la personalización"
ls "$H/.local/share/genos/respaldos/"*.tar.gz >/dev/null 2>&1 && bien "guarda un respaldo" || mal "no hay respaldo"
grep -q "1.0 → 2.1" "$H/.local/share/genos/actualizaciones.log" && grep -q "dos punto uno" "$H/.local/share/genos/actualizaciones.log" \
  && bien "historial con la lista de cambios" || mal "historial incompleto"
[ "$(corre --estado)" = "al-dia 2.1 2.1" ] && bien "queda al día" || mal "estado después: $(corre --estado)"

echo '{"modo": "roto"}' > "$H/.config/genos-personalizacion.json"
corre --revertir >/dev/null
grep -q '"modo": "claro"' "$H/.config/genos-personalizacion.json" && bien "revertir devuelve la configuración" || mal "revertir no funcionó"
[ "$(env HOME="$H" GENOS_BASE_URL="file://$T/no-existe" bash "$ACT" --estado)" = "sin-conexion 1.0" ] \
  && bien "sin conexión no rompe nada" || mal "sin conexión"

echo "== Instalador en modo actualización (sin tocar lo personalizado)"
GUARDAR=${GUARDAR:-}
I="$T/inst"; mkdir -p "$I/bin" "$I/.config" "$I/.themes" "$I/.icons" "$I/Pictures/GenOs-Fondos"
LOG="$I/llamadas"; : > "$LOG"
for p in sudo apt-get dpkg git plank pkill pgrep xfce4-panel xfdesktop fc-cache gsettings notify-send xrandr unzip; do
  printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 0\n' "$p" "$LOG" > "$I/bin/$p"
done
# sudo -v debe funcionar y sudo cmd debe correr el cmd simulado
printf '#!/bin/sh\necho "sudo $*" >> "%s"\n[ "$1" = -v ] && exit 0\nshift $(( $# > 0 ? 0 : 0 )); exit 0\n' "$LOG" > "$I/bin/sudo"
printf '#!/bin/sh\necho "xfconf-query $*" >> "%s"\ncase "$*" in *"-l -v"*) echo "/commands/custom/<Super>p  %s/.local/bin/genos-configuracion";; *" -l"*) echo /panels/panel-1/size;; esac\nexit 0\n' "$LOG" "$I" > "$I/bin/xfconf-query"
printf '#!/bin/sh\necho "dconf $*" >> "%s"\nexit 0\n' "$LOG" > "$I/bin/dconf"
chmod +x "$I/bin/"*
for t in WhiteSur-Dark-solid-red WhiteSur-Light-solid-grey WhiteSur-Dark-solid; do mkdir -p "$I/.themes/$t"; done
for t in WhiteSur-dark WhiteSur-light WhiteSur-cursors; do mkdir -p "$I/.icons/$t"; done
echo '{"fondo": "x.jpg"}' > "$I/.config/genos-personalizacion.json"
env -i GENOS_PRUEBA=1 HOME="$I" USER=prueba PATH="$I/bin:/usr/bin:/bin" XDG_CURRENT_DESKTOP=XFCE GENOS_FONDO_BIN="$I/bin/true" \
  bash "$SH" > "$I/salida" 2>&1 </dev/null
[ -n "$GUARDAR" ] && cp "$I/salida" "$GUARDAR"
grep -q "Actualización: se conservan" "$I/salida" && bien "entra en modo actualización" || mal "no detectó la actualización"
! grep -q "/Gtk/FontName" "$LOG" && bien "no cambia la fuente" || mal "cambió la fuente"
! grep -q "button_layout" "$LOG" && bien "no cambia los botones de ventana" || mal "cambió los botones de ventana"
! grep -q "dock-items" "$LOG" && bien "no rehace el dock" || mal "rehízo el dock"
! grep -q "icon-size" "$LOG" && bien "no cambia el tamaño del dock" || mal "cambió el tamaño del dock"
! grep -q 'custom/<Primary><Alt>p' "$LOG" && bien "respeta el atajo de Configuración que cambiaste" || mal "reescribió el atajo"
grep -q 'custom/<Primary><Alt>a' "$LOG" && bien "agrega atajos que faltan" || mal "no agregó el atajo que faltaba"
! grep -q BackgroundMode "$I/.config/xfce4/terminal/terminalrc" 2>/dev/null && bien "no toca la terminal" || mal "tocó la terminal"
[ "$(cat "$I/.config/genos-version" 2>/dev/null)" = "$V" ] && bien "guarda la versión $V" || mal "no guardó la versión"
[ -x "$I/.local/bin/genos-actualizar" ] && bien "instala genos-actualizar" || mal "falta genos-actualizar"
[ -f "$I/.config/autostart/genos-actualizar.desktop" ] && bien "aviso al iniciar sesión" || mal "falta el aviso al iniciar"

echo "== Instalador en una instalación nueva"
N="$T/nuevo"; mkdir -p "$N/.config" "$N/Pictures/GenOs-Fondos"; cp -r "$I/bin" "$I/.themes" "$I/.icons" "$N/"
LOG2="$N/llamadas"; : > "$LOG2"; sed -i "s|$LOG|$LOG2|; s|$I|$N|" "$N/bin/"*
env -i GENOS_PRUEBA=1 HOME="$N" USER=prueba PATH="$N/bin:/usr/bin:/bin" XDG_CURRENT_DESKTOP=XFCE bash "$SH" > "$N/salida" 2>&1 </dev/null
grep -q "/Gtk/FontName" "$LOG2" && bien "pone la fuente de GenOS" || mal "no puso la fuente"
grep -q "dock-items" "$LOG2" && bien "arma el dock" || mal "no armó el dock"

echo
if [ "$fallos" -eq 0 ]; then echo "Todo bien."; else echo "$fallos pruebas fallaron."; exit 1; fi
