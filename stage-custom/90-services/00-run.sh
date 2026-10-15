#!/bin/bash -e
# Enable or disable systemd units listed in custom.conf (ENABLE_SERVICES,
# DISABLE_SERVICES). Runs systemctl inside the image chroot.
#
# Numbered 90 so it runs after every sub-stage that installs units: systemctl
# enable fails for a unit that does not exist yet.

# shellcheck source=../lib.sh
source "${STAGE_DIR}/lib.sh"

if [ -z "${ENABLE_SERVICES}" ] && [ -z "${DISABLE_SERVICES}" ]; then
	log "No services to enable or disable"
	exit 0
fi

on_chroot << EOF
for unit in ${ENABLE_SERVICES}; do
	systemctl enable "\$unit"
done
for unit in ${DISABLE_SERVICES}; do
	systemctl disable "\$unit"
done
EOF
