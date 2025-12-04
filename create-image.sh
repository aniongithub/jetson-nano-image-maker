#! /bin/bash

#
# Author: Badr BADRI © pythops (refactor by aniongithub)
# License: MIT
#

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Check if the user is not root
if [ "x$(whoami)" != "xroot" ]; then
    printf "\e[31mThis script requires root privilege\e[0m\n"
    exit 1
fi

usage() {
    cat <<EOF
Usage: $0 -b <board> [-l <l4t>] [-r <revision>] [-d <SD|USB>] [-u <ubuntu>] [-o <outdir>] [--bsp <bsp_url>]

Supported boards: jetson-nano, jetson-nano-2gb, jetson-orin-nano, jetson-agx-orin, jetson-agx-xavier, jetson-xavier-nx
Example: $0 -b jetson-orin-nano -d SD -l 36 -u 24.04
EOF
    exit 1
}

# parse args
BOARD=""
L4T=""
REVISION=""
DEVICE=""
UBUNTU=""
OUTDIR="."
BSP=""

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -b|--board)
            BOARD="$2"; shift 2;;
        -l|--l4t)
            L4T="$2"; shift 2;;
        -r|--revision)
            REVISION="$2"; shift 2;;
        -d|--device)
            DEVICE="$2"; shift 2;;
        -u|--ubuntu)
            UBUNTU="$2"; shift 2;;
        -o|--outdir)
            OUTDIR="$2"; shift 2;;
        --bsp)
            BSP="$2"; shift 2;;
        -h|--help)
            usage;;
        *)
            echo "Unknown arg: $1"; usage;;
    esac
done

if [ -z "$BOARD" ]; then
    echo "Error: board is required"; usage
fi

# load boards metadata
source "$SCRIPT_DIR/boards.sh"
if ! board_metadata "$BOARD"; then
    echo "Unknown board: $BOARD"; exit 1
fi

# Apply Ubuntu default early so rootfs cache/build uses the correct path
UBUNTU=${UBUNTU:-$board_default_ubuntu}

# apply defaults from metadata (board_metadata sets `board_default_ubuntu` and `REQUIRES_DEVICE`)
REQUIRES_DEVICE=${REQUIRES_DEVICE:-no}
if [ -z "${DEVICE:-}" ]; then
    # use per-board default device when omitted
    DEVICE=${board_default_device:-}
fi
if [ "$REQUIRES_DEVICE" = "yes" ] && [ -z "$DEVICE" ]; then
    echo "Error: board $BOARD requires -d <SD|USB|EMMC>"; exit 1
fi


# Determine rootfs directory preference:
# 1) If user exported JETSON_ROOTFS_DIR, use it.
# 2) Else use default cache /var/cache/jetson-rootfs/rootfs-<ubuntu>.
# If the default cache is missing/empty, build into it.
if [ -n "${JETSON_ROOTFS_DIR:-}" ]; then
    echo "Using provided JETSON_ROOTFS_DIR=${JETSON_ROOTFS_DIR}"
else
    ROOTFS_OUT_DIR="/var/cache/jetson-rootfs/rootfs-${UBUNTU}"
    echo "JETSON_ROOTFS_DIR not set; checking default cache at ${ROOTFS_OUT_DIR}"
    if [ ! -d "$ROOTFS_OUT_DIR" ] || [ -z "$(ls -A "$ROOTFS_OUT_DIR")" ]; then
        echo "Cache missing or empty; building rootfs via build-rootfs.sh -> ${ROOTFS_OUT_DIR}"
        "$SCRIPT_DIR/build-rootfs.sh" "$UBUNTU" "$ROOTFS_OUT_DIR"
    else
        echo "Using cached rootfs at ${ROOTFS_OUT_DIR}"
    fi
    JETSON_ROOTFS_DIR="$ROOTFS_OUT_DIR"
fi

if [ ! -d "$JETSON_ROOTFS_DIR" ] || [ -z "$(ls -A "$JETSON_ROOTFS_DIR")" ]; then
    echo "No rootfs found in $JETSON_ROOTFS_DIR"; exit 1
fi

# Prepare build dir
JETSON_BUILD_DIR="${JETSON_BUILD_DIR:-$(pwd)/jetson-build}"
mkdir -p "$JETSON_BUILD_DIR"

# Resolve Ubuntu default from metadata, then pick the latest compatible L4T when not provided
UBUNTU=${UBUNTU:-$board_default_ubuntu}
if [ -z "${L4T:-}" ]; then
    L4T=$(l4t_latest_for "$BOARD" "$UBUNTU" || true)
fi
L4T=${L4T:-$(l4t_default_for "$BOARD" "$UBUNTU")}

# Determine BSP: precedence: CLI --bsp > per-board default mapping (bsp_default_for) > error
if [ -n "$BSP" ]; then
    echo "Using user-supplied BSP: $BSP"
else
    if type -t bsp_default_for >/dev/null 2>&1; then
        BSP_CANDIDATE=$(bsp_default_for "$BOARD" "$L4T" || true)
        if [ -n "$BSP_CANDIDATE" ]; then
            BSP="$BSP_CANDIDATE"
            echo "Auto-selected BSP: $BSP"
        fi
    fi
fi

if [ -z "$BSP" ]; then
    echo "No BSP URL known for board $BOARD and L4T $L4T. Please supply --bsp <url|path>"; exit 1
fi

# Key extraction path by BSP filename for idempotent runs (avoids stale extractions)
BSP_BFN=$(basename "$BSP")
BSP_KEY="${BSP_BFN%.tbz2}"
BSP_KEY="${BSP_KEY%.tar.bz2}"
BSP_EXTRACT_DIR="$JETSON_BUILD_DIR/$BSP_KEY"

echo "Build settings:"
echo "  board: $BOARD"
echo "  l4t:   $L4T"
echo "  ubuntu: $UBUNTU"
echo "  rootfs: $JETSON_ROOTFS_DIR"
echo "  build dir: $JETSON_BUILD_DIR"
echo "  bsp extract: $BSP_EXTRACT_DIR"
echo "  bsp: $BSP"

# Download / extract L4T into BSP-keyed directory if not present
if [ ! -d "$BSP_EXTRACT_DIR/Linux_for_Tegra" ]; then
    printf "\e[32mPrepare L4T BSP (%s)...\e[0m\n" "$BSP_KEY"

    mkdir -p "$BSP_EXTRACT_DIR"
    if [[ "$BSP" =~ ^https?:// ]]; then
        BSP_LOCAL="$JETSON_BUILD_DIR/$BSP_BFN"
        if [ ! -f "$BSP_LOCAL" ]; then
            echo "Downloading BSP to $BSP_LOCAL"
            if ! wget -O "$BSP_LOCAL" "$BSP"; then
                rm -f "$BSP_LOCAL" || true
                echo "\nFailed to download BSP from: $BSP" >&2
                echo "NVIDIA's BSP downloads often require accepting a license or using the Jetson Linux release page." >&2
                echo "Please download the Driver Package (BSP) for your board/L4T from:" >&2
                echo "  https://developer.nvidia.com/embedded/linux-tegra" >&2
                echo "or the Jetson Linux Archive:" >&2
                echo "  https://developer.nvidia.com/embedded/jetson-linux-archive" >&2
                echo "Then re-run with --bsp /path/to/Linux_for_Tegra.tbz2" >&2
                exit 1
            fi
        else
            echo "Reusing cached BSP at $BSP_LOCAL"
        fi
        tar -xjf "$BSP_LOCAL" -C "$BSP_EXTRACT_DIR"
    elif [ -f "$BSP" ]; then
        echo "Using local BSP file $BSP"
        tar -xjf "$BSP" -C "$BSP_EXTRACT_DIR"
    else
        echo "BSP value '$BSP' is not a valid URL or local file."; exit 1
    fi

    printf "\e[32m[OK]\e[0m\n"

    # Fix nvidia's bugs in various BSP scripts (best-effort)
    case "$BSP" in
        *32.5*)
            sed -i 's/cp -f/cp -af/g' "$BSP_EXTRACT_DIR/Linux_for_Tegra/tools/ota_tools/version_upgrade/ota_make_recovery_img_dtb.sh" || true
            ;;
        *32.6*)
            sed -i 's/rootfs_size +/rootfs_size + 128 +/g' "$BSP_EXTRACT_DIR/Linux_for_Tegra/tools/jetson-disk-image-creator.sh" || true
            ;;
    esac

    # L4T 36.x jetson-disk-image-creator.sh leaves boardsku empty for AGX Orin,
    # causing flash.sh to fail without a connected board. Patch it to default to "0000".
    DISK_CREATOR="$BSP_EXTRACT_DIR/Linux_for_Tegra/tools/jetson-disk-image-creator.sh"
    if [ -f "$DISK_CREATOR" ]; then
        # After the line that sets boardid="3701" for jetson-agx-orin-devkit, add boardsku="0000"
        if grep -q 'boardid="3701"' "$DISK_CREATOR" && ! grep -q 'boardsku="0000"' "$DISK_CREATOR"; then
            sed -i '/jetson-agx-orin-devkit)/{n;s/boardid="3701"/boardid="3701"\n\t\t\t\t\tboardsku="0000"/}' "$DISK_CREATOR" || true
        fi
    fi
fi

printf "\e[32mCreating image for %s...\n" "$BOARD"

# Ensure the BSP's Linux_for_Tegra/rootfs is populated.
# NVIDIA tools expect Linux_for_Tegra/rootfs to contain standard utils (mv, cp, /bin, /usr, /lib).
L4T_ROOTFS_DIR="$BSP_EXTRACT_DIR/Linux_for_Tegra/rootfs"
if [ -d "$BSP_EXTRACT_DIR/Linux_for_Tegra" ]; then
    need_populate=0
    if [ ! -d "$L4T_ROOTFS_DIR" ]; then
        need_populate=1
    else
        if [ ! -x "$L4T_ROOTFS_DIR/bin/mv" ]; then
            need_populate=1
        fi
    fi

    if [ "$need_populate" -eq 1 ]; then
        echo "Populating $L4T_ROOTFS_DIR from JETSON_ROOTFS_DIR ($JETSON_ROOTFS_DIR)"
        rm -rf "$L4T_ROOTFS_DIR" || true
        mkdir -p "$L4T_ROOTFS_DIR"
        if command -v rsync >/dev/null 2>&1; then
            rsync -aHAX --numeric-ids "$JETSON_ROOTFS_DIR"/ "$L4T_ROOTFS_DIR"/
        else
            cp -a "$JETSON_ROOTFS_DIR"/. "$L4T_ROOTFS_DIR"/
        fi
    fi
fi

# assemble disk-image args
OUT_IMG="${OUTDIR}/${BOARD}.img"

# Ensure output directory exists and is writable
if ! mkdir -p "${OUTDIR}" 2>/dev/null; then
    echo "Error: cannot create output directory ${OUTDIR}. Check permissions." >&2
    exit 1
fi
if [ ! -w "${OUTDIR}" ]; then
    echo "Error: output directory ${OUTDIR} is not writable." >&2
    exit 1
fi

CREATOR_SCRIPT="$BSP_EXTRACT_DIR/Linux_for_Tegra/tools/jetson-disk-image-creator.sh"

# Resolve disk id deterministically using boards.json via disk_id_for().
if ! type -t disk_id_for >/dev/null 2>&1; then
    echo "Error: disk_id_for() not available; ensure 'boards.sh' is loaded and defines it." >&2
    exit 1
fi
selected_board=$(disk_id_for "$BOARD" "$L4T" || true)
if [ -z "$selected_board" ]; then
    echo "Error: no disk id mapping for board '$BOARD' and L4T '$L4T' in boards.json." >&2
    if [ -x "$CREATOR_SCRIPT" ]; then
        echo "Detected BSP supports the following board ids:" >&2
        creator_usage=$($CREATOR_SCRIPT 2>&1 || true)
        printf "%s\n" "$creator_usage" | grep -oE 'jetson[-_a-z0-9]+' | sort -u | sed 's/^/  - /' >&2
    fi
    echo "Update 'boards.json' to include the correct disk_id for this board+L4T, or install 'jq' and re-run." >&2
    exit 1
fi

JETSON_DISK_ARGS=( -b "$selected_board" )
ARGS=("-o" "$OUT_IMG" "${JETSON_DISK_ARGS[@]}")

# add revision/device flags where relevant
case "$BOARD" in
    jetson-nano)
        rev=${REVISION:-${JETSON_NANO_REVISION:-300}}
        ARGS+=("-r" "$rev")
        ;;
    jetson-nano-2gb)
        ;;
    *)
        # Most Orin/Xavier boards need -r default to set FAB for offline image creation
        ARGS+=("-r" "${REVISION:-default}")
        if [ -n "$DEVICE" ]; then
            # Only pass -d when the BSP's creator script accepts it.
            if [ -x "$CREATOR_SCRIPT" ]; then
                creator_usage=$($CREATOR_SCRIPT 2>&1 || true)
                if echo "$creator_usage" | grep -qE '\s-d\b|\-d <'; then
                    ARGS+=("-d" "$DEVICE")
                else
                    echo "Note: BSP's jetson-disk-image-creator.sh does not accept -d; skipping device flag"
                fi
            else
                # If we can't probe the creator, conservatively skip -d
                echo "Note: cannot probe BSP creator; skipping -d device flag"
            fi
        fi
        ;;
esac

# Call the NVIDIA image creator
# Before invoking, validate that the BSP's creator actually recognizes the
# mapped board id. If it doesn't, present the supported ids and fail with
# actionable guidance so the user can update `boards.json` or pass `--bsp`.
if [ -x "$CREATOR_SCRIPT" ]; then
    creator_usage=$($CREATOR_SCRIPT 2>&1 || true)
    supported_list=$(printf "%s\n" "$creator_usage" | grep -oE 'jetson[-_a-z0-9]+' | sort -u)
    if ! printf "%s\n" "$supported_list" | grep -Fxq "$selected_board"; then
        echo "Error: BSP does not recognize mapped board id '$selected_board'." >&2
        echo "BSP supports the following ids:" >&2
        printf "%s\n" "$supported_list" | sed 's/^/  - /' >&2
        echo "Update 'boards.json' to map '$BOARD' + L4T '$L4T' to one of the above ids, or provide a different BSP with --bsp." >&2
        exit 1
    fi
fi

# Build environment for the NVIDIA creator script
CREATOR_ENV="ROOTFS_DIR=$JETSON_ROOTFS_DIR"
if [ -n "${board_sku:-}" ]; then
    CREATOR_ENV="$CREATOR_ENV BOARDSKU=$board_sku"
fi

env $CREATOR_ENV "$CREATOR_SCRIPT" "${ARGS[@]}"
if [ -f "$OUT_IMG" ]; then
    printf "\e[32mImage created successfully\n"
    printf "Image location: %s\n" "$OUT_IMG"
else
    printf "\e[31mImage creation failed: expected output %s not found\e[0m\n" "$OUT_IMG"
    exit 1
fi
