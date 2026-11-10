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
