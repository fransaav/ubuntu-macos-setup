# ahora puedo hacer cambios
# ubuntu-macos-setup

Convierte una instalación limpia de **Ubuntu con GNOME (46–50)** en un escritorio con aspecto de macOS.

## Instalación en un equipo nuevo

```bash
sudo apt install -y git
git clone https://github.com/fransaav/ubuntu-macos-setup.git
cd ubuntu-macos-setup
./install.sh
```

Después, **cierra sesión y vuelve a entrar**.
Usa `./install.sh --no-sudo` si no tienes permisos de administrador.

## Qué incluye

| Área | Detalle |
| --- | --- |
| Tema | WhiteSur Dark (GTK3/GTK4/Libadwaita/GNOME Shell), estilo Monterey, Nautilus *glassy* |
| Panel | Logo blanco personalizado, reloj a la derecha de los indicadores, widget multimedia |
| Dock | Abajo, centrado, Launchpad a la izquierda, iconos de 46 px |
| Iconos / cursores | WhiteSur icons + WhiteSur cursors |
| Tipografía | SF Pro Text / SF Pro Display |
| Fondos | macOS Tahoe (4K) + colección WhiteSur (Sonoma, Ventura, Monterey) |
| Extensiones | Blur my Shell, Magic Lamp, Just Perfection, Coverflow Alt-Tab, Search Light, Media Controls |
| Atajos | `Super+Espacio` Spotlight · `Super+E` Archivos · `Espacio` Quick Look · `Ctrl` localizar puntero · `Super+Shift+S` captura |
| Terminal | Ptyxis con paleta *Pro* (negro) |
| Opcionales | Google Chrome, pedir contraseña al iniciar, registro de huella digital |

## Estructura

```
install.sh                  Instalador principal
scripts/install_extensions.py  Descarga extensiones para tu versión de GNOME
scripts/patch_extensions.sh    Parches de compatibilidad con GNOME 50
scripts/apply_settings.sh      Todos los gsettings / dconf
scripts/export_settings.sh     Re-exporta tus ajustes actuales al repo
dconf/*.ini                    Configuración de cada extensión
assets/                        Logo del panel y definición del fondo
```

## Actualizar el repo con nuevos cambios

```bash
./scripts/export_settings.sh
git add -A && git commit -m "Actualizar ajustes" && git push
```

## Nota legal

El repositorio **no** redistribuye fuentes ni fondos de Apple: se descargan durante la instalación desde sus fuentes originales.
Los temas WhiteSur pertenecen a [vinceliuice](https://github.com/vinceliuice).
