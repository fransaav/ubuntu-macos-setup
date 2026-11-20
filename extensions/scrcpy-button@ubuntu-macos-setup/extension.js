import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';

const ScrcpyButton = GObject.registerClass(
class ScrcpyButton extends PanelMenu.Button {
    _init() {
        super._init(0.5, 'scrcpy');

        this._proc = null;
        this._connecting = false;
        this._retryTimeoutId = 0;

        this._icon = new St.Icon({
            icon_name: 'phone-symbolic',
            style_class: 'system-status-icon',
        });
        this.add_child(this._icon);

        this._buildMenu();
    }

    _buildMenu() {
        const openItem = new PopupMenu.PopupMenuItem('Abrir espejo (auto USB / Wi-Fi)');
        openItem.connect('activate', () => this._connectAndLaunch([], { preferWifi: false }));
        this.menu.addMenuItem(openItem);

        const screenOffItem = new PopupMenu.PopupMenuItem('Espejo con pantalla apagada');
        screenOffItem.connect('activate', () =>
            this._connectAndLaunch(['--turn-screen-off', '--stay-awake'], { preferWifi: false }));
        this.menu.addMenuItem(screenOffItem);

        const wifiScreenOffItem = new PopupMenu.PopupMenuItem('Espejo Wi-Fi con pantalla apagada');
        wifiScreenOffItem.connect('activate', () =>
            this._connectAndLaunch(['--turn-screen-off', '--stay-awake'], { preferWifi: true }));
        this.menu.addMenuItem(wifiScreenOffItem);

        const wifiTcpipItem = new PopupMenu.PopupMenuItem('Activar Wi-Fi desde USB (--tcpip)');
        wifiTcpipItem.connect('activate', () => this._launchScrcpy(['scrcpy', '--tcpip']));
        this.menu.addMenuItem(wifiTcpipItem);

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        const stopItem = new PopupMenu.PopupMenuItem('Cerrar scrcpy');
        stopItem.connect('activate', () => this._stop());
        this.menu.addMenuItem(stopItem);
    }

    vfunc_event(event) {
        const type = event.type();
        if (type === Clutter.EventType.BUTTON_PRESS) {
            const button = event.get_button();
            if (button === Clutter.BUTTON_PRIMARY) {
                this._launchOrFocus();
                return Clutter.EVENT_STOP;
            }
            if (button === Clutter.BUTTON_SECONDARY) {
                this.menu.toggle();
                return Clutter.EVENT_STOP;
            }
        } else if (type === Clutter.EventType.TOUCH_BEGIN) {
            this._launchOrFocus();
            return Clutter.EVENT_STOP;
        }
        return Clutter.EVENT_PROPAGATE;
    }

    _findScrcpyWindow() {
        for (const actor of global.get_window_actors()) {
            const win = actor.meta_window;
            if (!win)
                continue;
            const wmClass = (win.get_wm_class() || '').toLowerCase();
            if (wmClass === 'scrcpy' || wmClass.includes('scrcpy'))
                return win;
        }
        return null;
    }

    _launchOrFocus() {
        const existing = this._findScrcpyWindow();
        if (existing) {
            existing.activate(global.get_current_time());
            return;
        }
        this._connectAndLaunch([], { preferWifi: false });
    }

    _runCmdAsync(argv, callback) {
        try {
            const proc = Gio.Subprocess.new(
                argv,
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE
            );
            proc.communicate_utf8_async(null, null, (p, res) => {
                try {
                    const [, stdout, stderr] = p.communicate_utf8_finish(res);
                    const ok = p.get_if_exited() && p.get_exit_status() === 0;
                    callback(ok, stdout || '', stderr || '');
                } catch (_e) {
                    callback(false, '', '');
                }
            });
        } catch (_e) {
            callback(false, '', '');
        }
    }

    _parseAdbDevices(stdout) {
        const usb = [];
        const wifi = [];
        for (const line of stdout.split('\n')) {
            const trimmed = line.trim();
            if (!trimmed || trimmed.startsWith('List of devices'))
                continue;
            const parts = trimmed.split(/\s+/);
            if (parts.length >= 2 && parts[1] === 'device') {
                const serial = parts[0];
                if (serial.includes(':') || serial.includes('._tcp'))
                    wifi.push(serial);
                else
                    usb.push(serial);
            }
        }
        return { usb, wifi };
    }

    _parseMdnsEndpoint(stdout) {
        let tlsEndpoint = null;
        let tcpEndpoint = null;
        for (const line of stdout.split('\n')) {
            const parts = line.trim().split(/\s+/);
            if (parts.length < 3)
                continue;
            const svc = parts[1];
            const addr = parts[parts.length - 1];
            if (!addr.includes(':'))
                continue;
            if (svc.startsWith('_adb-tls-connect._tcp'))
                tlsEndpoint = tlsEndpoint || addr;
            else if (svc.startsWith('_adb._tcp'))
                tcpEndpoint = tcpEndpoint || addr;
        }
        return tlsEndpoint || tcpEndpoint;
    }

    _discoverMdnsAndLaunch(extraArgs, fallbackUsbSerial, allowRetry) {
        this._runCmdAsync(['adb', 'mdns', 'services'], (_ok, stdout) => {
            const endpoint = this._parseMdnsEndpoint(stdout);
            if (endpoint) {
                this._runCmdAsync(['adb', 'connect', endpoint], (connOk, connOut) => {
                    this._connecting = false;
                    if (connOk && /connected to/i.test(connOut)) {
                        this._launchScrcpy(['scrcpy', '-s', endpoint, ...extraArgs]);
                    } else if (fallbackUsbSerial) {
                        this._launchScrcpy(['scrcpy', '--tcpip', ...extraArgs]);
                    } else {
                        Main.notify(
                            'scrcpy',
                            `No se pudo conectar por Wi-Fi a ${endpoint}. Verifica que Depuración inalámbrica esté activa y el equipo vinculado.`
                        );
                    }
                });
                return;
            }

            if (allowRetry) {
                this._clearRetryTimeout();
                this._retryTimeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 800, () => {
                    this._retryTimeoutId = 0;
                    this._discoverMdnsAndLaunch(extraArgs, fallbackUsbSerial, false);
                    return GLib.SOURCE_REMOVE;
                });
                return;
            }

            this._connecting = false;
            if (fallbackUsbSerial) {
                this._launchScrcpy(['scrcpy', '--tcpip', ...extraArgs]);
            } else {
                Main.notify(
                    'scrcpy',
                    'No se encontró ningún Android por USB ni por Wi-Fi. Activa Depuración inalámbrica en tu celular o conecta el cable.'
                );
            }
        });
    }

    _connectAndLaunch(extraArgs, { preferWifi }) {
        if (!GLib.find_program_in_path('scrcpy')) {
            Main.notify('scrcpy', 'scrcpy no está instalado. Instálalo con: sudo apt install scrcpy adb');
            return;
        }
        if (!GLib.find_program_in_path('adb')) {
            this._launchScrcpy(['scrcpy', ...extraArgs]);
            return;
        }
        if (this._connecting)
            return;
        this._connecting = true;

        this._runCmdAsync(['adb', 'devices'], (_ok, stdout) => {
            const { usb, wifi } = this._parseAdbDevices(stdout);

            if (preferWifi) {
                if (wifi.length > 0) {
                    this._connecting = false;
                    this._launchScrcpy(['scrcpy', '-s', wifi[0], ...extraArgs]);
                    return;
                }
                // Buscar por Depuración inalámbrica (mDNS); si no aparece pero hay USB, usar --tcpip
                this._discoverMdnsAndLaunch(extraArgs, usb[0] || null, true);
                return;
            }

            // Modo automático: USB primero si está conectado, luego Wi-Fi ya conectado, luego mDNS
            if (usb.length > 0) {
                this._connecting = false;
                this._launchScrcpy(['scrcpy', '-s', usb[0], ...extraArgs]);
                return;
            }
            if (wifi.length > 0) {
                this._connecting = false;
                this._launchScrcpy(['scrcpy', '-s', wifi[0], ...extraArgs]);
                return;
            }

            this._discoverMdnsAndLaunch(extraArgs, null, true);
        });
    }

    _launchScrcpy(argv) {
        if (!GLib.find_program_in_path('scrcpy')) {
            Main.notify('scrcpy', 'scrcpy no está instalado. Instálalo con: sudo apt install scrcpy adb');
            return;
        }

        try {
            const proc = Gio.Subprocess.new(
                argv,
                Gio.SubprocessFlags.STDERR_PIPE
            );
            this._proc = proc;

            proc.communicate_utf8_async(null, null, (p, res) => {
                if (this._proc === p)
                    this._proc = null;

                let stderr = '';
                try {
                    [, , stderr] = p.communicate_utf8_finish(res);
                } catch (_e) {
                    return;
                }

                if (p.get_if_exited() && p.get_exit_status() !== 0) {
                    const text = (stderr || '').trim();
                    let msg = 'No se pudo iniciar scrcpy.';
                    if (text.includes('Could not find any ADB device'))
                        msg = 'No se detectó ningún dispositivo Android. Conecta el cable o activa Depuración inalámbrica.';
                    else if (text.includes('unauthorized'))
                        msg = 'Acepta el permiso de Depuración USB en la pantalla de tu celular.';
                    else if (text)
                        msg = text.split('\n').pop();
                    Main.notify('scrcpy', msg);
                }
            });
        } catch (e) {
            Main.notify('scrcpy', `Error al ejecutar scrcpy: ${e.message}`);
        }
    }

    _stop() {
        if (this._proc) {
            this._proc.force_exit();
            this._proc = null;
            return;
        }
        try {
            Gio.Subprocess.new(['pkill', '-x', 'scrcpy'], Gio.SubprocessFlags.NONE);
        } catch (_e) {
            // ignorar si no hay proceso activo
        }
    }

    _clearRetryTimeout() {
        if (this._retryTimeoutId) {
            GLib.Source.remove(this._retryTimeoutId);
            this._retryTimeoutId = 0;
        }
    }

    destroy() {
        this._clearRetryTimeout();
        this._connecting = false;
        this._proc = null;
        super.destroy();
    }
});

export default class ScrcpyButtonExtension extends Extension {
    _placeNextToClipboard() {
        const myContainer = this._indicator?.container;
        const clip = Main.panel.statusArea['Clipboard History Indicator'];
        if (!myContainer || !clip?.container)
            return;

        const rightBox = Main.panel._rightBox;
        const children = rightBox.get_children();
        const clipIdx = children.indexOf(clip.container);
        const myIdx = children.indexOf(myContainer);
        if (clipIdx === -1 || myIdx === -1)
            return;

        const target = myIdx < clipIdx ? clipIdx - 1 : clipIdx;
        if (myIdx !== target)
            rightBox.set_child_at_index(myContainer, target);
    }

    enable() {
        this._indicator = new ScrcpyButton();
        Main.panel.addToStatusArea('scrcpy-button', this._indicator, 1, 'right');

        this._placeNextToClipboard();
        Main.panel._rightBox.connectObject('child-added', () => {
            this._placeNextToClipboard();
        }, this);
    }

    disable() {
        Main.panel._rightBox.disconnectObject(this);
        this._indicator?.destroy();
        this._indicator = null;
    }
}
