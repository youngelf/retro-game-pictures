#!/usr/bin/env bash
# ==============================================================================
# commit_and_push_boxart.sh
#
# 1. If run from ~/xkdr/a/rom_list (outside a git repo), automatically syncs any
#    new boxart/ directories and scripts into ~/xkdr/a/retro-game-pictures and
#    switches to that git repository.
# 2. Regenerates images_list.txt using ./generate_images_list.sh.
# 3. Stages, commits, and pushes any new/uncommitted boxart/<system-name>/<file>
#    images in batches of 50 images at a time (along with images_list.txt,
#    boxart/ symlinks, and updated scripts).
#
# Usage:
#   ./commit_and_push_boxart.sh [OPTIONS]
#
# Options:
#   -b, --batch-size <N>   Number of images per commit/push (default: 50)
#   -i, --index <FILE>     Path to images_list.txt (default: ./images_list.txt)
#   -r, --remote <REMOTE>  Git remote name (default: current upstream or origin)
#   -B, --branch <BRANCH>  Git branch name (default: current branch)
#   -n, --dry-run          Preview batches and git commands without executing
#   -h, --help             Show this help message and exit
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_GIT_REPO="/usr/local/google/home/viki/xkdr/a/retro-game-pictures"
DEFAULT_SOURCE_DIR="/usr/local/google/home/viki/xkdr/a/rom_list"

BATCH_SIZE=50
INDEX_FILE="./images_list.txt"
GIT_REMOTE=""
GIT_BRANCH=""
DRY_RUN=false

usage() {
    cat << 'HELP_EOF'
Usage: ./commit_and_push_boxart.sh [OPTIONS]

Regenerates images_list.txt and commits/pushes uncommitted boxart/ images to
GitHub in batches of 50 images at a time:
  ./generate_images_list.sh
  git add boxart/<system-name>/<filename> ...
  git commit -m '<descriptive message>'
  git push

Options:
  -b, --batch-size <N>   Number of images per commit (default: 50)
  -i, --index <FILE>     Path to images_list.txt (default: ./images_list.txt)
  -r, --remote <REMOTE>  Git remote to push to (default: tracked upstream or origin)
  -B, --branch <BRANCH>  Git branch to push to (default: current HEAD branch)
  -n, --dry-run          Print the git add / commit / push commands without running them
  -h, --help             Show this help message and exit
HELP_EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        -b|--batch-size)
            [[ $# -lt 2 ]] && { echo "Error: Missing argument for $1" >&2; exit 1; }
            BATCH_SIZE="$2"
            shift 2
            ;;
        -i|--index)
            [[ $# -lt 2 ]] && { echo "Error: Missing argument for $1" >&2; exit 1; }
            INDEX_FILE="$2"
            shift 2
            ;;
        -r|--remote)
            [[ $# -lt 2 ]] && { echo "Error: Missing argument for $1" >&2; exit 1; }
            GIT_REMOTE="$2"
            shift 2
            ;;
        -B|--branch)
            [[ $# -lt 2 ]] && { echo "Error: Missing argument for $1" >&2; exit 1; }
            GIT_BRANCH="$2"
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Error: Unknown argument '$1'" >&2
            echo "Run '$(basename "$0") --help' for usage." >&2
            exit 1
            ;;
    esac
done

# If we are not inside a git work tree, check if DEFAULT_GIT_REPO exists and switch to it
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ -d "${DEFAULT_GIT_REPO}/.git" ]]; then
        echo "Switching to git repository: ${DEFAULT_GIT_REPO}"
        cd "$DEFAULT_GIT_REPO"
    elif [[ "$DRY_RUN" == false ]]; then
        echo "Error: Current directory ($(pwd)) is not a git repository." >&2
        exit 1
    fi
fi

REPO_ROOT="$(pwd)"

# If DEFAULT_SOURCE_DIR/boxart has new console folders/files not yet in REPO_ROOT/boxart, sync them
if [[ "$REPO_ROOT" != "$DEFAULT_SOURCE_DIR" && -d "${DEFAULT_SOURCE_DIR}/boxart" ]]; then
    echo "Syncing any new boxart files and scripts from ${DEFAULT_SOURCE_DIR} to ${REPO_ROOT} ..."
    if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "${REPO_ROOT}/boxart"
        cp -aln "${DEFAULT_SOURCE_DIR}/boxart/." "${REPO_ROOT}/boxart/" 2>/dev/null || cp -an "${DEFAULT_SOURCE_DIR}/boxart/." "${REPO_ROOT}/boxart/"
        for s in generate_images_list.sh fetch_boxart.sh commit_and_push_boxart.sh; do
            if [[ -f "${DEFAULT_SOURCE_DIR}/${s}" ]]; then
                cp -f "${DEFAULT_SOURCE_DIR}/${s}" "${REPO_ROOT}/${s}"
                chmod +x "${REPO_ROOT}/${s}"
            fi
        done
    fi
fi

if [[ ! -d "boxart" ]]; then
    echo "Error: 'boxart/' directory not found in $(pwd)." >&2
    exit 1
fi

# Step 1: Regenerate images_list.txt
if [[ -x "./generate_images_list.sh" ]]; then
    echo "Regenerating images_list.txt ..."
    if [[ "$DRY_RUN" == true ]]; then
        echo "  [DRY-RUN] ./generate_images_list.sh -o \"${INDEX_FILE}\""
    else
        ./generate_images_list.sh -o "$INDEX_FILE"
        # Keep DEFAULT_SOURCE_DIR/images_list.txt in sync if applicable
        if [[ -d "$DEFAULT_SOURCE_DIR" && "$REPO_ROOT" != "$DEFAULT_SOURCE_DIR" ]]; then
            cp -f "$INDEX_FILE" "${DEFAULT_SOURCE_DIR}/images_list.txt"
        fi
    fi
else
    echo "Generating '${INDEX_FILE}' from boxart/ ..."
    if [[ "$DRY_RUN" == false ]]; then
        find boxart -mindepth 2 -maxdepth 2 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) | LC_ALL=C sort > "$INDEX_FILE"
    fi
fi

# Step 2: Collect full list of boxart/<system-name>/<filename>
ALL_FILES=()
if [[ -f "$INDEX_FILE" ]]; then
    while IFS= read -r line; do
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        [[ -f "$line" ]] && ALL_FILES+=("$line")
    done < "$INDEX_FILE"
else
    while IFS= read -r line; do
        [[ -n "$line" ]] && ALL_FILES+=("$line")
    done < <(find boxart -mindepth 2 -maxdepth 2 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) | LC_ALL=C sort)
fi

TOTAL_FOUND=${#ALL_FILES[@]}
if [[ $TOTAL_FOUND -eq 0 ]]; then
    echo "No boxart image files found to commit."
    exit 0
fi

# Step 3: Filter out files that are already tracked and unmodified in git HEAD
PENDING_FILES=()
if git rev-parse --verify HEAD >/dev/null 2>&1; then
    declare -A COMMITTED_CLEAN=()
    while IFS= read -r tracked; do
        [[ -n "$tracked" ]] && COMMITTED_CLEAN["$tracked"]=1
    done < <(git ls-tree -r --name-only HEAD boxart/ 2>/dev/null || true)

    while IFS= read -r dirty; do
        if [[ -n "$dirty" ]]; then
            unset 'COMMITTED_CLEAN[$dirty]' || true
        fi
    done < <(git status --porcelain --untracked-files=no boxart/ 2>/dev/null | sed -E 's/^...//; s/^"(.*)"$/\1/' || true)

    for f in "${ALL_FILES[@]}"; do
        if [[ -z "${COMMITTED_CLEAN[$f]:-}" ]]; then
            PENDING_FILES+=("$f")
        fi
    done
else
    PENDING_FILES=("${ALL_FILES[@]}")
fi

# Collect metadata/utility files to commit (images_list.txt, scripts, symlinks)
EXTRA_META_FILES=()
for mf in "$INDEX_FILE" generate_images_list.sh fetch_boxart.sh commit_and_push_boxart.sh; do
    [[ -f "$mf" ]] && EXTRA_META_FILES+=("$mf")
done
while IFS= read -r link_path; do
    [[ -n "$link_path" ]] && EXTRA_META_FILES+=("$link_path")
done < <(find boxart -mindepth 1 -maxdepth 1 -type l | LC_ALL=C sort)

TOTAL_PENDING=${#PENDING_FILES[@]}
if [[ $TOTAL_PENDING -eq 0 ]]; then
    echo "All ${TOTAL_FOUND} boxart images are already committed in HEAD."
    if [[ "$DRY_RUN" == false && ${#EXTRA_META_FILES[@]} -gt 0 ]]; then
        git add -- "${EXTRA_META_FILES[@]}"
        if ! git diff --cached --quiet; then
            git commit -m "Regenerate images_list.txt (${TOTAL_FOUND} images) and update utility scripts"
            git push ${GIT_REMOTE:+$GIT_REMOTE} ${GIT_BRANCH:+$GIT_BRANCH}
        fi
    fi
    exit 0
fi

TOTAL_BATCHES=$(( (TOTAL_PENDING + BATCH_SIZE - 1) / BATCH_SIZE ))
echo "Found ${TOTAL_PENDING} uncommitted boxart image(s) (out of ${TOTAL_FOUND} total)."
echo "Processing in ${TOTAL_BATCHES} batch(es) of up to ${BATCH_SIZE} images each..."

BATCH_NUM=0
OFFSET=0

while [[ $OFFSET -lt $TOTAL_PENDING ]]; do
    BATCH_NUM=$((BATCH_NUM + 1))
    BATCH_SLICE=("${PENDING_FILES[@]:$OFFSET:$BATCH_SIZE}")
    COUNT=${#BATCH_SLICE[@]}

    FIRST_FILE="${BATCH_SLICE[0]}"
    LAST_FILE="${BATCH_SLICE[$((COUNT - 1))]}"

    FIRST_SYS="$(echo "$FIRST_FILE" | cut -d'/' -f2)"
    LAST_SYS="$(echo "$LAST_FILE" | cut -d'/' -f2)"

    FIRST_GAME="$(basename "$FIRST_FILE")"
    FIRST_GAME="${FIRST_GAME%.*}"
    LAST_GAME="$(basename "$LAST_FILE")"
    LAST_GAME="${LAST_GAME%.*}"

    if [[ "$FIRST_SYS" == "$LAST_SYS" ]]; then
        SYS_DESC="$FIRST_SYS"
    else
        SYS_DESC="${FIRST_SYS} -> ${LAST_SYS}"
    fi

    COMMIT_MSG="Add boxart batch ${BATCH_NUM}/${TOTAL_BATCHES} (${COUNT} images, ${SYS_DESC}: ${FIRST_GAME} .. ${LAST_GAME})"

    echo "------------------------------------------------------------------------------"
    echo "[Batch ${BATCH_NUM}/${TOTAL_BATCHES}] (${COUNT} images) ${SYS_DESC}"
    echo "  Commit message: ${COMMIT_MSG}"

    if [[ "$DRY_RUN" == true ]]; then
        echo "  [DRY-RUN] git add ${FIRST_FILE} ... (${COUNT} files)"
        echo "  [DRY-RUN] git commit -m \"${COMMIT_MSG}\""
        if [[ -n "$GIT_REMOTE" && -n "$GIT_BRANCH" ]]; then
            echo "  [DRY-RUN] git push ${GIT_REMOTE} ${GIT_BRANCH}"
        else
            echo "  [DRY-RUN] git push"
        fi
    else
        if [[ $BATCH_NUM -eq 1 && ${#EXTRA_META_FILES[@]} -gt 0 ]]; then
            git add -- "${EXTRA_META_FILES[@]}" "${BATCH_SLICE[@]}"
        else
            git add -- "${BATCH_SLICE[@]}"
        fi

        if git diff --cached --quiet; then
            echo "  No staged changes in batch ${BATCH_NUM}, skipping commit."
        else
            git commit -m "$COMMIT_MSG"

            PUSH_OK=false
            for attempt in 1 2 3; do
                if [[ -n "$GIT_REMOTE" && -n "$GIT_BRANCH" ]]; then
                    if git push "$GIT_REMOTE" "$GIT_BRANCH"; then
                        PUSH_OK=true
                        break
                    fi
                elif [[ -n "$GIT_REMOTE" ]]; then
                    if git push "$GIT_REMOTE"; then
                        PUSH_OK=true
                        break
                    fi
                else
                    if git push; then
                        PUSH_OK=true
                        break
                    fi
                fi
                echo "  Warning: git push attempt ${attempt} failed; retrying in $((attempt * 3))s..." >&2
                sleep $((attempt * 3))
            done

            if [[ "$PUSH_OK" == false ]]; then
                echo "Error: git push failed after 3 attempts on batch ${BATCH_NUM}." >&2
                exit 1
            fi
        fi
    fi

    OFFSET=$((OFFSET + BATCH_SIZE))
done

echo "------------------------------------------------------------------------------"
echo "Completed all ${TOTAL_BATCHES} batch(es) (${TOTAL_PENDING} images)."
