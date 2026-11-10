#!/usr/bin/env python3
"""Une src/ en un solo instalador: xfce-estetica.sh (más su huella .sha256)."""
import glob
import hashlib
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(RAIZ, "src")


def leer(nombre):
    with open(os.path.join(SRC, nombre), encoding="utf-8") as f:
        return f.read().rstrip("\n") + "\n"


def main():
    version = open(os.path.join(RAIZ, "VERSION")).read().strip()
    i18n = "".join(open(p, encoding="utf-8").read() for p in sorted(glob.glob(os.path.join(SRC, "traducciones", "*.py"))))
    with open(os.path.join(SRC, "genos_i18n.py"), "w", encoding="utf-8", newline="\n") as f:
        f.write(i18n)
    plantilla = leer("estetica.main.tpl")
    plantilla = re.sub(r'^GENOS_VERSION=".*"$', 'GENOS_VERSION="%s"' % version, plantilla, count=1, flags=re.M)
    piezas = {"I18N": "genos_i18n.py", "ACT": "genos-actualizar.sh", "RASI": "launchpad.rasi.tpl",
              "GENOS": "genos-fondo.sh", "PERS": "genos-configuracion.py", "EXPORT": "genos-exportar.sh",
              "WIDGETS": "genos-widgets.py", "CENTRO": "genos-centro.py", "BARRA": "genos-barra.py"}
    for marca, archivo in piezas.items():
        hueco = "@@%s@@%s_FIN" % (marca, marca)
        if hueco not in plantilla:
            sys.exit("Falta el hueco %s en la plantilla" % hueco)
        contenido = leer(archivo)
        if marca == "PERS":
            contenido = re.sub(r'^GENOS_VERSION = ".*"$', 'GENOS_VERSION = "%s"' % version, contenido, count=1, flags=re.M)
        plantilla = plantilla.replace(hueco, contenido + marca + "_FIN")
    salida = os.path.join(RAIZ, "xfce-estetica.sh")
    with open(salida, "w", encoding="utf-8", newline="\n") as f:
        f.write(plantilla)
    os.chmod(salida, 0o755)
    h = hashlib.sha256(open(salida, "rb").read()).hexdigest()
    with open(salida + ".sha256", "w", newline="\n") as f:
        f.write("%s  xfce-estetica.sh\n" % h)
    print("xfce-estetica.sh %s (%d líneas) sha256 %s" % (version, plantilla.count("\n"), h[:12]))


if __name__ == "__main__":
    main()
