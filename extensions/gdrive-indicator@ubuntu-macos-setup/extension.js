import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Soup from 'gi://Soup?version=3.0';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';

const RC_BASE = 'http://127.0.0.1:5572';
const POLL_SECONDS = 5;

function formatSpeed(bytesPerSec) {
    if (!bytesPerSec || bytesPerSec <= 0)
        return '';
    if (bytesPerSec >= 1048576)
        return `${(bytesPerSec / 1048576).toFixed(1)} MB/s`;
    if (bytesPerSec >= 1024)
        return `${(bytesPerSec / 1024).toFixed(0)} KB/s`;
    return `${Math.round(bytesPerSec)} B/s`;
}

const GDriveIndicator = GObject.registerClass(
class GDriveIndicator extends PanelMenu.Button {
    _init() {
        super._init(0.5, 'Google Drive');

        this._session = new Soup.Session({ timeout: 2 });
        this._pollId = 0;
        this._destroyed = false;

        this._box = new St.BoxLayout({ style_class: 'panel-status-menu-box' });
        this._icon = new St.Icon({
            icon_name: 'folder-owncloud-symbolic',
            fallback_icon_name: 'weather-overcast-symbolic',
            style_class: 'system-status-icon',
        });
        this._panelLabel = new St.Label({
            text: '',
            y_align: Clutter.ActorAlign.CENTER,
            visible: false,
        });
        this._box.add_child(this._icon);
        this._box.add_child(this._panelLabel);
        this.add_child(this._box);

        this._buildMenu();

        this.menu.connect('open-state-changed', (_menu, isOpen) => {
            if (isOpen) {
                this._poll();
                this._updateCacheSize();
            }
        });

        this._poll();
        this._pollId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, POLL_SECONDS, () => {
            this._poll();
            return GLib.SOURCE_CONTINUE;
        });
    }

    _buildMenu() {
        this._statusItem = new PopupMenu.PopupMenuItem('Estado: Comprobando…', { reactive: false });
        this.menu.addMenuItem(this._statusItem);

        this._transferItem = new PopupMenu.PopupMenuItem('', { reactive: false });
        this._transferItem.visible = false;
        this.menu.addMenuItem(this._transferItem);

        this._cacheItem = new PopupMenu.PopupMenuItem('Caché local: — / 10 GiB', { reactive: false });
        this.menu.addMenuItem(this._cacheItem);

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        const openItem = new PopupMenu.PopupMenuItem('Abrir carpeta Google Drive');
        openItem.connect('activate', () => this._openFolder());
        this.menu.addMenuItem(openItem);

        const refreshItem = new PopupMenu.PopupMenuItem('Refrescar carpetas ahora');
        refreshItem.connect('activate', () => this._triggerRefresh());
        this.menu.addMenuItem(refreshItem);

        const restartItem = new PopupMenu.PopupMenuItem('Reiniciar montaje');
        restartItem.connect('activate', () => this._restartService());
        this.menu.addMenuItem(restartItem);
    }

    _postJson(path, bodyObj, callback) {
        if (this._destroyed || !this._session)
            return;
        const msg = Soup.Message.new('POST', `${RC_BASE}${path}`);
        if (bodyObj) {
            const bytes = new GLib.Bytes(new TextEncoder().encode(JSON.stringify(bodyObj)));
            msg.set_request_body_from_bytes('application/json', bytes);
        }
        this._session.send_and_read_async(msg, GLib.PRIORITY_DEFAULT, null, (sess, res) => {
            if (this._destroyed)
                return;
            try {
                const data = sess.send_and_read_finish(res);
                if (msg.get_status() !== Soup.Status.OK) {
                    callback(false, null);
                    return;
                }
                const text = new TextDecoder().decode(data.get_data());
                callback(true, JSON.parse(text));
            } catch (_e) {
                callback(false, null);
            }
        });
    }

    _poll() {
        this._postJson('/core/stats', null, (ok, stats) => {
            if (this._destroyed)
                return;
            if (!ok || !stats) {
                this._icon.opacity = 110;
                this._panelLabel.visible = false;
                this._statusItem.label.text = 'Estado: Desconectado';
                this._transferItem.visible = false;
                return;
            }

            this._icon.opacity = 255;
            const transferring = Array.isArray(stats.transferring) ? stats.transferring : [];
            const speed = formatSpeed(stats.speed);

            if (transferring.length > 0) {
                const first = transferring[0];
                const name = (first.name || '').split('/').pop();
                const pct = typeof first.percentage === 'number' ? `${first.percentage}%` : '';
                this._panelLabel.text = speed ? ` ${speed}` : ' ⇅';
                this._panelLabel.visible = true;
                this._statusItem.label.text = speed
                    ? `Estado: Sincronizando (${speed})`
                    : 'Estado: Sincronizando…';
                this._transferItem.label.text = `Archivo: ${name}${pct ? ` (${pct})` : ''}`;
                this._transferItem.visible = true;
                return;
            }

            this._transferItem.visible = false;

            // Verificar si hay un trabajo vfs/refresh activo
            this._postJson('/job/list', null, (jOk, jobs) => {
                if (this._destroyed)
                    return;
                const activeJobs = jOk && Array.isArray(jobs?.jobids) ? jobs.jobids : [];
                if (activeJobs.length > 0) {
                    this._postJson('/job/status', { jobid: activeJobs[0] }, (sOk, jStatus) => {
                        if (this._destroyed)
                            return;
                        if (sOk && jStatus && jStatus.finished === false) {
                            this._panelLabel.text = ' …';
                            this._panelLabel.visible = true;
                            this._statusItem.label.text = 'Estado: Indexando carpetas…';
                        } else {
                            this._panelLabel.visible = false;
                            this._statusItem.label.text = 'Estado: Conectado';
                        }
                    });
                } else {
                    this._panelLabel.visible = false;
                    this._statusItem.label.text = 'Estado: Conectado';
                }
            });
        });
    }

    _updateCacheSize() {
        const cacheDir = GLib.build_filenamev([GLib.get_home_dir(), '.cache', 'rclone']);
        try {
            const proc = Gio.Subprocess.new(
                ['du', '-sh', cacheDir],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE
            );
            proc.communicate_utf8_async(null, null, (p, res) => {
                if (this._destroyed)
                    return;
                try {
                    const [, stdout] = p.communicate_utf8_finish(res);
                    const size = (stdout || '').trim().split(/\s+/)[0];
                    if (size)
                        this._cacheItem.label.text = `Caché local: ${size} / 10 GiB`;
                } catch (_e) {
                    // ignorar
                }
            });
        } catch (_e) {
            // ignorar
        }
    }

    _openFolder() {
        const path = GLib.build_filenamev([GLib.get_home_dir(), 'GoogleDrive']);
        const uri = GLib.filename_to_uri(path, null);
        try {
            Gio.AppInfo.launch_default_for_uri(uri, null);
        } catch (e) {
            Main.notify('Google Drive', `No se pudo abrir la carpeta: ${e.message}`);
        }
    }

    _triggerRefresh() {
        this._postJson('/vfs/refresh', { recursive: 'true', _async: true }, (ok) => {
            if (ok) {
                Main.notify('Google Drive', 'Actualizando lista de carpetas en segundo plano…');
                this._poll();
            } else {
                Main.notify('Google Drive', 'No se pudo conectar con rclone. Intenta reiniciar el montaje.');
            }
        });
    }

    _restartService() {
        try {
            Gio.Subprocess.new(
                ['systemctl', '--user', 'restart', 'rclone-gdrive.service'],
                Gio.SubprocessFlags.NONE
            );
            Main.notify('Google Drive', 'Reiniciando montaje de Google Drive…');
        } catch (e) {
            Main.notify('Google Drive', `Error al reiniciar el servicio: ${e.message}`);
        }
    }

    destroy() {
        this._destroyed = true;
        if (this._pollId) {
            GLib.Source.remove(this._pollId);
            this._pollId = 0;
        }
        if (this._session) {
            this._session.abort();
            this._session = null;
        }
        super.destroy();
    }
});

export default class GDriveIndicatorExtension extends Extension {
    enable() {
        this._indicator = new GDriveIndicator();
        Main.panel.addToStatusArea('gdrive-indicator', this._indicator, 1, 'right');
    }

    disable() {
        this._indicator?.destroy();
        this._indicator = null;
    }
}
