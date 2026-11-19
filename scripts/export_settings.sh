#!/usr/bin/env bash
# Vuelve a exportar los ajustes actuales de las extensiones al repositorio.
# Úsalo después de cambiar algo en tu equipo, y luego haz commit + push.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for p in blur-my-shell dash-to-dock just-perfection search-light mediacontrols; do
  dconf dump "/org/gnome/shell/extensions/$p/" > "$REPO_DIR/dconf/$p.ini"
  echo "  ✔ dconf/$p.ini"
done
