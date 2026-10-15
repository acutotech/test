#!/bin/bash -e
# Start from the previous stage's root filesystem (pi-gen convention).

if [ ! -d "${ROOTFS_DIR}" ]; then
	copy_previous
fi
