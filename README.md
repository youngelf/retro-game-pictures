# retro-game-pictures

Pictures from retro games, so they are easy to fetch.

This repository hosts **20,247** verified retro game box art images (all PNGs sized $\ge 256\times256$) organized under `boxart/<System Name>/<Game Title>.png`, along with a local index ([`images_list.txt`](./images_list.txt)) and a zero-clone query/download script ([`fetch_boxart.sh`](./fetch_boxart.sh)).

Users only need to download **`fetch_boxart.sh`** and **`images_list.txt`** (~1.5 MB) to perform fast offline searches and fetch matching box art images directly from GitHub on demand—without cloning the multi-gigabyte image repository.

---

## Supported Systems & Box Art Summary

We currently have complete box art coverage across **22 systems** (**20,247 images** total):

| System Directory (`boxart/<System>`) | CLI System Aliases | Auto-Inferred Extensions | Images |
| :--- | :--- | :--- | ---: |
| `Atari - 2600` | `A2600`, `2600`, `Atari 2600`, `VCS` | `.a26` | 482 |
| `Atari - Lynx (LYX)` | `Lynx`, `Atari Lynx`, `LYX` | `.lyx`, `.lnx` | 74 |
| `Atari - ST` | `AST`, `Atari ST`, `ST`, `STE` | `.st`, `.stx`, `.msa` | 314 |
| `Commodore - Amiga` | `Amiga`, `Commodore Amiga` | `.adf`, `.ipf`, `.lha`, `.hdf` | 2,759 |
| `Commodore - Commodore 64` | `C64`, `Commodore 64` | `.d64`, `.t64`, `.prg`, `.crt`, `.g64` | 230 |
| `Commodore - VIC-20` | `VIC20`, `VIC-20`, `Commodore VIC-20` | — | 173 |
| `Mattel - Intellivision` | `INTV`, `Intellivision`, `Mattel Intellivision` | `.int` | 144 |
| `Microsoft - MSX2` | `MSX2`, `Microsoft MSX2` | `.mx2` | 149 |
| `Nintendo - Family Computer Disk System (FDS)` | `FDS`, `Famicom Disk System`, `Family Computer Disk System` | `.fds`, `.qd` | 200 |
| `Nintendo - Game Boy` | `GB`, `GameBoy`, `Game Boy`, `DMG`, `SGB` | `.gb`, `.sgb`, `.dmg` | 1,051 |
| `Nintendo - Game Boy Advance` | `GBA`, `GameBoy Advance`, `Game Boy Advance`, `AGB` | `.gba`, `.agb` | 1,543 |
| `Nintendo - Game Boy Color` | `GBC`, `GameBoy Color`, `Game Boy Color`, `CGB` | `.gbc`, `.cgb` | 928 |
| `Nintendo - Nintendo 64 (BigEndian)` | `N64`, `Nintendo 64`, `Ultra 64`, `N64 BigEndian` | `.z64`, `.n64`, `.u64` | 390 |
| `Nintendo - Nintendo 64 (ByteSwapped)` | `N64 ByteSwapped`, `Nintendo 64 (ByteSwapped)` | `.v64` | 390 |
| `Nintendo - Nintendo DS` | `NDS`, `DS`, `DSi`, `Nintendo DS` | `.nds`, `.dsi`, `.ids`, `.srl` | 4,851 |
| `Nintendo - Nintendo Entertainment System (Headered)` | `NES`, `FC`, `Famicom`, `Nintendo Entertainment System` | `.nes`, `.fc`, `.unf`, `.nez` | 1,392 |
| `Nintendo - Super Nintendo Entertainment System` | `SNES`, `SFC`, `Super NES`, `Super Famicom`, `Super Nintendo` | `.sfc`, `.smc`, `.swc`, `.fig`, `.bs` | 1,746 |
| `Project EGG` | `EGG`, `Project EGG`, `ProjectEGG` | — | 1,469 |
| `Sega - Game Gear` | `GG`, `Game Gear`, `Sega Game Gear` | `.gg` | 366 |
| `Sega - Master System - Mark III` | `SMS`, `Master System`, `Mark III`, `MK3` | `.sms`, `.sg` | 336 |
| `Sega - Mega Drive - Genesis` | `MD`, `GEN`, `Genesis`, `Mega Drive`, `Sega Genesis` | `.md`, `.gen`, `.smd`, `.68k`, `.sgd` | 933 |
| `Sega - PICO` | `PICO`, `Sega PICO` | `.pico` | 327 |
| **Total (22 Systems)** | | | **20,247** |

---

## Quick Start (Lightweight Client Setup)

You do **not** need to clone the entire repository to search and download box art. Download just `fetch_boxart.sh` and `images_list.txt`:

```bash
curl -fsSLO https://raw.githubusercontent.com/youngelf/retro-game-pictures/main/fetch_boxart.sh
curl -fsSLO https://raw.githubusercontent.com/youngelf/retro-game-pictures/main/images_list.txt
chmod +x fetch_boxart.sh
```

---

## Fetching Box Art (`fetch_boxart.sh`)

### Usage

```bash
./fetch_boxart.sh [OPTIONS] <GAME_QUERY_OR_FILENAME> [SYSTEM]
```

### Arguments & Options

- `<GAME_QUERY_OR_FILENAME>`: A freeform game search query (e.g. `"mario picross"`) or a ROM filename (e.g. `marios_picross_na.gb`, `castlevania_eu.nes.zip`).
- `[SYSTEM]`: Optional freeform system name (e.g. `NES`, `SNES`, `GB`, `GBA`, `NDS`, `N64`, `MD`, `SMS`, `GG`, `PICO`, `FDS`, `Amiga`, `C64`, `VIC20`, `A2600`, `ST`, `Lynx`, `MSX2`, `INTV`, `EGG`). If omitted, the system is automatically inferred from the ROM file extension.

| Option | Description |
| :--- | :--- |
| `-i, --index <FILE>` | Path to `images_list.txt` (default: `./images_list.txt` or `<script_dir>/images_list.txt`) |
| `-r, --repo <GITHUB_URL>` | GitHub repository URL or `owner/repo` (default: `https://github.com/youngelf/retro-game-pictures`) |
| `-b, --branch <BRANCH>` | Git branch to fetch raw files from (default: tries `main`, then `master`) |
| `-s, --system <SYSTEM>` | Freeform system name (alternative to the 2nd positional argument) |
| `-m, --max-results <N>` | Maximum prospective matches returned on relaxed/fuzzy fallback (default: `15`) |
| `-o, -d, --out <DIR>` | Output directory for downloaded images (default: `.`) |
| `-l, --list` | List matching entries in `images_list.txt` and their raw GitHub URLs without downloading |
| `-n, --dry-run` | Preview resolved system, matching mode, URLs, and target filenames without downloading |
| `-h, --help` | Show help message and exit |

### Matching & Naming Behavior

1. **Strict System Isolation**:
   - Searches are strictly scoped to the resolved target console. Querying `NES` (or a `.nes` file) will **only** match `Nintendo - Nintendo Entertainment System (Headered)` and will never leak into `SNES`; querying `GB` (or `.gb`) will never match `GBA` or `GBC`.
2. **Extra ROM Tag & Region Stripping (`NA`, `EU`, `US`, `JP`, etc.)**:
   - Common ROM filename tags such as `NA` (North America), `EU` / `EUR` (Europe), `US` / `USA`, `JP` / `JPN`, `PAL`, `NTSC`, `Rev1`, `v1.0`, `SGB`, parentheticals, and release numbers are automatically stripped before matching.
   - Any region hint present in the ROM name (`NA`/`US` $\rightarrow$ `USA`, `EU`/`PAL` $\rightarrow$ `Europe`, `JP` $\rightarrow$ `Japan`) is used as a tie-breaker to prioritize the matching regional box art.
3. **Progressive 4-Stage Fuzzy Relaxation (`strict` $\rightarrow$ `relaxed` $\rightarrow$ `fuzzy`)**:
   - **Pass 1 & 2 (`strict`)**: Matches exact base title or all core query tokens (normalizing punctuation/apostrophes, Roman numerals `II`–`VIII` $\leftrightarrow$ `2`–`8`, plurals, and concatenated names like `supermariobros`).
   - **Pass 3 (`relaxed`)**: If strict matching finds no results, relaxes token requirements to allow partial token overlap and per-token typo tolerance (`SequenceMatcher >= 0.75`) within the target system.
   - **Pass 4 (`fuzzy`)**: If token matching still finds no results, scores all titles in the target system using character bigrams/trigrams and sequence similarity to return the closest prospective matches.
4. **Output File Naming (`<rom_name>.png` vs `<rom_name>-01.png`)**:
   - **Single match (`1`)**: Saved as `<rom_name>.png` (matching the input ROM filename prefix, e.g. `marios_picross_na.gb` $\rightarrow$ `marios_picross_na.png`).
   - **Multiple prospective matches (`> 1`)**: Numbered sequentially as `<rom_name>-01.png`, `<rom_name>-02.png`, `<rom_name>-03.png`, etc.

### Examples

```bash
# 1. ROM filename with 'NA' region tag -> infers Game Boy (.gb), strips 'NA',
#    finds 1 match, and saves it as ./marios_picross_na.png
./fetch_boxart.sh marios_picross_na.gb

# 2. ROM filename with 'EU' region tag and multiple matches on NES ->
#    saves ./castlevania_eu-01.png, ./castlevania_eu-02.png, ./castlevania_eu-03.png
./fetch_boxart.sh castlevania_eu.nes

# 3. Freeform query + explicit system name
./fetch_boxart.sh "mario picross" GB

# 4. Misspelled or concatenated ROM filenames automatically fall back to relaxed/fuzzy matching
./fetch_boxart.sh supermariobros_na.nes
./fetch_boxart.sh castelvania_na.nes

# 5. Preview matches and output filenames without downloading (-n / --dry-run)
./fetch_boxart.sh -n zelda_link_past_eu.sfc
```

---

## Repository Maintenance Scripts

- **[`generate_images_list.sh`](./generate_images_list.sh)**: Scans `boxart/` for all image files and writes the sorted relative paths (`boxart/<System>/<Image>.png`) to `images_list.txt`.
  ```bash
  ./generate_images_list.sh
  ```
