#!/bin/bash -e
# Branding: application icon, "Genesis" icon theme (replaces the app-menu
# icon through the start-here icon), wallpapers, Plymouth boot splash, login
# screen wallpaper and the banner.

# shellcheck source=../lib.sh
source "${STAGE_DIR}/lib.sh"

ICON_SIZES="16 22 24 32 48 64 96 128 256 512"

# --- application icon (hicolor) and the Genesis icon theme -------------------
HICOLOR="${ROOTFS_DIR}/usr/share/icons/hicolor"
GTHEME="${ROOTFS_DIR}/usr/share/icons/Genesis"
dirs=""
for s in ${ICON_SIZES}; do
	install -d -m 755 "${HICOLOR}/${s}x${s}/apps" "${GTHEME}/${s}x${s}/apps" "${GTHEME}/${s}x${s}/places"
	install -m 644 "files/icons/hicolor/${s}x${s}/apps/genesis-os.png" "${HICOLOR}/${s}x${s}/apps/genesis-os.png"
	install -m 644 "files/icons/hicolor/${s}x${s}/apps/genesis-os.png" "${HICOLOR}/${s}x${s}/apps/genesis-settings.png"
	# The panel's menu button loads the icon-theme's "start-here" icon.
	install -m 644 "files/icons/hicolor/${s}x${s}/apps/genesis-os.png" "${GTHEME}/${s}x${s}/places/start-here.png"
	install -m 644 "files/icons/hicolor/${s}x${s}/apps/genesis-os.png" "${GTHEME}/${s}x${s}/places/distributor-logo.png"
	dirs="${dirs}${dirs:+,}${s}x${s}/apps,${s}x${s}/places"
done
install -m 644 files/icons/genesis-os-tile-512.png "${ROOTFS_DIR}/usr/share/icons/hicolor/512x512/apps/genesis-os-tile.png"
{
	printf '[Icon Theme]\nName=Genesis\nComment=Genesis OS icons on top of the Raspberry Pi icon theme\n'
	printf 'Inherits=PiXnoir,PiXtrix,PiXflat,Adwaita,hicolor\nDirectories=%s\n\n' "${dirs}"
	for s in ${ICON_SIZES}; do
		printf '[%sx%s/apps]\nSize=%s\nContext=Applications\nType=Fixed\n\n' "$s" "$s" "$s"
		printf '[%sx%s/places]\nSize=%s\nContext=Places\nType=Fixed\n\n' "$s" "$s" "$s"
	done
} > "${GTHEME}/index.theme"
chmod 644 "${GTHEME}/index.theme"

# --- wallpapers ------------------------------------------------------------------
install -d -m 755 "${ROOTFS_DIR}/usr/share/genesis/wallpapers" "${ROOTFS_DIR}/usr/share/rpd-wallpaper"
for f in files/wallpapers/*.jpg; do
	install -m 644 "$f" "${ROOTFS_DIR}/usr/share/genesis/wallpapers/$(basename "$f")"
	# Appearance Settings browses /usr/share/rpd-wallpaper; make ours selectable there too.
	ln -sfn "/usr/share/genesis/wallpapers/$(basename "$f")" "${ROOTFS_DIR}/usr/share/rpd-wallpaper/$(basename "$f")"
done
if [ ! -f "${ROOTFS_DIR}/usr/share/genesis/wallpapers/${GENESIS_WALLPAPER}.jpg" ]; then
	echo "GENESIS_WALLPAPER=${GENESIS_WALLPAPER} does not exist in files/wallpapers" >&2
	exit 1
fi

# --- boot splash (Plymouth, script theme) ---------------------------------------
if [ "${ENABLE_BOOT_SPLASH}" = "1" ]; then
	PLY="${ROOTFS_DIR}/usr/share/plymouth/themes/genesis"
	install -d -m 755 "${PLY}" "${ROOTFS_DIR}/etc/plymouth"
	install -m 644 files/genesis.plymouth "${PLY}/genesis.plymouth"
	install -m 644 files/genesis.script "${PLY}/genesis.script"
	install -m 644 files/splash/splash.png "${PLY}/splash.png"
	# plymouth-set-default-theme writes /etc/plymouth/plymouthd.conf; the initramfs is
	# rebuilt by pi-gen's export stage, which picks the theme up from there.
	on_chroot << EOF
if command -v plymouth-set-default-theme > /dev/null 2>&1; then
	plymouth-set-default-theme genesis
else
	printf '[Daemon]\nTheme=genesis\n' > /etc/plymouth/plymouthd.conf
fi
EOF
fi

# --- login screen ------------------------------------------------------------------
GREETER="${ROOTFS_DIR}/etc/lightdm/pi-greeter.conf"
if [ -f "${GREETER}" ]; then
	sed -i \
		-e "s#^wallpaper=.*#wallpaper=/usr/share/genesis/wallpapers/${GENESIS_WALLPAPER}.jpg#" \
		-e "s#^desktop_bg=.*#desktop_bg=\#0b1420#" \
		-e "s#^wallpaper_mode=.*#wallpaper_mode=crop#" \
		-e "s#^gtk-icon-theme-name=.*#gtk-icon-theme-name=Genesis#" \
		-e "s#^default-user-image=.*#default-user-image=/usr/share/icons/hicolor/128x128/apps/genesis-os.png#" \
		"${GREETER}"
	grep -q '^wallpaper=' "${GREETER}" || printf 'wallpaper=/usr/share/genesis/wallpapers/%s.jpg\n' "${GENESIS_WALLPAPER}" >> "${GREETER}"
else
	log "No /etc/lightdm/pi-greeter.conf (Lite build?): login screen not themed"
fi

# --- banner --------------------------------------------------------------------------
install -m 644 files/motd "${ROOTFS_DIR}/etc/motd"

on_chroot << EOF
if command -v gtk-update-icon-cache > /dev/null 2>&1; then
	gtk-update-icon-cache -f -t /usr/share/icons/Genesis || true
	gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true
fi
EOF
