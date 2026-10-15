#!/bin/bash -e
# Example of shipping your own software: a script in /usr/local/bin and a
# systemd unit that runs it at every boot. Replace or delete this directory.
#
# Pattern:
#   1. install files from ./files into ${ROOTFS_DIR}
#   2. enable the unit with systemctl inside the chroot

# shellcheck source=../lib.sh
source "${STAGE_DIR}/lib.sh"

install -d -m 755 "${ROOTFS_DIR}/usr/local/bin" "${ROOTFS_DIR}/etc/systemd/system"
install -m 755 files/hello-custom "${ROOTFS_DIR}/usr/local/bin/hello-custom"
install -m 644 files/hello-custom.service "${ROOTFS_DIR}/etc/systemd/system/hello-custom.service"

on_chroot << EOF
systemctl enable hello-custom.service
EOF
