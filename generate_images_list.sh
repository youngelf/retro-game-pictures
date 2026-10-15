#!/usr/bin/env bash
# ==============================================================================
# generate_images_list.sh
#
# Traverses the boxart/ directory structure and writes a sorted list of all
# relative image file paths (boxart/<Console>/<File>.png) to images_list.txt.
#
# Usage:
#   ./generate_images_list.sh [OPTIONS] [ROOT_DIR]
#
# Options:
#   -o, --out <FILE>   Output index file path (default: <ROOT_DIR>/images_list.txt)
#   -h, --help         Show this help message and exit
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"
OUT_FILE=""

usage() {
    cat << 'HELP_EOF'
Usage: generate_images_list.sh [OPTIONS] [ROOT_DIR]

Traverses <ROOT_DIR>/boxart and writes all image paths (boxart/<Console>/<Image>)
to images_list.txt.

Options:
  -o, --out <FILE>   Path to write images_list.txt (default: <ROOT_DIR>/images_list.txt)
  -h, --help         Show this help message and exit
HELP_EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        -o|--out|--output)
            [[ $# -lt 2 ]] && { echo "Error: Missing argument for $1" >&2; exit 1; }
            OUT_FILE="$2"
            shift 2
            ;;
        -*)
            echo "Error: Unknown option '$1'" >&2
            exit 1
            ;;
        *)
            ROOT_DIR="$1"
            shift
            ;;
    esac
done

ROOT_DIR="$(cd "$ROOT_DIR" && pwd)"
BOXART_DIR="${ROOT_DIR}/boxart"

if [[ ! -d "$BOXART_DIR" ]]; then
    echo "Error: Boxart directory not found at '$BOXART_DIR'" >&2
    exit 1
fi

if [[ -z "$OUT_FILE" ]]; then
    OUT_FILE="${ROOT_DIR}/images_list.txt"
fi

# Collect all regular image files inside non-symlinked console directories under boxart/
(
    cd "$ROOT_DIR"
    find boxart -mindepth 2 -maxdepth 2 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) | LC_ALL=C sort
) > "$OUT_FILE"

COUNT="$(wc -l < "$OUT_FILE" | tr -d ' ')"
echo "Generated '$OUT_FILE' with ${COUNT} image entries."
