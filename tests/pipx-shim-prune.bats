#!/usr/bin/env bats
# _prune_include_deps_shims — scripts/install/ai-toolchain.sh
#
# `pipx install --include-deps <pkg>` publishes an entry point for EVERY
# dependency, not just the package asked for. crewai alone put 27 commands in
# ~/.local/bin here, among them `httpx` — the Python HTTP client, which shadows
# ProjectDiscovery's scanner wherever ~/.local/bin precedes ~/go/bin and turns
# a security scan into a command that exits 0 and finds nothing (spec §20.1
# blocker 3).
#
# The pruner deletes files, so what it must NEVER delete is the real test
# surface: a genuine binary, a shim from another venv, or the command the
# package was installed for.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export PIPX_BIN_DIR="$BATS_TEST_TMPDIR/bin"
  export PIPX_HOME="$BATS_TEST_TMPDIR/pipx"
  VENV="$PIPX_HOME/venvs/crewai"
  OTHER="$PIPX_HOME/venvs/otherpkg"
  mkdir -p "$PIPX_BIN_DIR" "$VENV/bin" "$OTHER/bin"

  # The function under test, lifted from the installer so the test exercises
  # the shipped source rather than a copy.
  eval "$(sed -n '/^_prune_include_deps_shims()/,/^}/p' "$REPO/scripts/install/ai-toolchain.sh")"
  log_info() { :; }
  DRY_RUN=0
}

# make_shim <name> <venv-dir>
make_shim() {
  : > "$2/bin/$1"; chmod +x "$2/bin/$1"
  ln -s "$2/bin/$1" "$PIPX_BIN_DIR/$1"
}

@test "dependency shims from the package's own venv are removed" {
  make_shim crewai "$VENV"
  make_shim httpx  "$VENV"
  make_shim typer  "$VENV"

  _prune_include_deps_shims crewai

  [ ! -e "$PIPX_BIN_DIR/httpx" ]
  [ ! -e "$PIPX_BIN_DIR/typer" ]
}

@test "the command the package was installed for survives" {
  make_shim crewai "$VENV"
  make_shim httpx  "$VENV"

  _prune_include_deps_shims crewai

  [ -L "$PIPX_BIN_DIR/crewai" ]
  [ -x "$PIPX_BIN_DIR/crewai" ]
}

@test "a shim belonging to a DIFFERENT venv is never touched" {
  make_shim crewai "$VENV"
  make_shim httpx  "$OTHER"      # same name, different package

  _prune_include_deps_shims crewai

  [ -L "$PIPX_BIN_DIR/httpx" ]
}

@test "a real binary in the bin dir is never touched" {
  make_shim crewai "$VENV"
  printf '#!/bin/sh\n' > "$PIPX_BIN_DIR/httpx"    # a file, not a symlink
  chmod +x "$PIPX_BIN_DIR/httpx"

  _prune_include_deps_shims crewai

  [ -f "$PIPX_BIN_DIR/httpx" ]
  [ ! -L "$PIPX_BIN_DIR/httpx" ]
}

@test "a dangling symlink out of the venv is left alone" {
  make_shim crewai "$VENV"
  ln -s /nowhere/at/all "$PIPX_BIN_DIR/ghost"

  _prune_include_deps_shims crewai

  [ -L "$PIPX_BIN_DIR/ghost" ]
}

@test "dry run reports but deletes nothing" {
  make_shim crewai "$VENV"
  make_shim httpx  "$VENV"
  DRY_RUN=1

  _prune_include_deps_shims crewai

  [ -L "$PIPX_BIN_DIR/httpx" ]
}

@test "running twice is idempotent and still exits 0" {
  make_shim crewai "$VENV"
  make_shim httpx  "$VENV"

  _prune_include_deps_shims crewai
  run _prune_include_deps_shims crewai

  [ "$status" -eq 0 ]
  [ -L "$PIPX_BIN_DIR/crewai" ]
}

@test "a package with no venv is a no-op, not an error" {
  make_shim crewai "$VENV"

  run _prune_include_deps_shims not-installed-anywhere

  [ "$status" -eq 0 ]
  [ -L "$PIPX_BIN_DIR/crewai" ]
}
