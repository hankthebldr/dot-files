#!/usr/bin/env bats
# audit 2026-09-20 F-17/F-18/F-06/F-20: the two-level login menu is replaced by
# ONE flat, fuzzy, frecency-ranked palette over the registry, reachable only on
# demand (bare `claw`, `claw menu`, ^G) and never on the login path.
#
# Everything here stubs fzf — CI has none, and an interactive picker with no tty
# would hang. The stub records argv + stdin and replays a scripted outcome.

REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  export CLAW_NO_LOG=1
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export STUB="$BATS_TEST_TMPDIR/bin"
  export TERM=xterm-256color
  export OS_FAMILY=mac
  export DOTFILES_DIR="$REPO"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$STUB"
  export PATH="$STUB:$PATH"
  export FZF_ARGV="$BATS_TEST_TMPDIR/fzf.argv"
  export FZF_STDIN="$BATS_TEST_TMPDIR/fzf.stdin"
  export DASH_LOG="$BATS_TEST_TMPDIR/dash.log"
  export FF_LOG="$BATS_TEST_TMPDIR/ff.log"
  export MARKER="$BATS_TEST_TMPDIR/marker"
  export FZF_OUT="" FZF_RC=0 FZF_VERSION="0.74.3" FZF_STDERR=""
  stub_fzf
}

# --------------------------------------------------------------------- stubs --

stub_fzf() {
  cat > "$STUB/fzf" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "--version" ]; then echo "${FZF_VERSION:-0.74.3} (stub)"; exit 0; fi
printf '%s\n' "$@" > "${FZF_ARGV:-/dev/null}"
cat > "${FZF_STDIN:-/dev/null}"
if [ -n "${FZF_STDERR:-}" ]; then printf '%s\n' "$FZF_STDERR" >&2; fi
if [ -n "${FZF_OUT:-}" ]; then printf '%b' "$FZF_OUT"; fi
exit "${FZF_RC:-0}"
EOF
  chmod +x "$STUB/fzf"
}

stub_python3() {
  cat > "$STUB/python3" <<'EOF'
#!/usr/bin/env bash
{ printf 'ARGV:%s\n' "$*"
  printf 'CLASS:%s\n' "${PROFILE_CLASS:-}"
  printf 'TAG:%s\n' "${PROFILE_TAG:-}"
  printf 'GLYPH:%s\n' "${PROFILE_GLYPH:-}"
  printf 'HELP:%s\n' "${PROFILE_HELP_CMD:-}"
  printf 'TOOLS:%s\n' "${PROFILE_KEY_TOOLS:-}"
  printf 'DOT:%s\n' "${DOTFILES_DIR:-}"
} >> "${DASH_LOG:-/dev/null}"
EOF
  chmod +x "$STUB/python3"
}

stub_fastfetch() {
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "${FF_LOG:-/dev/null}"\n' > "$STUB/fastfetch"
  chmod +x "$STUB/fastfetch"
}

stub_gum() {  # $1 = exit code for `gum confirm`
  cat > "$STUB/gum" <<EOF
#!/usr/bin/env bash
exit $1
EOF
  chmod +x "$STUB/gum"
}

# Run zsh INTERACTIVELY (-i) with no rc files, source claw-fn.zsh, then \$1.
# Interactive matters: the render, _claw_profile_cd and the ^G bindkey are all
# gated on it, exactly as in a real shell.
zi() { run zsh -fic "source '$REPO/shell/claw-fn.zsh'; $1"; }

# A throwaway DOTFILES_DIR with a scripted registry — for flag-vocabulary and
# failure cases the real registry has no row for.
mkfix() {
  export FIX="$BATS_TEST_TMPDIR/fix"
  mkdir -p "$FIX/scripts/utils" "$FIX/shell/profiles"
  local f
  for f in claw-fn.zsh claw-palette.zsh claw-login.zsh profile-helpers.zsh; do
    ln -sf "$REPO/shell/$f" "$FIX/shell/$f"
  done
  printf 'action\tdanger\t-\tsystem\tD\tDanger\tdestructive\tprintf RAN > "$MARKER"\t!\n' \
     > "$FIX/scripts/utils/rows.tsv"
  printf 'action\tlazy\t-\ttools\tL\tLazy\tneeds a module\tfixfn\tl:fixmod\n' \
    >> "$FIX/scripts/utils/rows.tsv"
  printf 'action\tplain\t-\ttools\tP\tPlain\tno flags\tprintf PLAIN > "$MARKER"\t-\n' \
    >> "$FIX/scripts/utils/rows.tsv"
  printf 'profile\tghostly\t-\tcore\tG\tghostly\tbroken on purpose\tclaw load ghostly\ttheme=;start=;class=X;help=x\n' \
    >> "$FIX/scripts/utils/rows.tsv"
  printf 'fixfn() { printf SOURCED > "$MARKER" }\n' > "$FIX/shell/fixmod.zsh"
  cat > "$FIX/scripts/utils/registry.sh" <<'EOF'
#!/usr/bin/env bash
R="$(dirname "$0")/rows.tsv"
case "$1" in
  rows)    cat "$R" ;;
  palette) awk -F'\t' -v OFS='\t' '$9 !~ /hidden/ {print $2,$1,$5" "$6,$7,$4}' "$R" ;;
  ids)     awk -F'\t' '{print $2}' "$R" ;;
  *)       exit 2 ;;
esac
EOF
  chmod +x "$FIX/scripts/utils/registry.sh"
  # A profile whose dispatcher fails half-way (F-20: unchecked `source`).
  printf 'PROFILE_NAME="ghostly"\nfalse\n' > "$FIX/shell/profiles/ghostly.zsh"
}

zf() { run env DOTFILES_DIR="$FIX" zsh -fic "source '$FIX/shell/claw-fn.zsh'; $1"; }

# ============================================================== T1-08a ========

@test "shell/claw-palette.zsh parses under zsh -n" {
  run zsh -n "$REPO/shell/claw-palette.zsh"
  [ "$status" -eq 0 ]
}

@test "a PROFILE selection goes through the ONE load path" {
  # --print-query + --expect: line 1 query, line 2 key, line 3 selection
  export FZF_OUT='\n\nvault\tprofile\t\xef\x80\xad vault\tObsidian vault root\tknowledge\n'
  zi '_claw_load_profile() { printf "%s %s" "$1" "$2" > "$MARKER" }; claw_palette --src=cmd'
  [ "$status" -eq 0 ]
  [ -f "$MARKER" ]
  [ "$(cat "$MARKER")" = "vault palette" ]
}

@test "an ACTION selection is applied by kind, not by id" {
  export FZF_OUT='\n\nai\taction\t ai\tai services\ttools\n'
  zi '_claw_load_profile() { printf PROFILE > "$MARKER" }; _claw_action() { printf "ACTION %s" "$1" > "$MARKER" }; claw_palette'
  [ "$status" -eq 0 ]
  [ "$(cat "$MARKER")" = "ACTION ai" ]
}

@test "Enter on a query that matches nothing loads nothing and logs palette:esc" {
  unset CLAW_NO_LOG
  export FZF_OUT='cd ~/work\n\n\n' FZF_RC=1
  zi '_claw_load_profile() { printf LOADED > "$MARKER" }; _claw_action() { printf ACTED > "$MARKER" }; claw_palette --src=cmd'
  [ "$status" -eq 0 ]
  [ ! -f "$MARKER" ]
  grep -q 'palette:esc' "$XDG_CACHE_HOME/claw/usage.tsv"
}

@test "ESC loads nothing" {
  export FZF_OUT='\n\n\n' FZF_RC=130
  zi '_claw_load_profile() { printf LOADED > "$MARKER" }; claw_palette'
  [ ! -f "$MARKER" ]
}

@test "fzf rc 2 is loud — its stderr is printed and nothing is applied" {
  export FZF_RC=2 FZF_STDERR="unknown option: --height=~60%"
  zi '_claw_load_profile() { printf LOADED > "$MARKER" }; claw_palette'
  [ ! -f "$MARKER" ]
  [[ "$output" == *"unknown option"* ]]
}

@test "--height auto-sizing is gated on fzf 0.34" {
  export FZF_VERSION="0.29.0"
  zi 'claw_palette'
  grep -qx -- '--height=60%' "$FZF_ARGV"
  export FZF_VERSION="0.74.3"
  zi 'claw_palette'
  grep -qx -- '--height=~60%' "$FZF_ARGV"
}

@test "the palette argv searches the displayed fields" {
  zi 'claw_palette'
  grep -qx -- '--with-nth=3..' "$FZF_ARGV"
  grep -qx -- '--tiebreak=index' "$FZF_ARGV"
  grep -qx -- '--expect=ctrl-p' "$FZF_ARGV"
  grep -qx -- '--layout=reverse' "$FZF_ARGV"
  # the stream fzf consumed is the registry's palette stream
  grep -q $'\tprofile\t' "$FZF_STDIN"
}

@test "a pick bumps frecency.tsv" {
  export FZF_OUT='\n\ndefault\tprofile\t default\tdaily driver\tcore\n'
  zi '_claw_load_profile() { : }; CLAW_NOW=1700000000 claw_palette'
  [ -f "$XDG_STATE_HOME/claw/frecency.tsv" ]
  grep -q $'^default\t1\t1700000000$' "$XDG_STATE_HOME/claw/frecency.tsv"
  # a second pick increments in place, it does not append a duplicate row
  zi '_claw_load_profile() { : }; CLAW_NOW=1700000900 claw_palette'
  [ "$(wc -l < "$XDG_STATE_HOME/claw/frecency.tsv")" -eq 1 ]
  grep -q $'^default\t2\t1700000900$' "$XDG_STATE_HOME/claw/frecency.tsv"
}

@test "^G is bound to the palette widget in emacs, viins and vicmd" {
  zi 'for m in emacs viins vicmd; do bindkey -M $m "^G"; done'
  [ "$status" -eq 0 ]
  [ "$(grep -c '_claw_palette_widget' <<< "$output")" -eq 3 ]
}

@test "CLAW_PALETTE_KEY= leaves the chord unbound" {
  export CLAW_PALETTE_KEY=
  zi 'bindkey -M emacs "^G"'
  [[ "$output" != *"_claw_palette_widget"* ]]
}

@test "CLAW_PALETTE_KEY rebinds the chord" {
  export CLAW_PALETTE_KEY='^T'
  zi 'bindkey -M viins "^T"'
  [[ "$output" == *"_claw_palette_widget"* ]]
}

@test "_claw_action refuses an id with no registry row" {
  unset CLAW_NO_LOG
  mkfix
  zf '_claw_action nosuchverb'
  [ "$status" -eq 1 ]
  [[ "$output" == *"nosuchverb"* ]]
  grep -q 'palette:badid' "$XDG_CACHE_HOME/claw/usage.tsv"
}

@test "_claw_action runs an unflagged verb and bumps its frecency" {
  mkfix
  zf 'CLAW_NOW=1700000000 _claw_action plain'
  [ "$(cat "$MARKER")" = "PLAIN" ]
  grep -q $'^plain\t1\t1700000000$' "$XDG_STATE_HOME/claw/frecency.tsv"
}

@test "a ! verb declined at the confirm prompt never runs" {
  mkfix; stub_gum 1
  zf '_claw_action danger'
  [ "$status" -ne 0 ]
  [ ! -f "$MARKER" ]
}

@test "a ! verb confirmed at the prompt runs" {
  mkfix; stub_gum 0
  zf '_claw_action danger'
  [ "$(cat "$MARKER")" = "RAN" ]
}

@test "an l:<mod> verb lazy-sources its module before running" {
  mkfix
  zf '_claw_action lazy'
  [ "$(cat "$MARKER")" = "SOURCED" ]
}

@test "an l:<mod> verb does not re-source when the run is already a function" {
  mkfix
  zf 'fixfn() { printf ALREADY > "$MARKER" }; _claw_action lazy'
  [ "$(cat "$MARKER")" = "ALREADY" ]
}

@test "F-06: the strings fzf swallowed at login pick no profile in the palette" {
  command -v fzf >/dev/null || skip "no fzf on this host"
  local real_path="${PATH#$STUB:}"
  local stream q hits top
  stream="$(DOTFILES_DIR="$REPO" bash "$REPO/scripts/utils/registry.sh" palette)"
  # The two the audit reproduced on a pty (`git status` -> default,
  # `cd ~/work` -> claude) now match NOTHING, so Enter is a no-op.
  for q in 'git status' 'cd ~/work'; do
    hits="$(printf '%s\n' "$stream" \
      | PATH="$real_path" fzf --delimiter=$'\t' --with-nth=3.. --nth=1.. --tiebreak=index --filter="$q" \
      | wc -l | tr -d ' ')"
    [ "$hits" -eq 0 ] || { echo "query '$q' matched $hits rows"; return 1; }
  done
  # `ls` still fuzzy-matches deeper rows (tooLS, toolS...), which is harmless:
  # Enter takes rank 1, and no profile ranks there. The structural half of F-06
  # is that none of this is on the login path any more.
  for q in 'git status' 'cd ~/work' 'ls'; do
    top="$(printf '%s\n' "$stream" \
      | PATH="$real_path" fzf --delimiter=$'\t' --with-nth=3.. --nth=1.. --tiebreak=index --filter="$q" \
      | head -1 | cut -f2)"
    [ "$top" != "profile" ] || { echo "query '$q' preselects a profile"; return 1; }
  done
}

# ============================================================== T1-08b ========

@test "claw load with no profile lists the registry's profiles, not a hardcoded copy" {
  zi 'claw load'
  [ "$status" -eq 1 ]
  [[ "$output" == *"blackwell"* ]]
  [[ "$output" == *"tunnels"* ]]
  run grep -n 'default local claude cloud devops security' "$REPO/shell/claw-fn.zsh"
  [ "$status" -ne 0 ]
}

@test "claw load <unknown> returns 1 and leaves CLAW_ACTIVE_PROFILE unset" {
  zi 'claw load ghost; print "rc=$?"; print "p=[${CLAW_ACTIVE_PROFILE-unset}]"'
  [[ "$output" == *"rc=1"* ]]
  [[ "$output" == *"p=[unset]"* ]]
}

@test "F-20: a profile whose source fails is rolled back, not left half-applied" {
  mkfix
  zf 'claw load ghostly; print "rc=$?"; print "p=[${CLAW_ACTIVE_PROFILE-unset}]"'
  [[ "$output" == *"rc=1"* ]]
  [[ "$output" == *"p=[unset]"* ]]
}

@test "F-20: claw load security loads the helper-guarded aliases, all 20" {
  stub_python3
  zi 'claw load security >/dev/null 2>&1
      n=0
      for a in nrecon nharvest amasse subf sqli listen hash0 hydraq fuzz gobust; do
        (( ${+aliases[$a]} + ${+functions[$a]} )) && (( n++ ))
      done
      print "guarded=$n"'
  [[ "$output" == *"guarded=10"* ]]
}

@test "F-20: claw load security does not leak 'command not found: _claw_guard'" {
  stub_python3
  zi 'claw load security'
  [[ "$output" != *"_claw_guard"* ]]
}

@test "the profile frame gets the PROFILE_* env and the --profile argv" {
  stub_python3
  zi 'claw load security'
  grep -q -- '--profile security' "$DASH_LOG"
  grep -q '^CLASS:NIGHTHACKER$' "$DASH_LOG"
  grep -q '^HELP:sec-help$' "$DASH_LOG"
  grep -q "^DOT:$REPO\$" "$DASH_LOG"
}

@test "CLAW_PROFILE_ART=fastfetch takes the fastfetch branch instead of the frame" {
  stub_python3; stub_fastfetch
  export CLAW_PROFILE_ART=fastfetch
  zi 'claw load security'
  [ ! -f "$DASH_LOG" ]
  grep -q 'config-security.jsonc' "$FF_LOG"
}

@test "claw load bumps frecency and logs a load row with its source" {
  unset CLAW_NO_LOG
  stub_python3
  zi 'CLAW_NOW=1700000000 claw load security'
  grep -q $'^security\t1\t1700000000$' "$XDG_STATE_HOME/claw/frecency.tsv"
  grep -q $'\tload\t' "$XDG_CACHE_HOME/claw/usage.tsv"
  grep -q 'src=cmd' "$XDG_CACHE_HOME/claw/usage.tsv"
}

@test "bare claw opens the palette in this shell" {
  export FZF_OUT='\n\n\n' FZF_RC=130
  zi 'claw'
  [ -f "$FZF_ARGV" ]
  grep -qx -- "--prompt=claw ▸ " "$FZF_ARGV"
}

@test "claw menu opens the palette too" {
  export FZF_OUT='\n\n\n' FZF_RC=130
  zi 'claw menu'
  [ -f "$FZF_ARGV" ]
}

@test "claw dash renders the login card" {
  stub_python3
  zi 'claw dash'
  grep -q -- '--login' "$DASH_LOG"
}

@test "claw theme set recolours the prompt live" {
  zi 'source "$DOTFILES_DIR/scripts/utils/theme.sh"
      p10k() { print "p10k $*" }
      claw theme set tokyo-night
      print "DIR=$POWERLEVEL9K_DIR_BACKGROUND"'
  [[ "$output" == *"p10k reload"* ]]
  [[ "$output" == *"DIR=#"* ]]
  [ "$(cat "$XDG_STATE_HOME/claw/theme")" = "tokyo-night" ]
}

@test "claw theme with any other verb still passes through to the binary" {
  zi 'claw theme list'
  [ "$status" -eq 0 ]
  [[ "$output" == *"tokyo-night"* ]]
}
