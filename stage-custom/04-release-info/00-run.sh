#!/bin/bash -e
# Record what this image was built from in /etc/custom-image-release
# (key=value, shell and systemd EnvironmentFile compatible).
#
# IMG_NAME, IMG_DATE, RELEASE, ARCH and GIT_HASH (pi-gen's commit) come from
# pi-gen. CUSTOM_GIT_SHA, CUSTOM_GIT_REF and CUSTOM_BUILD_URL come from
# build-info.env, written by scripts/build-local.sh or the GitHub workflow.

# shellcheck source=../lib.sh
source "${STAGE_DIR}/lib.sh"

RELEASE_FILE="${ROOTFS_DIR}/etc/custom-image-release"

{
	printf 'IMAGE_NAME=%s\n' "${IMG_NAME:-unknown}"
	printf 'IMAGE_DATE=%s\n' "${IMG_DATE:-unknown}"
	printf 'DEBIAN_RELEASE=%s\n' "${RELEASE:-unknown}"
	printf 'ARCH=%s\n' "${ARCH:-unknown}"
	printf 'PI_GEN_COMMIT=%s\n' "${GIT_HASH:-unknown}"
	printf 'SOURCE_COMMIT=%s\n' "${CUSTOM_GIT_SHA:-unknown}"
	printf 'SOURCE_REF=%s\n' "${CUSTOM_GIT_REF:-unknown}"
	printf 'BUILD_URL=%s\n' "${CUSTOM_BUILD_URL:-local}"
} > "${RELEASE_FILE}"
chmod 644 "${RELEASE_FILE}"

log "Wrote $(basename "${RELEASE_FILE}") (source ${CUSTOM_GIT_SHA:-unknown})"
