#!/bin/bash -e
# Genesis Glass look: GTK theme (translucent panel, frosted menus, rounded
# controls, steel-blue accent), fonts, panel layout, wallpaper, terminal,
# labwc titlebars (rounded corners + shadows) and the Wayfire "Genesis Glass"
# session with real background blur. Defaults land in /etc, /etc/skel and the
# first user's home, in the files the Raspberry Pi Appearance app also uses.

# shellcheck source=../lib.sh
source "${STAGE_DIR}/lib.sh"

USER_HOME="${ROOTFS_DIR}/home/${FIRST_USER_NAME}"
SKEL="${ROOTFS_DIR}/etc/skel"

# --- GTK theme -------------------------------------------------------------------
THEME="${ROOTFS_DIR}/usr/share/themes/GenesisGlass/gtk-3.0"
install -d -m 755 "${THEME}"
BASE_IMPORT=""
for base in PiXnoir PiXtrix PiXflat; do
	if [ -f "${ROOTFS_DIR}/usr/share/themes/${base}/gtk-3.0/gtk.css" ]; then
		BASE_IMPORT="@import url(\"/usr/share/themes/${base}/gtk-3.0/gtk.css\");"
		break
	fi
done
if [ -z "${BASE_IMPORT}" ]; then
	BASE_IMPORT='@import url("resource:///org/gtk/libgtk/theme/Adwaita/gtk-contained-dark.css");'
	log "No Raspberry Pi GTK theme found; GenesisGlass builds on Adwaita dark"
fi
{
	printf '%s\n\n' "${BASE_IMPORT}"
	cat files/gtk-colours.css
	printf '\n'
	cat files/gtk-glass.css
} > "${THEME}/gtk.css"
install -m 644 files/gtk-colours.css "${THEME}/gtk-colours.css"
chmod 644 "${THEME}/gtk.css"
install -d -m 755 "${ROOTFS_DIR}/usr/share/themes/GenesisGlass/gtk-2.0"
printf 'gtk-color-scheme = "selected_bg_color:#5f7d9a"\n' > "${ROOTFS_DIR}/usr/share/themes/GenesisGlass/gtk-2.0/gtkrc"

# --- toolkit defaults (GTK settings, gsettings, xsettingsd for XWayland apps) ----
install -d -m 755 "${ROOTFS_DIR}/etc/gtk-3.0" "${ROOTFS_DIR}/usr/share/glib-2.0/schemas"
install -m 644 files/settings.ini "${ROOTFS_DIR}/etc/gtk-3.0/settings.ini"
install -m 644 files/90_genesis.gschema.override "${ROOTFS_DIR}/usr/share/glib-2.0/schemas/90_genesis.gschema.override"
if [ -d "${ROOTFS_DIR}/etc/xsettingsd" ] || [ -f "${ROOTFS_DIR}/usr/bin/xsettingsd" ]; then
	install -d -m 755 "${ROOTFS_DIR}/etc/xsettingsd"
	install -m 644 files/xsettingsd.conf "${ROOTFS_DIR}/etc/xsettingsd/xsettingsd.conf"
fi

# --- per-user defaults (first user + /etc/skel) ------------------------------------
LAUNCHERS="${GENESIS_PANEL_LAUNCHERS}"
for base in "${SKEL}" "${USER_HOME}"; do
	install -d -m 755 "${base}/.config/wf-panel-pi" "${base}/.config/pcmanfm/default" \
		"${base}/.config/pcmanfm/LXDE-pi" "${base}/.config/lxterminal" "${base}/.config/labwc" \
		"${base}/.config/gtk-3.0" "${base}/.config/xsettingsd" "${base}/Pictures"
	sed -e "s#@PANEL_POSITION@#${GENESIS_PANEL_POSITION}#" -e "s#@LAUNCHERS@#${LAUNCHERS}#" \
		files/wf-panel-pi.ini.in > "${base}/.config/wf-panel-pi/wf-panel-pi.ini"
	sed -e "s#@WALLPAPER@#${GENESIS_WALLPAPER}#" files/desktop-items-0.conf.in \
		> "${base}/.config/pcmanfm/default/desktop-items-0.conf"
	cp "${base}/.config/pcmanfm/default/desktop-items-0.conf" "${base}/.config/pcmanfm/LXDE-pi/desktop-items-0.conf"
	install -m 644 files/lxterminal.conf "${base}/.config/lxterminal/lxterminal.conf"
	install -m 644 files/labwc-themerc-override "${base}/.config/labwc/themerc-override"
	install -m 644 files/settings.ini "${base}/.config/gtk-3.0/settings.ini"
	install -m 644 files/xsettingsd.conf "${base}/.config/xsettingsd/xsettingsd.conf"
done

# System-wide desktop defaults for pcmanfm (used when no user config exists yet).
for profile in default LXDE-pi; do
	install -d -m 755 "${ROOTFS_DIR}/etc/xdg/pcmanfm/${profile}"
	sed -e "s#@WALLPAPER@#${GENESIS_WALLPAPER}#" files/desktop-items-0.conf.in \
		> "${ROOTFS_DIR}/etc/xdg/pcmanfm/${profile}/desktop-items-0.conf"
done

# --- labwc: rounded corners, shadows, font (user rc.xml patched from the system one)
install -d -m 755 "${ROOTFS_DIR}/usr/lib/genesis"
install -m 755 files/labwc-rc-patch.py "${ROOTFS_DIR}/usr/lib/genesis/labwc-rc-patch.py"
on_chroot << EOF
if [ -f /etc/xdg/labwc/rc.xml ]; then
	for base in /etc/skel /home/${FIRST_USER_NAME}; do
		mkdir -p "\$base/.config/labwc"
		/usr/bin/python3 /usr/lib/genesis/labwc-rc-patch.py /etc/xdg/labwc/rc.xml "\$base/.config/labwc/rc.xml"
	done
else
	echo "No /etc/xdg/labwc/rc.xml: labwc rounded corners not configured"
fi
if command -v glib-compile-schemas > /dev/null 2>&1; then
	glib-compile-schemas /usr/share/glib-2.0/schemas
fi
EOF

# --- Genesis Glass session (Wayfire) ---------------------------------------------------
install -d -m 755 "${ROOTFS_DIR}/etc/genesis" "${ROOTFS_DIR}/etc/wayfire" "${ROOTFS_DIR}/usr/share/wayland-sessions"
SESSION="labwc"
if [ "${GENESIS_SESSION}" = "wayfire" ]; then
	on_chroot << EOF
if apt-get -o Acquire::Retries=3 install -y wayfire; then
	apt-get -o Acquire::Retries=3 install -y wcm || echo "WARNING: wcm (Wayfire Config Manager) unavailable"
	apt-get -o Acquire::Retries=3 install -y wayfire-plugin-winshadows || echo "WARNING: wayfire-plugin-winshadows unavailable (no window shadows)"
else
	echo "WARNING: wayfire is not installable from the configured archives; falling back to the labwc session"
fi
EOF
	if [ -x "${ROOTFS_DIR}/usr/bin/wayfire" ]; then
		SESSION="wayfire"
		EXTRA_PLUGINS=""
		if ls "${ROOTFS_DIR}"/usr/lib/*/wayfire/libwinshadows.so > /dev/null 2>&1; then
			EXTRA_PLUGINS="winshadows"
		fi
		sed -e "s#@XKB_LAYOUT@#${KEYBOARD_KEYMAP:-us}#" -e "s#@EXTRA_PLUGINS@#${EXTRA_PLUGINS}#" \
			files/wayfire.ini.in > "${ROOTFS_DIR}/etc/wayfire/genesis.ini"
		chmod 644 "${ROOTFS_DIR}/etc/wayfire/genesis.ini"
		for base in "${SKEL}" "${USER_HOME}"; do
			install -m 644 "${ROOTFS_DIR}/etc/wayfire/genesis.ini" "${base}/.config/wayfire.ini"
		done
		install -m 755 files/genesis-wayfire "${ROOTFS_DIR}/usr/bin/genesis-wayfire"
		install -m 755 files/genesis-xdg-autostart "${ROOTFS_DIR}/usr/bin/genesis-xdg-autostart"
		install -m 644 files/genesis-glass.desktop "${ROOTFS_DIR}/usr/share/wayland-sessions/genesis-glass.desktop"
	fi
fi
printf '%s\n' "${SESSION}" > "${ROOTFS_DIR}/etc/genesis/session"
log "Genesis default session: ${SESSION}"

chown -R 1000:1000 "${USER_HOME}/.config" "${USER_HOME}/Pictures"
