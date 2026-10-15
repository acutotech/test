# shellcheck shell=bash
# Shared helpers for the custom stage. Source it at the top of every *-run.sh:
#
#     source "${STAGE_DIR}/lib.sh"
#
# pi-gen exports STAGE_DIR (this directory), ROOTFS_DIR (the image root being
# built), FIRST_USER_NAME, TARGET_HOSTNAME, WPA_COUNTRY, ENABLE_CLOUD_INIT,
# IMG_NAME, IMG_DATE, RELEASE, ARCH, GIT_HASH and the functions log/on_chroot.

# Load knobs: custom.conf (defaults), then secrets.env and build-info.env when
# present. Both are git-ignored and written by the build scripts or CI.
custom_load_config() {
	# shellcheck source=custom.conf
	source "${STAGE_DIR}/custom.conf"
	local f
	for f in "${STAGE_DIR}/secrets.env" "${STAGE_DIR}/build-info.env"; do
		if [ -f "$f" ]; then
			# shellcheck source=/dev/null
			source "$f"
		fi
	done
}

# Print $1 as a double-quoted YAML scalar (escapes backslash and double quote).
yaml_dq() {
	local s=$1
	s=${s//\\/\\\\}
	s=${s//\"/\\\"}
	printf '"%s"' "$s"
}

# Append $2 as a line to file $1 unless that exact line is already present.
ensure_line() {
	local file=$1 line=$2
	if ! grep -qxF -- "$line" "$file" 2>/dev/null; then
		printf '%s\n' "$line" >> "$file"
	fi
}

custom_load_config
