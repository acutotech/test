#!/usr/bin/python3
"""Genesis Settings: interfaces, system, appearance, connectivity, display,
software and about pages for Genesis OS on Raspberry Pi.

Privileged changes go through /usr/lib/genesis-settings/genesis-helper via
sudo (passwordless, or with the Raspberry Pi askpass prompt) or pkexec.
"""
import configparser
import os
import shutil
import subprocess
import threading

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GdkPixbuf, GLib, Gtk, Pango  # noqa: E402

HELPER = "/usr/lib/genesis-settings/genesis-helper"
WALLPAPER_DIRS = ("/usr/share/genesis/wallpapers", "/usr/share/rpd-wallpaper")
WAYFIRE_INI = os.path.expanduser("~/.config/wayfire.ini")
RELEASE_FILE = "/etc/custom-image-release"

CSS = b"""
window.genesis { background-color: #0e1622; color: #dfe8f0; }
.genesis-sidebar { background-color: rgba(255,255,255,0.03); border-right: 1px solid rgba(255,255,255,0.06); }
.genesis-sidebar row { padding: 10px 14px; border-radius: 10px; margin: 2px 8px; }
.genesis-sidebar row:selected { background-color: #5f7d9a; color: #ffffff; }
.card { background-color: rgba(255,255,255,0.045); border: 1px solid rgba(255,255,255,0.08);
        border-radius: 14px; padding: 6px; }
.card row { padding: 8px 10px; border-radius: 10px; }
.page-title { font-size: 20px; font-weight: 600; }
.row-title { font-weight: 600; }
.row-subtitle { opacity: 0.65; font-size: 12px; }
.banner { background-color: rgba(95,125,154,0.30); border: 1px solid rgba(138,164,189,0.4);
          border-radius: 10px; padding: 8px 12px; }
.pill { border-radius: 999px; padding: 6px 16px; }
.wallpaper { border-radius: 10px; border: 2px solid transparent; }
.wallpaper-selected { border: 2px solid #8aa4bd; }
"""

INTERFACES = [
    ("i2c", "I2C", "Inter-Integrated Circuit bus on GPIO 2/3", True),
    ("spi", "SPI", "Serial Peripheral Interface on GPIO 7-11", True),
    ("serial_hw", "Serial port", "UART on GPIO 14/15 for devices (Pi 5: uart0)", True),
    ("serial_cons", "Serial console", "Login shell on the serial port (usually off)", True),
    ("onewire", "1-Wire", "Dallas 1-Wire bus (w1-gpio overlay)", True),
    ("camera", "Camera auto-detect", "Detect CSI cameras at boot", True),
    ("ssh", "SSH server", "Remote shell access (port 22)", False),
    ("vnc", "VNC server", "Remote desktop with wayvnc (port 5900)", False),
]


def sh(cmd, timeout=20, env=None):
    """Run a command, never raise; return CompletedProcess."""
    try:
        full_env = dict(os.environ, **env) if env else None
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=full_env)
    except (OSError, subprocess.SubprocessError) as exc:
        return subprocess.CompletedProcess(cmd, 1, "", str(exc))


def spawn(cmd):
    """Launch a desktop program detached from this process."""
    try:
        subprocess.Popen(cmd, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except OSError:
        return False


def helper_get(item):
    out = sh([HELPER, "get", item]).stdout.strip()
    return out


def root_command(args):
    if sh(["sudo", "-n", "true"]).returncode == 0:
        return ["sudo", "-n", HELPER] + args, None
    if os.path.exists("/usr/bin/sudopwd"):
        return ["sudo", "-A", HELPER] + args, {"SUDO_ASKPASS": "/usr/bin/sudopwd"}
    return ["pkexec", HELPER] + args, None


def run_root_async(args, callback):
    """Run a helper command as root in a thread; callback(result) on the main loop."""
    cmd, env = root_command(args)

    def work():
        result = sh(cmd, timeout=180, env=env)
        GLib.idle_add(callback, result)

    threading.Thread(target=work, daemon=True).start()


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read().strip()
    except OSError:
        return ""


def release_info():
    info = {}
    for line in read_text(RELEASE_FILE).splitlines():
        if "=" in line:
            key, _, value = line.partition("=")
            info[key.strip()] = value.strip()
    return info


class Row(Gtk.ListBoxRow):
    def __init__(self, title, subtitle=None, widget=None):
        super().__init__(activatable=False)
        box = Gtk.Box(spacing=12)
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, hexpand=True)
        label = Gtk.Label(label=title, xalign=0)
        label.get_style_context().add_class("row-title")
        text.pack_start(label, False, False, 0)
        if subtitle:
            sub = Gtk.Label(label=subtitle, xalign=0, wrap=True)
            sub.get_style_context().add_class("row-subtitle")
            text.pack_start(sub, False, False, 0)
        box.pack_start(text, True, True, 0)
        if widget is not None:
            widget.set_valign(Gtk.Align.CENTER)
            box.pack_end(widget, False, False, 0)
        self.add(box)


def card(rows):
    frame = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
    frame.get_style_context().add_class("card")
    for row in rows:
        frame.add(row)
    return frame


def page(title, *sections):
    scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14, margin=24)
    heading = Gtk.Label(label=title, xalign=0)
    heading.get_style_context().add_class("page-title")
    box.pack_start(heading, False, False, 0)
    for section in sections:
        box.pack_start(section, False, False, 0)
    scroller.add(box)
    return scroller


class GenesisSettings(Gtk.Window):
    def __init__(self):
        super().__init__(title="Genesis Settings")
        self.set_default_size(960, 640)
        self.set_icon_name("genesis-settings")
        self.get_style_context().add_class("genesis")
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            self.get_screen(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        header = Gtk.HeaderBar(title="Genesis Settings", show_close_button=True)
        self.set_titlebar(header)

        self.banner = Gtk.Label(label="", xalign=0, no_show_all=True)
        self.banner.get_style_context().add_class("banner")

        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        sidebar = Gtk.StackSidebar(stack=self.stack)
        sidebar.get_style_context().add_class("genesis-sidebar")
        sidebar.set_size_request(200, -1)

        self.stack.add_titled(self.build_interfaces(), "interfaces", "Interfaces")
        self.stack.add_titled(self.build_system(), "system", "System")
        self.stack.add_titled(self.build_appearance(), "appearance", "Appearance")
        self.stack.add_titled(self.build_connectivity(), "connectivity", "Connectivity")
        self.stack.add_titled(self.build_display(), "display", "Display & Sound")
        self.stack.add_titled(self.build_software(), "software", "Software")
        self.stack.add_titled(self.build_about(), "about", "About")

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        banner_box = Gtk.Box(margin_start=24, margin_end=24, margin_top=12)
        banner_box.pack_start(self.banner, True, True, 0)
        content.pack_start(banner_box, False, False, 0)
        content.pack_start(self.stack, True, True, 0)

        root = Gtk.Box()
        root.pack_start(sidebar, False, False, 0)
        root.pack_start(content, True, True, 0)
        self.add(root)
        self.show_all()

    # ---------------------------------------------------------------- helpers
    def show_banner(self, text):
        self.banner.set_text(text)
        self.banner.show()

    def error(self, text, detail=""):
        dialog = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.ERROR,
                                   buttons=Gtk.ButtonsType.CLOSE, text=text)
        if detail:
            dialog.format_secondary_text(detail.strip()[-800:])
        dialog.run()
        dialog.destroy()

    def launch(self, *candidates):
        for cmd in candidates:
            if shutil.which(cmd[0]):
                if spawn(cmd):
                    return
        self.error("Not installed", "None of these programs is available: " + ", ".join(c[0] for c in candidates))

    def toggle_switch(self, key, needs_reboot, switch, state):
        switch.set_sensitive(False)

        def done(result):
            switch.set_sensitive(True)
            if result.returncode != 0:
                switch.handler_block_by_func(self.on_interface_toggled)
                switch.set_active(not state)
                switch.handler_unblock_by_func(self.on_interface_toggled)
                self.error("Could not change %s" % key, result.stderr or result.stdout)
            elif needs_reboot:
                self.show_banner("Reboot to apply the hardware interface changes.")

        run_root_async(["set", key, "0" if state else "1"], done)

    def on_interface_toggled(self, switch, _param):
        key, needs_reboot = switch.genesis_key, switch.genesis_reboot
        self.toggle_switch(key, needs_reboot, switch, switch.get_active())

    def make_switch(self, key, needs_reboot):
        switch = Gtk.Switch()
        switch.genesis_key = key
        switch.genesis_reboot = needs_reboot
        switch.set_active(helper_get(key) == "0")
        switch.connect("notify::active", self.on_interface_toggled)
        return switch

    # ---------------------------------------------------------------- pages
    def build_interfaces(self):
        rows = [Row(title, subtitle, self.make_switch(key, reboot)) for key, title, subtitle, reboot in INTERFACES]
        hint = Gtk.Label(label="VNC is served by wayvnc and works with any VNC viewer on port 5900. "
                               "SSH and VNC accept the account password; change it under System.",
                         xalign=0, wrap=True)
        hint.get_style_context().add_class("row-subtitle")
        return page("Interfaces", card(rows), hint)

    def build_system(self):
        self.hostname_entry = Gtk.Entry(text=read_text("/etc/hostname") or "nodobox", width_chars=22)
        apply_host = Gtk.Button(label="Apply")
        apply_host.get_style_context().add_class("pill")
        apply_host.connect("clicked", self.on_hostname_apply)
        host_box = Gtk.Box(spacing=8)
        host_box.pack_start(self.hostname_entry, False, False, 0)
        host_box.pack_start(apply_host, False, False, 0)

        self.tz_entry = Gtk.Entry(text=read_text("/etc/timezone") or "Asia/Kolkata", width_chars=22)
        completion = Gtk.EntryCompletion()
        store = Gtk.ListStore(str)
        for zone in sh(["timedatectl", "list-timezones"]).stdout.split():
            store.append([zone])
        completion.set_model(store)
        completion.set_text_column(0)
        completion.set_minimum_key_length(1)
        self.tz_entry.set_completion(completion)
        apply_tz = Gtk.Button(label="Apply")
        apply_tz.get_style_context().add_class("pill")
        apply_tz.connect("clicked", self.on_timezone_apply)
        tz_box = Gtk.Box(spacing=8)
        tz_box.pack_start(self.tz_entry, False, False, 0)
        tz_box.pack_start(apply_tz, False, False, 0)

        self.locale_combo = Gtk.ComboBoxText.new_with_entry()
        current_locale = ""
        for line in read_text("/etc/default/locale").splitlines():
            if line.startswith("LANG="):
                current_locale = line.split("=", 1)[1].strip().strip('"')
        for line in read_text("/usr/share/i18n/SUPPORTED").splitlines():
            name = line.split()[0] if line.split() else ""
            if name.endswith(".UTF-8") and name.startswith(("en_", "hi_", "de_", "fr_", "es_", "ja_", "zh_", "pt_", "it_", "nl_", "ru_", "ko_", "ar_")):
                self.locale_combo.append_text(name)
        self.locale_combo.get_child().set_text(current_locale or "en_US.UTF-8")
        apply_locale = Gtk.Button(label="Apply")
        apply_locale.get_style_context().add_class("pill")
        apply_locale.connect("clicked", self.on_locale_apply)
        locale_box = Gtk.Box(spacing=8)
        locale_box.pack_start(self.locale_combo, False, False, 0)
        locale_box.pack_start(apply_locale, False, False, 0)

        identity = card([
            Row("Hostname", "Also reachable as <hostname>.local on the local network", host_box),
            Row("Time zone", "Area/City, for example Asia/Kolkata", tz_box),
            Row("Language", "System locale (log out to apply)", locale_box),
        ])

        passwd = Gtk.Button(label="Change password")
        passwd.get_style_context().add_class("pill")
        passwd.connect("clicked", lambda _b: self.launch(["lxterminal", "-e", "sh -c 'passwd; echo; echo Done. Press Enter.; read x'"],
                                                        ["x-terminal-emulator", "-e", "passwd"]))
        boot = card([
            Row("Desktop auto-login", "Log straight into the desktop at boot", self.make_switch("autologin", False)),
            Row("Boot splash", "Show the Genesis logo while booting", self.make_switch("splash", True)),
            Row("Password-less sudo", "Do not ask for the password for admin commands (less secure)",
                self.make_switch("sudo_nopass", False)),
            Row("Account password", "Change the password of the current user", passwd),
        ])

        reboot = Gtk.Button(label="Reboot")
        reboot.get_style_context().add_class("pill")
        reboot.connect("clicked", lambda _b: spawn(["systemctl", "reboot"]))
        shutdown = Gtk.Button(label="Shut down")
        shutdown.get_style_context().add_class("pill")
        shutdown.connect("clicked", lambda _b: spawn(["systemctl", "poweroff"]))
        power_box = Gtk.Box(spacing=8)
        power_box.pack_start(reboot, False, False, 0)
        power_box.pack_start(shutdown, False, False, 0)
        power = card([Row("Power", "Restart or switch off the device", power_box)])
        return page("System", identity, boot, power)

    def on_hostname_apply(self, _button):
        name = self.hostname_entry.get_text().strip()
        if not name or not all(c.isalnum() or c == "-" for c in name) or name[0] == "-" or name[-1] == "-":
            self.error("Invalid hostname", "Use letters, digits and hyphens only.")
            return
        run_root_async(["hostname", name], lambda r: self.after_change(r, "Hostname changed; reboot to apply everywhere."))

    def on_timezone_apply(self, _button):
        zone = self.tz_entry.get_text().strip()
        if not os.path.exists(os.path.join("/usr/share/zoneinfo", zone)):
            self.error("Unknown time zone", zone)
            return
        run_root_async(["timezone", zone], lambda r: self.after_change(r, "Time zone set to %s." % zone))

    def on_locale_apply(self, _button):
        loc = self.locale_combo.get_child().get_text().strip()
        run_root_async(["locale", loc], lambda r: self.after_change(r, "Locale set to %s; log out and back in." % loc))

    def after_change(self, result, success_text):
        if result.returncode != 0:
            self.error("Change failed", result.stderr or result.stdout)
        else:
            self.show_banner(success_text)

    def build_appearance(self):
        self.wall_flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.SINGLE, max_children_per_line=4,
                                     homogeneous=True, row_spacing=10, column_spacing=10)
        current = self.current_wallpaper()
        seen = set()
        for directory in WALLPAPER_DIRS:
            if not os.path.isdir(directory):
                continue
            for name in sorted(os.listdir(directory)):
                path = os.path.realpath(os.path.join(directory, name))
                if path in seen or not name.lower().endswith((".jpg", ".jpeg", ".png")) or "-2560" in name:
                    continue
                seen.add(path)
                try:
                    pix = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, 200, 112, True)
                except GLib.Error:
                    continue
                image = Gtk.Image.new_from_pixbuf(pix)
                image.get_style_context().add_class("wallpaper")
                button = Gtk.Button(relief=Gtk.ReliefStyle.NONE, tooltip_text=name)
                button.add(image)
                button.genesis_path = path
                button.connect("clicked", self.on_wallpaper_clicked)
                if path == current:
                    image.get_style_context().add_class("wallpaper-selected")
                self.wall_flow.add(button)
        browse = Gtk.Button(label="Browse…")
        browse.get_style_context().add_class("pill")
        browse.connect("clicked", self.on_wallpaper_browse)
        greeter = Gtk.Button(label="Use current on login screen")
        greeter.get_style_context().add_class("pill")
        greeter.connect("clicked", self.on_greeter_wallpaper)
        wall_buttons = Gtk.Box(spacing=8)
        wall_buttons.pack_start(browse, False, False, 0)
        wall_buttons.pack_start(greeter, False, False, 0)
        wall_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        wall_box.pack_start(self.wall_flow, False, False, 0)
        wall_box.pack_start(wall_buttons, False, False, 0)
        wallpapers = card([Row("Wallpaper", "Click a wallpaper to use it on the desktop", None)])
        wallpapers.add(Gtk.ListBoxRow(activatable=False, child=wall_box))

        rows = []
        session_now = helper_get("session")
        glass_available = os.path.exists("/usr/share/wayland-sessions/genesis-glass.desktop")
        self.session_glass = Gtk.RadioButton.new_with_label(None, "Genesis Glass (blur, animations)")
        self.session_fast = Gtk.RadioButton.new_with_label_from_widget(self.session_glass, "Raspberry Pi labwc (lightest)")
        (self.session_glass if session_now == "wayfire" else self.session_fast).set_active(True)
        self.session_glass.set_sensitive(glass_available)
        for radio in (self.session_glass, self.session_fast):
            radio.connect("toggled", self.on_session_toggled)
        radios = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        radios.pack_start(self.session_glass, False, False, 0)
        radios.pack_start(self.session_fast, False, False, 0)
        rows.append(Row("Desktop session", "Takes effect at the next login", radios))
        if glass_available:
            blur = Gtk.Switch(active=self.blur_enabled())
            blur.connect("notify::active", self.on_blur_toggled)
            rows.append(Row("Glass blur", "Blur behind the panel, menus and terminal (Glass session; Super+B toggles it live)", blur))
        pipanel = Gtk.Button(label="Open")
        pipanel.get_style_context().add_class("pill")
        pipanel.connect("clicked", lambda _b: self.launch(["pipanel"]))
        rows.append(Row("Raspberry Pi appearance settings", "Fonts, colours, panel size and more", pipanel))
        return page("Appearance", wallpapers, card(rows))

    @staticmethod
    def current_wallpaper():
        for profile in ("default", "LXDE-pi"):
            conf = os.path.expanduser("~/.config/pcmanfm/%s/desktop-items-0.conf" % profile)
            for line in read_text(conf).splitlines():
                if line.startswith("wallpaper="):
                    return os.path.realpath(line.split("=", 1)[1].strip())
        return ""

    def set_wallpaper(self, path):
        if shutil.which("pcmanfm"):
            spawn(["pcmanfm", "--set-wallpaper=%s" % path, "--wallpaper-mode=crop"])
        for child in self.wall_flow.get_children():
            button = child.get_child()
            image = button.get_child()
            ctx = image.get_style_context()
            if getattr(button, "genesis_path", "") == path:
                ctx.add_class("wallpaper-selected")
            else:
                ctx.remove_class("wallpaper-selected")
        self.show_banner("Wallpaper set to %s" % os.path.basename(path))

    def on_wallpaper_clicked(self, button):
        self.set_wallpaper(button.genesis_path)

    def on_wallpaper_browse(self, _button):
        dialog = Gtk.FileChooserDialog(title="Choose a wallpaper", transient_for=self, action=Gtk.FileChooserAction.OPEN)
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, Gtk.STOCK_OPEN, Gtk.ResponseType.OK)
        images = Gtk.FileFilter()
        images.set_name("Images")
        images.add_mime_type("image/jpeg")
        images.add_mime_type("image/png")
        dialog.add_filter(images)
        if dialog.run() == Gtk.ResponseType.OK:
            self.set_wallpaper(dialog.get_filename())
        dialog.destroy()

    def on_greeter_wallpaper(self, _button):
        path = self.current_wallpaper()
        if not path:
            self.error("No wallpaper configured yet")
            return
        run_root_async(["greeter-wallpaper", path], lambda r: self.after_change(r, "Login screen wallpaper updated."))

    def on_session_toggled(self, radio):
        if not radio.get_active():
            return
        name = "wayfire" if radio is self.session_glass else "labwc"
        if helper_get("session") == name:
            return
        run_root_async(["session", name], lambda r: self.after_change(r, "Session changed; log out to switch."))

    def wayfire_config(self):
        parser = configparser.RawConfigParser(strict=False)
        parser.optionxform = str
        parser.read(WAYFIRE_INI)
        return parser

    def blur_enabled(self):
        parser = self.wayfire_config()
        plugins = parser.get("core", "plugins", fallback="")
        return "blur" in plugins.split()

    def on_blur_toggled(self, switch, _param):
        parser = self.wayfire_config()
        if not parser.has_section("core"):
            parser.add_section("core")
        plugins = parser.get("core", "plugins", fallback="").split()
        if switch.get_active() and "blur" not in plugins:
            plugins.append("blur")
        if not switch.get_active() and "blur" in plugins:
            plugins.remove("blur")
        parser.set("core", "plugins", " ".join(plugins))
        try:
            os.makedirs(os.path.dirname(WAYFIRE_INI), exist_ok=True)
            with open(WAYFIRE_INI, "w", encoding="utf-8") as fh:
                parser.write(fh, space_around_delimiters=True)
        except OSError as exc:
            self.error("Could not write wayfire.ini", str(exc))

    def build_connectivity(self):
        wifi = Gtk.Button(label="Wi-Fi networks")
        wifi.get_style_context().add_class("pill")
        wifi.connect("clicked", lambda _b: self.launch(["wfpanelctl", "netman", "menu"], ["lp-connection-editor"], ["nm-connection-editor"]))
        edit = Gtk.Button(label="Edit connections")
        edit.get_style_context().add_class("pill")
        edit.connect("clicked", lambda _b: self.launch(["lp-connection-editor"], ["nm-connection-editor"]))
        bt = Gtk.Button(label="Bluetooth")
        bt.get_style_context().add_class("pill")
        bt.connect("clicked", lambda _b: self.launch(["wfpanelctl", "bluetooth", "menu"], ["blueman-manager"]))

        self.country_combo = Gtk.ComboBoxText()
        current = sh(["raspi-config", "nonint", "get_wifi_country"]).stdout.strip()
        index = 0
        for i, line in enumerate(l for l in read_text("/usr/share/zoneinfo/iso3166.tab").splitlines() if l and not l.startswith("#")):
            code, _, name = line.partition("\t")
            self.country_combo.append(code, "%s  %s" % (code, name))
            if code == current:
                index = i
        self.country_combo.set_active(index)
        apply_country = Gtk.Button(label="Apply")
        apply_country.get_style_context().add_class("pill")
        apply_country.connect("clicked", self.on_country_apply)
        country_box = Gtk.Box(spacing=8)
        country_box.pack_start(self.country_combo, False, False, 0)
        country_box.pack_start(apply_country, False, False, 0)

        ips = sh(["hostname", "-I"]).stdout.strip() or "no address yet"
        return page("Connectivity", card([
            Row("Wi-Fi", "Join or forget wireless networks", wifi),
            Row("Wired and advanced", "Static addresses, VPN, hotspots", edit),
            Row("Bluetooth", "Pair audio devices, keyboards and phones", bt),
            Row("Wi-Fi country", "Sets the allowed channels; required before Wi-Fi works", country_box),
            Row("IP addresses", ips, None),
        ]))

    def on_country_apply(self, _button):
        code = self.country_combo.get_active_id()
        if code:
            run_root_async(["wifi-country", code], lambda r: self.after_change(r, "Wi-Fi country set to %s." % code))

    def build_display(self):
        screens = Gtk.Button(label="Screen layout")
        screens.get_style_context().add_class("pill")
        screens.connect("clicked", lambda _b: self.launch(["raindrop"], ["wdisplays"], ["arandr"]))
        sound = Gtk.Button(label="Sound")
        sound.get_style_context().add_class("pill")
        sound.connect("clicked", lambda _b: self.launch(["pavucontrol"]))
        return page("Display & Sound", card([
            Row("Displays", "Resolution, rotation and arrangement", screens),
            Row("Screen blanking", "Turn the screen off after a period of inactivity", self.make_switch("blanking", False)),
            Row("Audio", "Output device, volume and input levels", sound),
        ]))

    def build_software(self):
        def button(label, *cmds):
            b = Gtk.Button(label=label)
            b.get_style_context().add_class("pill")
            b.connect("clicked", lambda _b: self.launch(*cmds))
            return b

        update_cmd = "sh -c 'sudo apt update && sudo apt full-upgrade; echo; echo Done. Press Enter.; read x'"
        rows = [
            Row("Raspberry Pi Configuration", "The full Raspberry Pi system settings tool", button("Open", ["rc_gui"])),
            Row("Recommended software", "Install curated applications", button("Open", ["rp-prefapps"])),
            Row("Update the system", "Fetch and install updates in a terminal", button("Update", ["lxterminal", "-e", update_cmd])),
            Row("Visual Studio Code", "Editor with the Python extension; python is %s" % self.python_version("python"),
                button("Open", ["code"])),
        ]
        return page("Software", card(rows))

    @staticmethod
    def python_version(binary):
        out = sh([binary, "--version"]).stdout.strip() or sh([binary, "--version"]).stderr.strip()
        return out.replace("Python ", "") or "not found"

    def build_about(self):
        info = release_info()
        model = read_text("/proc/device-tree/model").replace("\x00", "") or "unknown"
        pretty = ""
        for line in read_text("/etc/os-release").splitlines():
            if line.startswith("PRETTY_NAME="):
                pretty = line.split("=", 1)[1].strip('"')
        mem_kb = 0
        for line in read_text("/proc/meminfo").splitlines():
            if line.startswith("MemTotal:"):
                mem_kb = int(line.split()[1])
        try:
            usage = shutil.disk_usage("/")
            disk = "%.1f GB free of %.1f GB" % (usage.free / 1e9, usage.total / 1e9)
        except OSError:
            disk = "unknown"
        code_version = sh(["code", "--version"]).stdout.split("\n")[0] if shutil.which("code") else "not installed"
        rows = [
            Row("Genesis OS", "Image %s built %s" % (info.get("IMAGE_NAME", "?"), info.get("IMAGE_DATE", "?")), None),
            Row("Base", pretty or "Debian", None),
            Row("Device", model, None),
            Row("Kernel", sh(["uname", "-r"]).stdout.strip(), None),
            Row("Memory", "%.1f GB" % (mem_kb / 1e6), None),
            Row("Storage", disk, None),
            Row("Python", "python %s (default), python3 %s (system)" % (self.python_version("python"), self.python_version("python3")), None),
            Row("Visual Studio Code", code_version, None),
            Row("Session", helper_get("session") or "labwc", None),
            Row("Source", info.get("SOURCE_COMMIT", "unknown"), None),
        ]
        return page("About", card(rows))


def main():
    win = GenesisSettings()
    win.connect("destroy", Gtk.main_quit)
    Gtk.main()


if __name__ == "__main__":
    main()
