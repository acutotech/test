#!/bin/bash -e
# Genesis Settings: a GTK settings application (interfaces, system, appearance,
# connectivity, display & sound, software, about) and its privileged helper.

# shellcheck source=../lib.sh
source "${STAGE_DIR}/lib.sh"

install -d -m 755 "${ROOTFS_DIR}/usr/lib/genesis-settings" "${ROOTFS_DIR}/usr/bin" \
	"${ROOTFS_DIR}/usr/share/applications" "${ROOTFS_DIR}/usr/share/polkit-1/actions"
install -m 644 files/genesis_settings.py "${ROOTFS_DIR}/usr/lib/genesis-settings/genesis_settings.py"
install -m 755 files/genesis-helper "${ROOTFS_DIR}/usr/lib/genesis-settings/genesis-helper"
install -m 755 files/genesis-settings "${ROOTFS_DIR}/usr/bin/genesis-settings"
install -m 644 files/genesis-settings.desktop "${ROOTFS_DIR}/usr/share/applications/genesis-settings.desktop"
install -m 644 files/com.genesis.settings.policy "${ROOTFS_DIR}/usr/share/polkit-1/actions/com.genesis.settings.policy"

on_chroot << EOF
/usr/bin/python3 -m py_compile /usr/lib/genesis-settings/genesis_settings.py
rm -rf /usr/lib/genesis-settings/__pycache__
if command -v update-desktop-database > /dev/null 2>&1; then
	update-desktop-database /usr/share/applications || true
fi
EOF
