#!/bin/bash -e
# Visual Studio Code from Microsoft's repository (added in 06-apt-repos), with
# default settings that point it at the primary Python and the extensions from
# VSCODE_EXTENSIONS. Extension installs need the marketplace; a failure there is
# reported but does not fail the image.

# shellcheck source=../lib.sh
source "${STAGE_DIR}/lib.sh"

if [ "${INSTALL_VSCODE}" != "1" ]; then
	log "INSTALL_VSCODE is not 1: skipping Visual Studio Code"
	exit 0
fi

on_chroot << EOF
apt-get -o Acquire::Retries=3 install -y code
EOF

for base in "${ROOTFS_DIR}/etc/skel" "${ROOTFS_DIR}/home/${FIRST_USER_NAME}"; do
	install -d -m 755 "${base}/.config/Code/User"
	install -m 644 files/settings.json "${base}/.config/Code/User/settings.json"
done
chown -R 1000:1000 "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/.config"

if [ -n "${VSCODE_EXTENSIONS}" ]; then
	on_chroot << EOF
for ext in ${VSCODE_EXTENSIONS}; do
	if ! su -s /bin/bash "${FIRST_USER_NAME}" -c "HOME=/home/${FIRST_USER_NAME} code --no-sandbox --user-data-dir /home/${FIRST_USER_NAME}/.config/Code --install-extension \$ext --force" > /tmp/code-ext.log 2>&1; then
		echo "WARNING: could not preinstall VS Code extension \$ext (install it from the Extensions view later):"
		tail -n 5 /tmp/code-ext.log
	fi
done
rm -f /tmp/code-ext.log
chown -R ${FIRST_USER_NAME}: /home/${FIRST_USER_NAME}/.config /home/${FIRST_USER_NAME}/.vscode 2> /dev/null || true
EOF
fi
