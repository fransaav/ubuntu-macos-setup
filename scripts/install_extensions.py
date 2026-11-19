#!/usr/bin/env python3
"""Descarga extensiones desde extensions.gnome.org para la versión de GNOME Shell instalada."""
import io, json, os, subprocess, sys, urllib.request, zipfile

ext_dir = os.path.expanduser("~/.local/share/gnome-shell/extensions")
os.makedirs(ext_dir, exist_ok=True)

try:
    major = subprocess.check_output(["gnome-shell", "--version"]).decode().split()[2].split(".")[0]
except Exception:
    major = "50"
candidates = [str(v) for v in range(int(major), int(major) - 4, -1)]

for uuid in sys.argv[1:]:
    ok = False
    for sv in candidates:
        try:
            info = json.loads(urllib.request.urlopen(
                f"https://extensions.gnome.org/extension-info/?uuid={uuid}&shell_version={sv}", timeout=15).read())
            if "download_url" not in info:
                continue
            data = urllib.request.urlopen("https://extensions.gnome.org" + info["download_url"], timeout=30).read()
            target = os.path.join(ext_dir, uuid)
            os.makedirs(target, exist_ok=True)
            zipfile.ZipFile(io.BytesIO(data)).extractall(target)
            meta = os.path.join(target, "metadata.json")
            m = json.load(open(meta))
            if major not in m.get("shell-version", []):
                m.setdefault("shell-version", []).append(major)
                json.dump(m, open(meta, "w"), indent=2)
            schemas = os.path.join(target, "schemas")
            if os.path.isdir(schemas):
                subprocess.run(["glib-compile-schemas", schemas], check=False)
            print(f"  ✔ {uuid} (build para GNOME {sv})")
            ok = True
            break
        except Exception:
            continue
    if not ok:
        print(f"  ✘ {uuid}: no se encontró versión compatible")
