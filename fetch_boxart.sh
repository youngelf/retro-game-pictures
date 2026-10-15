#!/usr/bin/env bash
# ==============================================================================
# fetch_boxart.sh
#
# Reads a local index file (images_list.txt) containing relative paths of the
# form "boxart/<Console>/<ImageFile>.png", resolves a freeform system name (or
# infers it from the ROM filename extension), finds all matching box art entries
# from images_list.txt, and downloads them directly from GitHub:
#   https://github.com/youngelf/retro-game-pictures
#
# Standalone usage: A user only needs this script (fetch_boxart.sh) and
# images_list.txt to query and download box art from GitHub.
#
# Usage:
#   ./fetch_boxart.sh [OPTIONS] <GAME_QUERY_OR_FILENAME> [SYSTEM]
#
# Examples:
#   ./fetch_boxart.sh "mario picross" GB
#   ./fetch_boxart.sh marios_picross.gb
#   ./fetch_boxart.sh mario_picross.gb
#   ./fetch_boxart.sh "chrono trigger" SNES
#   ./fetch_boxart.sh -o ./covers super_mario_bros_3.nes
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GITHUB_REPO="${BOXART_GITHUB_REPO:-https://github.com/youngelf/retro-game-pictures}"
GITHUB_BRANCH="${BOXART_GITHUB_BRANCH:-}"
INDEX_FILE="${BOXART_INDEX_FILE:-}"
DEST_DIR="."
SYSTEM_ARG=""
QUERY_ARG=""
LIST_ONLY=false
DRY_RUN=false

usage() {
    cat << 'HELP_EOF'
Usage: fetch_boxart.sh [OPTIONS] <GAME_QUERY_OR_FILENAME> [SYSTEM]

Queries a local images_list.txt index file and downloads matching box art
directly from https://github.com/youngelf/retro-game-pictures.

Arguments:
  <GAME_QUERY_OR_FILENAME>  Game search string (e.g. 'mario picross') or ROM
                            filename (e.g. 'marios_picross.gb', 'zelda.nes').
  [SYSTEM]                  Optional freeform system name (e.g. NES, SNES, SFC,
                            GB, GBC, GBA, NDS, DS, N64, MD, Genesis, SMS).
                            If omitted, inferred from the filename extension.

Options:
  -i, --index <FILE>        Path to images_list.txt
                            (default: ./images_list.txt or <script_dir>/images_list.txt)
  -r, --repo <GITHUB_URL>   GitHub repository URL or owner/repo
                            (default: https://github.com/youngelf/retro-game-pictures)
  -b, --branch <BRANCH>     Git branch to fetch raw files from (default: tries main, then master)
  -s, --system <SYSTEM>     Freeform system name (alternative to 2nd positional argument)
  -o, -d, --out <DIR>       Output directory for downloaded images (default: .)
  -l, --list                List matching entries and GitHub URLs without downloading
  -n, --dry-run             Preview matches, URLs, and target filenames without downloading
  -h, --help                Show this help message and exit

Supported Extensions for Auto-Inference:
  .nes, .fc, .fds, .unf     -> Nintendo - Nintendo Entertainment System (Headered)
  .sfc, .smc, .swc, .fig    -> Nintendo - Super Nintendo Entertainment System
  .gb, .sgb, .dmg           -> Nintendo - Game Boy
  .gbc, .cgb                -> Nintendo - Game Boy Color
  .gba, .agb                -> Nintendo - Game Boy Advance
  .nds, .ids, .dsi          -> Nintendo - Nintendo DS
  .z64, .n64                -> Nintendo - Nintendo 64 (BigEndian)
  .v64                      -> Nintendo - Nintendo 64 (ByteSwapped)
  .md, .gen, .smd, .68k     -> Sega - Mega Drive - Genesis
  .sms, .sg                 -> Sega - Master System - Mark III

Examples:
  fetch_boxart.sh "mario picross" GB
  fetch_boxart.sh marios_picross.gb
  fetch_boxart.sh "super metroid" SNES
  fetch_boxart.sh -o /tmp/covers contra.nes
HELP_EOF
    exit 0
}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        -i|--index)
            [[ $# -lt 2 ]] && { echo "Error: Missing argument for $1" >&2; exit 1; }
            INDEX_FILE="$2"
            shift 2
            ;;
        -r|--repo)
            [[ $# -lt 2 ]] && { echo "Error: Missing argument for $1" >&2; exit 1; }
            GITHUB_REPO="$2"
            shift 2
            ;;
        -b|--branch)
            [[ $# -lt 2 ]] && { echo "Error: Missing argument for $1" >&2; exit 1; }
            GITHUB_BRANCH="$2"
            shift 2
            ;;
        -s|--system)
            [[ $# -lt 2 ]] && { echo "Error: Missing argument for $1" >&2; exit 1; }
            SYSTEM_ARG="$2"
            shift 2
            ;;
        -o|-d|--out|--output)
            [[ $# -lt 2 ]] && { echo "Error: Missing argument for $1" >&2; exit 1; }
            DEST_DIR="$2"
            shift 2
            ;;
        -l|--list)
            LIST_ONLY=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --)
            shift
            while [[ $# -gt 0 ]]; do
                POSITIONAL+=("$1")
                shift
            done
            break
            ;;
        -*)
            echo "Error: Unknown option '$1'" >&2
            echo "Run '$(basename "$0") --help' for usage." >&2
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

if [[ ${#POSITIONAL[@]} -eq 0 ]]; then
    echo "Error: Missing <GAME_QUERY_OR_FILENAME> argument." >&2
    echo "Run '$(basename "$0") --help' for usage." >&2
    exit 1
fi

QUERY_ARG="${POSITIONAL[0]}"
if [[ ${#POSITIONAL[@]} -ge 2 && -z "$SYSTEM_ARG" ]]; then
    SYSTEM_ARG="${POSITIONAL[1]}"
fi

# Locate images_list.txt
if [[ -z "$INDEX_FILE" ]]; then
    if [[ -f "./images_list.txt" ]]; then
        INDEX_FILE="./images_list.txt"
    elif [[ -f "${SCRIPT_DIR}/images_list.txt" ]]; then
        INDEX_FILE="${SCRIPT_DIR}/images_list.txt"
    else
        echo "Error: Could not find 'images_list.txt' in current directory or '${SCRIPT_DIR}'." >&2
        echo "Generate it with generate_images_list.sh or specify -i /path/to/images_list.txt." >&2
        exit 1
    fi
elif [[ ! -f "$INDEX_FILE" ]]; then
    echo "Error: Index file '$INDEX_FILE' does not exist." >&2
    exit 1
fi

# Extract GitHub owner/repo slug from GITHUB_REPO URL
REPO_SLUG="$GITHUB_REPO"
REPO_SLUG="${REPO_SLUG%.git}"
REPO_SLUG="${REPO_SLUG%/}"
if [[ "$REPO_SLUG" =~ github\.com[:/]([^/]+/[^/]+)$ ]]; then
    REPO_SLUG="${BASH_REMATCH[1]}"
fi

# Resolve freeform system alias or file extension to canonical console directory name
resolve_system_name() {
    local raw="$1"
    local key
    key="$(echo "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]._-]+//; s/[[:space:]_-]+$//; s/[[:space:]_-]+/ /g')"

    case "$key" in
        nes|fc|famicom|fds|"family computer"|"nintendo entertainment system"|"nintendo nes"|"nes headered"|"nintendo entertainment system (headered)"|unf|nez)
            echo "Nintendo - Nintendo Entertainment System (Headered)"
            ;;
        snes|sfc|"super nes"|"super nintendo"|"super famicom"|"super nintendo entertainment system"|"nintendo snes"|smc|swc|fig|bs)
            echo "Nintendo - Super Nintendo Entertainment System"
            ;;
        gb|gameboy|"game boy"|dmg|sgb|"super game boy"|"super gameboy"|"nintendo gb"|"nintendo game boy"|"nintendo gameboy")
            echo "Nintendo - Game Boy"
            ;;
        gbc|cgb|"gameboy color"|"game boy color"|"gameboy colour"|"game boy colour"|"nintendo gbc"|"nintendo game boy color")
            echo "Nintendo - Game Boy Color"
            ;;
        gba|agb|"gameboy advance"|"game boy advance"|"nintendo gba"|"nintendo game boy advance")
            echo "Nintendo - Game Boy Advance"
            ;;
        nds|ds|dsi|ids|"nintendo ds"|"nintendo dsi"|"dual screen")
            echo "Nintendo - Nintendo DS"
            ;;
        n64|z64|u64|"ultra 64"|"nintendo 64"|"n64 bigendian"|"nintendo 64 (bigendian)"|"nintendo 64 bigendian")
            echo "Nintendo - Nintendo 64 (BigEndian)"
            ;;
        v64|"n64 byteswapped"|"nintendo 64 (byteswapped)"|"nintendo 64 byteswapped"|byteswapped)
            echo "Nintendo - Nintendo 64 (ByteSwapped)"
            ;;
        md|gen|smd|genesis|megadrive|"mega drive"|"sega genesis"|"sega mega drive"|"sega megadrive"|"mega drive genesis"|68k|sgd)
            echo "Sega - Mega Drive - Genesis"
            ;;
        sms|sg|mastersystem|"master system"|"mark iii"|"mark 3"|mk3|"sega master system"|"sega mark iii"|"master system mark iii")
            echo "Sega - Master System - Mark III"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Inspect QUERY_ARG to see if it has a ROM/file extension
BASENAME_QUERY="$(basename "$QUERY_ARG")"
FILE_PREFIX=""
INFERRED_EXT=""

if [[ "$BASENAME_QUERY" =~ ^(.+)\.([a-zA-Z0-9]{2,4})\.(zip|7z|gz)$ ]]; then
    FILE_PREFIX="${BASH_REMATCH[1]}"
    INFERRED_EXT="${BASH_REMATCH[2]}"
elif [[ "$BASENAME_QUERY" =~ ^(.+)\.([a-zA-Z0-9]{2,4})$ ]]; then
    CAND_PREFIX="${BASH_REMATCH[1]}"
    CAND_EXT="${BASH_REMATCH[2]}"
    EXT_LOWER="$(echo "$CAND_EXT" | tr '[:upper:]' '[:lower:]')"
    case "$EXT_LOWER" in
        nes|fc|fds|unf|nez|sfc|smc|swc|fig|bs|gb|sgb|dmg|gbc|cgb|gba|agb|nds|ids|dsi|srl|z64|n64|u64|v64|md|gen|smd|68k|sgd|sms|sg|zip|7z|rom|bin)
            FILE_PREFIX="$CAND_PREFIX"
            INFERRED_EXT="$EXT_LOWER"
            ;;
    esac
fi

RESOLVED_CONSOLE=""
if [[ -n "$SYSTEM_ARG" ]]; then
    RESOLVED_CONSOLE="$(resolve_system_name "$SYSTEM_ARG")"
elif [[ -n "$INFERRED_EXT" ]]; then
    RESOLVED_CONSOLE="$(resolve_system_name "$INFERRED_EXT")"
fi

# Query images_list.txt directly and build URL-encoded paths
MATCH_OUTPUT="$(python3 - "$INDEX_FILE" "$QUERY_ARG" "${FILE_PREFIX}" "${SYSTEM_ARG}" "${RESOLVED_CONSOLE}" << 'PY_EOF'
import os
import re
import sys
import urllib.parse

index_file, raw_query, file_prefix, system_arg, resolved_console = sys.argv[1:6]

entries = []  # (rel_path, console_name, filename)
with open(index_file, "r", encoding="utf-8", errors="replace") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("/", 2)
        if len(parts) == 3 and parts[0] == "boxart":
            entries.append((line, parts[1], parts[2]))

available_consoles = sorted({c for _, c, _ in entries})
if not resolved_console and system_arg:
    s_norm = re.sub(r"[^a-z0-9]+", " ", system_arg.lower()).strip()
    s_tokens = set(s_norm.split())
    best_c = None
    best_score = 0
    for c in available_consoles:
        c_norm = re.sub(r"[^a-z0-9]+", " ", c.lower()).strip()
        if s_norm == c_norm or s_norm in c_norm:
            score = 100 - abs(len(c_norm) - len(s_norm))
        else:
            c_tokens = set(c_norm.split())
            overlap = len(s_tokens & c_tokens)
            score = overlap * 10 if overlap == len(s_tokens) else 0
        if score > best_score:
            best_score = score
            best_c = c
    if best_c:
        resolved_console = best_c
    else:
        print(f"ERROR\tCould not resolve system name '{system_arg}'. Available consoles in {index_file}: {', '.join(available_consoles)}")
        sys.exit(0)

if resolved_console:
    if resolved_console not in available_consoles:
        for c in available_consoles:
            if resolved_console.lower() in c.lower() or c.lower() in resolved_console.lower():
                resolved_console = c
                break
    entries = [e for e in entries if e[1] == resolved_console]

search_str = file_prefix if file_prefix else raw_query
search_str_clean = re.sub(r"\s*\([^)]*\)", " ", search_str)

def extract_tokens(text: str) -> list[str]:
    text = text.lower()
    text = re.sub(r"['’`]", "", text)
    return re.findall(r"[a-z0-9]+", text)

def stem_token(tok: str) -> str:
    if len(tok) >= 4 and tok.endswith("s"):
        return tok[:-1]
    return tok

q_tokens = extract_tokens(search_str_clean)
if not q_tokens:
    q_tokens = extract_tokens(search_str)
q_stems = [stem_token(t) for t in q_tokens]
q_joined = "".join(q_tokens)
q_stemmed_joined = "".join(q_stems)

tier1_exact_title = []
tier2_all_words = []
tier3_all_anywhere = []

for rel_path, console, fname in entries:
    stem_name = os.path.splitext(fname)[0]
    base_title = re.sub(r"^[0-9]{4}\s+", "", stem_name)
    base_title = re.sub(r"\s*\([^)]*\)", "", base_title).strip()

    b_tokens = extract_tokens(base_title)
    b_stems = [stem_token(t) for t in b_tokens]
    b_token_set = set(b_tokens)
    b_stem_set = set(b_stems)
    b_joined = "".join(b_tokens)
    b_stemmed_joined = "".join(b_stems)

    f_tokens = extract_tokens(stem_name)
    f_stem_set = {stem_token(t) for t in f_tokens}

    reg_rank = 4
    if "(USA" in stem_name or "(US)" in stem_name:
        reg_rank = 0
    elif "(World" in stem_name:
        reg_rank = 1
    elif "(Europe" in stem_name or "(EU)" in stem_name:
        reg_rank = 2
    elif "(Japan" in stem_name or "(JP)" in stem_name:
        reg_rank = 3

    if b_joined == q_joined or b_stemmed_joined == q_stemmed_joined:
        tier1_exact_title.append((reg_rank, len(b_tokens), stem_name, rel_path, console, fname))
        continue

    all_word_match = True
    for qt, qs in zip(q_tokens, q_stems):
        if qt in b_token_set or qs in b_stem_set:
            continue
        if len(qt) >= 4 and any(bt.startswith(qt) or bt.startswith(qs) for bt in b_tokens):
            continue
        all_word_match = False
        break

    if all_word_match:
        tier2_all_words.append((len(b_tokens), reg_rank, stem_name, rel_path, console, fname))
        continue

    all_sub_match = True
    for qt, qs in zip(q_tokens, q_stems):
        if qt in f_stem_set or qs in f_stem_set or qt in b_joined or qs in b_stemmed_joined:
            continue
        all_sub_match = False
        break

    if all_sub_match:
        tier3_all_anywhere.append((len(f_tokens), reg_rank, stem_name, rel_path, console, fname))

tier1_exact_title.sort()
tier2_all_words.sort()
tier3_all_anywhere.sort()

combined = [x[3:] for x in tier1_exact_title] + [x[3:] for x in tier2_all_words]
if not combined:
    combined = [x[3:] for x in tier3_all_anywhere]

print(f"CONSOLE\t{resolved_console or 'ALL'}")
for rel_path, console, fname in combined:
    encoded_path = "/".join(urllib.parse.quote(seg, safe="") for seg in rel_path.split("/"))
    print(f"MATCH\t{rel_path}\t{encoded_path}\t{fname}")
PY_EOF
)"

if [[ "$MATCH_OUTPUT" == ERROR$'\t'* ]]; then
    ERR_MSG="${MATCH_OUTPUT#ERROR$'\t'}"
    echo "Error: $ERR_MSG" >&2
    exit 1
fi

RESOLVED_DISPLAY=""
MATCH_LINES=()
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" == CONSOLE$'\t'* ]]; then
        RESOLVED_DISPLAY="${line#CONSOLE$'\t'}"
    elif [[ "$line" == MATCH$'\t'* ]]; then
        MATCH_LINES+=("${line#MATCH$'\t'}")
    fi
done <<< "$MATCH_OUTPUT"

TOTAL_MATCHES=${#MATCH_LINES[@]}

if [[ $TOTAL_MATCHES -eq 0 ]]; then
    echo "No matching box art found in '$INDEX_FILE' for query '$QUERY_ARG' (system: ${RESOLVED_DISPLAY:-ALL})." >&2
    exit 1
fi

DEFAULT_BRANCH="${GITHUB_BRANCH:-main}"
echo "System: ${RESOLVED_DISPLAY} | Query: '${QUERY_ARG}' | Found ${TOTAL_MATCHES} matching file(s) in ${INDEX_FILE}"

if [[ "$LIST_ONLY" == true ]]; then
    for item in "${MATCH_LINES[@]}"; do
        IFS=$'\t' read -r rel_path encoded_path fname <<< "$item"
        echo "  ${rel_path} -> https://raw.githubusercontent.com/${REPO_SLUG}/${DEFAULT_BRANCH}/${encoded_path}"
    done
    exit 0
fi

if [[ "$DRY_RUN" == false ]]; then
    mkdir -p "$DEST_DIR"
fi

IDX=0
for item in "${MATCH_LINES[@]}"; do
    IDX=$((IDX + 1))
    IFS=$'\t' read -r rel_path encoded_path fname <<< "$item"
    ext="${fname##*.}"
    orig_stem="${fname%.*}"

    if [[ -n "$FILE_PREFIX" ]]; then
        if [[ $IDX -eq 1 ]]; then
            out_name="${FILE_PREFIX}.${ext}"
        else
            out_name="${FILE_PREFIX}_${orig_stem}.${ext}"
        fi
    else
        out_name="$fname"
    fi

    dest_file="${DEST_DIR%/}/${out_name}"
    raw_url_primary="https://raw.githubusercontent.com/${REPO_SLUG}/${DEFAULT_BRANCH}/${encoded_path}"

    if [[ "$DRY_RUN" == true ]]; then
        echo "  [DRY-RUN] Would download '${raw_url_primary}' -> '${dest_file}'"
        continue
    fi

    # Try downloading from GitHub raw URL (if branch not explicitly set, try main then master)
    BRANCHES_TO_TRY=()
    if [[ -n "$GITHUB_BRANCH" ]]; then
        BRANCHES_TO_TRY=("$GITHUB_BRANCH")
    else
        BRANCHES_TO_TRY=("main" "master")
    fi

    DOWNLOADED=false
    for br in "${BRANCHES_TO_TRY[@]}"; do
        candidate_url="https://raw.githubusercontent.com/${REPO_SLUG}/${br}/${encoded_path}"
        if curl -fsSL "$candidate_url" -o "$dest_file" 2>/dev/null; then
            echo "  Downloaded: '${candidate_url}' -> '${dest_file}'"
            DOWNLOADED=true
            break
        fi
    done

    if [[ "$DOWNLOADED" == false ]]; then
        echo "  Error: Failed to download '${raw_url_primary}' from GitHub (${REPO_SLUG})." >&2
        exit 1
    fi
done
