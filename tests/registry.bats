#!/usr/bin/env bats
# audit 2026-09-20 F-15/F-17: five taxonomies, two menu models and six copies of
# the 18-profile list. scripts/utils/registry.sh + config/claw/actions.tsv are
# the single source of truth every downstream surface (palette, claw help,
# completion, tui-stats) is generated from — so these tests pin the emitter's
# OUTPUT FORMATS as a contract, not just its exit codes.

REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
REG="$REPO/scripts/utils/registry.sh"

setup() {
  export CLAW_NO_LOG=1
  export DOTFILES_DIR="$REPO"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  mkdir -p "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
}

# The arms bin/claw actually dispatches on, per the item spec's extractor.
dispatch_arms() {
  awk '/^case "\$\{1:-menu\}" in/{f=1;next} f&&/^esac/{exit} f&&/^    [^ #].*\)/{sub(/\).*/,""); gsub(/^ +/,""); print}' "$REPO/bin/claw" \
    | tr '|' '\n' | sed 's/^"//; s/"$//' \
    | grep -vx -e '' -e '\*' -e '-h' -e '--help'
}

profile_dirs() {
  find "$REPO/shell/profiles" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
}

# ---------------------------------------------------------------- coverage ---

@test "registry.sh is executable and 100755 in the index" {
  [ -x "$REG" ]
  run git -C "$REPO" ls-files -s scripts/utils/registry.sh
  [ "$status" -eq 0 ]
  [[ "$output" == 100755* ]]
}

@test "every bin/claw dispatch arm has a registry row or alias" {
  ids="$(bash "$REG" ids --with-aliases)"
  missing=""
  while IFS= read -r arm; do
    printf '%s\n' "$ids" | grep -qxF -- "$arm" || missing="$missing $arm"
  done < <(dispatch_arms)
  echo "uncovered dispatch arms:$missing"
  [ -z "$missing" ]
}

@test "one row per profile dir, none with an empty glyph or desc" {
  n_dirs="$(profile_dirs | wc -l | tr -d ' ')"
  run bash "$REG" rows
  [ "$status" -eq 0 ]
  n_rows="$(printf '%s\n' "$output" | awk -F'\t' '$1=="profile"' | wc -l | tr -d ' ')"
  [ "$n_rows" -eq "$n_dirs" ]
  [ "$n_rows" -eq 18 ]
  bad="$(printf '%s\n' "$output" | awk -F'\t' '$1=="profile" && ($5=="" || $5=="-" || $7=="" || $7=="-"){print $2}')"
  echo "profiles with empty glyph/desc: $bad"
  [ -z "$bad" ]
  # every dir is represented by name
  for p in $(profile_dirs); do
    printf '%s\n' "$output" | awk -F'\t' -v p="$p" '$1=="profile" && $2==p{found=1} END{exit !found}'
  done
}

@test "rows emits 9 tab-separated fields and 18 profile rows + every action row" {
  run bash "$REG" rows
  [ "$status" -eq 0 ]
  widths="$(printf '%s\n' "$output" | awk -F'\t' '{print NF}' | sort -u)"
  [ "$widths" = "9" ]
  n_actions_file="$(awk -F'\t' '!/^#/ && NF>1{c++} END{print c+0}' "$REPO/config/claw/actions.tsv")"
  n_actions_rows="$(printf '%s\n' "$output" | awk -F'\t' '$1=="action"' | wc -l | tr -d ' ')"
  [ "$n_actions_rows" -eq "$n_actions_file" ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq "$((18 + n_actions_file))" ]
}

@test "glyphs are unique across BOTH sources" {
  run bash "$REG" rows
  [ "$status" -eq 0 ]
  dupes="$(printf '%s\n' "$output" | awk -F'\t' '$5!="-" && $5!=""{print $5}' | sort | uniq -d)"
  echo "duplicate glyphs: $dupes"
  [ -z "$dupes" ]
}

@test "ids are unique within each kind and aliases never shadow an action id" {
  run bash "$REG" rows
  [ "$status" -eq 0 ]
  for kind in profile action; do
    dupes="$(printf '%s\n' "$output" | awk -F'\t' -v k="$kind" '$1==k{print $2}' | sort | uniq -d)"
    echo "duplicate $kind ids: $dupes"
    [ -z "$dupes" ]
  done
  # action namespace: ids + aliases must all be distinct
  dupes="$(printf '%s\n' "$output" \
    | awk -F'\t' '$1=="action"{print $2; if ($3!="-" && $3!="") {n=split($3,a,"|"); for(i=1;i<=n;i++) print a[i]}}' \
    | sort | uniq -d)"
  echo "duplicate action names: $dupes"
  [ -z "$dupes" ]
}

# ------------------------------------------------------------------- check ---

@test "check exits 0 and prints nothing on the real tree" {
  run bash "$REG" check
  echo "$output"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check fails on a duplicate action id" {
  tmp="$BATS_TEST_TMPDIR/dup"; mkdir -p "$tmp/config/claw" "$tmp/shell/profiles"
  { grep -v '^#' "$REPO/config/claw/actions.tsv" | grep -v '^$'
    printf 'doctor\t-\tsystem\t-\tDoctor2\tsecond one\tcommand claw doctor\thidden\n'; } \
    > "$tmp/config/claw/actions.tsv"
  run env DOTFILES_DIR="$tmp" bash "$REG" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate action id 'doctor'"* ]]
}

@test "check fails on a bad column count" {
  tmp="$BATS_TEST_TMPDIR/cols"; mkdir -p "$tmp/config/claw" "$tmp/shell/profiles"
  printf 'lonely\t-\tsystem\t-\tLonely\n' > "$tmp/config/claw/actions.tsv"
  run env DOTFILES_DIR="$tmp" bash "$REG" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"5 columns, want 8"* ]]
}

@test "check fails on an unknown flag" {
  tmp="$BATS_TEST_TMPDIR/flag"; mkdir -p "$tmp/config/claw" "$tmp/shell/profiles"
  printf 'weird\t-\tsystem\t-\tWeird\tbad flag\techo hi\tnope\n' > "$tmp/config/claw/actions.tsv"
  run env DOTFILES_DIR="$tmp" bash "$REG" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown flag 'nope'"* ]]
}

@test "check fails on a duplicate glyph across the two sources" {
  tmp="$BATS_TEST_TMPDIR/glyph"; mkdir -p "$tmp/config/claw" "$tmp/shell/profiles/ghost"
  glyph="$(printf '\xef\x80\x9b')"   # U+F01B, the lint's spare fixture glyph
  cat > "$tmp/shell/profiles/ghost/meta.zsh" <<EOF
PROFILE_NAME="ghost"
PROFILE_TIER="4"
PROFILE_GLYPH="$glyph"
PROFILE_DESC="fixture profile"
PROFILE_START_DIR=""
EOF
  printf 'ghostly\t-\tsystem\t%s\tGhostly\tsame glyph as the profile\techo hi\t-\n' "$glyph" \
    > "$tmp/config/claw/actions.tsv"
  run env DOTFILES_DIR="$tmp" bash "$REG" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate glyph"* ]]
}

@test "check fails on a missing PROFILE_GLYPH or PROFILE_DESC" {
  tmp="$BATS_TEST_TMPDIR/meta"; mkdir -p "$tmp/config/claw" "$tmp/shell/profiles/ghost"
  cat > "$tmp/shell/profiles/ghost/meta.zsh" <<'EOF'
PROFILE_NAME="ghost"
PROFILE_TIER="4"
PROFILE_START_DIR=""
EOF
  : > "$tmp/config/claw/actions.tsv"
  run env DOTFILES_DIR="$tmp" bash "$REG" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"ghost"* ]]
  [[ "$output" == *"PROFILE_GLYPH"* ]]
}

@test "check fails when a run calls a claw subcommand that is not a dispatch arm" {
  tmp="$BATS_TEST_TMPDIR/arm"; mkdir -p "$tmp/config/claw" "$tmp/shell/profiles" "$tmp/bin"
  cp "$REPO/bin/claw" "$tmp/bin/claw"
  printf 'bogus\t-\tsystem\t-\tBogus\tno such arm\tcommand claw frobnicate\thidden\n' \
    > "$tmp/config/claw/actions.tsv"
  run env DOTFILES_DIR="$tmp" bash "$REG" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"frobnicate"* ]]
}

# ----------------------------------------------------------------- palette ---

@test "palette emits 5 fields, omits hidden rows, and prefixes the glyph" {
  run bash "$REG" palette
  [ "$status" -eq 0 ]
  widths="$(printf '%s\n' "$output" | awk -F'\t' '{print NF}' | sort -u)"
  [ "$widths" = "5" ]
  # hidden ids are absent
  run bash -c "DOTFILES_DIR='$REPO' bash '$REG' palette | awk -F'\t' '\$1==\"mcp-sync\"'"
  [ -z "$output" ]
  # a known visible action is present with its glyph attached to its label
  run bash -c "DOTFILES_DIR='$REPO' bash '$REG' palette | awk -F'\t' '\$1==\"doctor\"{print \$3\"|\"\$5}'"
  [[ "$output" == *"Doctor|system"* ]]
  [ "${#output}" -gt 13 ]   # glyph really is prefixed
}

@test "palette ranks a frecency-bumped id first and is deterministic under CLAW_NOW" {
  mkdir -p "$XDG_STATE_HOME/claw"
  printf 'gamble\t50\t1000000\n' > "$XDG_STATE_HOME/claw/frecency.tsv"
  run env CLAW_NOW=1000100 bash "$REG" palette
  [ "$status" -eq 0 ]
  first="$(printf '%s\n' "$output" | head -1 | cut -f1)"
  [ "$first" = "gamble" ]
  # the same count 30 days stale scores 16x less and loses to a fresh smaller count
  printf 'gamble\t50\t1000000\ntheme\t20\t4000000\n' > "$XDG_STATE_HOME/claw/frecency.tsv"
  run env CLAW_NOW=4000100 bash "$REG" palette
  first="$(printf '%s\n' "$output" | head -1 | cut -f1)"
  [ "$first" = "theme" ]
}

@test "palette with no frecency file falls back to rows order (profiles first)" {
  run bash "$REG" palette
  [ "$status" -eq 0 ]
  first="$(printf '%s\n' "$output" | head -1 | cut -f2)"
  [ "$first" = "profile" ]
}

# ------------------------------------------------------- ids / completion ----

@test "ids filters by kind and --with-aliases adds the alias names" {
  run bash "$REG" ids profiles
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 18 ]
  printf '%s\n' "$output" | grep -qx security

  run bash "$REG" ids actions
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx doctor
  ! printf '%s\n' "$output" | grep -qx upgrade

  run bash "$REG" ids --with-aliases actions
  printf '%s\n' "$output" | grep -qx upgrade
}

@test "completion emits id:desc for ids, aliases and profiles" {
  run bash "$REG" completion
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '^doctor:'
  printf '%s\n' "$output" | grep -q '^upgrade:'
  printf '%s\n' "$output" | grep -q '^security:'
  printf '%s\n' "$output" | grep -q '^mcp-sync:'   # hidden rows still complete
  # exactly one colon-separated key per line, no tabs
  ! printf '%s\n' "$output" | grep -q '	'
}

@test "help groups the registry and survives a bare environment" {
  run env -u CLAW_RGB_BLUE bash "$REG" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"core"* ]]
  [[ "$output" == *"security"* ]]
  [[ "$output" == *"system"* ]]
}

@test "run and show resolve an id, and a bogus id exits 1" {
  run bash "$REG" run doctor
  [ "$status" -eq 0 ]
  [ "$output" = "command claw doctor" ]

  run bash "$REG" run action:homelab
  [ "$status" -eq 0 ]
  [ "$output" = "command claw homelab" ]

  run bash "$REG" run profile:security
  [ "$status" -eq 0 ]
  [ "$output" = "claw load security" ]

  run bash "$REG" show security
  [ "$status" -eq 0 ]
  [[ "$output" == *"security"* ]]

  run bash "$REG" run nope-not-here
  [ "$status" -eq 1 ]
}

# -------------------------------------------------------------- parity ------

@test "rows theme= matches a zsh-sourced meta.zsh for all 18 profiles" {
  command -v zsh >/dev/null 2>&1 || skip "zsh not available"
  run bash "$REG" rows
  [ "$status" -eq 0 ]
  rows="$output"
  n=0
  for p in $(profile_dirs); do
    want="$(zsh -fc "source '$REPO/shell/profiles/$p/meta.zsh'; print -r -- \$PROFILE_THEME_DEFAULT")"
    got="$(printf '%s\n' "$rows" | awk -F'\t' -v p="$p" '$1=="profile" && $2==p{print $9}' \
             | sed -n 's/.*theme=\([^;]*\);.*/\1/p')"
    echo "$p: want='$want' got='$got'"
    [ "$want" = "$got" ]
    n=$((n+1))
  done
  [ "$n" -eq 18 ]
}

@test "rows start= carries the RAW unexpanded PROFILE_START_DIR" {
  run bash "$REG" rows
  [ "$status" -eq 0 ]
  got="$(printf '%s\n' "$output" | awk -F'\t' '$1=="profile" && $2=="security"{print $9}')"
  [[ "$got" == *'start=${PENTEST_WORKSPACE:-$HOME/pentest}|@vault-folder;'* ]]
}

@test "rows maps tier to the spec group vocabulary" {
  run bash "$REG" rows
  [ "$status" -eq 0 ]
  g() { printf '%s\n' "$output" | awk -F'\t' -v p="$1" '$1=="profile" && $2==p{print $4}'; }
  [ "$(g default)"   = core ]
  [ "$(g security)"  = domain ]
  [ "$(g claude)"    = agent ]
  [ "$(g vault)"     = knowledge ]
  [ "$(g deck)"      = customer ]
  [ "$(g blackwell)" = hardware ]
}

# -------------------------------------------------------------- strict ------

@test "no surviving hardcoded 18-profile list (strict; CLAW_REGISTRY_STRICT=0 opts out)" {
  [ "${CLAW_REGISTRY_STRICT:-1}" = 1 ] || skip "strict mode disabled via CLAW_REGISTRY_STRICT=0"
  hits="$(grep -rlE 'default[ |]+local[ |]+claude' "$REPO/shell" "$REPO/bin" "$REPO/scripts" \
            2>/dev/null | grep -v 'scripts/utils/registry.sh' | grep -v '/legacy/' || true)"
  echo "hardcoded profile lists: $hits"
  [ -z "$hits" ]
}

# T2-05: the grep above only matched ONE word order, which is why three copies
# in onboarding.sh (a different order) survived it for weeks. This one is
# order-independent: tokenise every line and count DISTINCT registry profile
# ids on it. Eight or more on a single line is a destination list, whatever
# order it is written in. registry.sh and legacy/ are the only legal homes.
@test "strict: no line outside registry.sh names 8+ profile ids, in any order" {
  [ "${CLAW_REGISTRY_STRICT:-1}" = 1 ] || skip "strict mode disabled via CLAW_REGISTRY_STRICT=0"
  # one space-separated line: BSD awk rejects a newline inside a -v value.
  ids="$(bash "$REG" ids profiles | tr '\n' ' ')"
  [ -n "$ids" ]
  hits="$(find "$REPO/shell" "$REPO/bin" "$REPO/scripts" -type f \
            ! -path '*/legacy/*' ! -name 'registry.sh' -print0 2>/dev/null \
          | xargs -0 awk -v ids="$ids" '
              BEGIN { n = split(ids, a, " ")
                      for (i = 1; i <= n; i++) if (a[i] != "") want[a[i]] = 1 }
              # Two exemptions, both content-anchored so they survive line drift:
              # a prose comment is not a dispatcher, and `claw install` lists
              # TOOLCHAIN domains (nextgen, ai-workstation, ai-skills…) which
              # are a different taxonomy the registry does not own.
              /^[ \t]*#/ { next }
              /claw install/ { next }
              {
                split("", seen); c = 0
                m = split($0, w, /[^A-Za-z0-9_]+/)
                for (i = 1; i <= m; i++)
                  if ((w[i] in want) && !(w[i] in seen)) { seen[w[i]] = 1; c++ }
                if (c >= 8) printf "%s:%d: %d profile ids on one line\n", FILENAME, FNR, c
              }' || true)"
  echo "$hits"
  [ -z "$hits" ]
}

# --------------------------------------------------------------- onboarding --
# T2-05: onboarding.sh scored the quiz against a hand-written list of all 18
# profiles in THREE places and carried its own class + description tables.
# All four now come from the registry, so a 19th profile needs no edit here.

@test "onboarding.sh takes its profile list from the registry, not a literal" {
  run grep -c 'registry.sh' "$REPO/scripts/utils/onboarding.sh"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
  run grep -nE 'for p in (cloud|default|ai|local) ' "$REPO/scripts/utils/onboarding.sh"
  [ "$status" -ne 0 ]
}

@test "onboarding.sh: class + impact come from the registry for every profile" {
  # Source-free probe: re-run the file's own accessors through a tiny driver
  # so the quiz is never entered. `help` is a no-op subcommand.
  run env DOTFILES_DIR="$REPO" bash -c '
    set -e
    eval "$(sed -n "/^_load_registry/,/^}/p" "$1")"
    REPO_ROOT="'"$REPO"'"
    REGISTRY="$REPO_ROOT/scripts/utils/registry.sh"
    declare -a _CLAW_PROFILE_IDS=()
    declare -A _CLAW_PROFILE_CLASS=()
    declare -A _CLAW_PROFILE_DESC=()
    _load_registry
    printf "%s\n" "${#_CLAW_PROFILE_IDS[@]}"
    printf "%s\n" "${_CLAW_PROFILE_CLASS[security]}"
    printf "%s\n" "${_CLAW_PROFILE_CLASS[blackwell]}"
    printf "%s\n" "${_CLAW_PROFILE_DESC[vault]}"
  ' _ "$REPO/scripts/utils/onboarding.sh"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | sed -n 1p)" = 18 ]
  [ "$(echo "$output" | sed -n 2p)" = NIGHTHACKER ]
  [ "$(echo "$output" | sed -n 3p)" = PHOSPHOR-GHOST ]
  [ "$(echo "$output" | sed -n 4p)" = "Obsidian vault root" ]
}

@test "onboarding.sh: the flow still runs end to end on piped input" {
  stub="$BATS_TEST_TMPDIR/stub"; mkdir -p "$stub"
  # gum, if installed, would try to own the tty for the install prompt.
  printf '#!/bin/sh\nexit 1\n' > "$stub/gum"; chmod +x "$stub/gum"
  export XDG_DATA_HOME="$BATS_TEST_TMPDIR/data"
  # Every read takes its default: 1 theme + 1 press-enter + 6 quiz answers +
  # 1 install answer (empty = skip, so no toolchain ever runs). A file, not a
  # herestring: $(printf ...) eats the trailing newlines.
  yes '' | head -20 > "$BATS_TEST_TMPDIR/keys"
  # TERM matters — `clear` fails without it and set -e takes the script down.
  run env PATH="$stub:$PATH" DOTFILES_DIR="$REPO" CLAW_NO_ANIM=1 TERM=xterm \
      bash "$REPO/scripts/utils/onboarding.sh" start < "$BATS_TEST_TMPDIR/keys"
  [ "$status" -eq 0 ]
  [[ "$output" == *"YOU ARE THE"* ]]
  [[ "$output" == *"SCOREBOARD"* ]]
  [ -s "$XDG_DATA_HOME/claw/onboarding.tsv" ]
}

@test "cheatsheet.sh: the profile count is derived, not a literal 18" {
  run grep -n '18 available' "$REPO/scripts/utils/cheatsheet.sh"
  [ "$status" -ne 0 ]
  run env DOTFILES_DIR="$REPO" NO_COLOR=1 bash "$REPO/scripts/utils/cheatsheet.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"18 available"* ]]
}
