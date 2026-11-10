/* launchpad.rasi (plantilla de genos-fondo, los colores se rellenan solos)
   Lanzador minimalista: buscador arriba y cuadrícula de apps.
   Deja a la vista el panel de arriba y el dock.
   La transparencia necesita el compositor de xfwm4 activado. */

configuration {
    modi: "drun";
    show-icons: true;
    icon-theme: "@@ICONOS@@";
    drun-display-format: "{name}";
    drun-use-desktop-cache: true;
    drun-reload-desktop-cache: false;
    disable-history: false;
    display-drun: "";
    matching: "fuzzy";
    sorting-method: "fzf";
    kb-row-left: "Left";
    kb-row-right: "Right";
    kb-move-char-back: "Control+b";
    kb-move-char-forward: "Control+f";
}

* {
    bg:      @@BG@@;
    bg-soft: @@BGSOFT@@;
    bg-sel:  @@BGSEL@@;
    fg:      @@FG@@;
    fg-dim:  @@FGDIM@@;
    font: "Inter 11";
    background-color: transparent;
    text-color: @fg;
    margin: 0;
    padding: 0;
    spacing: 0;
}

window {
    location: center;
    anchor: center;
    width: 62%;
    height: 72%;
    background-color: @bg;
    border: 1px;
    border-color: @@BORDE@@;
    border-radius: 24px;
}

mainbox {
    padding: 28px;
    spacing: 24px;
    children: [ inputbar, listview ];
}

inputbar {
    padding: 12px 18px;
    background-color: @bg-soft;
    border-radius: 14px;
    children: [ entry ];
}

entry {
    placeholder: "Buscar";
    placeholder-color: @fg-dim;
}

listview {
    columns: 6;
    lines: 4;
    flow: horizontal;
    fixed-columns: true;
    scrollbar: false;
    cycle: false;
    spacing: 12px;
}

element {
    orientation: vertical;
    padding: 16px 6px;
    spacing: 8px;
    border-radius: 16px;
}

element normal.normal, element alternate.normal {
    background-color: transparent;
    text-color: @fg-dim;
}

element selected.normal {
    background-color: @bg-sel;
    text-color: @fg;
}

element-icon {
    size: 56px;
    horizontal-align: 0.5;
    background-color: transparent;
}

element-text {
    horizontal-align: 0.5;
    vertical-align: 0.5;
    font: "Inter 9";
    background-color: transparent;
    text-color: inherit;
}
