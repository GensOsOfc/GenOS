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
