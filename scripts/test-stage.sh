#!/usr/bin/env bash
# Dry-run of stage-custom: no root, no Docker, no image.
#
# Emulates the parts of pi-gen's run_stage/run_sub_stage that matter for our
# scripts (exported variables, log, on_chroot, sub-stage order, the
# executable-bit rule), runs the stage against a throw-away root filesystem and
# asserts on the result in several scenarios. *-packages, *-debconf and
# *-patches need apt/quilt and are only syntax-checked.
#
# What this does NOT prove: that the packages exist in trixie, that the image
# boots, or that cloud-init accepts the generated files on a device.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# Work on a copy so local secrets.env / build-info.env cannot leak into results.
cp -a "${REPO_DIR}/stage-custom" "${WORK}/stage-custom"
rm -f "${WORK}/stage-custom/secrets.env" "${WORK}/stage-custom/build-info.env"
export STAGE_DIR="${WORK}/stage-custom"

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok    $*"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL  $*" >&2; }
rel()  { printf '%s' "${1#"${ROOTFS_DIR}"}"; }

assert_file()     { if [ -f "$1" ]; then ok "exists $(rel "$1")"; else fail "missing $(rel "$1")"; fi; }
assert_no_file()  { if [ ! -e "$1" ]; then ok "absent $(rel "$1")"; else fail "should be absent: $(rel "$1")"; fi; }
assert_exec()     { if [ -x "$1" ]; then ok "executable $(rel "$1")"; else fail "not executable $(rel "$1")"; fi; }
assert_grep()     { if grep -qE -- "$1" "$2"; then ok "/$1/ in $(rel "$2")"; else fail "/$1/ not in $(rel "$2")"; fi; }
assert_no_grep()  { if ! grep -qE -- "$1" "$2"; then ok "/$1/ absent from $(rel "$2")"; else fail "/$1/ unexpectedly in $(rel "$2")"; fi; }
assert_count()    { # pattern file expected
	local n; n="$(grep -cE -- "$1" "$2" || true)"
	if [ "${n}" = "$3" ]; then ok "/$1/ appears $3x in $(rel "$2")"; else fail "/$1/ appears ${n}x in $(rel "$2"), expected $3"; fi
}
assert_eq()       { if [ "$1" = "$2" ]; then ok "$3"; else fail "$3 (got '$1', expected '$2')"; fi; }

# --- pi-gen environment, as build.sh exports it -----------------------------------
export ROOTFS_DIR="${WORK}/rootfs"
export STAGE_WORK_DIR="${WORK}"
export LOG_FILE="${WORK}/build.log"
export IMG_NAME="custom-raspios" IMG_DATE="2026-01-01" RELEASE="trixie" ARCH="arm64" GIT_HASH="0123abcd"
export FIRST_USER_NAME="nodoai" TARGET_HOSTNAME="nodobox" WPA_COUNTRY="IN" ENABLE_CLOUD_INIT="1" USE_QEMU="0" KEYBOARD_KEYMAP="us"
export WORK_DIR="${WORK}/work"
export CHROOT_LOG="${WORK}/chroot-commands.sh"

log() { echo "    [log] $*"; }
# Capture instead of executing; syntax-check what would run inside the chroot.
on_chroot() {
	local script
	script="$(cat)"
	printf '# --- on_chroot from %s ---\n%s\n' "${PWD##*/}" "${script}" >> "${CHROOT_LOG}"
	bash -n <(printf '%s\n' "${script}")
}
export -f log on_chroot

make_rootfs() {
	rm -rf "${ROOTFS_DIR}"
	mkdir -p "${ROOTFS_DIR}/boot/firmware" "${ROOTFS_DIR}/etc/lightdm" "${ROOTFS_DIR}/home/nodoai" "${ROOTFS_DIR}/etc/skel" \
		"${ROOTFS_DIR}/etc/xdg/labwc" "${ROOTFS_DIR}/usr/bin"
	# a greeter config and a labwc config as the desktop stages leave them
	printf '[greeter]\nwallpaper=/usr/share/rpd-wallpaper/old.png\ndesktop_bg=#d6d6d3d3dede\ngtk-icon-theme-name=PiXtrix\ngtk-theme-name=PiXtrix\n' > "${ROOTFS_DIR}/etc/lightdm/pi-greeter.conf"
	printf '<?xml version="1.0"?>\n<labwc_config><theme><name>PiXnoir</name></theme></labwc_config>\n' > "${ROOTFS_DIR}/etc/xdg/labwc/rc.xml"
	if [ "${FAKE_WAYFIRE:-0}" = "1" ]; then
		printf '#!/bin/sh\n' > "${ROOTFS_DIR}/usr/bin/wayfire"; chmod +x "${ROOTFS_DIR}/usr/bin/wayfire"
	fi
	# what the desktop packages leave behind and 13-system-defaults checks for
	mkdir -p "${ROOTFS_DIR}/usr/lib/systemd/system" "${ROOTFS_DIR}/etc/plymouth"
	: > "${ROOTFS_DIR}/usr/lib/systemd/system/lightdm.service"
	: > "${ROOTFS_DIR}/usr/lib/systemd/system/wayvnc.service"
	: > "${ROOTFS_DIR}/etc/plymouth/plymouthd.conf"
	for b in chromium firefox; do printf '#!/bin/sh\n' > "${ROOTFS_DIR}/usr/bin/${b}"; chmod +x "${ROOTFS_DIR}/usr/bin/${b}"; done
	printf 'console=serial0,115200 console=tty1 root=PARTUUID=x rootfstype=ext4 fsck.repair=yes rootwait cfg80211.ieee80211_regdom=IN\n' > "${ROOTFS_DIR}/boot/firmware/cmdline.txt"
	# What stage1/stage2 leave behind and stage-custom touches.
	printf '# pi-gen config.txt (abridged)\ndtparam=audio=on\narm_64bit=1\n\n[all]\n' > "${ROOTFS_DIR}/boot/firmware/config.txt"
	printf '# pi-gen placeholder network-config\n' > "${ROOTFS_DIR}/boot/firmware/network-config"
	printf '#cloud-config\n# pi-gen placeholder user-data\n' > "${ROOTFS_DIR}/boot/firmware/user-data"
	: > "${CHROOT_LOG}"
}

# Mirrors pi-gen for *-run.sh (host) and *-run-chroot.sh (captured).
run_stage() {
	local sub i
	for sub in "${STAGE_DIR}"/*/; do
		[ -f "${sub}/SKIP" ] && continue
		pushd "${sub}" > /dev/null
		for i in $(seq -w 0 99); do
			if [ -x "${i}-run.sh" ]; then
				"./${i}-run.sh"
			fi
			if [ -f "${i}-run-chroot.sh" ]; then
				on_chroot < "${i}-run-chroot.sh"
			fi
		done
		popd > /dev/null
	done
}

# Reset every custom.conf knob so scenarios do not bleed into each other.
reset_knobs() {
	unset WIFI_SSID WIFI_PASSWORD WIFI_HIDDEN WIFI_INTERFACE
	unset ENABLE_I2C ENABLE_SPI ENABLE_UART CONFIG_TXT_EXTRA
	unset PERSISTENT_JOURNAL JOURNAL_MAX_USE ENABLE_UNATTENDED_UPGRADES
	unset ENABLE_SERVICES DISABLE_SERVICES PASSWORDLESS_SUDO
	unset ENABLE_SERIAL_PORT ENABLE_SERIAL_CONSOLE ENABLE_ONEWIRE ENABLE_VNC GENESIS_SESSION GENESIS_WALLPAPER
	unset GENESIS_PANEL_POSITION GENESIS_PANEL_LAUNCHERS DESKTOP_AUTOLOGIN DEFAULT_BROWSER ENABLE_BOOT_SPLASH
	unset INSTALL_VSCODE VSCODE_EXTENSIONS PYTHON_PRIMARY FAKE_WAYFIRE GENESIS_PRUNE_WORK
	export ENABLE_CLOUD_INIT="1" WPA_COUNTRY="IN" ARCH="arm64"
}

# ===================================================================================
echo "Static checks"
assert_exec "${STAGE_DIR}/prerun.sh"
assert_file "${STAGE_DIR}/EXPORT_IMAGE"
bash -n "${STAGE_DIR}/EXPORT_IMAGE" && ok "EXPORT_IMAGE parses"
for sub in "${STAGE_DIR}"/*/; do
	name="$(basename "${sub}")"
	if [[ "${name}" =~ ^[0-9]{2}- ]]; then ok "sub-stage ${name} is numbered"; else fail "sub-stage ${name} must start with two digits"; fi
	for f in "${sub}"[0-9][0-9]-run.sh; do
		[ -e "${f}" ] || continue
		if [ -x "${f}" ]; then ok "${name}/$(basename "${f}") is executable"; else fail "${name}/$(basename "${f}") is NOT executable: pi-gen would log 'Skip' and build without it"; fi
		bash -n "${f}" && ok "${name}/$(basename "${f}") parses"
	done
	for f in "${sub}"[0-9][0-9]-run-chroot.sh; do
		[ -e "${f}" ] || continue
		bash -n "${f}" && ok "${name}/$(basename "${f}") parses"
	done
	for f in "${sub}"[0-9][0-9]-packages "${sub}"[0-9][0-9]-packages-nr; do
		[ -e "${f}" ] || continue
		# Same stripping as pi-gen's scripts/remove-comments.sed
		pkgs="$(sed -e 's/#.*//' "${f}" | tr -s '[:space:]' ' ')"
		if [ -z "${pkgs// /}" ]; then fail "${name}/$(basename "${f}") is empty after stripping comments"; fi
		for p in ${pkgs}; do
			if [[ "${p}" =~ ^[a-z0-9][a-z0-9+.-]*$ ]]; then ok "package token '${p}'"; else fail "invalid package token '${p}' in ${name}/$(basename "${f}")"; fi
		done
	done
done

# ===================================================================================
echo "Scenario 1: defaults (no Wi-Fi, no knobs)"
reset_knobs
make_rootfs
run_stage
CFG="${ROOTFS_DIR}/boot/firmware/config.txt"
assert_count '^# --- stage-custom' "${CFG}" 1
assert_eq "$(grep -B1 -E '^# --- stage-custom' "${CFG}" | head -n1)" "[all]" "marker block opens with [all]"
assert_count '^dtparam=i2c_arm=on$' "${CFG}" 1
assert_count '^dtparam=spi=on$' "${CFG}" 1
assert_count '^enable_uart=1$' "${CFG}" 1
assert_count '^dtparam=uart0=on$' "${CFG}" 1
assert_eq "$(grep -B1 -E '^dtparam=uart0=on$' "${CFG}" | head -n1)" "[pi5]" "Pi 5 UART line sits under [pi5]"
assert_eq "$(grep -A1 -E '^dtparam=uart0=on$' "${CFG}" | tail -n1)" "[all]" "[pi5] block is closed with [all]"
assert_count '^disable_splash=1$' "${CFG}" 1
assert_no_grep '^dtoverlay=w1-gpio' "${CFG}"
# desktop defaults
assert_grep 'apt-get -o Acquire::Retries=3 update' "${CHROOT_LOG}"
assert_file "${ROOTFS_DIR}/usr/share/keyrings/microsoft.gpg"
assert_file "${ROOTFS_DIR}/etc/apt/sources.list.d/vscode.sources"
assert_grep 'install -y code' "${CHROOT_LOG}"
assert_file "${ROOTFS_DIR}/home/nodoai/.config/Code/User/settings.json"
assert_grep 'cpython-3.10.22\+20261009-aarch64-unknown-linux-gnu-install_only_stripped.tar.gz' "${CHROOT_LOG}"
assert_grep '"ecbe978a7ecbeb3a9aed67bb5d161180701513b4fa8101037b2a3f1ac11e96be  .*" \| sha256sum -c -' "${CHROOT_LOG}"
assert_grep 'ln -sfn "/opt/python/3.10/bin/python3.10" /usr/local/bin/python$' "${CHROOT_LOG}"
assert_no_grep 'ln -sfn [^ ]* /usr/local/bin/python3$' "${CHROOT_LOG}"
assert_file "${ROOTFS_DIR}/usr/share/icons/hicolor/256x256/apps/genesis-os.png"
assert_file "${ROOTFS_DIR}/usr/share/icons/Genesis/48x48/places/start-here.png"
assert_grep '^Inherits=PiXnoir,PiXtrix' "${ROOTFS_DIR}/usr/share/icons/Genesis/index.theme"
assert_file "${ROOTFS_DIR}/usr/share/genesis/wallpapers/genesis-horizon.jpg"
assert_file "${ROOTFS_DIR}/usr/share/plymouth/themes/genesis/splash.png"
assert_grep 'plymouth-set-default-theme genesis' "${CHROOT_LOG}"
assert_grep '^wallpaper=/usr/share/genesis/wallpapers/genesis-horizon.jpg$' "${ROOTFS_DIR}/etc/lightdm/pi-greeter.conf"
assert_grep '^gtk-icon-theme-name=Genesis$' "${ROOTFS_DIR}/etc/lightdm/pi-greeter.conf"
assert_grep '^#PanelToplevel' "${ROOTFS_DIR}/usr/share/themes/GenesisGlass/gtk-3.0/gtk.css"
assert_grep 'Adwaita/gtk-contained-dark.css' "${ROOTFS_DIR}/usr/share/themes/GenesisGlass/gtk-3.0/gtk.css"
assert_grep '^launchers=chromium code pcmanfm lxterminal genesis-settings$' "${ROOTFS_DIR}/home/nodoai/.config/wf-panel-pi/wf-panel-pi.ini"
assert_grep '^position=top$' "${ROOTFS_DIR}/etc/skel/.config/wf-panel-pi/wf-panel-pi.ini"
assert_grep '^wallpaper=/usr/share/genesis/wallpapers/genesis-horizon.jpg$' "${ROOTFS_DIR}/home/nodoai/.config/pcmanfm/default/desktop-items-0.conf"
assert_grep '^wallpaper=/usr/share/genesis/wallpapers/genesis-horizon.jpg$' "${ROOTFS_DIR}/etc/xdg/pcmanfm/default/desktop-items-0.conf"
# shellcheck disable=SC2016  # the chroot script must contain a literal "$base"
assert_grep 'labwc-rc-patch.py /etc/xdg/labwc/rc.xml "\$base/.config/labwc/rc.xml"' "${CHROOT_LOG}"
assert_grep 'install -y wayfire; then' "${CHROOT_LOG}"
assert_eq "$(cat "${ROOTFS_DIR}/etc/genesis/session")" "labwc" "no wayfire binary -> labwc session recorded"
assert_no_file "${ROOTFS_DIR}/usr/share/wayland-sessions/genesis-glass.desktop"
assert_file "${ROOTFS_DIR}/usr/lib/genesis-settings/genesis_settings.py"
assert_exec "${ROOTFS_DIR}/usr/lib/genesis-settings/genesis-helper"
assert_exec "${ROOTFS_DIR}/usr/bin/genesis-settings"
assert_file "${ROOTFS_DIR}/usr/share/applications/genesis-settings.desktop"
assert_grep 'rc do_i2c 0 ' "${CHROOT_LOG}"
assert_grep 'rc do_spi 0 ' "${CHROOT_LOG}"
assert_grep 'rc do_serial_hw 0 ' "${CHROOT_LOG}"
assert_grep 'rc do_serial_cons 1 ' "${CHROOT_LOG}"
assert_grep 'systemctl enable wayvnc.service' "${CHROOT_LOG}"
assert_grep 'update-alternatives --set x-www-browser "/usr/bin/chromium"' "${CHROOT_LOG}"
assert_grep '^if ! rc do_boot_behaviour B4; then$' "${CHROOT_LOG}"
assert_grep "^grep -q '\^autologin-user=nodoai\\\$' /etc/lightdm/lightdm.conf " "${CHROOT_LOG}"
assert_no_grep 'genesis-helper session wayfire' "${CHROOT_LOG}"
assert_grep '^text/html=chromium.desktop$' "${ROOTFS_DIR}/home/nodoai/.config/mimeapps.list"
assert_grep ' quiet splash plymouth.ignore-serial-consoles logo.nologo$' "${ROOTFS_DIR}/boot/firmware/cmdline.txt"
assert_count 'splash' "${ROOTFS_DIR}/boot/firmware/cmdline.txt" 1
assert_file "${ROOTFS_DIR}/etc/motd"
assert_file "${ROOTFS_DIR}/etc/systemd/journald.conf.d/10-custom.conf"
assert_grep '^SystemMaxUse=64M$' "${ROOTFS_DIR}/etc/systemd/journald.conf.d/10-custom.conf"
assert_grep 'Unattended-Upgrade "1"' "${ROOTFS_DIR}/etc/apt/apt.conf.d/20auto-upgrades"
assert_file "${ROOTFS_DIR}/etc/apt/apt.conf.d/52unattended-upgrades-raspberrypi"
assert_grep '^# pi-gen placeholder network-config' "${ROOTFS_DIR}/boot/firmware/network-config"
assert_eq "$(head -n1 "${ROOTFS_DIR}/boot/firmware/user-data")" "#cloud-config" "user-data starts with #cloud-config"
assert_no_grep '^[^#]' "${ROOTFS_DIR}/boot/firmware/user-data"
assert_file "${ROOTFS_DIR}/etc/custom-image-release"
assert_grep '^IMAGE_NAME=custom-raspios$' "${ROOTFS_DIR}/etc/custom-image-release"
assert_grep '^PI_GEN_COMMIT=0123abcd$' "${ROOTFS_DIR}/etc/custom-image-release"
assert_grep '^SOURCE_COMMIT=unknown$' "${ROOTFS_DIR}/etc/custom-image-release"
assert_exec "${ROOTFS_DIR}/usr/local/bin/hello-custom"
assert_file "${ROOTFS_DIR}/etc/systemd/system/hello-custom.service"
assert_grep 'systemctl enable hello-custom.service' "${CHROOT_LOG}"
assert_no_grep 'for unit in' "${CHROOT_LOG}"
assert_no_grep 'do_sudo_pass' "${CHROOT_LOG}"
assert_no_file "${ROOTFS_DIR}/stage-custom"
assert_no_file "${ROOTFS_DIR}/secrets.env"

# ===================================================================================
echo "Scenario 2: Wi-Fi with awkward characters, interfaces, services, knobs off"
reset_knobs
export FAKE_WAYFIRE=1
make_rootfs
export WIFI_SSID='Café "Net" \ 5G' WIFI_PASSWORD='correct horse battery' WIFI_HIDDEN=1
export ENABLE_I2C=1 ENABLE_SPI=1 ENABLE_SERIAL_PORT=1 ENABLE_ONEWIRE=1 CONFIG_TXT_EXTRA=$'gpu_mem=16\n\ndtoverlay=disable-bt'
export GENESIS_WALLPAPER=genesis-aurora GENESIS_PANEL_POSITION=bottom GENESIS_PANEL_LAUNCHERS='code lxterminal'
export DEFAULT_BROWSER=firefox ENABLE_VNC=0 DESKTOP_AUTOLOGIN=0 INSTALL_VSCODE=0
export ENABLE_SERVICES='hello-custom.service' DISABLE_SERVICES='bluetooth.service hciuart.service'
export PERSISTENT_JOURNAL=0 ENABLE_UNATTENDED_UPGRADES=0
printf 'CUSTOM_GIT_SHA=abc123\nCUSTOM_GIT_REF=main\nCUSTOM_BUILD_URL=https://example.test/run/1\nPASSWORDLESS_SUDO=1\n' > "${STAGE_DIR}/build-info.env"
run_stage
rm -f "${STAGE_DIR}/build-info.env"
assert_count '^dtparam=i2c_arm=on$' "${CFG}" 1
assert_count '^dtparam=spi=on$' "${CFG}" 1
assert_count '^enable_uart=1$' "${CFG}" 1
assert_count '^dtoverlay=w1-gpio$' "${CFG}" 1
assert_count '^gpu_mem=16$' "${CFG}" 1
assert_count '^dtoverlay=disable-bt$' "${CFG}" 1
assert_eq "$(cat "${ROOTFS_DIR}/etc/genesis/session")" "wayfire" "wayfire present -> glass session recorded"
assert_file "${ROOTFS_DIR}/usr/share/wayland-sessions/genesis-glass.desktop"
assert_exec "${ROOTFS_DIR}/usr/bin/genesis-wayfire"
assert_grep '^xkb_layout = us$' "${ROOTFS_DIR}/etc/wayfire/genesis.ini"
assert_grep '^plugins = .*blur' "${ROOTFS_DIR}/home/nodoai/.config/wayfire.ini"
assert_no_grep '@EXTRA_PLUGINS@\|@XKB_LAYOUT@' "${ROOTFS_DIR}/etc/wayfire/genesis.ini"
assert_grep 'genesis-helper session wayfire' "${CHROOT_LOG}"
assert_grep '^position=bottom$' "${ROOTFS_DIR}/home/nodoai/.config/wf-panel-pi/wf-panel-pi.ini"
assert_grep '^launchers=code lxterminal$' "${ROOTFS_DIR}/home/nodoai/.config/wf-panel-pi/wf-panel-pi.ini"
assert_grep 'genesis-aurora.jpg$' "${ROOTFS_DIR}/home/nodoai/.config/pcmanfm/default/desktop-items-0.conf"
assert_no_grep 'install -y code' "${CHROOT_LOG}"
assert_no_file "${ROOTFS_DIR}/etc/apt/sources.list.d/vscode.sources"
assert_no_grep 'systemctl enable wayvnc.service' "${CHROOT_LOG}"
assert_grep '^if ! rc do_boot_behaviour B3; then$' "${CHROOT_LOG}"
assert_no_grep 'do_boot_behaviour B4' "${CHROOT_LOG}"
assert_grep 'update-alternatives --set x-www-browser "/usr/bin/firefox"' "${CHROOT_LOG}"
# CONFIG_TXT_EXTRA must land under [all], not inside the [pi5] block
assert_eq "$(awk '/^\[/{sec=$0} /^gpu_mem=16$/{print sec}' "${CFG}")" "[all]" "CONFIG_TXT_EXTRA is in the [all] section"
assert_grep '^text/html=firefox.desktop$' "${ROOTFS_DIR}/home/nodoai/.config/mimeapps.list"
assert_grep 'rc do_onewire 0 ' "${CHROOT_LOG}"
# the labwc rc.xml patcher really works (it runs inside the chroot in a real build)
assert_eq "$(python3 "${STAGE_DIR}/11-glass-theme/files/labwc-rc-patch.py" "${ROOTFS_DIR}/etc/xdg/labwc/rc.xml" "${WORK}/rc-patched.xml" && grep -o 'cornerRadius>10<\|dropShadows>yes<' "${WORK}/rc-patched.xml" | wc -l)" "2" "labwc-rc-patch.py adds cornerRadius and dropShadows"
# the privileged helper parses and refuses garbage
assert_eq "$(bash -n "${STAGE_DIR}/12-genesis-settings/files/genesis-helper" && echo ok)" "ok" "genesis-helper parses"
if (bash "${STAGE_DIR}/12-genesis-settings/files/genesis-helper" set i2c 5 > /dev/null 2>&1); then fail "genesis-helper accepted a bad value"; else ok "genesis-helper rejects a bad value"; fi
assert_no_file "${ROOTFS_DIR}/etc/systemd/journald.conf.d/10-custom.conf"
assert_grep 'Unattended-Upgrade "0"' "${ROOTFS_DIR}/etc/apt/apt.conf.d/20auto-upgrades"
assert_no_file "${ROOTFS_DIR}/etc/apt/apt.conf.d/52unattended-upgrades-raspberrypi"
assert_grep '^SOURCE_COMMIT=abc123$' "${ROOTFS_DIR}/etc/custom-image-release"
assert_grep '^BUILD_URL=https://example.test/run/1$' "${ROOTFS_DIR}/etc/custom-image-release"
assert_grep '^SUDO_USER="nodoai" raspi-config nonint do_sudo_pass 1$' "${CHROOT_LOG}"
assert_grep 'for unit in hello-custom.service; do' "${CHROOT_LOG}"
first_05="$(grep -n 'on_chroot from 05-hello-service' "${CHROOT_LOG}" | head -n1 | cut -d: -f1)"
first_90="$(grep -n 'on_chroot from 90-services' "${CHROOT_LOG}" | head -n1 | cut -d: -f1)"
if [ -n "${first_05}" ] && [ -n "${first_90}" ] && [ "${first_05}" -lt "${first_90}" ]; then
	ok "services sub-stage runs after the example unit is installed"
else
	fail "services sub-stage must run after sub-stages that install units (05 at line ${first_05:-?}, 90 at line ${first_90:-?})"
fi
assert_grep 'for unit in bluetooth.service hciuart.service; do' "${CHROOT_LOG}"
# shellcheck disable=SC2016  # the chroot script must contain a literal "$unit"
assert_grep 'systemctl disable "\$unit"' "${CHROOT_LOG}"
NETCFG="${ROOTFS_DIR}/boot/firmware/network-config"
assert_no_grep 'pi-gen placeholder' "${NETCFG}"
assert_grep '^network:$' "${NETCFG}"
assert_grep '^    renderer: NetworkManager$' "${NETCFG}"
assert_grep '^    wlan0:$' "${NETCFG}"
assert_grep '^      regulatory-domain: "IN"$' "${NETCFG}"
assert_grep '^          hidden: true$' "${NETCFG}"
if python3 -c 'import yaml' 2>/dev/null; then
	python3 - "${NETCFG}" "${WIFI_SSID}" "${WIFI_PASSWORD}" <<'PY'
import sys, yaml
path, ssid, password = sys.argv[1:4]
with open(path, encoding="utf-8") as fh:
    doc = yaml.safe_load(fh)
wlan = doc["network"]["wifis"]["wlan0"]
ap = wlan["access-points"]
assert doc["network"]["version"] == 2, doc
assert wlan["dhcp4"] is True and wlan["optional"] is True, wlan
assert wlan["regulatory-domain"] == "IN", wlan
assert list(ap) == [ssid], list(ap)
assert ap[ssid]["password"] == password, ap[ssid]
assert ap[ssid]["hidden"] is True, ap[ssid]
print("    network-config parses as YAML and round-trips SSID and password")
PY
	ok "network-config YAML round-trip"
else
	echo "    python3-yaml not available: skipping YAML round-trip, checking escaped text instead"
	assert_grep '"Café \\"Net\\" \\\\ 5G":' "${NETCFG}"
fi

# ===================================================================================
echo "Scenario 3: running the stage twice does not duplicate config.txt lines"
run_stage
assert_count '^# --- stage-custom' "${CFG}" 1
assert_count '^\[all\]$' "${CFG}" 3
assert_count '^\[pi5\]$' "${CFG}" 1
assert_count '^dtparam=i2c_arm=on$' "${CFG}" 1
assert_count '^gpu_mem=16$' "${CFG}" 1

# ===================================================================================
echo "Scenario 4: invalid Wi-Fi settings make the build fail loudly"
reset_knobs
make_rootfs
if (cd "${STAGE_DIR}/02-cloud-init" && WIFI_SSID=net WPA_COUNTRY='' ./00-run.sh > /dev/null 2>&1); then
	fail "Wi-Fi without WPA_COUNTRY should fail"
else
	ok "Wi-Fi without WPA_COUNTRY fails"
fi
if (cd "${STAGE_DIR}/02-cloud-init" && WIFI_SSID=net WIFI_PASSWORD=short ./00-run.sh > /dev/null 2>&1); then
	fail "7-character Wi-Fi password should fail"
else
	ok "short Wi-Fi password fails"
fi
if (cd "${STAGE_DIR}/02-cloud-init" && WIFI_SSID=net WIFI_PASSWORD=longenough WIFI_INTERFACE='wlan0; rm' ./00-run.sh > /dev/null 2>&1); then
	fail "invalid WIFI_INTERFACE should fail"
else
	ok "invalid WIFI_INTERFACE fails"
fi
if (cd "${STAGE_DIR}/02-cloud-init" && WIFI_SSID=open-net ./00-run.sh > /dev/null); then
	ok "open network (no password) is accepted"
	assert_no_grep 'password:' "${NETCFG}"
else
	fail "open network (no password) should be accepted"
fi

# ===================================================================================
echo "Scenario 5: ENABLE_CLOUD_INIT=0 leaves the boot partition files alone"
reset_knobs
make_rootfs
export ENABLE_CLOUD_INIT=0 WIFI_SSID=net WIFI_PASSWORD=longenough
run_stage
assert_grep '^# pi-gen placeholder network-config' "${NETCFG}"
assert_grep '^# pi-gen placeholder user-data' "${ROOTFS_DIR}/boot/firmware/user-data"

# ===================================================================================
echo
echo "${PASS} passed, ${FAIL} failed"
[ "${FAIL}" -eq 0 ]
