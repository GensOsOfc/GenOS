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
