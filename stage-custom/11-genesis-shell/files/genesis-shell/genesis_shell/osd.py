"""On-screen display for volume and brightness changes."""

from __future__ import annotations

from gi.repository import GLib, Gtk, GtkLayerShell

from .util import add_class, icon_image, label, make_layer_window


class Osd:
    def __init__(self, shell) -> None:
        self.shell = shell
        self.window = make_layer_window(
            namespace="genesis-osd", layer=GtkLayerShell.Layer.OVERLAY, anchors=(GtkLayerShell.Edge.BOTTOM,),
            margins={GtkLayerShell.Edge.BOTTOM: 72}, exclusive=False, keyboard=GtkLayerShell.KeyboardMode.NONE,
        )
        self.box = Gtk.Box(spacing=12)
        add_class(self.box, "osd")
        self.icon = icon_image("audio-volume-high-symbolic", 20)
        self.level = Gtk.LevelBar()
        self.level.set_min_value(0)
        self.level.set_max_value(1)
        self.level.set_size_request(180, 6)
        self.level.set_valign(Gtk.Align.CENTER)
        self.text = label("", css=("dim",))
        self.text.set_width_chars(4)
        self.text.set_xalign(1.0)
        self.box.pack_start(self.icon, False, False, 0)
        self.box.pack_start(self.level, True, True, 0)
        self.box.pack_start(self.text, False, False, 0)
        self.window.add(self.box)
        self._hide_source = 0

    def show_level(self, icon: str, fraction: float, text: str | None = None) -> None:
        fraction = max(0.0, min(1.0, fraction))
        self.icon.set_from_icon_name(icon, Gtk.IconSize.BUTTON)
        self.icon.set_pixel_size(20)
        self.level.set_value(fraction)
        self.text.set_text(text if text is not None else f"{int(round(fraction * 100))}%")
        if not self.window.get_visible():
            mon = self.shell.current_monitor()
            if mon is not None:
                GtkLayerShell.set_monitor(self.window, mon)
            self.window.show_all()
        if self._hide_source:
            GLib.source_remove(self._hide_source)
        self._hide_source = GLib.timeout_add(1600, self._hide)

    def _hide(self) -> bool:
        self._hide_source = 0
        self.window.hide()
        return False
