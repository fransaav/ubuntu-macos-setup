#!/usr/bin/env bash
# Parches de compatibilidad con GNOME Shell 50 (inofensivos en versiones anteriores)
EXT="$HOME/.local/share/gnome-shell/extensions"

# Search Light: 'affectsInputRegion' fue eliminado de addChrome() en GNOME 50
SL="$EXT/search-light@icedman.github.com/extension.js"
[[ -f "$SL" ]] && sed -i '/affectsInputRegion: true,/d' "$SL"

# Just Perfection: permitir colocar el reloj al final de la caja derecha
JP="$EXT/just-perfection-desktop@just-perfection/lib/API.js"
[[ -f "$JP" ]] && sed -i 's/childLength = panelBoxes\[pos\].get_children().length;/childLength = panelBoxes[pos].get_children().length - ((pos === i) ? 1 : 0);/' "$JP"

echo "  ✔ Parches aplicados"
