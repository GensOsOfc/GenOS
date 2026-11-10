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
