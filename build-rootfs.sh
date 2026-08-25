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

# Jetson boards are aarch64, so the rootfs must be built for arm64 regardless of
# the host arch. Building natively on an amd64 runner would produce an unbootable
# amd64 rootfs and also breaks apt (the arm64-only ubuntu-ports source 404s for
# binary-amd64, and the nvidia-l4t-* packages are arm64). Override with
# TARGET_PLATFORM if needed.
TARGET_PLATFORM="${TARGET_PLATFORM:-linux/arm64}"
echo "Building for platform: ${TARGET_PLATFORM}"

# Ensure QEMU binfmt handlers are registered so the arm64 build can run under
# emulation on an amd64 host. Best-effort: the host may already have them (e.g.
# via the qemu-user-static package) and local users may lack privileges.
if [ "${BUILDER}" = "docker" ]; then
  # --platform requires BuildKit; enable it explicitly for older docker defaults.
  export DOCKER_BUILDKIT=1
  docker run --privileged --rm tonistiigi/binfmt --install arm64 >/dev/null 2>&1 \
    || echo "Note: could not register QEMU binfmt via tonistiigi/binfmt; assuming host already provides it"
fi

# Allow selecting the base Ubuntu image via build-arg
BASE_IMAGE="ubuntu:${UBUNTU_VERSION}"
echo "Building image with BASE_IMAGE=${BASE_IMAGE}"

# Whether/how to install the NVIDIA L4T packages (kernel, modules, initrd, DTBs,
# bootloader, init) is driven entirely by boards.json via create-image.sh, which
# exports the following for the resolved board + L4T:
#   L4T_SOC      NVIDIA apt repo SoC segment (e.g. t210, t234)
#   L4T_RELEASE  NVIDIA apt release/suite    (e.g. r32.6, r36.4)
#   NEEDS_BIONIC 1/true if the L4T packages require the bionic source (libffi6)
# When run standalone (no board context) these are unset and no L4T is
# installed, yielding a plain Ubuntu rootfs. INSTALL_L4T can still be forced.
L4T_SOC="${L4T_SOC:-}"
L4T_RELEASE="${L4T_RELEASE:-}"
NEEDS_BIONIC="${NEEDS_BIONIC:-0}"
if [ -z "${INSTALL_L4T:-}" ]; then
  if [ -n "${L4T_SOC}" ] && [ -n "${L4T_RELEASE}" ]; then
    INSTALL_L4T=true
  else
    INSTALL_L4T=false
  fi
fi
echo "INSTALL_L4T=${INSTALL_L4T} L4T_SOC=${L4T_SOC:-<none>} L4T_RELEASE=${L4T_RELEASE:-<none>}"

# Whether to install the Docker engine + NVIDIA container runtime into the
# rootfs, and the L4T major used to pick the correct per-era package set
# (r32 vs r36). Driven by boards.json (board.features.container_runtime) via
# create-image.sh; defaults off when building standalone.
INSTALL_CONTAINER_RUNTIME="${INSTALL_CONTAINER_RUNTIME:-false}"
L4T_MAJOR="${L4T_MAJOR:-}"
echo "INSTALL_CONTAINER_RUNTIME=${INSTALL_CONTAINER_RUNTIME} L4T_MAJOR=${L4T_MAJOR:-<none>}"

# Some L4T releases (r32.x) depend on libffi6, which only ships in bionic
# (18.04). Keep the bundled bionic apt source when the board requires it and the
# base isn't already 18.04; otherwise drop it (newer releases use libffi7/8 from
# the base).
if [ "${INSTALL_L4T}" = "true" ] \
    && { [ "${NEEDS_BIONIC}" = "1" ] || [ "${NEEDS_BIONIC}" = "true" ]; } \
    && [ "${UBUNTU_VERSION}" != "18.04" ]; then
  SKIP_BIONIC_APT=0
else
  SKIP_BIONIC_APT=1
fi

${BUILDER} build \
  --platform "${TARGET_PLATFORM}" \
  --build-arg BASE_IMAGE="${BASE_IMAGE}" \
  --build-arg SKIP_BIONIC_APT="${SKIP_BIONIC_APT}" \
  --build-arg INSTALL_L4T="${INSTALL_L4T}" \
  --build-arg L4T_SOC="${L4T_SOC}" \
  --build-arg L4T_RELEASE="${L4T_RELEASE}" \
  --build-arg INSTALL_CONTAINER_RUNTIME="${INSTALL_CONTAINER_RUNTIME}" \
  --build-arg L4T_MAJOR="${L4T_MAJOR}" \
  -t "${BUILD_TAG}" .

tmpcid=$(${BUILDER} create --platform "${TARGET_PLATFORM}" "${BUILD_TAG}")
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
