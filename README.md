# ubuntu-macos-setup

Convierte una instalación limpia de **Ubuntu con GNOME (46–50)** en un escritorio con aspecto de macOS.

## Instalación en un equipo nuevo

```bash
sudo apt install -y git
git clone https://github.com/fransaav/ubuntu-macos-setup.git
cd ubuntu-macos-setup
./install.sh
```

Después, **cierra sesión y vuelve a entrar** (o **reinicia** si activaste la hibernación).
Usa `./install.sh --no-sudo` si no tienes permisos de administrador.

## Qué incluye

| Área | Detalle |
| --- | --- |
| Tema | WhiteSur Dark (GTK3/GTK4/Libadwaita/GNOME Shell), estilo Monterey, Nautilus *glassy*, tema **GTK** en Google Chrome y PWAs para botones semáforo |
| Panel | Logo blanco personalizado, reloj a la derecha de los indicadores, widget multimedia |
| Dock | Abajo, centrado, Launchpad a la izquierda, iconos de 46 px |
| Iconos / cursores | WhiteSur icons + WhiteSur cursors |
| Tipografía | SF Pro Text / SF Pro Display |
| Fondos | macOS Tahoe (4K) + colección WhiteSur (Sonoma, Ventura, Monterey) |
| Extensiones | Blur my Shell, Magic Lamp, Just Perfection, Coverflow Alt-Tab, Search Light, Media Controls, **Clipboard History** |
| Atajos | `Super+Espacio` Spotlight · `Super+V` historial del portapapeles (con pegado directo) · `Ctrl+Shift+Esc` Monitor de recursos · `Super+E` Archivos · `Espacio` Quick Look · `Ctrl` localizar puntero · `Super+Shift+S` captura |
| Terminal | Ptyxis con paleta *Pro* (negro) |
| Opcionales | Google Chrome (con tema GTK), **hibernación real al cerrar la tapa** (`setup_hibernate.sh`), pedir contraseña al iniciar, registro de huella digital |

## Estructura

```
install.sh                     Instalador principal
scripts/install_extensions.py  Descarga extensiones para tu versión de GNOME
scripts/patch_extensions.sh    Parches de compatibilidad con GNOME 50
scripts/apply_settings.sh      Todos los gsettings / dconf y tema GTK en Chrome
scripts/export_settings.sh     Re-exporta tus ajustes actuales al repo
scripts/setup_hibernate.sh     Configura swap, GRUB, dracut/initramfs, Polkit y logind para hibernar al cerrar la tapa
dconf/*.ini                    Configuración de cada extensión
assets/                        Logo del panel y definición del fondo
```

## Notas útiles

- **Botones de ventana en Chrome y apps web (PWAs):** `apply_settings.sh` activa el tema GTK (`system_theme: 1`) si Chrome está cerrado. Si Chrome ya estaba abierto, actívalo manualmente en `chrome://settings/appearance` → **Tema** → **Usar GTK**.
- **Hibernación al cerrar la tapa:** requiere **Secure Boot desactivado** y partición raíz en `ext4`. Puedes ejecutarla por separado en cualquier momento con `sudo ./scripts/setup_hibernate.sh` y luego **reiniciar**. Con monitor externo conectado (`HandleLidSwitchDocked=ignore`), el equipo permanece encendido al cerrar la tapa.
- **Huella digital y depósito de claves (Keyring):** al iniciar sesión con huella en GDM, GNOME Keyring queda bloqueado y apps como Chrome o Antigravity pedirán la contraseña una vez. Si inicias sesión con contraseña al encender y luego usas **hibernación**, el depósito se mantiene desbloqueado al despertar y podrás desbloquear la pantalla y usar `sudo` solo con la huella.

## Actualizar el repo con nuevos cambios

```bash
./scripts/export_settings.sh
git add -A && git commit -m "Actualizar ajustes" && git push
```

## Nota legal

El repositorio **no** redistribuye fuentes ni fondos de Apple: se descargan durante la instalación desde sus fuentes originales.
Los temas WhiteSur pertenecen a [vinceliuice](https://github.com/vinceliuice).
