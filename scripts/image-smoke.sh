#!/bin/bash
# Smoke-test the desktop of a built image without a Raspberry Pi: mount the
# image, chroot into it as the first user and run the Genesis headless preview
# (labwc on a virtual output + Genesis Shell + screenshots). Needs root and a
# host of the same architecture as the image (or binfmt + qemu-user-static).
#
#   sudo scripts/image-smoke.sh pi-gen/deploy/image_*.img.xz OUTPUT_DIR
set -euo pipefail

IMAGE="${1:?usage: image-smoke.sh IMAGE OUTPUT_DIR}"
OUT="${2:?usage: image-smoke.sh IMAGE OUTPUT_DIR}"
mkdir -p "${OUT}"
OUT="$(cd "${OUT}" && pwd)"

if [ "$(id -u)" != "0" ]; then
	echo "image-smoke: run as root (loop devices, mounts, chroot)" >&2
	exit 1
fi

WORK="$(mktemp -d)"
LOOP=""
MOUNTED=()

# shellcheck disable=SC2317  # invoked through the EXIT trap
cleanup() {
	set +e
	for m in "${MOUNTED[@]}"; do
		umount -l "$m" 2> /dev/null
	done
	[ -n "${LOOP}" ] && losetup -d "${LOOP}" 2> /dev/null
	rm -rf "${WORK}"
}
trap cleanup EXIT

echo "image-smoke: unpacking $(basename "${IMAGE}")"
case "${IMAGE}" in
	*.xz) xz -dkc "${IMAGE}" > "${WORK}/image.img" ;;
	*.gz) gzip -dc "${IMAGE}" > "${WORK}/image.img" ;;
	*.zst) zstd -dc "${IMAGE}" > "${WORK}/image.img" ;;
	*.zip) unzip -p "${IMAGE}" > "${WORK}/image.img" ;;
	*.img) cp --reflink=auto "${IMAGE}" "${WORK}/image.img" ;;
	*) echo "image-smoke: unsupported image format: ${IMAGE}" >&2; exit 65 ;;
esac

LOOP="$(losetup --show -f -P "${WORK}/image.img")"
ROOT="${WORK}/root"
mkdir -p "${ROOT}"
mount "${LOOP}p2" "${ROOT}"
MOUNTED+=("${ROOT}")
mount "${LOOP}p1" "${ROOT}/boot/firmware"
MOUNTED+=("${ROOT}/boot/firmware")
for d in dev dev/pts proc sys; do
	mount --bind "/$d" "${ROOT}/$d"
	MOUNTED+=("${ROOT}/$d")
done
# a bind of /dev does not carry the host's /dev/shm mount; wlroots and grim need shared memory
mkdir -p "${ROOT}/dev/shm" "${ROOT}/run"
mount -t tmpfs -o mode=1777 tmpfs "${ROOT}/dev/shm"
MOUNTED+=("${ROOT}/dev/shm")
mount -t tmpfs -o mode=755 tmpfs "${ROOT}/run"
MOUNTED+=("${ROOT}/run")
mount -t tmpfs -o mode=1777 tmpfs "${ROOT}/tmp"
MOUNTED+=("${ROOT}/tmp")

image_arch="$(chroot "${ROOT}" /usr/bin/dpkg --print-architecture 2> /dev/null || echo unknown)"
host_arch="$(uname -m)"
if [ "${image_arch}" = "arm64" ] && [ "${host_arch}" != "aarch64" ] && [ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
	echo "image-smoke: SKIP (image is arm64, host is ${host_arch} without qemu-user-static binfmt)"
	echo "skipped" > "${OUT}/result"
	exit 0
fi

if [ ! -x "${ROOT}/usr/share/genesis-shell/preview.sh" ]; then
	echo "image-smoke: FAIL the image has no /usr/share/genesis-shell/preview.sh (Genesis Shell missing?)" >&2
	exit 1
fi

user_name="$(awk -F: '$3 == 1000 { print $1 }' "${ROOT}/etc/passwd")"
[ -n "${user_name}" ] || user_name=root
home="/home/${user_name}"
[ "${user_name}" = root ] && home=/root
mkdir -p "${ROOT}/tmp/genesis-smoke"
chown 1000:1000 "${ROOT}/tmp/genesis-smoke" 2> /dev/null || true

echo "image-smoke: running the Genesis session headless as ${user_name}"
set +e
chroot --userspec="${user_name}:${user_name}" "${ROOT}" /usr/bin/env -i \
	HOME="${home}" USER="${user_name}" LOGNAME="${user_name}" LANG=C.UTF-8 \
	PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
	XDG_RUNTIME_DIR=/tmp/genesis-smoke-runtime \
	/usr/share/genesis-shell/preview.sh /tmp/genesis-smoke
status=$?
set -e
cp -a "${ROOT}/tmp/genesis-smoke/." "${OUT}/" 2> /dev/null || true
echo "image-smoke: preview exit status ${status}; results in ${OUT}"
ls -l "${OUT}" || true
exit "${status}"
