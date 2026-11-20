#!/usr/bin/env bash
# =============================================================================
#  ubuntu-macos-setup — Transforma Ubuntu (GNOME 46-50) en una interfaz tipo macOS
#  Uso:   ./install.sh            (instala todo)
#         ./install.sh --no-sudo  (omite pasos que requieren contraseña)
# =============================================================================
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${HOME}/.cache/ubuntu-macos-setup"
EXT_DIR="${HOME}/.local/share/gnome-shell/extensions"
NO_SUDO=false
[[ "${1:-}" == "--no-sudo" ]] && NO_SUDO=true

mkdir -p "$SRC_DIR" "$EXT_DIR"
step() { echo -e "\n\033[1;34m==> $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }

clone() { # clone <url> <dir>
  [[ -d "$2/.git" ]] && git -C "$2" pull -q --ff-only || git clone -q --depth 1 "$1" "$2"
}

# -----------------------------------------------------------------------------
step "1. Dependencias"
if ! $NO_SUDO; then
  sudo apt update
  sudo apt install -y git wget unzip python3-pil gnome-tweaks \
    gnome-shell-extensions gnome-shell-extension-manager gnome-sushi
fi

# -----------------------------------------------------------------------------
step "2. Tema WhiteSur (GTK, GNOME Shell, Libadwaita)"
clone https://github.com/vinceliuice/WhiteSur-gtk-theme.git "$SRC_DIR/WhiteSur-gtk-theme"
( cd "$SRC_DIR/WhiteSur-gtk-theme" && \
  ./install.sh -c Dark -c Light -t default -m -N glassy -l --round --shell -i ubuntu )
$NO_SUDO || ( cd "$SRC_DIR/WhiteSur-gtk-theme" && sudo ./tweaks.sh -F ) || true

# Logo blanco personalizado en la esquina superior izquierda
for d in "$HOME"/.themes/WhiteSur*/gnome-shell/assets; do
  [[ -d "$d" ]] || continue
  cp "$REPO_DIR/assets/activities-ubuntu-white.svg" "$d/activities.svg"
  cp "$REPO_DIR/assets/activities-ubuntu-white.svg" "$d/activities-white.svg"
done

# -----------------------------------------------------------------------------
step "3. Iconos y cursores"
clone https://github.com/vinceliuice/WhiteSur-icon-theme.git "$SRC_DIR/WhiteSur-icon-theme"
( cd "$SRC_DIR/WhiteSur-icon-theme" && ./install.sh )
clone https://github.com/vinceliuice/WhiteSur-cursors.git "$SRC_DIR/WhiteSur-cursors"
( cd "$SRC_DIR/WhiteSur-cursors" && ./install.sh )

# -----------------------------------------------------------------------------
step "4. Fondos de pantalla"
clone https://github.com/vinceliuice/WhiteSur-wallpapers.git "$SRC_DIR/WhiteSur-wallpapers"
( cd "$SRC_DIR/WhiteSur-wallpapers" && ./install-wallpapers.sh )

WALL="$HOME/.local/share/backgrounds/macOS-Tahoe.jpg"
mkdir -p "$(dirname "$WALL")" "$HOME/.local/share/gnome-background-properties"
if [[ ! -f "$WALL" ]] && wget -q "https://developer.apple.com/macos/images/screen-macos27-large_2x.jpg" -O /tmp/macos-preview.jpg; then
  python3 - "$WALL" << 'PY'
import sys
from PIL import Image
im = Image.open("/tmp/macos-preview.jpg"); w, h = im.size
im.crop((0, int(h*0.038), w, int(h*0.905))).resize((3840, 2160), Image.Resampling.LANCZOS).save(sys.argv[1], quality=95)
PY
  rm -f /tmp/macos-preview.jpg
fi
[[ -f "$WALL" ]] || WALL="$HOME/.local/share/backgrounds/WhiteSur-dark.jpg"
sed "s|@WALL@|$WALL|g" "$REPO_DIR/assets/macos-tahoe.xml" > "$HOME/.local/share/gnome-background-properties/macos-tahoe.xml"

# -----------------------------------------------------------------------------
step "5. Tipografía San Francisco Pro"
FONT_DIR="$HOME/.local/share/fonts/apple-sf"
mkdir -p "$FONT_DIR"
clone https://github.com/sahibjotsaggu/San-Francisco-Pro-Fonts.git "$SRC_DIR/sf-pro"
cp "$SRC_DIR"/sf-pro/*.otf "$FONT_DIR/"
fc-cache -f "$FONT_DIR" >/dev/null

# -----------------------------------------------------------------------------
step "6. Extensiones de GNOME Shell"
python3 "$REPO_DIR/scripts/install_extensions.py" \
  blur-my-shell@aunetx \
  compiz-alike-magic-lamp-effect@hermes83.github.com \
  just-perfection-desktop@just-perfection \
  CoverflowAltTab@palatis.blogspot.com \
  search-light@icedman.github.com \
  mediacontrols@cliffniff.github.com \
  clipboard-history@alexsaveau.dev \
  window-title-is-back@fthx
# Instalar extensiones locales incluidas en el repositorio
for d in "$REPO_DIR"/extensions/*; do
  [[ -d "$d" ]] || continue
  cp -r "$d" "$EXT_DIR/"
done
bash "$REPO_DIR/scripts/patch_extensions.sh"

# -----------------------------------------------------------------------------
step "7. Ajustes del sistema (gsettings / dconf)"
bash "$REPO_DIR/scripts/apply_settings.sh" "$WALL"

# -----------------------------------------------------------------------------
if ! $NO_SUDO; then
  step "8. Opcionales (Chrome, scrcpy, hibernación, Howdy, login, huella)"
  read -rp "¿Instalar Google Chrome? [s/N] " a
  if [[ "$a" =~ ^[sS]$ ]]; then
    wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /tmp/chrome.deb
    sudo apt install -y /tmp/chrome.deb && rm -f /tmp/chrome.deb
    # Aplicar tema GTK en Chrome para botones de ventana estilo macOS
    mkdir -p "$HOME/.config/google-chrome/Default"
    [[ -f "$HOME/.config/google-chrome/Default/Preferences" ]] || \
      printf '{"extensions":{"theme":{"id":"","system_theme":1}}}' > "$HOME/.config/google-chrome/Default/Preferences"
  fi
  read -rp "¿Instalar scrcpy y adb (control espejo de Android desde la PC)? [s/N] " a
  [[ "$a" =~ ^[sS]$ ]] && sudo apt install -y scrcpy adb
  read -rp "¿Configurar hibernación real al cerrar la tapa (requiere Secure Boot desactivado)? [s/N] " a
  [[ "$a" =~ ^[sS]$ ]] && sudo bash "$REPO_DIR/scripts/setup_hibernate.sh"
  read -rp "¿Instalar Howdy (desbloqueo facial con cámara IR, compila dlib)? [s/N] " a
  [[ "$a" =~ ^[sS]$ ]] && sudo bash "$REPO_DIR/scripts/setup_howdy.sh"
  read -rp "¿Desactivar inicio de sesión automático (pedir contraseña al encender)? [s/N] " a
  [[ "$a" =~ ^[sS]$ ]] && sudo sed -i 's/^AutomaticLoginEnable=true/AutomaticLoginEnable=false/' /etc/gdm3/custom.conf
  if command -v fprintd-enroll >/dev/null && fprintd-list "$USER" 2>/dev/null | grep -q "Device at"; then
    read -rp "Lector de huellas detectado. ¿Registrar huella ahora? [s/N] " a
    if [[ "$a" =~ ^[sS]$ ]]; then
      sudo pam-auth-update --enable fprintd
      echo "Apoya y levanta el dedo índice derecho en el lector varias veces..."
      sudo fprintd-enroll "$USER"
    fi
  fi
fi

echo -e "\n\033[1;32m✔ Listo. Cierra sesión y vuelve a entrar para cargar las extensiones.\033[0m"
