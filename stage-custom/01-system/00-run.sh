#!/bin/bash -e
# System configuration: boot firmware config, journald, unattended upgrades,
# login banner. Runs on the build host; ${ROOTFS_DIR} is the image root.

# shellcheck source=../lib.sh
source "${STAGE_DIR}/lib.sh"

# --- /boot/firmware/config.txt --------------------------------------------------
# Our block opens its own [all] section so the lines apply to every board even
# if upstream's config.txt stops ending with [all]. Re-running the stage must
# not duplicate lines.
CONFIG_TXT="${ROOTFS_DIR}/boot/firmware/config.txt"
MARKER="# --- stage-custom: settings from stage-custom/custom.conf ---"

if [ ! -f "${CONFIG_TXT}" ]; then
	echo "${CONFIG_TXT} is missing: stage1 must run before stage-custom" >&2
	exit 1
fi

if ! grep -qxF -- "${MARKER}" "${CONFIG_TXT}"; then
	printf '\n[all]\n%s\n' "${MARKER}" >> "${CONFIG_TXT}"
fi
if [ "${ENABLE_I2C}" = "1" ]; then
	ensure_line "${CONFIG_TXT}" "dtparam=i2c_arm=on"
fi
if [ "${ENABLE_SPI}" = "1" ]; then
	ensure_line "${CONFIG_TXT}" "dtparam=spi=on"
fi
if [ "${ENABLE_UART}" = "1" ]; then
	ensure_line "${CONFIG_TXT}" "enable_uart=1"
fi
if [ -n "${CONFIG_TXT_EXTRA}" ]; then
	while IFS= read -r line; do
		if [ -n "${line}" ]; then
			ensure_line "${CONFIG_TXT}" "${line}"
		fi
	done <<< "${CONFIG_TXT_EXTRA}"
fi

# --- journald ------------------------------------------------------------------
if [ "${PERSISTENT_JOURNAL}" = "1" ]; then
	install -d -m 755 "${ROOTFS_DIR}/etc/systemd/journald.conf.d"
	sed "s/@JOURNAL_MAX_USE@/${JOURNAL_MAX_USE}/" files/journald-custom.conf \
		> "${ROOTFS_DIR}/etc/systemd/journald.conf.d/10-custom.conf"
	chmod 644 "${ROOTFS_DIR}/etc/systemd/journald.conf.d/10-custom.conf"
fi

# --- unattended-upgrades ---------------------------------------------------------
# The package itself comes from 00-packages/00-packages.
install -d -m 755 "${ROOTFS_DIR}/etc/apt/apt.conf.d"
if [ "${ENABLE_UNATTENDED_UPGRADES}" = "1" ]; then
	install -m 644 files/20auto-upgrades "${ROOTFS_DIR}/etc/apt/apt.conf.d/20auto-upgrades"
	install -m 644 files/52unattended-upgrades-raspberrypi \
		"${ROOTFS_DIR}/etc/apt/apt.conf.d/52unattended-upgrades-raspberrypi"
else
	printf 'APT::Periodic::Update-Package-Lists "0";\nAPT::Periodic::Unattended-Upgrade "0";\n' \
		> "${ROOTFS_DIR}/etc/apt/apt.conf.d/20auto-upgrades"
	rm -f "${ROOTFS_DIR}/etc/apt/apt.conf.d/52unattended-upgrades-raspberrypi"
fi

# --- passwordless sudo -------------------------------------------------------------
# pi-gen applies PASSWORDLESS_SUDO itself in stage2, but pi-gen-action v1.11.0 has
# no input for it, so CI forwards the value via build-info.env and we apply it here
# the same way pi-gen does (idempotent: writes /etc/sudoers.d/010_pi-nopasswd).
if [ "${PASSWORDLESS_SUDO:-0}" = "1" ]; then
	on_chroot << EOF
SUDO_USER="${FIRST_USER_NAME}" raspi-config nonint do_sudo_pass 1
EOF
fi

# --- login banner ------------------------------------------------------------------
install -m 644 files/motd "${ROOTFS_DIR}/etc/motd"
