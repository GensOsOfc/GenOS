# Lista de cambios de GenOS

Cada versión empieza con `## número (fecha)`. El actualizador muestra las secciones más nuevas que la versión instalada.

## 1.2.1 (2026-11-10)
- Créditos: autor GenOsDev y enlaces a sus redes (YouTube, GitHub, Telegram y TikTok).
- El instalador muestra las redes al terminar.
- Compilar en Windows ya no deja el instalador con CRLF. Los `.sh` llevan bit de ejecución.
- Los mensajes ya no repiten el número de versión.

## 1.2 (2026-11-10)
- Actualizaciones desde GitHub: GenOS revisa una vez al día al entrar y avisa con una notificación cuando hay versión nueva.
- La actualización conserva tu fondo, colores, barra, dock, atajos y terminal. Antes de instalar guarda un respaldo.
- Nuevo comando `genos-actualizar` con `--cambios`, `--instalar`, `--historial` y `--revertir`.
- Configuración > Sistema trae la sección Actualizaciones: buscar, lista de cambios, historial y volver al respaldo.
- Aplicar ya no falla cuando xfce4-notifyd guarda la posición de las burbujas como texto (`top-right`).
- El tema GTK se aplica primero y ya no lo pisan los ajustes sueltos. También se guarda en `settings.ini` y gsettings.
- Acerca de GenOS usa el emblema de los wallpapers (hexágono y G) y muestra menos texto.

## 1.1 (2026-11-08)
- Configuración reemplaza al Gestor de ajustes de XFCE, con todas sus secciones.
- Créditos en Acerca de GenOS.
- Traducción al inglés y al portugués; el idioma se elige en Configuración > Sistema.

## 1.0 (2026-11-01)
- Primera versión: barra en pastillas, dock con zoom, lanzador en cuadrícula, 30 fondos con tema automático, notificaciones, widgets y Centro de control.
