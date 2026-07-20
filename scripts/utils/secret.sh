#!/usr/bin/env bash
################################################################################
# secret.sh — foundational secret storage on age + sops.
#
# Pattern (the 2026 homelab/GitOps standard): `age` is the keypair primitive,
# `sops` encrypts only the VALUES in yaml/json/env so files stay diffable and
# git-safe. One offline key, no GPG, no keyserver. `op`/`bw` optional on top.
#
#   claw secret init                generate an age key (idempotent), print pubkey
#   claw secret encrypt <file>      sops-encrypt in place (yaml/json/env/ini)
#   claw secret decrypt <file>      sops-decrypt to stdout
#   claw secret edit <file>         open the decrypted file in $EDITOR, re-encrypt on save
#   claw secret env                 edit the encrypted env (config/secrets/.env.sops)
#   claw secret doctor              age/sops present? key present? .sops.yaml present?
################################################################################
set -uo pipefail
DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
# shellcheck source=/dev/null
source "$DOTFILES/scripts/utils/cinematic.sh" 2>/dev/null || { log_info(){ echo "▸ $*"; }; log_success(){ echo "✓ $*"; }; log_warning(){ echo "! $*"; }; log_error(){ echo "✗ $*" >&2; }; log_skip(){ echo "· $*"; }; c_white=''; c_dim=''; c_reset=''; }

AGE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/age"
AGE_KEY="$AGE_DIR/keys.txt"
SOPS_ENV="$DOTFILES/config/secrets/.env.sops"
SOPS_RULES="$DOTFILES/.sops.yaml"
export SOPS_AGE_KEY_FILE="$AGE_KEY"

_need() { command -v "$1" &>/dev/null || { log_error "$1 not installed — run: claw install nextgen"; return 1; }; }

sec_init() {
    _need age || return 1
    mkdir -p "$AGE_DIR"; chmod 700 "$AGE_DIR"
    if [[ -f "$AGE_KEY" ]]; then log_skip "age key exists: $AGE_KEY"; else
        age-keygen -o "$AGE_KEY" 2>/dev/null && chmod 600 "$AGE_KEY" && log_success "generated $AGE_KEY"
    fi
    local pub; pub="$(grep -oE 'age1[0-9a-z]+' "$AGE_KEY" | tail -1)"
    log_info "public key: ${c_white}${pub}${c_reset}"
    # Seed a .sops.yaml creation rule so `sops` auto-targets this key.
    if [[ ! -f "$SOPS_RULES" ]]; then
        cat > "$SOPS_RULES" <<EOF
# sops creation rules — encrypt secrets to the operator's age key.
creation_rules:
  - path_regex: (\.env\.sops|secrets/.*\.(ya?ml|json|env))\$
    age: ${pub}
EOF
        log_success "wrote $SOPS_RULES (targets your age key)"
    fi
    log_info "back up ${c_white}$AGE_KEY${c_reset} somewhere safe (a lost key = lost secrets)"
}

sec_encrypt() { _need sops || return 1; sops -e -i "$1" && log_success "encrypted $1"; }
sec_decrypt() { _need sops || return 1; sops -d "$1"; }
sec_edit()    { _need sops || return 1; sops "$1"; }

sec_env() {
    _need sops || return 1
    mkdir -p "$(dirname "$SOPS_ENV")"
    if [[ ! -f "$SOPS_ENV" ]]; then
        [[ -f "$AGE_KEY" ]] || { log_error "no age key — run: claw secret init"; return 1; }
        printf 'OPENROUTER_API_KEY=\nANTHROPIC_API_KEY=\nGOOGLE_API_KEY=\nGEMINI_API_KEY=\nGITHUB_TOKEN=\nSHODAN_API_KEY=\nOBSIDIAN_API_KEY=\n' > "$SOPS_ENV"
        sops -e -i "$SOPS_ENV" && log_success "created encrypted $SOPS_ENV"
    fi
    sops "$SOPS_ENV"
}

# Decrypt the sops env into the current environment (called from load-env.zsh).
sec_load_env() {
    [[ -f "$SOPS_ENV" ]] && command -v sops &>/dev/null || return 0
    local line k v
    while IFS= read -r line; do
        # split on the FIRST '=' only — values may contain '=' (base64, JWTs).
        k="${line%%=*}"; v="${line#*=}"
        [[ "$k" =~ ^[A-Za-z_][A-Za-z0-9_]*$ && -n "$v" ]] && export "$k=$v"
    done < <(sops -d "$SOPS_ENV" 2>/dev/null)
}

# Emit `export KEY=VAL` lines for eval by a caller that must NOT inherit this
# script's `set -uo pipefail` (load-env.zsh sources into the interactive shell).
sec_env_export() {
    [[ -f "$SOPS_ENV" ]] && command -v sops &>/dev/null || return 0
    local line k v
    while IFS= read -r line; do
        k="${line%%=*}"; v="${line#*=}"
        [[ "$k" =~ ^[A-Za-z_][A-Za-z0-9_]*$ && -n "$v" ]] && printf 'export %s=%q\n' "$k" "$v"
    done < <(sops -d "$SOPS_ENV" 2>/dev/null)
}

sec_doctor() {
    printf "\n  ${c_white}secret stack${c_reset}\n"
    command -v age  &>/dev/null && log_success "age  $(age --version 2>/dev/null | head -1)"   || log_warning "age missing"
    command -v sops &>/dev/null && log_success "sops $(sops --version 2>/dev/null | head -1)"   || log_warning "sops missing"
    [[ -f "$AGE_KEY" ]]    && log_success "age key: $AGE_KEY"     || log_warning "no age key (claw secret init)"
    [[ -f "$SOPS_RULES" ]] && log_success ".sops.yaml present"    || log_warning "no .sops.yaml"
    [[ -f "$SOPS_ENV" ]]   && log_success "encrypted env present" || log_skip "no encrypted env (claw secret env)"
    command -v op &>/dev/null && log_success "1Password CLI present (optional layer)" || log_skip "op (optional)"
}

case "${1:-doctor}" in
    init)         sec_init ;;
    encrypt|enc)  shift; [[ -z "${1:-}" ]] && { echo "usage: claw secret encrypt <file>"; exit 1; }; sec_encrypt "$1" ;;
    decrypt|dec)  shift; [[ -z "${1:-}" ]] && { echo "usage: claw secret decrypt <file>"; exit 1; }; sec_decrypt "$1" ;;
    edit)         shift; [[ -z "${1:-}" ]] && { echo "usage: claw secret edit <file>"; exit 1; }; sec_edit "$1" ;;
    env)          sec_env ;;
    load)         sec_load_env ;;
    env-export)   sec_env_export ;;
    doctor)       sec_doctor ;;
    *)            echo "usage: claw secret {init|encrypt|decrypt|edit|env|doctor}" ;;
esac
