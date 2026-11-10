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
