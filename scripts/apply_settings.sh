#!/usr/bin/env bash
# Aplica todos los ajustes gsettings/dconf. Uso: apply_settings.sh <ruta_fondo>
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WALL="${1:-$HOME/.local/share/backgrounds/macOS-Tahoe.jpg}"
g() { gsettings set "$@" 2>/dev/null || echo "  (omitido: $1 $2)"; }

# --- Apariencia ---
g org.gnome.shell disable-extension-version-validation true
g org.gnome.desktop.interface color-scheme 'prefer-dark'
g org.gnome.desktop.interface gtk-theme 'WhiteSur-Dark'
g org.gnome.shell.extensions.user-theme name 'WhiteSur-Dark'
g org.gnome.desktop.interface icon-theme 'WhiteSur-dark'
g org.gnome.desktop.interface cursor-theme 'WhiteSur-cursors'
g org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:'
g org.gnome.desktop.interface font-name 'SF Pro Text 11'
g org.gnome.desktop.interface document-font-name 'SF Pro Text 11'
g org.gnome.desktop.wm.preferences titlebar-font 'SF Pro Display Bold 11'

# --- Fondo ---
g org.gnome.desktop.background picture-uri "file://$WALL"
g org.gnome.desktop.background picture-uri-dark "file://$WALL"
g org.gnome.desktop.background picture-options 'zoom'
g org.gnome.desktop.screensaver picture-uri "file://$WALL"

# --- Reloj ---
g org.gnome.desktop.interface clock-show-weekday true
g org.gnome.desktop.interface clock-show-date true
g org.gnome.desktop.interface clock-format '12h'

# --- Atajos y productividad ---
g org.gnome.settings-daemon.plugins.media-keys home "['<Super>e']"          # Super+E = Archivos
g org.gnome.desktop.interface locate-pointer true                          # Ctrl = localizar puntero
g org.gnome.shell.keybindings show-screenshot-ui "['<Super><Shift>s']"
g org.gnome.desktop.wm.keybindings switch-input-source "['XF86Keyboard']"  # libera Super+Espacio
g org.gnome.desktop.wm.keybindings switch-input-source-backward "['<Shift>XF86Keyboard']"
g org.freedesktop.ibus.general.hotkey triggers "['<Control><Shift>space']"

# --- Rendimiento ---
g org.freedesktop.Tracker3.Miner.Files index-on-battery false
g org.freedesktop.Tracker3.Miner.Files throttle 5

# --- Terminal Ptyxis negra ---
if gsettings get org.gnome.Ptyxis default-profile-uuid >/dev/null 2>&1; then
  P=$(gsettings get org.gnome.Ptyxis default-profile-uuid | tr -d "'")
  g "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$P/" palette 'Pro'
  g "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$P/" opacity 0.94
fi

# --- Ajustes de extensiones (exportados con dconf dump) ---
for f in "$REPO_DIR"/dconf/*.ini; do
  name=$(basename "$f" .ini)
  dconf load "/org/gnome/shell/extensions/$name/" < "$f"
done

# --- Activar extensiones ---
python3 - << 'PY'
import ast, subprocess
want = ["user-theme@gnome-shell-extensions.gcampax.github.com",
        "places-menu@gnome-shell-extensions.gcampax.github.com",
        "blur-my-shell@aunetx", "compiz-alike-magic-lamp-effect@hermes83.github.com",
        "just-perfection-desktop@just-perfection", "CoverflowAltTab@palatis.blogspot.com",
        "search-light@icedman.github.com", "mediacontrols@cliffniff.github.com"]
cur = subprocess.check_output(["gsettings", "get", "org.gnome.shell", "enabled-extensions"]).decode().strip()
exts = ast.literal_eval(cur.replace("@as ", "")) if "[" in cur else []
exts += [e for e in want if e not in exts]
subprocess.run(["gsettings", "set", "org.gnome.shell", "enabled-extensions", str(exts)])
PY
echo "  ✔ Ajustes aplicados"
