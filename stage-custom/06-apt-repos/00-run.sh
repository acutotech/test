#!/bin/bash -e
# Third-party apt repositories. Microsoft's repository provides Visual Studio
# Code for arm64; its signing key is vendored in files/microsoft.asc so the
# build does not depend on fetching it (fingerprint BC52 8686 B50D 79E3 39D3
# 721C EB3E 94AD BE12 29CF).

# shellcheck source=../lib.sh
source "${STAGE_DIR}/lib.sh"

if [ "${INSTALL_VSCODE}" != "1" ]; then
	log "INSTALL_VSCODE is not 1: no extra apt repositories"
	exit 0
fi

command -v gpg > /dev/null 2>&1 || { echo "gpg is required on the build host" >&2; exit 1; }

install -d -m 755 "${ROOTFS_DIR}/usr/share/keyrings" "${ROOTFS_DIR}/etc/apt/sources.list.d"
GNUPGHOME="$(mktemp -d)"
export GNUPGHOME
gpg --batch --dearmor --output "${ROOTFS_DIR}/usr/share/keyrings/microsoft.gpg" --yes files/microsoft.asc
rm -rf "${GNUPGHOME}"
chmod 644 "${ROOTFS_DIR}/usr/share/keyrings/microsoft.gpg"
install -m 644 files/vscode.sources "${ROOTFS_DIR}/etc/apt/sources.list.d/vscode.sources"

on_chroot << EOF
apt-get -o Acquire::Retries=3 update
EOF
