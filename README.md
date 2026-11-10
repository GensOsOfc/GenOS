# GenOS

Escritorio minimalista sobre XFCE para Debian en WSL2 con xrdp. Barra superior en pastillas, dock con zoom, lanzador en cuadrícula, fondos que cambian el tema solos, widgets, Centro de control y una app de Configuración que reemplaza al Gestor de ajustes de XFCE. En español, inglés y portugués.

## Instalar

```
curl -fsSLO https://raw.githubusercontent.com/GensOsOfc/GenOS/main/xfce-estetica.sh
```
```
bash xfce-estetica.sh
```

Después cierra sesión y vuelve a entrar.

## Actualizar

GenOS revisa una vez al día al entrar y avisa con una notificación. También puedes hacerlo a mano:

```
genos-actualizar
```
```
genos-actualizar --instalar
```

La actualización conserva tu personalización (fondo, colores, barra, dock, atajos y terminal) y antes guarda un respaldo en `~/.local/share/genos/respaldos`. Para volver a él:

```
genos-actualizar --revertir
```

## Publicar una versión nueva

1. Cambia lo que necesites en `src/`.
2. Sube el número en `VERSION` y escribe qué cambió arriba de todo en `CHANGELOG.md`, con el formato `## 1.3 (fecha)`.
3. Construye y prueba:
   ```
   python3 herramientas/construir.py
   ```
   ```
   bash pruebas/probar.sh
   ```
4. Sube los cambios (`git commit` y `git push`). Los equipos con GenOS ven el aviso al día siguiente.

`xfce-estetica.sh` y `xfce-estetica.sh.sha256` se generan con el constructor; no se editan a mano.

## Estructura

- `src/estetica.main.tpl`: el instalador, con huecos `@@NOMBRE@@` donde entra cada programa.
- `src/genos-*.py` y `src/genos-*.sh`: Configuración, fondos, widgets, Centro de control, barra, exportar y actualizar.
- `src/traducciones/`: textos en inglés y portugués.
- `herramientas/construir.py`: arma `xfce-estetica.sh`.
- `pruebas/probar.sh`: revisa sintaxis y simula una actualización completa.

## Créditos

Proyecto de Duvan Esteban Chaparro Castro, con la ayuda de Claude, de Anthropic. Usa Debian, XFCE, Plank, Rofi, xrdp y el tema WhiteSur de vinceliuice, que se descargan de sus repos oficiales y conservan su licencia.
