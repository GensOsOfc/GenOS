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
