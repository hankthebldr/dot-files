#!/usr/bin/env bash
# scripts/utils/storage-doctor.sh
# Storage Doctor — inventory and (optionally) manage disk usage of the CLI
# install footprint: package-manager caches, dev-tool caches, brew Cellar.
#
# Read-only by default. Mutations require explicit confirmation per category.
#
# Usage:
#   storage-doctor.sh                  # interactive FZF UI
#   storage-doctor.sh report           # plain inventory, no prompts
#   storage-doctor.sh report --json    # machine-readable inventory
#   storage-doctor.sh purge <key>      # purge a category with confirmation
#   storage-doctor.sh --help
#
# Categories are defined in the STORAGE_CATEGORIES array below. Each row:
#   key|label|kind|path|purge_cmd
#     kind   = "cache" (safe to purge, regenerates) | "live" (binaries, manual)
#     path   = absolute path measured with `du -sh`
#     purge_cmd = command run when user confirms a purge ("-" if not purgeable)

set -e

# ============================================
# RESOLVE HELPERS
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./tui-style.sh
source "$SCRIPT_DIR/tui-style.sh"

# Use the unaliased binaries — `du`/`df` may be shadowed by dust/duf in zsh.
DU() { command du "$@"; }
DF() { command df "$@"; }

# ============================================
# CATEGORY REGISTRY
# ============================================
# Format: key|label|kind|path|action_cmd
#   kind   = "cache"   → safe to purge, regenerates on next use
#            "live"    → installed binaries / active state, manual mgmt only
#            "offload" → AI models / large blobs that belong on external SSD;
#                        action_cmd MOVES to $CLAW_OFFLOAD_ROOT, doesn't delete
#   action_cmd is templated against $PATH_FULL and $OFFLOAD_DEST at runtime
#
# *** EXTERNAL OFFLOAD TARGET (LACIE SSD) ***
# AI models (Ollama, HuggingFace, Whisper, etc.) belong on the external SSD,
# not the SSD that runs the OS. We detect the LACIE drive at runtime; if it's
# not mounted, offload categories degrade to read-only "this would move to ..."
CLAW_OFFLOAD_ROOT="${CLAW_OFFLOAD_ROOT:-/Volumes/LacieDrive}"
offload_available() { [[ -d "$CLAW_OFFLOAD_ROOT" && -w "$CLAW_OFFLOAD_ROOT" ]]; }

# Default set targets Henry's macOS + Parrot stack: Homebrew, Node, Python,
# Rust, Go, Docker (live — do not touch, active workspace), and AI caches
# which are offload candidates rather than purge candidates.
STORAGE_CATEGORIES=(
  # --- Homebrew ---
  "brew-cellar|Homebrew Cellar (installed formulae)|live|/opt/homebrew/Cellar|-"
  "brew-cache|Homebrew download cache|cache|$HOME/Library/Caches/Homebrew|brew cleanup -s --prune=all"
  "brew-logs|Homebrew logs|cache|$HOME/Library/Logs/Homebrew|rm -rf $HOME/Library/Logs/Homebrew"

  # --- Node / npm ---
  "npm-cache|npm content-addressable cache|cache|$HOME/.npm/_cacache|npm cache verify"
  "npm-npx|npx package cache|cache|$HOME/.npm/_npx|rm -rf $HOME/.npm/_npx"

  # --- Python ---
  "pip-cache|pip wheel + HTTP cache|cache|$HOME/Library/Caches/pip|pip cache purge"
  "uv-cache|uv cache (Python tooling)|cache|$HOME/.cache/uv|uv cache prune --force"
  "pipx-venvs|pipx tool venvs|live|$HOME/.local/pipx|-"

  # --- Rust / Go ---
  "cargo|Rust cargo (registry + git)|cache|$HOME/.cargo|-"
  "go-modules|Go module cache|cache|$HOME/go/pkg/mod|go clean -modcache"

  # --- Containers (LIVE — active workspace, never auto-touch) ---
  "docker-vm|Docker Desktop VM disk image|live|$HOME/Library/Containers/com.docker.docker/Data/vms|-"

  # --- AI MODELS — offload candidates (LACIE SSD) ---
  # action_cmd uses $PATH_FULL and $OFFLOAD_DEST tokens substituted at runtime.
  "ollama-models|Ollama local model store|offload|$HOME/.ollama/models|claw_offload_ollama"
  "huggingface|HuggingFace model cache|offload|$HOME/.cache/huggingface|claw_offload_rsync"
  "whisper|Whisper.cpp model cache|offload|$HOME/.cache/whisper|claw_offload_rsync"

  # --- Misc dev caches ---
  "puppeteer|Puppeteer Chromium binary|cache|$HOME/.cache/puppeteer|-"
  "firebase|Firebase CLI cache|cache|$HOME/.cache/firebase|-"
  "pre-commit|pre-commit hook envs|cache|$HOME/.cache/pre-commit|pre-commit clean"
)

# ============================================
# LACIE OFFLOAD HELPERS
# ============================================
# Generic rsync-based offload: copy contents to LACIE, verify, then remove
# from local. The order matters — never delete before verifying the copy.
claw_offload_rsync() {
  local src="$1" dest_root="$2" name="$3"
  local dest="$dest_root/$name"
  echo "  ${c_cyan}rsync:${c_reset} $src → $dest"
  mkdir -p "$dest"
  rsync -a --info=progress2 "$src/" "$dest/" || { echo "${c_red}rsync failed.${c_reset}"; return 1; }
  echo "  ${c_dim}verifying...${c_reset}"
  # Cheap verification: file count match. Real verification would use checksums.
  local src_count dest_count
  src_count=$(find "$src" -type f 2>/dev/null | wc -l | tr -d ' ')
  dest_count=$(find "$dest" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$src_count" != "$dest_count" ]]; then
    echo "  ${c_red}file count mismatch ($src_count vs $dest_count) — leaving local copy in place${c_reset}"
    return 1
  fi
  echo "  ${c_green}✓ verified $dest_count files${c_reset}"
  rm -rf "$src"
  mkdir -p "$src"  # leave empty directory so tools don't error
  echo "  ${c_green}✓ removed local copy${c_reset}"
}

# Ollama-specific: also set OLLAMA_MODELS so the daemon writes to LACIE.
# This is the canonical Ollama redirection — symlinks risk getting clobbered.
claw_offload_ollama() {
  local src="$1" dest_root="$2"
  local dest="$dest_root/ollama-models"
  echo "  ${c_cyan}offload target:${c_reset} $dest"

  # If LACIE already has an ollama-models dir, we merge into it.
  if [[ -d "$dest" ]]; then
    echo "  ${c_dim}target exists — merging via rsync${c_reset}"
  fi

  mkdir -p "$dest"
  rsync -a --info=progress2 "$src/" "$dest/" || { echo "${c_red}rsync failed.${c_reset}"; return 1; }

  # Verify
  local src_count dest_count
  src_count=$(find "$src" -type f 2>/dev/null | wc -l | tr -d ' ')
  dest_count=$(find "$dest" -type f 2>/dev/null | wc -l | tr -d ' ')
  echo "  ${c_dim}local files: $src_count · lacie files: $dest_count${c_reset}"

  rm -rf "$src"
  ln -s "$dest" "$src"  # symlink so existing tooling keeps working
  echo "  ${c_green}✓ symlinked $src → $dest${c_reset}"
  echo ""
  echo "  ${c_yellow}NEXT STEP:${c_reset} add to your shell rc to make Ollama use LACIE directly:"
  echo "    ${c_white}export OLLAMA_MODELS=\"$dest\"${c_reset}"
  echo "  (this avoids the symlink, which Ollama updates can clobber.)"
}

# ============================================
# CORE INVENTORY
# ============================================

# Measure one path. Returns human size + raw bytes (tab-separated).
# Missing paths return "0|0".
measure_path() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    printf "0\t0\n"
    return
  fi
  local hr bytes
  hr=$(DU -sh "$path" 2>/dev/null | awk '{print $1}')
  bytes=$(DU -sk "$path" 2>/dev/null | awk '{print $1 * 1024}')
  printf "%s\t%s\n" "${hr:-0}" "${bytes:-0}"
}

# Build the inventory. Emits TSV: key, label, kind, size_hr, size_bytes, path, purge_cmd
inventory() {
  local row key label kind path purge hr bytes
  for row in "${STORAGE_CATEGORIES[@]}"; do
    IFS='|' read -r key label kind path purge <<< "$row"
    # Expand $HOME inside the path field (was literal in array)
    path="${path/#\$HOME/$HOME}"
    IFS=$'\t' read -r hr bytes < <(measure_path "$path")
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
      "$key" "$label" "$kind" "$hr" "$bytes" "$path" "$purge"
  done
}

# ============================================
# REPORT MODE (plain table)
# ============================================
cmd_report() {
  local fmt="${1:-table}"
  if [[ "$fmt" == "--json" ]]; then
    inventory | awk -F'\t' 'BEGIN{print "["} NR>1{print ","} {printf "  {\"key\":\"%s\",\"label\":\"%s\",\"kind\":\"%s\",\"size\":\"%s\",\"bytes\":%s,\"path\":\"%s\",\"purge\":\"%s\"}", $1,$2,$3,$4,$5,$6,$7} END{print "\n]"}'
    return
  fi

  tui_header "💾 STORAGE DOCTOR" "Inventory of CLI install footprint"

  # Disk free up top — what's the headroom?
  echo ""
  printf "  ${c_dim}Disk:${c_reset} "
  DF -h / 2>/dev/null | awk 'NR==2 {printf "%s used of %s (%s) · %s free", $3, $2, $5, $4}'
  echo ""

  tui_section "Categories"
  printf "  ${c_bold}%-18s %-9s %-8s  %s${c_reset}\n" "KEY" "SIZE" "KIND" "PATH"
  inventory | sort -t$'\t' -k5 -rn | while IFS=$'\t' read -r key label kind hr bytes path purge; do
    local kind_color="$c_dim"
    [[ "$kind" == "cache" ]]   && kind_color="$c_green"
    [[ "$kind" == "live" ]]    && kind_color="$c_orange"
    [[ "$kind" == "offload" ]] && kind_color="$c_purple"
    printf "  %-18s ${c_white}%-9s${c_reset} ${kind_color}%-8s${c_reset}  ${c_dim}%s${c_reset}\n" \
      "$key" "$hr" "$kind" "$path"
  done

  echo ""
  # Totals
  local total_cache total_live total_offload
  total_cache=$(inventory   | awk -F'\t' '$3=="cache"{s+=$5}   END{print s+0}')
  total_live=$(inventory    | awk -F'\t' '$3=="live"{s+=$5}    END{print s+0}')
  total_offload=$(inventory | awk -F'\t' '$3=="offload"{s+=$5} END{print s+0}')
  printf "  ${c_green}cache:${c_reset} %s   ${c_orange}live:${c_reset} %s   ${c_purple}offload-candidates:${c_reset} %s\n" \
    "$(numfmt --to=iec --suffix=B "$total_cache"   2>/dev/null || echo "${total_cache}B")" \
    "$(numfmt --to=iec --suffix=B "$total_live"    2>/dev/null || echo "${total_live}B")" \
    "$(numfmt --to=iec --suffix=B "$total_offload" 2>/dev/null || echo "${total_offload}B")"

  # LACIE status line
  echo ""
  if offload_available; then
    local lacie_free
    lacie_free=$(DF -h "$CLAW_OFFLOAD_ROOT" 2>/dev/null | awk 'NR==2 {print $4}')
    printf "  ${c_purple}LACIE:${c_reset} mounted at ${c_white}%s${c_reset} ${c_dim}(%s free)${c_reset}\n" "$CLAW_OFFLOAD_ROOT" "${lacie_free:-?}"
  else
    printf "  ${c_dim}LACIE:${c_reset} not mounted at $CLAW_OFFLOAD_ROOT — offload disabled\n"
  fi
  echo ""
}

# ============================================
# ACTION (purge or offload, depending on kind)
# ============================================
cmd_action() {
  local mode="$1"  # "purge" or "offload"
  local target="$2"
  [[ -z "$target" ]] && { echo "${c_red}usage: storage-doctor.sh $mode <key>${c_reset}"; exit 2; }

  local row key label kind path action found=0
  for row in "${STORAGE_CATEGORIES[@]}"; do
    IFS='|' read -r key label kind path action <<< "$row"
    path="${path/#\$HOME/$HOME}"
    [[ "$key" == "$target" ]] || continue
    found=1

    # Mode/kind compatibility check
    if [[ "$mode" == "purge" && "$kind" == "offload" ]]; then
      echo "${c_yellow}$key is an offload candidate, not a cache.${c_reset}"
      echo "${c_dim}Use:  storage-doctor.sh offload $key${c_reset}"
      exit 1
    fi
    if [[ "$mode" == "offload" && "$kind" != "offload" ]]; then
      echo "${c_yellow}$key is kind '$kind' — only 'offload' categories support offload.${c_reset}"
      exit 1
    fi
    if [[ "$action" == "-" ]]; then
      echo "${c_yellow}$key is marked '$kind' — no automatic action defined.${c_reset}"
      echo "${c_dim}path: $path${c_reset}"
      exit 1
    fi

    # Offload path: needs LACIE
    if [[ "$mode" == "offload" ]]; then
      if ! offload_available; then
        echo "${c_red}LACIE not mounted at $CLAW_OFFLOAD_ROOT${c_reset}"
        echo "${c_dim}plug in the drive (or override with CLAW_OFFLOAD_ROOT=/path)${c_reset}"
        exit 1
      fi
      printf "  ${c_bold}%s${c_reset} ${c_dim}(%s)${c_reset}\n" "$label" "$key"
      printf "  source: ${c_dim}%s${c_reset}\n" "$path"
      printf "  target: ${c_dim}%s/%s${c_reset}\n" "$CLAW_OFFLOAD_ROOT" "$key"
      printf "  size:   ${c_white}%s${c_reset}\n" "$(DU -sh "$path" 2>/dev/null | awk '{print $1}')"
      printf "\n  ${c_orange}offload to LACIE? [y/N]${c_reset} "
      read -r answer
      if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        echo "${c_dim}aborted.${c_reset}"
        exit 0
      fi
      # Dispatch to the helper function named in $action
      "$action" "$path" "$CLAW_OFFLOAD_ROOT" "$key" || { echo "${c_red}offload failed.${c_reset}"; exit 1; }
      exit 0
    fi

    # Purge path (kind=cache)
    printf "  ${c_bold}%s${c_reset} ${c_dim}(%s)${c_reset}\n" "$label" "$key"
    printf "  path:   ${c_dim}%s${c_reset}\n" "$path"
    printf "  before: ${c_white}%s${c_reset}\n" "$(DU -sh "$path" 2>/dev/null | awk '{print $1}')"
    printf "  will run: ${c_cyan}%s${c_reset}\n" "$action"
    printf "\n  ${c_orange}proceed? [y/N]${c_reset} "
    read -r answer
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
      echo "${c_dim}aborted.${c_reset}"
      exit 0
    fi
    # Run the purge — eval intentional because $action can be a pipeline
    eval "$action" || { echo "${c_red}purge failed.${c_reset}"; exit 1; }
    printf "  after:  ${c_green}%s${c_reset}\n" "$(DU -sh "$path" 2>/dev/null | awk '{print $1}' || echo "(gone)")"
    break
  done
  [[ "$found" -eq 0 ]] && { echo "${c_red}unknown key: $target${c_reset}"; exit 2; }
}

# Thin wrappers for back-compat / clear CLI verbs
cmd_purge()   { cmd_action "purge"   "$@"; }
cmd_offload() { cmd_action "offload" "$@"; }

# ============================================
# INTERACTIVE (FZF picker — purge OR offload, branched by kind)
# ============================================
cmd_interactive() {
  if ! command -v fzf &>/dev/null; then
    echo "${c_yellow}fzf not installed — falling back to plain report.${c_reset}"
    cmd_report
    return
  fi

  cmd_report

  # Build FZF rows: any actionable category (purge OR offload).
  # Kind is shown so the user sees the verb that will run.
  local rows
  rows=$(inventory | sort -t$'\t' -k5 -rn | awk -F'\t' '$7!="-" {
    verb = ($3 == "offload") ? "→ LACIE" : "purge  "
    printf "%-18s  %-9s  %-7s  %-8s  %s\n", $1, $4, $3, verb, $2
  }')

  if [[ -z "$rows" ]]; then
    echo "${c_dim}no actionable categories.${c_reset}"
    return
  fi

  local pick pick_kind
  pick=$(echo "$rows" | fzf --reverse --height=~15 --margin=0,0,0,4 \
    --prompt="action ▶ " \
    --header="  ENTER apply · ESC cancel  ·  green=purge purple=offload" \
    --color="bg+:#161b22,fg+:#c9d1d9,prompt:#bc8cff,header:#8b949e,pointer:#3fb950" \
    | awk '{print $1}')

  [[ -z "$pick" ]] && { echo "${c_dim}cancelled.${c_reset}"; return; }
  # Look up the kind so we dispatch to the right verb
  pick_kind=$(inventory | awk -F'\t' -v k="$pick" '$1==k {print $3}')
  if [[ "$pick_kind" == "offload" ]]; then
    cmd_offload "$pick"
  else
    cmd_purge "$pick"
  fi
}

# ============================================
# DISPATCH
# ============================================
case "${1:-}" in
  report)        shift; cmd_report "$@" ;;
  purge)         shift; cmd_purge "$@" ;;
  offload)       shift; cmd_offload "$@" ;;
  -h|--help)
    cat <<EOF
storage-doctor.sh — inventory and manage CLI install storage

  storage-doctor.sh                  interactive FZF UI (default)
  storage-doctor.sh report           plain inventory
  storage-doctor.sh report --json    machine-readable inventory
  storage-doctor.sh purge <key>      purge one cache category (confirm prompt)
  storage-doctor.sh offload <key>    move an AI-model category to LACIE SSD

Env:
  CLAW_OFFLOAD_ROOT  external mount target (default: /Volumes/LacieDrive)

Categories: $(printf '%s\n' "${STORAGE_CATEGORIES[@]}" | cut -d'|' -f1 | tr '\n' ' ')
EOF
    ;;
  "")            cmd_interactive ;;
  *)             echo "${c_red}unknown command: $1${c_reset}  (try --help)"; exit 2 ;;
esac
