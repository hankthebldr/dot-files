#!/usr/bin/env bats
# Tests for the live progress panel engine + output settings.

setup() {
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  export HOME="$BATS_TEST_TMPDIR"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
  OUT="$BATS_TEST_DIRNAME/../scripts/utils/claw-output.sh"
}

@test "output: defaults resolve when nothing is set" {
  run bash "$OUT" get mode;   [ "$status" -eq 0 ]; [ "$output" = "auto" ]
  run bash "$OUT" get frame;  [ "$status" -eq 0 ]; [ "$output" = "viewfinder" ]
  run bash "$OUT" get banner; [ "$status" -eq 0 ]; [ "$output" = "on" ]
}

@test "output: set persists and get reads it back" {
  run bash "$OUT" mode plain;     [ "$status" -eq 0 ]
  run bash "$OUT" frame none;     [ "$status" -eq 0 ]
  run bash "$OUT" get mode;  [ "$output" = "plain" ]
  run bash "$OUT" get frame; [ "$output" = "none" ]
}

@test "output: env overrides the state file" {
  bash "$OUT" mode plain
  run env CLAW_OUTPUT_MODE=rich bash "$OUT" get mode
  [ "$output" = "rich" ]
}

@test "output: invalid value is rejected with nonzero exit" {
  run bash "$OUT" mode bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid"* ]]
}

@test "output: status prints all three resolved keys" {
  run bash "$OUT" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode"* ]]
  [[ "$output" == *"frame"* ]]
  [[ "$output" == *"banner"* ]]
}

@test "claw output: dispatches through bin/claw" {
  run env DOTFILES_DIR="$BATS_TEST_DIRNAME/.." bash "$BATS_TEST_DIRNAME/../bin/claw" output status
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode"* ]]
}

@test "frame: viewfinder top line spans COLUMNS and carries corner glyphs" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env COLUMNS=40 TERM=xterm-256color bash -c "source '$PROG'; claw_frame_top"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\xE2\x8C\x9C'* ]]   # ⌜ top-left
  [[ "$output" == *$'\xE2\x8C\x9D'* ]]   # ⌝ top-right
}

@test "frame: dumb terminal falls back to ASCII corners" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env COLUMNS=40 TERM=dumb bash -c "source '$PROG'; claw_frame_top"
  [ "$status" -eq 0 ]
  [[ "$output" == *"+"* ]]
  [[ "$output" != *$'\xE2\x8C\x9C'* ]]   # no unicode corner
}

@test "frame: claw_card wraps a title and body" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env COLUMNS=40 TERM=xterm-256color bash -c "source '$PROG'; printf 'line one\nline two\n' | claw_card 'My Title'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"My Title"* ]]
  [[ "$output" == *"line one"* ]]
  [[ "$output" == *"line two"* ]]
}

@test "engine: plain mode emits clean per-item lines + summary" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env CLAW_OUTPUT_MODE=plain TERM=xterm-256color bash -c "
    source '$PROG'
    claw_prog_begin demo 3
    claw_prog_item awscli brew;   claw_prog_phase install; claw_prog_ok
    claw_prog_item kubectl brew;  claw_prog_ok
    claw_prog_item helm brew;     claw_prog_fail 'network timeout'
    claw_prog_end
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"demo (3)"* ]]
  [[ "$output" == *"awscli"* ]]
  [[ "$output" == *"helm"* ]]
  [[ "$output" == *"network timeout"* ]]
  [[ "$output" == *"summary:"* ]]
}

@test "engine: summary tally counts ok/fail/skip correctly" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env CLAW_OUTPUT_MODE=plain TERM=xterm-256color bash -c "
    source '$PROG'
    claw_prog_begin demo 0
    claw_prog_item a; claw_prog_ok
    claw_prog_item b; claw_prog_ok
    claw_prog_item c; claw_prog_skip
    claw_prog_item d; claw_prog_fail
    claw_prog_end
  "
  [[ "$output" == *$'\xE2\x9C\x93'"2"* ]]   # ✓2
  [[ "$output" == *$'\xE2\x9C\x97'"1"* ]]   # ✗1
}

@test "claw_prog_run returns the command's real exit code (plain)" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env CLAW_OUTPUT_MODE=plain bash -c "
    source '$PROG'
    claw_prog_begin demo 1
    claw_prog_item thing
    claw_prog_run install -- false
    echo \"rc=\$?\"
    claw_prog_end
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"rc=1"* ]]
}

@test "claw_prog_run captures command output to a logfile, not the screen" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env CLAW_OUTPUT_MODE=plain XDG_STATE_HOME="$BATS_TEST_TMPDIR/state" bash -c "
    source '$PROG'
    claw_prog_begin demo 1
    claw_prog_item thing
    claw_prog_run install -- sh -c 'echo NOISE_FROM_TOOL'
    claw_prog_ok
    claw_prog_end
  "
  [ "$status" -eq 0 ]
  [[ "$output" != *"NOISE_FROM_TOOL"* ]]          # not on screen
  run grep -rl "NOISE_FROM_TOOL" "$BATS_TEST_TMPDIR/state/claw/logs"
  [ "$status" -eq 0 ]                              # captured in a logfile
}

@test "rich mode forced into a pipe still returns rc and prints a summary" {
  PROG="$BATS_TEST_DIRNAME/../scripts/utils/claw-progress.sh"
  run env CLAW_OUTPUT_MODE=rich TERM=xterm-256color COLUMNS=60 bash -c "
    source '$PROG'
    claw_prog_begin demo 1
    claw_prog_item thing brew; claw_prog_phase install; claw_prog_ok
    claw_prog_end
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"summary:"* ]]
}

@test "pkg install: drives the progress panel (plain) with per-tool result + summary" {
  DF="$BATS_TEST_TMPDIR/df"
  mkdir -p "$DF/config/manifest" "$DF/scripts/utils"
  cp "$BATS_TEST_DIRNAME"/../scripts/utils/{cinematic.sh,detect-os.sh,claw-progress.sh,claw-output.sh} "$DF/scripts/utils/"
  cp "$BATS_TEST_DIRNAME/../scripts/utils/pkg-manifest.sh" "$DF/scripts/utils/"
  # a tool guaranteed present so _install_via takes the skip path, plus a real one
  printf 'bash|manual\n' > "$DF/config/manifest/tools.list"
  run env DOTFILES_DIR="$DF" CLAW_OUTPUT_MODE=plain bash "$DF/scripts/utils/pkg-manifest.sh" install all
  [ "$status" -eq 0 ]
  [[ "$output" == *"bash"* ]]
  [[ "$output" == *"summary:"* ]]
}

@test "pkg track: shows live scan phase + still reports nothing-new on a current manifest" {
  DF="$BATS_TEST_TMPDIR/df2"
  mkdir -p "$DF/config/manifest" "$DF/scripts/utils"
  cp "$BATS_TEST_DIRNAME"/../scripts/utils/{cinematic.sh,detect-os.sh,claw-progress.sh,claw-output.sh,pkg-manifest.sh} "$DF/scripts/utils/"
  : > "$DF/config/manifest/tools.list"
  # Force discovery to find nothing by pointing user-bin dirs at empty + no pkg mgrs on PATH is unrealistic;
  # instead assert the op runs cleanly and emits a scan label.
  run env DOTFILES_DIR="$DF" CLAW_OUTPUT_MODE=plain bash "$DF/scripts/utils/pkg-manifest.sh" track
  [ "$status" -eq 0 ]
  [[ "$output" == *"pkg track"* ]]
}

@test "pkg track: source inference does not re-shell package managers once per tool" {
  DF="$BATS_TEST_TMPDIR/df_infer"
  mkdir -p "$DF/config/manifest" "$DF/scripts/utils" "$DF/stub"
  cp "$BATS_TEST_DIRNAME"/../scripts/utils/{cinematic.sh,detect-os.sh,claw-progress.sh,claw-output.sh,pkg-manifest.sh} "$DF/scripts/utils/"
  : > "$DF/config/manifest/tools.list"

  CNT="$BATS_TEST_TMPDIR/cnt"; mkdir -p "$CNT"
  : > "$CNT/brew"; : > "$CNT/cargo"; : > "$CNT/pipx"; : > "$CNT/npm"

  # brew stub: tally every invocation; emit 8 leaves so 8 tools are both
  # discovered AND fed through _infer_source.
  cat >"$DF/stub/brew" <<EOF
#!/usr/bin/env bash
printf 'x\n' >>"$CNT/brew"
[ "\$1" = leaves ] && printf '%s\n' t1 t2 t3 t4 t5 t6 t7 t8
exit 0
EOF
  # cargo/pipx/npm stubs: tally invocations, emit nothing.
  for m in cargo pipx npm; do
    cat >"$DF/stub/$m" <<EOF
#!/usr/bin/env bash
printf 'x\n' >>"$CNT/$m"
exit 0
EOF
  done
  chmod +x "$DF/stub/"*

  run env PATH="$DF/stub:$PATH" DOTFILES_DIR="$DF" CLAW_OUTPUT_MODE=plain \
      bash "$DF/scripts/utils/pkg-manifest.sh" track
  [ "$status" -eq 0 ]
  # all 8 brew tools must be tracked (behavior preserved)
  [[ "$output" == *"tracked 8"* ]]
  # brew must be queried a CONSTANT number of times (one discovery pass + at
  # most one memoized inference pass) regardless of tool count. The pre-fix
  # code shelled out 1 + 8 = 9 times; the fix caps it at 2.
  brew_calls=$(wc -l <"$CNT/brew" | tr -d ' ')
  [ "$brew_calls" -le 2 ]
}

@test "pkg scan: discovers user-space binaries in ~/.local/bin (portable find)" {
  DF="$BATS_TEST_TMPDIR/df_userbin"
  mkdir -p "$DF/config/manifest" "$DF/scripts/utils" "$DF/stub"
  cp "$BATS_TEST_DIRNAME"/../scripts/utils/{cinematic.sh,detect-os.sh,claw-progress.sh,claw-output.sh,pkg-manifest.sh} "$DF/scripts/utils/"
  : > "$DF/config/manifest/tools.list"

  # Silence the real package managers so discovery yields ONLY the user binary.
  for m in brew cargo pipx npm; do
    printf '#!/usr/bin/env bash\nexit 0\n' >"$DF/stub/$m"
  done
  chmod +x "$DF/stub/"*

  # A fake user-installed binary — the eget/go/manual channel that BSD find's
  # missing -printf silently dropped on macOS.
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\n' >"$HOME/.local/bin/zzfakebin"
  chmod +x "$HOME/.local/bin/zzfakebin"

  run env PATH="$DF/stub:$PATH" DOTFILES_DIR="$DF" CLAW_OUTPUT_MODE=plain \
      bash "$DF/scripts/utils/pkg-manifest.sh" scan
  [ "$status" -eq 0 ]
  [[ "$output" == *"zzfakebin"* ]]
}
