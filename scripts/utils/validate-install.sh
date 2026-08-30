#!/usr/bin/env bash
################################################################################
# validate-install.sh — top-to-bottom validation of the workstation install.
#
# One command that walks the whole install (mirrors bootstrap.sh's steps),
# reports PASS / WARN / FAIL per area, tells you when the repo is behind
# (CLI update available), and prints the exact command to fix every gap.
#
# Read-only. Wired as `claw validate` (and `claw doctor --full`).
#
# Flags:
#   --no-fetch   skip the `git fetch` used for update detection (offline)
#   --deep       also run full integrity verify + container GPU passthrough
#   --help
################################################################################
set -e
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck disable=SC1091
source "$DOTFILES_DIR/scripts/utils/logger.sh"
[[ -d "$HOME/.local/bin" ]] && PATH="$HOME/.local/bin:$PATH"
[[ -d /usr/local/cuda/bin ]] && PATH="/usr/local/cuda/bin:$PATH"

FETCH=true; DEEP=false
for a in "$@"; do case $a in
    --no-fetch) FETCH=false ;;
    --deep)     DEEP=true ;;
    --help|-h)  awk 'NR==1&&/^#!/{next} /^####*$/{next} /^# /||/^#$/{sub(/^# ?/,"");print;next} NF==0{print"";next} {exit}' "${BASH_SOURCE[0]}"; exit 0 ;;
esac; done

OS="$(uname -s)"   # Linux | Darwin
PASS=0; WARN=0; FAIL=0; FIXES=()
ok()    { printf '  \033[0;32m✓\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
warn()  { printf '  \033[0;33m!\033[0m %s\n' "$*"; WARN=$((WARN+1)); }
bad()   { printf '  \033[0;31m✗\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
note()  { printf '  \033[0;90m·\033[0m %s\n' "$*"; }
phase() { printf '\n  \033[1;35m%s\033[0m\n' "$*"; }
fix()   { FIXES+=("$1"); }

printf '\n  \033[1mclaw validate\033[0m  \033[0;90m— %s · %s\033[0m\n' "$OS" "$(date '+%Y-%m-%d %H:%M')"

# ── 1. Repo, symlinks, and update status (bootstrap steps 1 & 8) ──────────────
phase "1 · Repo & symlinks"
if [[ -d "$DOTFILES_DIR/.git" ]]; then
    ok "repo present: $DOTFILES_DIR"
    if [[ -L "$HOME/.dotfiles" || -d "$HOME/.dotfiles" ]]; then
        ok "~/.dotfiles → $(readlink -f "$HOME/.dotfiles" 2>/dev/null || echo "$HOME/.dotfiles")"
    else
        bad "~/.dotfiles missing (expected clone/symlink path)"; fix "ln -s '$DOTFILES_DIR' ~/.dotfiles"
    fi
    # stow-deployed configs (representative)
    for f in "$HOME/.zshrc" "$HOME/.tmux.conf"; do
        short="${f/#$HOME/~}"
        if [[ -L "$f" ]]; then ok "linked: $short"
        elif [[ -e "$f" ]]; then warn "$short exists but is NOT a symlink (stow not applied?)"; fix "bash $DOTFILES_DIR/bootstrap.sh   # step 8: stow"
        else bad "$short not deployed"; fix "bash $DOTFILES_DIR/bootstrap.sh   # step 8: stow"; fi
    done
    # update detection
    branch="$(git -C "$DOTFILES_DIR" branch --show-current 2>/dev/null)"
    [[ "$FETCH" == true ]] && git -C "$DOTFILES_DIR" fetch --quiet 2>/dev/null || true
    up="$(git -C "$DOTFILES_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
    if [[ -n "$up" ]]; then
        behind="$(git -C "$DOTFILES_DIR" rev-list --count "HEAD..$up" 2>/dev/null || echo 0)"
        if [[ "${behind:-0}" -gt 0 ]]; then warn "CLI update available: $behind commit(s) behind $up"; fix "claw update"
        else ok "up to date with $up"; fi
    else
        note "branch '$branch' has no upstream — can't check for updates"
    fi
    dirty="$(git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    [[ "${dirty:-0}" -gt 0 ]] && note "$dirty uncommitted change(s) in the working tree"
else
    bad "no git repo at $DOTFILES_DIR"
fi

# ── 1b. Ghostty config chain (2026-07-18 experience spec § 5) ─────────────────
# Guards the repo→app chain: ~/.config/ghostty must resolve into the repo,
# os-active.conf must point at THIS OS's layer, theme.conf must exist (claw
# theme build), and on macOS no App Support shadow config may lurk. Skipped
# entirely when Ghostty is neither installed nor deployed on this box.
if command -v ghostty >/dev/null || [[ -e "$HOME/.config/ghostty" ]]; then
    phase "1b · Ghostty chain"
    gdir="$HOME/.config/ghostty"
    # Normalize both sides — DOTFILES_DIR may arrive unnormalized (tests/..).
    # readlink -f is GNU/macOS-12.3+; fall back to realpath then the literal
    # path on older BSD userlands (same idiom as pkg-manifest.sh).
    droot="$(readlink -f "$DOTFILES_DIR" 2>/dev/null || realpath "$DOTFILES_DIR" 2>/dev/null || echo "$DOTFILES_DIR")"
    if [[ -e "$gdir" ]]; then
        greal="$(readlink -f "$gdir" 2>/dev/null || realpath "$gdir" 2>/dev/null || echo "$gdir")"
        case "$greal" in
            "$droot"/*) ok "~/.config/ghostty → repo ($greal)" ;;
            *) warn "~/.config/ghostty is NOT linked into the repo ($greal)"; fix "bash $DOTFILES_DIR/scripts/setup/symlinks.sh   # relink terminal/" ;;
        esac
        osa="$gdir/os-active.conf"
        [[ "$OS" == "Darwin" ]] && oswant="os-macos.conf" || oswant="os-linux.conf"
        if [[ -L "$osa" || -e "$osa" ]]; then
            osreal="$(readlink "$osa" 2>/dev/null || echo "?")"
            case "$osreal" in
                *"$oswant") ok "os-active.conf → $oswant" ;;
                *) warn "os-active.conf → $osreal (expected $oswant for $OS)"; fix "bash $DOTFILES_DIR/scripts/setup/symlinks.sh   # re-point os-active.conf" ;;
            esac
        else
            warn "os-active.conf missing — per-OS layer (font size, titlebar, quick terminal) not loaded"; fix "bash $DOTFILES_DIR/scripts/setup/symlinks.sh"
        fi
        if [[ -s "$gdir/theme.conf" ]]; then ok "theme.conf present (palette wired)"
        else warn "theme.conf missing — Ghostty runs on fallback colors"; fix "claw theme build   # then cmd+shift+r in Ghostty"; fi
    else
        warn "ghostty installed but ~/.config/ghostty not deployed"; fix "bash $DOTFILES_DIR/scripts/setup/symlinks.sh"
    fi
    if [[ "$OS" == "Darwin" ]]; then
        appsup="$HOME/Library/Application Support/com.mitchellh.ghostty"
        shadow=""
        for f in "$appsup"/config "$appsup"/config.*; do
            if [[ -e "$f" ]]; then shadow="$f"; break; fi
        done
        if [[ -n "$shadow" ]]; then
            warn "App Support shadow config exists: $shadow (may override the repo config)"; fix "mv '$shadow' '$shadow.bak'   # then restart Ghostty"
        else
            ok "no App Support shadow config"
        fi
    fi
fi

# ── 2. Shell stack (bootstrap steps 5 & 7) ────────────────────────────────────
phase "2 · Shell & fonts"
command -v zsh >/dev/null && ok "zsh $(zsh --version | awk '{print $2}')" || { bad "zsh not installed"; fix "bash $DOTFILES_DIR/bootstrap.sh"; }
case "${SHELL:-}" in *zsh) ok "login shell is zsh" ;; *) warn "login shell is ${SHELL:-unknown}, not zsh"; fix "chsh -s \"\$(command -v zsh)\"" ;; esac
[[ -d "$HOME/.oh-my-zsh" ]] && ok "oh-my-zsh present" || { warn "oh-my-zsh missing"; fix "bash $DOTFILES_DIR/bootstrap.sh"; }
if command -v starship >/dev/null; then ok "starship prompt"
elif [[ -f "$HOME/.p10k.zsh" ]]; then ok "powerlevel10k config"
else warn "no starship / p10k prompt config"; fi
if command -v fc-list >/dev/null; then
    fc-list 2>/dev/null | grep -qi 'nerd' && ok "Nerd Font installed" || { warn "no Nerd Font found (icons/prompt glyphs will break)"; fix "bash $DOTFILES_DIR/bootstrap.sh   # step 7: fonts"; }
else
    note "fontconfig (fc-list) absent — skipping font check"
fi

# ── 3. Core CLI tools (bootstrap step 6) ──────────────────────────────────────
phase "3 · Core CLI tools"
missing_cli=()
for t in eza bat rg fd fzf zoxide atuin delta btop lazygit yazi starship gum glow tldr fastfetch; do
    command -v "$t" >/dev/null && ok "$t" || { bad "$t missing"; missing_cli+=("$t"); }
done
[[ ${#missing_cli[@]} -gt 0 ]] && fix "install missing CLI: ${missing_cli[*]}  (bootstrap step 6, or brew/cargo/apt)"

# ── 4. GPU / CUDA (Linux + NVIDIA only) ───────────────────────────────────────
if [[ "$OS" == "Linux" ]] && command -v nvidia-smi >/dev/null; then
    phase "4 · GPU / CUDA"
    if nvidia-smi -L &>/dev/null; then ok "GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
    else bad "nvidia-smi present but no GPU enumerated"; fi
    command -v nvcc >/dev/null && ok "CUDA toolkit $(nvcc --version | grep -o 'release [0-9.]*' | head -1)" || { warn "nvcc missing"; fix "claw install ai-workstation"; }
    command -v nvidia-ctk >/dev/null && ok "nvidia-container-toolkit" || { bad "nvidia-container-toolkit missing"; fix "claw install ai-workstation"; }
fi

# ── 5. AI stack ───────────────────────────────────────────────────────────────
phase "5 · AI stack"
if command -v ollama >/dev/null; then
    curl -fsS --max-time 2 http://localhost:11434/api/tags &>/dev/null && ok "ollama daemon (:11434)" || warn "ollama installed but daemon not reachable"
else warn "ollama not installed"; fix "claw install ai"; fi
command -v vllm >/dev/null && ok "vLLM $(vllm --version 2>&1 | head -1)" || { warn "vLLM not installed"; fix "claw install ai-workstation --inference-only"; }
command -v openshell >/dev/null && ok "OpenShell $(openshell --version 2>&1 | head -1)" || { warn "OpenShell not installed"; fix "claw install ai-workstation --agentic-only"; }
note "deep AI/GPU detail: claw doctor ai --deep"

# ── 6. Desktop (Linux + GNOME only) ───────────────────────────────────────────
if [[ "$OS" == "Linux" ]] && command -v gnome-shell >/dev/null; then
    phase "6 · Desktop (GNOME)"
    command -v gext >/dev/null && ok "gext (extension CLI)" || { warn "gext missing"; fix "bash $DOTFILES_DIR/scripts/install/desktop-linux.sh"; }
    dpkg -s gnome-shell-extension-manager &>/dev/null && ok "Extension Manager" || warn "Extension Manager not installed"
    command -v ghostty >/dev/null && ok "ghostty terminal" || warn "ghostty not installed"
    if gsettings get org.gnome.shell enabled-extensions 2>/dev/null | grep -q 'caffeine@patapon.info'; then ok "Caffeine extension enabled"
    else warn "Caffeine extension not enabled"; fix "bash $DOTFILES_DIR/scripts/install/desktop-linux.sh"; fi
    dpkg -s caffeine &>/dev/null && { warn "legacy apt 'caffeine' still installed (conflicts with the extension)"; fix "sudo apt-get remove -y caffeine"; }
fi

# ── 7. Peripherals (Linux) ────────────────────────────────────────────────────
if [[ "$OS" == "Linux" ]]; then
    phase "7 · Peripherals"
    [[ -f /etc/udev/rules.d/99-tesmart-kvm.rules ]] && ok "TESmart KVM udev rule deployed" || { warn "KVM udev rule not deployed (input drops possible)"; fix "sudo install -m0644 $DOTFILES_DIR/config/udev/99-tesmart-kvm.rules /etc/udev/rules.d/ && sudo udevadm control --reload && sudo udevadm trigger"; }
    command -v solaar >/dev/null && ok "solaar (Logitech)" || note "solaar not installed (optional: sudo apt install solaar)"
    command -v logid  >/dev/null && ok "logiops (logid)"   || note "logiops not installed (optional: sudo apt install logiops)"
fi

# ── 8. Homelab / K3s integration ──────────────────────────────────────────────
if [[ "$OS" == "Linux" ]]; then
    phase "8 · Homelab / K3s"
    if systemctl list-unit-files 2>/dev/null | grep -qE '^k3s(-agent)?\.service'; then
        ok "k3s present on this node"
        if command -v kubectl >/dev/null && kubectl get nodes &>/dev/null; then
            gpu=$(kubectl get nodes -o jsonpath='{.items[*].status.capacity.nvidia\.com/gpu}' 2>/dev/null | tr -d ' ')
            [[ -n "$gpu" ]] && ok "GPU schedulable in cluster (nvidia.com/gpu=$gpu)" || { warn "GPU not advertised to cluster"; fix "claw gpu --test   # from the K3s server"; }
        fi
    else
        note "not joined to a K3s cluster yet (pending SSH/homelab access)"
        note "when ready: homelab-toolchain.sh --agent --server <url> --token-file <path>"
    fi
fi

# ── 9. Integrity (bootstrap step 9b) ──────────────────────────────────────────
phase "9 · Integrity"
man="$DOTFILES_DIR/config/integrity/manifest.sha256"
if [[ -s "$man" ]]; then
    ok "manifest present ($(wc -l < "$man" | tr -d ' ') entries)"
    if [[ "$DEEP" == true ]]; then
        if claw integrity verify &>/dev/null; then ok "integrity verify: no drift"
        else warn "integrity verify reported drift"; fix "claw integrity audit   # inspect CHANGED/MISSING/EXTRA"; fi
    else
        note "run with --deep to diff the tree against the manifest"
    fi
else
    bad "integrity manifest empty/missing"; fix "claw integrity generate"
fi

# ── 10. Security harness (spec §14) ───────────────────────────────────────────
# Readiness, not a scan. Nothing here touches a target or resolves a name — it
# reports whether the gate, the registry and the tool identities are sound.
if [[ -d "$DOTFILES_DIR/scripts/security" ]]; then
    phase "10 · Security harness"
    sec="$DOTFILES_DIR/scripts/security/sec.sh"

    if bash "$sec" lint &>/dev/null; then
        ok "registry + flows lint clean"
    else
        warn "registry or flows fail lint"; fix "claw sec lint   # type, egress and argv rules"
    fi

    # One scope grammar for the hook and the gate. A hook that cannot import
    # scope.py authorizes nothing, which is safe but silently disables recon.
    if DOTFILES_DIR="$DOTFILES_DIR" python3 -c "
import sys; sys.path.insert(0, '$DOTFILES_DIR/claude/hooks')
import _lib; sys.exit(0 if _lib._scope_module() is not None else 1)" &>/dev/null; then
        ok "hook and gate share one scope parser"
    else
        warn "pre_tool_use hook cannot reach scope.py — it will authorize nothing"
        fix "claw harness deploy   # relink claude/ into ~/.claude"
    fi

    # Presence is not identity (§13): a Python httpx or a shell alias reads as
    # installed and produces nothing. Note this runs under the PATH set at the
    # top of this script, which prepends ~/.local/bin — deliberately a harsher
    # ordering than an interactive shell, because the harness must resolve the
    # right binary under any PATH, not just a friendly one.
    if out="$(bash "$sec" doctor 2>&1)"; then
        ok "tool identity: $(printf '%s' "$out" | grep -oE '[0-9]+/[0-9]+ tool\(s\) verified.*' || echo 'all verified')"
    else
        shadowed="$(printf '%s' "$out" | awk '$1=="IDENTITY"{printf "%s ", $2}')"
        warn "tool identity failed: ${shadowed:-unknown} (wrong binary ahead on PATH)"
        note "presence is not identity — a shadowing binary exits 0 and returns nothing"
        fix "claw sec doctor        # names the imposter and the fix per tool"
    fi

    scope_file="${CLAW_SEC_SCOPE_FILE:-$HOME/.claude/scope.txt}"
    if [[ -r "$scope_file" ]]; then
        if bash "$sec" scope show &>/dev/null; then
            ok "scope parses ($(grep -cvE '^\s*#|^\s*$' "$scope_file" || true) entries)"
        else
            bad "scope file does not parse — the hook is authorizing nothing"
            fix "claw sec scope show   # find the offending line"
        fi
    else
        warn "no scope file at $scope_file — all active recon is denied"
        fix "claw sec scope add <target> --global"
    fi
else
    note "security harness not present in this checkout"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
printf '\n  \033[1mResult:\033[0m \033[0;32m%d pass\033[0m · \033[0;33m%d warn\033[0m · \033[0;31m%d fail\033[0m\n' "$PASS" "$WARN" "$FAIL"
if [[ ${#FIXES[@]} -gt 0 ]]; then
    printf '\n  \033[1mTo fix (in order):\033[0m\n'
    # de-dupe while preserving order
    seen=""; n=0
    for f in "${FIXES[@]}"; do
        case "$seen" in *"|$f|"*) continue ;; esac
        seen="$seen|$f|"; n=$((n+1))
        printf '   \033[0;33m%d.\033[0m %s\n' "$n" "$f"
    done
fi
echo
[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0
