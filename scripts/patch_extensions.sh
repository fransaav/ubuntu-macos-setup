#!/usr/bin/env bash
# Parches de compatibilidad con GNOME Shell 50 (inofensivos en versiones anteriores)
EXT="$HOME/.local/share/gnome-shell/extensions"

# Search Light: 'affectsInputRegion' fue eliminado de addChrome() en GNOME 50
SL="$EXT/search-light@icedman.github.com/extension.js"
[[ -f "$SL" ]] && sed -i '/affectsInputRegion: true,/d' "$SL"

# Just Perfection: permitir colocar el reloj al final de la caja derecha
JP="$EXT/just-perfection-desktop@just-perfection/lib/API.js"
[[ -f "$JP" ]] && sed -i 's/childLength = panelBoxes\[pos\].get_children().length;/childLength = panelBoxes[pos].get_children().length - ((pos === i) ? 1 : 0);/' "$JP"

# Window Title Is Back: colocar el nombre de la app a la izquierda de Lugares (índice 1) y en negrita estilo macOS
WT="$EXT/window-title-is-back@fthx/extension.js"
if [[ -f "$WT" ]]; then
  python3 - "$WT" << 'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

# Nombre de la aplicación en negrita (como en macOS / AppMenuButton de WhiteSur)
old_app = "this._app = new St.Label({ y_align: Clutter.ActorAlign.CENTER });"
new_app = "this._app = new St.Label({ y_align: Clutter.ActorAlign.CENTER, style: 'font-weight: bold;' });"
if old_app in s:
    s = s.replace(old_app, new_app, 1)

# Insertar en índice 1 (entre el logo y Lugares) y mantener esa posición si Lugares carga después
old_add = "Main.panel.addToStatusArea('focused-window-indicator', this._indicator, -1, 'left');"
new_add = """Main.panel.addToStatusArea('focused-window-indicator', this._indicator, 1, 'left');
        Main.panel._leftBox.connectObject('child-added', () => {
            const c = this._indicator?.container;
            if (c && Main.panel._leftBox.get_children().indexOf(c) > 1)
                Main.panel._leftBox.set_child_at_index(c, 1);
        }, this);"""
if old_add in s:
    s = s.replace(old_add, new_add, 1)

old_dis = "        this._settings.disconnectObject(this);"
new_dis = "        Main.panel._leftBox.disconnectObject(this);\n        this._settings.disconnectObject(this);"
if "Main.panel._leftBox.disconnectObject(this);" not in s and old_dis in s:
    s = s.replace(old_dis, new_dis, 1)

p.write_text(s, encoding="utf-8")
PY
fi

echo "  ✔ Parches aplicados"
