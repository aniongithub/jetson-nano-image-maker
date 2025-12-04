#!/usr/bin/env bash
# Per-board metadata and mapping helpers for create-image.sh
# This file exports helper functions used to resolve sane defaults
# and supported Ubuntu <-> L4T combinations per board.

board_metadata() {
  # Simple, deterministic loader: require `jq` and `boards.json`.
  # This avoids multiple fallbacks and keeps mapping maintenance in one place.
  local board="$1"
  JSON_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/boards.json"

  if ! command -v jq >/dev/null 2>&1; then
    echo "Error: 'jq' is required to read boards.json. Install 'jq' and re-run." >&2
    return 1
  fi
  if [ ! -f "$JSON_PATH" ]; then
    echo "Error: $JSON_PATH not found. Please ensure boards.json exists." >&2
    return 1
  fi

  if ! jq -e --arg b "$board" '.boards[$b]' "$JSON_PATH" >/dev/null 2>&1; then
    echo "Error: no metadata for board '$board' in $JSON_PATH" >&2
    return 1
  fi

  board_default_ubuntu=$(jq -r --arg b "$board" '.boards[$b].default_ubuntu // empty' "$JSON_PATH")
  if [ -z "$board_default_ubuntu" ]; then
    echo "Error: default_ubuntu missing for '$board' in $JSON_PATH" >&2
    return 1
  fi
  req=$(jq -r --arg b "$board" '.boards[$b].requires_device // false' "$JSON_PATH")
  if [ "$req" = "true" ] || [ "$req" = "True" ]; then
    REQUIRES_DEVICE="yes"
  else
    REQUIRES_DEVICE="no"
  fi
  board_default_device=$(jq -r --arg b "$board" '.boards[$b].default_device // empty' "$JSON_PATH")
  board_sku=$(jq -r --arg b "$board" '.boards[$b].boardsku // empty' "$JSON_PATH")

  # load candidates array (if present)
  mapfile -t JETSON_DISK_CANDIDATES < <(jq -r --arg b "$board" '.boards[$b].candidates[]? // empty' "$JSON_PATH")

  export JETSON_DISK_CANDIDATES
  export board_default_ubuntu
  export REQUIRES_DEVICE
  export board_default_device
  export board_sku
  return 0
}

# disk_id_for <board> <l4t>
# Return the mapped disk id (string) for the board+L4T from boards.json, or
# empty if not found. Requires `jq` and `boards.json` to be present.
disk_id_for() {
  local board="$1" l4t="$2"
  JSON_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/boards.json"
  if command -v jq >/dev/null 2>&1 && [ -f "$JSON_PATH" ]; then
    jq -r --arg b "$board" --arg l "$l4t" '.boards[$b].disk_ids[$l] // empty' "$JSON_PATH" 2>/dev/null || true
  else
    echo "";
  fi
}

# l4t_default_for <board> <ubuntu>
# Returns the default L4T major (e.g. 32,35,36) for a given board+ubuntu
l4t_default_for() {
  local board="$1" ubuntu="$2"
  JSON_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/boards.json"
  if ! command -v jq >/dev/null 2>&1 || [ ! -f "$JSON_PATH" ]; then
    echo ""; return 0
  fi
  jq -r --arg b "$board" --arg u "$ubuntu" '.boards[$b].l4t_default_for[$u] // empty' "$JSON_PATH" 2>/dev/null || true
}

# ubuntu_default_for <board> <l4t_major>
# Returns a suggested Ubuntu base for a given board + l4t major
ubuntu_default_for() {
  local board="$1" l4t="$2"
  JSON_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/boards.json"
  if ! command -v jq >/dev/null 2>&1 || [ ! -f "$JSON_PATH" ]; then
    echo ""; return 0
  fi
  jq -r --arg b "$board" --arg l "$l4t" '.boards[$b].ubuntu_default_for[$l] // empty' "$JSON_PATH" 2>/dev/null || true
}

# list_supported_combos <board>
# Prints supported Ubuntu -> L4T combos for the board
list_supported_combos() {
  local board="$1"
  JSON_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/boards.json"
  if ! command -v jq >/dev/null 2>&1 || [ ! -f "$JSON_PATH" ]; then
    echo "(no known combos)"; return 0
  fi
  jq -r --arg b "$board" '.boards[$b].supported_combos[]? // empty' "$JSON_PATH" 2>/dev/null || echo "(no known combos)"
}
# l4t_latest_for <board> <ubuntu>
# l4t_latest_for <board> <ubuntu>
# Returns the latest/most-recent L4T major known to work with the given Ubuntu for the board.
# This lets create-image.sh default to the newest compatible L4T when -l is not provided.
l4t_latest_for() {
  local board="$1" ubuntu="$2"
  case "$board" in
    jetson-nano|jetson-nano-2gb)
      if [ "$ubuntu" = "20.04" ]; then echo "32"; else echo ""; fi
      ;;

    jetson-agx-xavier|jetson-xavier-nx)
      if [ "$ubuntu" = "22.04" ]; then echo "35";
      elif [ "$ubuntu" = "20.04" ]; then echo "32";
      else echo ""; fi
      ;;

    jetson-orin-nano|jetson-agx-orin)
      if [ "$ubuntu" = "24.04" ]; then echo "36";
      elif [ "$ubuntu" = "22.04" ]; then echo "35";
      else echo ""; fi
      ;;

    *)
      echo "" ;;
  esac
}


# bsp_default_for <board> <l4t_major>
# Returns a canonical BSP download URL (or empty) for the board + L4T major.
# NOTE: These URLs are best-effort defaults. Verify them for your environment
# or override with --bsp <local-file-or-url> when running `create-image.sh`.
bsp_default_for() {
  local board="$1" l4t="$2"
  JSON_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/boards.json"
  if ! command -v jq >/dev/null 2>&1 || [ ! -f "$JSON_PATH" ]; then
    echo ""; return 0
  fi
  jq -r --arg b "$board" --arg l "$l4t" '.boards[$b].bsp[$l] // empty' "$JSON_PATH" 2>/dev/null || true
}

