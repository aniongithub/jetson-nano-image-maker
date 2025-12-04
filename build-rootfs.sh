#!/usr/bin/env bash
# Build and export the Docker rootfs used as JETSON_ROOTFS_DIR
# Usage: ./build-rootfs.sh [ubuntu_version] [output_dir]

set -euo pipefail


# Ubuntu version (default)
UBUNTU_VERSION=${1:-20.04}
# If user provided an explicit output dir, use it; otherwise
# if JETSON_ROOTFS_DIR is set, write to that; otherwise default
# to /var/cache/jetson-rootfs/rootfs-<ubuntu>
if [ -n "${2:-}" ]; then
  OUT_DIR="$2"
elif [ -n "${JETSON_ROOTFS_DIR:-}" ]; then
  OUT_DIR="$JETSON_ROOTFS_DIR"
else
  OUT_DIR="/var/cache/jetson-rootfs/rootfs-${UBUNTU_VERSION}"
fi

echo "Building rootfs for Ubuntu ${UBUNTU_VERSION} -> ${OUT_DIR}"

BUILD_TAG="jetson-rootfs:${UBUNTU_VERSION//./_}"

if command -v podman >/dev/null 2>&1; then
  BUILDER=podman
else
  BUILDER=docker
fi

# The top-level Dockerfile currently targets 20.04. If you need other
# Ubuntu versions, adjust or add Dockerfiles accordingly.
echo "Using builder: ${BUILDER}"

# Allow selecting the base Ubuntu image via build-arg
BASE_IMAGE="ubuntu:${UBUNTU_VERSION}"
echo "Building image with BASE_IMAGE=${BASE_IMAGE}"

# Pass SKIP_BIONIC_APT=1 for non-18.04 builds so Dockerfile can conditionally skip bionic sources
SKIP_BIONIC_APT=0
if [ "${UBUNTU_VERSION}" != "18.04" ]; then
  SKIP_BIONIC_APT=1
fi

${BUILDER} build --build-arg BASE_IMAGE="${BASE_IMAGE}" --build-arg SKIP_BIONIC_APT="${SKIP_BIONIC_APT}" -t "${BUILD_TAG}" .

tmpcid=$(${BUILDER} create "${BUILD_TAG}")
echo "Ensuring output directory exists: ${OUT_DIR}"
if ! mkdir -p "${OUT_DIR}" 2>/dev/null; then
  echo "Failed to create ${OUT_DIR}. Try running with sudo or set JETSON_ROOTFS_CACHE_DIR to a writable path." >&2
  ${BUILDER} rm "${tmpcid}"
  exit 1
fi

echo "Exporting container filesystem to ${OUT_DIR} (this may take a while)"
${BUILDER} export "${tmpcid}" | tar -C "${OUT_DIR}" -xf -
${BUILDER} rm "${tmpcid}"

echo "Cleaning up export artifacts"
rm -f "${OUT_DIR}/root/.bash_history" || true

echo "Rootfs available at: ${OUT_DIR}"
echo "Set JETSON_ROOTFS_DIR=${OUT_DIR} when running create-image.sh"
