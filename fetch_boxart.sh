#!/usr/bin/env bash
# ==============================================================================
# fetch_boxart.sh
#
# Reads a local index file (images_list.txt) containing relative paths of the
# form "boxart/<Console>/<ImageFile>.png", strictly resolves the target console
# from a freeform system name (or infers it from the ROM filename extension),
# performs multi-stage fuzzy/relaxed keyword matching (ignoring extra region/tag
# tokens like NA, EU, US, JP, Rev, etc.), and downloads matching images from:
#   https://github.com/youngelf/retro-game-pictures
#
# Output Naming:
#   - 1 match with filename prefix: <rom_name>.png
#   - >1 matches:                   <rom_name>-01.png, <rom_name>-02.png, ...
#
# Usage:
#   ./fetch_boxart.sh [OPTIONS] <GAME_QUERY_OR_FILENAME> [SYSTEM]
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
MAX_FUZZY_RESULTS=15

usage() {
    cat << 'HELP_EOF'
Usage: fetch_boxart.sh [OPTIONS] <GAME_QUERY_OR_FILENAME> [SYSTEM]

Queries a local images_list.txt index file (strictly scoped to the target
system) with progressive fuzzy keyword matching, and downloads matching box art
directly from https://github.com/youngelf/retro-game-pictures.

Arguments:
  <GAME_QUERY_OR_FILENAME>  Game search string (e.g. 'mario picross') or ROM
                            filename (e.g. 'marios_picross_na.gb', 'zelda_eu.nes').
  [SYSTEM]                  Optional freeform system name (e.g. NES, SNES, SFC,
                            GB, GBC, GBA, NDS, DS, N64, MD, Genesis, SMS, GG,
                            PICO, FDS, Amiga, C64, VIC20, A2600, ST, Lynx,
                            MSX2, Intellivision, Project EGG).
                            If omitted, inferred from the filename extension.

Options:
  -i, --index <FILE>        Path to images_list.txt
                            (default: ./images_list.txt or <script_dir>/images_list.txt)
  -r, --repo <GITHUB_URL>   GitHub repository URL or owner/repo
                            (default: https://github.com/youngelf/retro-game-pictures)
  -b, --branch <BRANCH>     Git branch to fetch raw files from (default: tries main, then master)
  -s, --system <SYSTEM>     Freeform system name (alternative to 2nd positional argument)
  -m, --max-results <N>     Maximum prospective matches on relaxed/fuzzy fallback (default: 15)
  -o, -d, --out <DIR>       Output directory for downloaded images (default: .)
  -l, --list                List matching entries and GitHub URLs without downloading
  -n, --dry-run             Preview matches, URLs, and target filenames without downloading
  -h, --help                Show this help message and exit

Examples:
  fetch_boxart.sh "mario picross" GB
  fetch_boxart.sh marios_picross_na.gb
  fetch_boxart.sh castlevania_eu.nes
  fetch_boxart.sh supermariobros.nes
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
        -m|--max-results)
            [[ $# -lt 2 ]] && { echo "Error: Missing argument for $1" >&2; exit 1; }
            MAX_FUZZY_RESULTS="$2"
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

# Strictly resolve freeform system alias or file extension to exact console directory name
resolve_system_name() {
    local raw="$1"
    local key
    key="$(echo "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]._-]+//; s/[[:space:]_-]+$//; s/[[:space:]_-]+/ /g')"

    case "$key" in
        nes|fc|famicom|"family computer"|"nintendo entertainment system"|"nintendo nes"|"nes headered"|"nintendo entertainment system (headered)"|"nintendo - nintendo entertainment system"|"nintendo - nintendo entertainment system (headered)"|unf|nez)
            echo "Nintendo - Nintendo Entertainment System (Headered)"
            ;;
        fds|"famicom disk system"|"family computer disk system"|"nintendo family computer disk system"|"family computer disk system (fds)"|"nintendo - family computer disk system"|"nintendo - family computer disk system (fds)"|qd)
            echo "Nintendo - Family Computer Disk System (FDS)"
            ;;
        snes|sfc|"super nes"|"super nintendo"|"super famicom"|"super nintendo entertainment system"|"nintendo snes"|"nintendo - super nintendo entertainment system"|smc|swc|fig|bs)
            echo "Nintendo - Super Nintendo Entertainment System"
            ;;
        gb|gameboy|"game boy"|dmg|sgb|"super game boy"|"super gameboy"|"nintendo gb"|"nintendo game boy"|"nintendo gameboy"|"nintendo - game boy")
            echo "Nintendo - Game Boy"
            ;;
        gbc|cgb|"gameboy color"|"game boy color"|"gameboy colour"|"game boy colour"|"nintendo gbc"|"nintendo game boy color"|"nintendo - game boy color")
            echo "Nintendo - Game Boy Color"
            ;;
        gba|agb|"gameboy advance"|"game boy advance"|"nintendo gba"|"nintendo game boy advance"|"nintendo - game boy advance")
            echo "Nintendo - Game Boy Advance"
            ;;
        nds|ds|dsi|ids|srl|"nintendo ds"|"nintendo dsi"|"dual screen"|"nintendo - nintendo ds")
            echo "Nintendo - Nintendo DS"
            ;;
        n64|z64|u64|"ultra 64"|"nintendo 64"|"n64 bigendian"|"nintendo 64 (bigendian)"|"nintendo 64 bigendian"|"nintendo - nintendo 64"|"nintendo - nintendo 64 (bigendian)")
            echo "Nintendo - Nintendo 64 (BigEndian)"
            ;;
        v64|"n64 byteswapped"|"nintendo 64 (byteswapped)"|"nintendo 64 byteswapped"|byteswapped|"nintendo - nintendo 64 (byteswapped)")
            echo "Nintendo - Nintendo 64 (ByteSwapped)"
            ;;
        md|gen|smd|genesis|megadrive|"mega drive"|"sega genesis"|"sega mega drive"|"sega megadrive"|"mega drive genesis"|"sega - mega drive - genesis"|68k|sgd)
            echo "Sega - Mega Drive - Genesis"
            ;;
        sms|sg|mastersystem|"master system"|"mark iii"|"mark 3"|mk3|"sega master system"|"sega mark iii"|"master system mark iii"|"sega - master system - mark iii")
            echo "Sega - Master System - Mark III"
            ;;
        gg|gamegear|"game gear"|"sega game gear"|"sega gamegear"|"sega - game gear")
            echo "Sega - Game Gear"
            ;;
        pico|"sega pico"|"sega - pico")
            echo "Sega - PICO"
            ;;
        amiga|"commodore amiga"|"commodore - amiga"|adf|ipf|lha|hdf)
            echo "Commodore - Amiga"
            ;;
        c64|"commodore 64"|"commodore c64"|"commodore - 64"|"commodore - commodore 64"|d64|t64|prg|crt|g64)
            echo "Commodore - Commodore 64"
            ;;
        vic20|"vic 20"|"vic-20"|"commodore vic 20"|"commodore vic-20"|"commodore vic20"|"commodore - vic-20")
            echo "Commodore - VIC-20"
            ;;
        a2600|2600|"atari 2600"|vcs|"atari vcs"|"atari - 2600"|a26)
            echo "Atari - 2600"
            ;;
        ast|"atari st"|"atari - st"|st|ste|stx|msa)
            echo "Atari - ST"
            ;;
        lynx|"atari lynx"|"atari - lynx"|"atari - lynx (lyx)"|lyx|lnx)
            echo "Atari - Lynx (LYX)"
            ;;
        msx2|"microsoft msx2"|"microsoft - msx2"|mx2)
            echo "Microsoft - MSX2"
            ;;
        intv|intellivision|"mattel intellivision"|"mattel - intellivision"|int)
            echo "Mattel - Intellivision"
            ;;
        egg|"project egg"|projectegg)
            echo "Project EGG"
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
        nes|fc|fds|qd|unf|nez|sfc|smc|swc|fig|bs|gb|sgb|dmg|gbc|cgb|gba|agb|nds|ids|dsi|srl|z64|n64|u64|v64|md|gen|smd|68k|sgd|sms|sg|gg|pico|adf|ipf|lha|hdf|d64|t64|prg|crt|g64|a26|st|stx|msa|lyx|lnx|mx2|int|zip|7z|rom|bin)
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

# Query images_list.txt with strict console filtering and progressive fuzzy keyword matching
MATCH_OUTPUT="$(python3 - "$INDEX_FILE" "$QUERY_ARG" "${FILE_PREFIX}" "${SYSTEM_ARG}" "${RESOLVED_CONSOLE}" "${MAX_FUZZY_RESULTS}" << 'PY_EOF'
import difflib
import os
import re
import sys
import urllib.parse

index_file, raw_query, file_prefix, system_arg, resolved_console, max_fuzzy_str = sys.argv[1:7]
max_fuzzy = int(max_fuzzy_str)

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

# Strict console resolution if user passed a custom system string not in static table
if not resolved_console and system_arg:
    s_tokens = re.findall(r"[a-z0-9]+", system_arg.lower())
    s_set = set(s_tokens)
    exact_matches = []
    for c in available_consoles:
        c_tokens = re.findall(r"[a-z0-9]+", c.lower())
        c_set = set(c_tokens)
        # Require exact token match (never substring match like "nes" inside "snes")
        if s_tokens == c_tokens or (s_set and s_set.issubset(c_set)):
            # Guard against "game boy" matching "game boy advance" or "game boy color"
            if "boy" in s_set and not ({"advance", "color", "colour"} & s_set):
                if {"advance", "color", "colour"} & c_set:
                    continue
            # Guard against "nintendo entertainment system" matching "super nintendo entertainment system"
            if "entertainment" in s_set and "super" not in s_set and "super" in c_set:
                continue
            exact_matches.append((len(c_tokens), c))
    if exact_matches:
        exact_matches.sort()
        resolved_console = exact_matches[0][1]
    else:
        print(f"ERROR\tCould not resolve system name '{system_arg}'. Available systems: {', '.join(available_consoles)}")
        sys.exit(0)

# Strictly filter entries to ONLY the resolved console
if resolved_console:
    if resolved_console not in available_consoles:
        print(f"ERROR\tResolved system '{resolved_console}' not found in {index_file}. Available systems: {', '.join(available_consoles)}")
        sys.exit(0)
    entries = [e for e in entries if e[1] == resolved_console]

# Region & ROM-tag noise words commonly appended to ROM filenames (e.g. NA, EU, US, JP, Rev1, v1.0)
REGION_HINTS = {
    "na": "USA", "us": "USA", "usa": "USA", "ntsc": "USA", "u": "USA",
    "eu": "Europe", "eur": "Europe", "europe": "Europe", "pal": "Europe", "uk": "Europe", "e": "Europe",
    "jp": "Japan", "jpn": "Japan", "japan": "Japan", "j": "Japan",
    "de": "Germany", "ger": "Germany",
    "fr": "France", "fra": "France",
    "es": "Spain", "esp": "Spain",
    "it": "Italy", "ita": "Italy",
    "nl": "Netherlands",
    "kr": "Korea", "ks": "Korea", "kor": "Korea",
    "br": "Brazil", "bra": "Brazil",
    "au": "Australia", "aus": "Australia",
}

ROM_NOISE_TOKENS = {
    "na", "us", "usa", "ntsc",
    "eu", "eur", "europe", "pal", "uk",
    "jp", "jpn", "japan",
    "ger", "fra", "esp", "ita", "kor", "bra", "aus",
    "en", "ja",
    "rev", "reva", "revb", "revc", "rev0", "rev1", "rev2", "rev3",
    "v1", "v2", "v3", "v10", "v11", "v12", "v01", "v02",
    "m2", "m3", "m4", "m5", "m6", "m7", "m8",
    "sgb", "unl", "pirate", "proto",
    "headered", "unheadered", "bigendian", "byteswapped", "aga", "ecs", "ocs", "lyx", "fds",
}

STOPWORDS = {"the", "and", "of", "for", "in", "on", "to", "a", "an", "no", "ni", "wo", "wa", "de", "der", "die", "das", "le", "la", "les", "el", "il"}

ROMAN_MAP = {
    "viii": "8", "vii": "7", "vi": "6", "iv": "4", "iii": "3", "ii": "2",
}

def extract_raw_tokens(text: str) -> list[str]:
    text = text.lower()
    text = re.sub(r"['’`]", "", text)
    # Split camelCase or alpha-to-digit boundaries if needed, while keeping standard tokens
    tokens = re.findall(r"[a-z0-9]+", text)
    return [ROMAN_MAP.get(t, t) for t in tokens]

def stem_token(tok: str) -> str:
    if len(tok) >= 4 and tok.endswith("s") and not tok.endswith("ss"):
        return tok[:-1]
    return tok

def char_ngrams(s: str, n: int = 3) -> set[str]:
    s_padded = f"^{s}$"
    if len(s_padded) < n:
        return {s_padded}
    return {s_padded[i:i+n] for i in range(len(s_padded) - n + 1)}

search_str = file_prefix if file_prefix else raw_query
# Strip leading 4-digit release number if present (e.g. "0001_electroplankton")
search_str_no_num = re.sub(r"^[0-9]{4}[_\s-]+", "", search_str)

# Detect preferred region if user had NA, EU, US, JP, etc. in their filename/query
all_q_raw_tokens = extract_raw_tokens(search_str_no_num)
preferred_region = None
for t in reversed(all_q_raw_tokens):
    if t in REGION_HINTS:
        preferred_region = REGION_HINTS[t]
        break

# Strip parenthetical/bracketed tags first
search_str_clean = re.sub(r"\s*[\(\[][^\)\]]*[\)\]]", " ", search_str_no_num)
raw_clean_tokens = extract_raw_tokens(search_str_clean)

# Filter out trailing/extra ROM noise tokens (like NA, EU, US, JP, Rev1) and stopwords
core_tokens = [t for t in raw_clean_tokens if t not in ROM_NOISE_TOKENS and t not in STOPWORDS]
if not core_tokens:
    # Fallback if the game title itself consists only of noise/stopwords (e.g. "U.S.A." or " E.V.O.")
    core_tokens = [t for t in raw_clean_tokens if t not in REGION_HINTS] or raw_clean_tokens or all_q_raw_tokens

q_tokens = core_tokens
q_stems = [stem_token(t) for t in q_tokens]
q_joined = "".join(q_tokens)
q_stemmed_joined = "".join(q_stems)
q_trigrams = char_ngrams(q_stemmed_joined, 3) | char_ngrams(q_stemmed_joined, 2)

def get_region_rank(stem_name: str) -> int:
    if preferred_region and preferred_region in stem_name:
        return -1
    if "(USA" in stem_name or "(US)" in stem_name:
        return 0
    if "(World" in stem_name:
        return 1
    if "(Europe" in stem_name or "(EU)" in stem_name:
        return 2
    if "(Japan" in stem_name or "(JP)" in stem_name:
        return 3
    return 4

# Precompute candidate features for all entries in the target console
candidates = []
for rel_path, console, fname in entries:
    stem_name = os.path.splitext(fname)[0]
    base_title = re.sub(r"^[0-9]{4}\s+", "", stem_name)
    base_title = re.sub(r"\s*\([^)]*\)", "", base_title).strip()

    b_raw = extract_raw_tokens(base_title)
    b_core = [t for t in b_raw if t not in STOPWORDS] or b_raw
    b_stems = [stem_token(t) for t in b_core]
    b_token_set = set(b_core) | set(b_raw)
    b_stem_set = set(b_stems) | {stem_token(t) for t in b_raw}
    b_joined = "".join(b_core)
    b_stemmed_joined = "".join(b_stems)

    f_raw = extract_raw_tokens(stem_name)
    f_stem_set = {stem_token(t) for t in f_raw}
    reg_rank = get_region_rank(stem_name)

    candidates.append({
        "rel_path": rel_path,
        "console": console,
        "fname": fname,
        "stem_name": stem_name,
        "base_title": base_title,
        "b_core": b_core,
        "b_stems": b_stems,
        "b_token_set": b_token_set,
        "b_stem_set": b_stem_set,
        "b_joined": b_joined,
        "b_stemmed_joined": b_stemmed_joined,
        "f_stem_set": f_stem_set,
        "reg_rank": reg_rank,
    })

def token_matches_candidate(qt: str, qs: str, c: dict, allow_fuzzy_tok: bool = False) -> bool:
    if qt in c["b_token_set"] or qs in c["b_stem_set"]:
        return True
    if len(qt) >= 4 and any(bt.startswith(qt) or bt.startswith(qs) for bt in c["b_core"]):
        return True
    if len(qt) >= 5 and (qt in c["b_joined"] or qs in c["b_stemmed_joined"]):
        return True
    if allow_fuzzy_tok and len(qt) >= 4:
        for bs in c["b_stems"]:
            if len(bs) >= 3 and difflib.SequenceMatcher(None, qs, bs).ratio() >= 0.75:
                return True
    return False

# Pass 1: Exact base title match (after stripping NA/EU/US/stopwords)
pass1_exact = []
# Pass 2: All core query tokens match in base title (exact/prefix/substring)
pass2_all_tokens = []

for c in candidates:
    if c["b_joined"] == q_joined or c["b_stemmed_joined"] == q_stemmed_joined:
        pass1_exact.append((c["reg_rank"], len(c["b_core"]), c["stem_name"], c["rel_path"], c["console"], c["fname"]))
        continue

    if all(token_matches_candidate(qt, qs, c, allow_fuzzy_tok=False) for qt, qs in zip(q_tokens, q_stems)):
        pass2_all_tokens.append((len(c["b_core"]), c["reg_rank"], c["stem_name"], c["rel_path"], c["console"], c["fname"]))

pass1_exact.sort()
pass2_all_tokens.sort()

combined = [x[3:] for x in pass1_exact] + [x[3:] for x in pass2_all_tokens]
match_mode = "strict"

# Pass 3 (Relaxed Token / Typo Match): If strict matching found nothing, relax token requirements!
if not combined:
    match_mode = "relaxed"
    relaxed_hits = []
    num_q = len(q_tokens)
    min_required = max(1, num_q - 1) if num_q <= 3 else max(2, int(round(num_q * 0.6)))

    for c in candidates:
        exact_tok_count = sum(
            1 for qt, qs in zip(q_tokens, q_stems)
            if token_matches_candidate(qt, qs, c, allow_fuzzy_tok=False)
        )
        fuzzy_tok_count = sum(
            1 for qt, qs in zip(q_tokens, q_stems)
            if token_matches_candidate(qt, qs, c, allow_fuzzy_tok=True)
        )
        if fuzzy_tok_count >= min_required and num_q >= 2:
            # If only 1 token matched, require it to be an exact/prefix token match unless num_q == 1
            if fuzzy_tok_count == 1 and exact_tok_count == 0:
                continue
            seq_sim = difflib.SequenceMatcher(None, q_stemmed_joined, c["b_stemmed_joined"]).ratio()
            relaxed_hits.append((
                - fuzzy_tok_count,
                - exact_tok_count,
                - round(seq_sim, 3),
                c["reg_rank"],
                len(c["b_core"]),
                c["stem_name"],
                c["rel_path"],
                c["console"],
                c["fname"],
            ))
    if relaxed_hits:
        relaxed_hits.sort()
        # If there are candidates that matched ALL tokens (via typo tolerance, e.g. marios_picros),
        # keep only those top-tier matches rather than polluting with 1-token partial matches!
        best_fuzzy_count = -relaxed_hits[0][0]
        if best_fuzzy_count == num_q:
            relaxed_hits = [x for x in relaxed_hits if (-x[0]) == num_q]
        combined = [x[6:] for x in relaxed_hits[:max_fuzzy]]

# Pass 4 (Fuzzy Character N-gram + Sequence Similarity Fallback):
# Handles concatenated ROM names (e.g. supermariobros), abbreviations, or heavier misspellings
if not combined:
    match_mode = "fuzzy"
    fuzzy_scored = []
    for c in candidates:
        b_str = c["b_stemmed_joined"]
        if not b_str:
            continue
        seq_sim = difflib.SequenceMatcher(None, q_stemmed_joined, b_str).ratio()
        # Also check if query is a substring of candidate or vice versa
        sub_bonus = 0.20 if (len(q_stemmed_joined) >= 4 and (q_stemmed_joined in b_str or b_str in q_stemmed_joined)) else 0.0
        b_trigrams = char_ngrams(b_str, 3) | char_ngrams(b_str, 2)
        ngram_sim = (2.0 * len(q_trigrams & b_trigrams)) / max(1, len(q_trigrams) + len(b_trigrams))
        # Token overlap bonus
        tok_hits = sum(1 for qt, qs in zip(q_tokens, q_stems) if token_matches_candidate(qt, qs, c, allow_fuzzy_tok=True))
        tok_sim = tok_hits / max(1, len(q_tokens))

        score = max(seq_sim + sub_bonus, 0.45 * seq_sim + 0.35 * ngram_sim + 0.20 * tok_sim + sub_bonus)
        if score >= 0.48:
            fuzzy_scored.append((
                -round(score, 4),
                c["reg_rank"],
                len(c["b_core"]),
                c["stem_name"],
                c["rel_path"],
                c["console"],
                c["fname"],
            ))

    fuzzy_scored.sort()
    if fuzzy_scored:
        top_score = -fuzzy_scored[0][0]
        # Keep prospective matches close to the top score
        cutoff = max(0.48, top_score - 0.12)
        filtered = [x for x in fuzzy_scored if (-x[0]) >= cutoff][:max_fuzzy]
        combined = [x[4:] for x in filtered]

print(f"CONSOLE\t{resolved_console or 'ALL'}\t{match_mode}")
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
MATCH_MODE="strict"
MATCH_LINES=()
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" == CONSOLE$'\t'* ]]; then
        REST="${line#CONSOLE$'\t'}"
        RESOLVED_DISPLAY="${REST%%$'\t'*}"
        MATCH_MODE="${REST#*$'\t'}"
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
echo "System: ${RESOLVED_DISPLAY} | Mode: ${MATCH_MODE} | Query: '${QUERY_ARG}' | Found ${TOTAL_MATCHES} matching file(s)"

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

# Determine base prefix for renaming:
# - If a filename with extension was given, use FILE_PREFIX (e.g. marios_picross.gb -> marios_picross)
# - If multiple matches exist even without an extension, derive a clean prefix from QUERY_ARG
ROM_NAME_PREFIX="$FILE_PREFIX"
if [[ -z "$ROM_NAME_PREFIX" && $TOTAL_MATCHES -gt 1 ]]; then
    ROM_NAME_PREFIX="$(echo "$BASENAME_QUERY" | sed -E 's/[[:space:]]+/_/g; s/[^a-zA-Z0-9._-]+//g')"
fi

IDX=0
for item in "${MATCH_LINES[@]}"; do
    IDX=$((IDX + 1))
    IFS=$'\t' read -r rel_path encoded_path fname <<< "$item"
    ext="${fname##*.}"

    if [[ $TOTAL_MATCHES -gt 1 ]]; then
        out_name="$(printf "%s-%02d.%s" "$ROM_NAME_PREFIX" "$IDX" "$ext")"
    elif [[ -n "$FILE_PREFIX" ]]; then
        out_name="${FILE_PREFIX}.${ext}"
    else
        out_name="$fname"
    fi

    dest_file="${DEST_DIR%/}/${out_name}"
    raw_url_primary="https://raw.githubusercontent.com/${REPO_SLUG}/${DEFAULT_BRANCH}/${encoded_path}"

    if [[ "$DRY_RUN" == true ]]; then
        echo "  [DRY-RUN] Would download '${raw_url_primary}' -> '${dest_file}'"
        continue
    fi

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
