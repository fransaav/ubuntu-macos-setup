#!/usr/bin/env bash
# =============================================================================
#  Configura hibernación real (suspend-to-disk) al cerrar la tapa en Ubuntu
#  Uso: sudo ./scripts/setup_hibernate.sh
# =============================================================================
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Ejecuta este script con sudo: sudo $0" >&2
  exit 1
fi

SWAPFILE="/swap.img"

# 1. Comprobar Secure Boot / kernel lockdown
if [[ -r /sys/kernel/security/lockdown ]] && ! grep -q '\[none\]' /sys/kernel/security/lockdown; then
  echo "[!] Kernel lockdown activo ($(cat /sys/kernel/security/lockdown))." >&2
  echo "    Desactiva Secure Boot en la BIOS/UEFI para poder hibernar." >&2
  exit 1
fi

if ! grep -qw disk /sys/power/state 2>/dev/null; then
  echo "[!] El kernel no reporta soporte para hibernación ('disk' ausente en /sys/power/state)." >&2
  exit 1
fi

# 2. Comprobar sistema de archivos raíz
ROOT_FS="$(findmnt -no FSTYPE /)"
ROOT_UUID="$(findmnt -no UUID /)"
if [[ "$ROOT_FS" != "ext4" ]]; then
  echo "[!] Este script soporta swapfile sobre ext4 (detectado: $ROOT_FS)." >&2
  exit 1
fi
if [[ -z "$ROOT_UUID" ]]; then
  echo "[!] No se pudo detectar el UUID de la partición raíz." >&2
  exit 1
fi

# 3. Calcular tamaño de swap necesario (>= RAM + margen)
RAM_MIB="$(awk '/^MemTotal:/ {printf "%d", ($2 + 1023) / 1024}' /proc/meminfo)"
SWAP_GIB="$(( ((RAM_MIB + 1024 + 2047) / 2048) * 2 ))"
SWAP_MIB="$(( SWAP_GIB * 1024 ))"

CUR_SWAP_MIB=0
if [[ -f "$SWAPFILE" ]]; then
  CUR_SWAP_MIB="$(( $(stat -c%s "$SWAPFILE") / 1048576 ))"
fi

echo "==> RAM detectada: ${RAM_MIB} MiB · Swap actual: ${CUR_SWAP_MIB} MiB · Swap objetivo: ${SWAP_GIB} GiB"

if (( CUR_SWAP_MIB < SWAP_MIB )); then
  AVAIL_MIB="$(df -Pm / | awk 'NR==2 {print $4}')"
  if (( AVAIL_MIB + CUR_SWAP_MIB < SWAP_MIB + 4096 )); then
    echo "[!] Espacio insuficiente en / para crear swapfile de ${SWAP_GIB} GiB." >&2
    exit 1
  fi

  echo "==> Redimensionando ${SWAPFILE} a ${SWAP_GIB} GiB (puede tardar unos segundos)..."
  swapoff "$SWAPFILE" 2>/dev/null || true
  rm -f "$SWAPFILE"
  dd if=/dev/zero of="$SWAPFILE" bs=1M count="$SWAP_MIB" status=progress
  chmod 600 "$SWAPFILE"
  mkswap "$SWAPFILE"
  swapon "$SWAPFILE"
else
  echo "==> ${SWAPFILE} ya tiene tamaño suficiente (${CUR_SWAP_MIB} MiB)."
  swapon "$SWAPFILE" 2>/dev/null || true
fi

# Asegurar entrada en /etc/fstab
if ! grep -qE "^[[:space:]]*${SWAPFILE}[[:space:]]" /etc/fstab; then
  printf '%s\tnone\tswap\tsw\t0\t0\n' "$SWAPFILE" >> /etc/fstab
fi

# 4. Obtener offset físico del swapfile
OFFSET="$(filefrag -v "$SWAPFILE" | awk '$1=="0:" {gsub(/\.\.*/,"",$4); print $4}')"
if [[ ! "$OFFSET" =~ ^[0-9]+$ ]]; then
  echo "[!] No se pudo obtener resume_offset de ${SWAPFILE} (obtenido: '${OFFSET}')." >&2
  exit 1
fi
echo "==> Root UUID: ${ROOT_UUID} · resume_offset: ${OFFSET}"

# 5. Configurar GRUB (drop-in en /etc/default/grub.d/)
echo "==> Configurando GRUB..."
mkdir -p /etc/default/grub.d
cat > /etc/default/grub.d/99-hibernate.cfg <<EOF
GRUB_CMDLINE_LINUX_DEFAULT="\$GRUB_CMDLINE_LINUX_DEFAULT resume=UUID=${ROOT_UUID} resume_offset=${OFFSET}"
EOF
update-grub

# 6. Configurar initramfs (dracut en Ubuntu 26.04 / initramfs-tools en Ubuntu 24.04)
echo "==> Actualizando initramfs..."
if command -v dracut >/dev/null 2>&1; then
  mkdir -p /etc/dracut.conf.d
  cat > /etc/dracut.conf.d/99-resume.conf <<'EOF'
add_dracutmodules+=" resume "
EOF
fi
if [[ -d /etc/initramfs-tools/conf.d ]]; then
  cat > /etc/initramfs-tools/conf.d/resume <<EOF
RESUME=UUID=${ROOT_UUID}
EOF
fi

if command -v update-initramfs >/dev/null 2>&1; then
  update-initramfs -u -k all
elif command -v dracut >/dev/null 2>&1; then
  dracut --regenerate-all --force
fi

# 7. Habilitar permiso de hibernación en Polkit (Ubuntu lo bloquea por defecto)
echo "==> Habilitando hibernación en Polkit..."
mkdir -p /etc/polkit-1/rules.d
cat > /etc/polkit-1/rules.d/10-enable-hibernate.rules <<'EOF'
// Permite hibernar al usuario local activo (anula el bloqueo por defecto de Ubuntu)
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.login1.hibernate" ||
         action.id == "org.freedesktop.login1.hibernate-multiple-sessions" ||
         action.id == "org.freedesktop.upower.hibernate" ||
         action.id == "org.freedesktop.login1.handle-hibernate-key") &&
        subject.active && subject.local) {
        return polkit.Result.YES;
    }
});
EOF

# 8. Configurar systemd-logind para hibernar al cerrar la tapa
echo "==> Configurando systemd-logind para hibernar al cerrar la tapa..."
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/99-lid-hibernate.conf <<'EOF'
[Login]
HandleLidSwitch=hibernate
HandleLidSwitchExternalPower=hibernate
HandleLidSwitchDocked=ignore
EOF

# 9. Configurar acción al cerrar la tapa en GNOME para el usuario actual
if [[ -n "${SUDO_USER:-}" ]]; then
  SUDO_UID_NUM="$(id -u "$SUDO_USER")"
  if [[ -S "/run/user/${SUDO_UID_NUM}/bus" ]]; then
    sudo -u "$SUDO_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${SUDO_UID_NUM}/bus" \
      gsettings set org.gnome.settings-daemon.plugins.power lid-close-ac-action 'hibernate' 2>/dev/null || true
    sudo -u "$SUDO_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${SUDO_UID_NUM}/bus" \
      gsettings set org.gnome.settings-daemon.plugins.power lid-close-battery-action 'hibernate' 2>/dev/null || true
  fi
fi

echo ""
echo "✔ Hibernación configurada correctamente."
echo "  Reinicia el equipo para activar resume/resume_offset en el kernel."
echo "  Tras reiniciar, puedes probar con: systemctl hibernate"
