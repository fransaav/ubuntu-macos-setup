#!/usr/bin/env bash
# =============================================================================
#  Instala y configura Howdy 3 (desbloqueo facial tipo Windows Hello) en Ubuntu
#  Compatible con Ubuntu 24.04–26.04 (PEP 668 / Python 3.12–3.14) y cámaras IR
#  Uso: sudo ./scripts/setup_howdy.sh
# =============================================================================
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Ejecuta este script con sudo: sudo $0" >&2
  exit 1
fi

TARGET_USER="${SUDO_USER:-}"
VENV_DIR="/usr/local/lib/howdy-venv"
BUILD_SRC="/tmp/howdy-build"
DLIB_DATA_DIR="/usr/local/share/dlib-data"
ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
  amd64) MULTIARCH="x86_64-linux-gnu" ;;
  arm64) MULTIARCH="aarch64-linux-gnu" ;;
  *)     MULTIARCH="$(gcc -dumpmachine 2>/dev/null || echo x86_64-linux-gnu)" ;;
esac
PAM_DIR="/usr/lib/${MULTIARCH}/security"

step() { echo -e "\n\033[1;34m==> $*\033[0m"; }

# 1. Dependencias de compilación y ejecución
step "1. Instalando dependencias del sistema"
apt-get update
apt-get install -y \
  git wget bzip2 gettext build-essential cmake pkg-config meson ninja-build \
  python3-dev python3-venv python3-pip python3-numpy python3-opencv \
  libpam0g-dev libinih-dev libevdev-dev libopenblas-dev v4l-utils

# 2. Entorno virtual Python propio (evita conflictos con PEP 668 / Python 3.14)
step "2. Preparando entorno Python (${VENV_DIR}) e instalando dlib"
if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
  python3 -m venv --system-site-packages "$VENV_DIR"
fi
"${VENV_DIR}/bin/pip" install --upgrade pip setuptools wheel
if ! "${VENV_DIR}/bin/python" -c "import dlib" >/dev/null 2>&1; then
  echo "  Compilando/instalando dlib (puede tardar 2-5 minutos la primera vez)..."
  "${VENV_DIR}/bin/pip" install dlib
fi

# 3. Clonar, compilar e instalar Howdy 3 con Meson
step "3. Compilando e instalando Howdy desde GitHub"
rm -rf "$BUILD_SRC"
git clone --depth 1 https://github.com/boltgolt/howdy.git "$BUILD_SRC"
(
  cd "$BUILD_SRC/howdy"
  meson setup build \
    --prefix=/usr/local \
    -Dpython_path="${VENV_DIR}/bin/python" \
    -Dconfig_dir=/etc/howdy \
    -Ddlib_data_dir="$DLIB_DATA_DIR" \
    -Dpam_dir="$PAM_DIR" \
    -Dinstall_pam_config=true
  ninja -C build
  ninja -C build install
)
rm -rf "$BUILD_SRC"

# Asegurar que pam-auth-update encuentre la definición de PAM en /usr/share/pam-configs
if [[ -f /usr/local/share/pam-configs/howdy && ! -f /usr/share/pam-configs/howdy ]]; then
  mkdir -p /usr/share/pam-configs
  cp /usr/local/share/pam-configs/howdy /usr/share/pam-configs/howdy
fi

# 4. Descargar modelos de reconocimiento facial de dlib
step "4. Descargando modelos faciales de dlib"
mkdir -p "$DLIB_DATA_DIR"
if [[ ! -f "${DLIB_DATA_DIR}/dlib_face_recognition_resnet_model_v1.dat" ]]; then
  ( cd "$DLIB_DATA_DIR" && bash ./install.sh )
else
  echo "  Modelos ya descargados en ${DLIB_DATA_DIR}"
fi

# 5. Detectar automáticamente la cámara infrarroja (GREY) o cámara RGB
step "5. Detectando cámara IR y configurando /etc/howdy/config.ini"
CAM_PATH="$(python3 - << 'PY'
import fcntl, glob, os, struct

VIDIOC_ENUM_FMT = 0xC0405602
ir_dev = None
rgb_dev = None

for dev in sorted(glob.glob("/dev/video*")):
    try:
        fd = os.open(dev, os.O_RDONLY)
    except OSError:
        continue
    fmts = []
    i = 0
    while True:
        buf = bytearray(64)
        struct.pack_into("<II", buf, 0, i, 1)
        try:
            fcntl.ioctl(fd, VIDIOC_ENUM_FMT, buf)
        except OSError:
            break
        fmts.append(bytes(buf[44:48]).decode(errors="ignore"))
        i += 1
    os.close(fd)
    if not fmts:
        continue
    if any(f in ("GREY", "Y16 ", "Y10 ", "Y12 ") for f in fmts) and ir_dev is None:
        ir_dev = dev
    elif rgb_dev is None:
        rgb_dev = dev

chosen = ir_dev or rgb_dev
if not chosen:
    raise SystemExit(0)

# Preferir ruta estable en /dev/v4l/by-path/
real_chosen = os.path.realpath(chosen)
for link in sorted(glob.glob("/dev/v4l/by-path/*")):
    if os.path.realpath(link) == real_chosen and "usbv2" not in link:
        print(link)
        raise SystemExit(0)
print(chosen)
PY
)"

if [[ -n "$CAM_PATH" && -f /etc/howdy/config.ini ]]; then
  sed -i "s|^device_path = .*|device_path = ${CAM_PATH}|" /etc/howdy/config.ini
  echo "  ✔ Cámara configurada: ${CAM_PATH}"
else
  echo "  [!] No se detectó cámara automáticamente. Configúrala con: sudo howdy config"
fi

# 6. Activar Howdy en PAM
step "6. Activando módulo Howdy en PAM"
if [[ -f /usr/share/pam-configs/howdy ]]; then
  pam-auth-update --enable howdy
else
  echo "  [!] No se encontró /usr/share/pam-configs/howdy; actívalo manualmente si es necesario."
fi

# 7. Registrar rostro del usuario
if [[ -n "$TARGET_USER" ]]; then
  echo ""
  read -rp "¿Registrar tu rostro ahora para el usuario '${TARGET_USER}'? [S/n] " a
  if [[ ! "$a" =~ ^[nN]$ ]]; then
    echo "Mira directamente a la cámara..."
    howdy -U "$TARGET_USER" add || true
  fi
fi

echo ""
echo "✔ Howdy instalado y configurado."
echo "  Comandos útiles:"
echo "    sudo howdy test          # probar detección en vivo"
echo "    sudo howdy add           # registrar otro ángulo/iluminación"
echo "    sudo howdy config        # ajustar cámara o sensibilidad"
echo "    sudo pam-auth-update --remove howdy   # desactivar PAM si lo necesitas"
