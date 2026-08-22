#!/usr/bin/env bats
# profile-start-dirs.bats — the declarative profile start-dir contract
# (PROFILE_START_DIR in meta.zsh → _claw_resolve_start_dir → _claw_profile_cd,
# all in shell/profile-helpers.zsh). Everything runs against a FAKED home +
# vault tree so no host state is touched.

setup() {
  command -v zsh &>/dev/null || skip "zsh not installed"
  REPO="$BATS_TEST_DIRNAME/.."
  FAKE="$BATS_TEST_TMPDIR/home"
  # A stand-in for ~/hr-vault-main-pa with two of the mapped folders carved out.
  mkdir -p "$FAKE/hr-vault-main-pa/CORTEX" "$FAKE/hr-vault-main-pa/Secops" \
           "$FAKE/hr-vault-main-pa/_brainstorm" "$FAKE/devops" "$FAKE/pentest"
}

# XDG_CONFIG_HOME is pinned into the fake tree because the resolver reads the
# per-machine map from ${XDG_CONFIG_HOME:-$HOME/.config}/claw/start-dirs.conf —
# overriding HOME alone leaves the override lookup pointing at the real machine
# (CI runners export XDG_CONFIG_HOME; most laptops don't).
zrun() {
  HOME="$FAKE" XDG_CONFIG_HOME="$FAKE/.config" OBSIDIAN_ROOT="$FAKE" DOTFILES_DIR="$REPO" \
    run zsh -c "source '$REPO/shell/profile-helpers.zsh'; $1"
}

# Same, but interactive (the applier is interactive-only by design).
zrun_i() {
  HOME="$FAKE" XDG_CONFIG_HOME="$FAKE/.config" OBSIDIAN_ROOT="$FAKE" DOTFILES_DIR="$REPO" \
    run zsh -ic "source '$REPO/shell/profile-helpers.zsh'; $1"
}

@test "vault profile starts in the vault ROOT, not a scoped folder" {
  zrun '_claw_profile_start_dir vault'
  [ "$status" -eq 0 ]
  [ "$output" = "$FAKE/hr-vault-main-pa" ]
}

@test "@vault-folder routes through the obsidian profile→folder map" {
  zrun '_claw_resolve_start_dir "@vault-folder" security'
  [ "$output" = "$FAKE/hr-vault-main-pa/Secops" ]
}

@test "@vault-folder falls back to the vault root when the folder is absent" {
  # pmo maps to "WWTS - Projects", which this fake vault does not have.
  zrun '_claw_resolve_start_dir "@vault-folder" pmo'
  [ "$output" = "$FAKE/hr-vault-main-pa" ]
}

@test "@vault:<Folder> targets an explicit folder" {
  zrun '_claw_resolve_start_dir "@vault:_brainstorm" brainstorm'
  [ "$output" = "$FAKE/hr-vault-main-pa/_brainstorm" ]
}

@test "candidate lists take the first entry that EXISTS" {
  zrun "_claw_resolve_start_dir '\$HOME/nope|\$HOME/devops' devops"
  [ "$output" = "$FAKE/devops" ]
}

@test "candidate lists fall back to the first entry when none exists" {
  # Reported (not silently dropped) so the applier can say what is missing.
  zrun "_claw_resolve_start_dir '\$HOME/nope|\$HOME/also-nope' devops"
  [ "$output" = "$FAKE/nope" ]
}

@test "an empty spec resolves to nothing (profile stays put)" {
  zrun '_claw_resolve_start_dir "" default'
  [ -z "$output" ]
}

@test "every shipped profile declares a resolvable spec" {
  for meta in "$REPO"/shell/profiles/*/meta.zsh; do
    name="$(basename "$(dirname "$meta")")"
    zrun "source '$meta'; _claw_profile_start_dir '$name'"
    [ "$status" -eq 0 ]
    if [ "$name" = "default" ]; then
      [ -z "$output" ]            # the daily driver never relocates you
    else
      [[ "$output" == /* ]]       # everything else resolves to an absolute path
    fi
  done
}

@test "applier lands the shell in the start dir and says so" {
  zrun_i "source '$REPO/shell/profiles/vault/meta.zsh'; _claw_profile_cd vault; print -r -- \$PWD"
  [[ "${lines[-1]}" = "$FAKE/hr-vault-main-pa" ]]
  [[ "$output" == *"cd - to go back"* ]]
}

@test "applier warns and stays put when the start dir is missing" {
  zrun_i "PROFILE_NAME=ghost PROFILE_START_DIR=\$HOME/nowhere; cd \$HOME; _claw_profile_cd ghost; print -r -- \$PWD"
  [[ "$output" == *"start dir missing"* ]]
  [[ "${lines[-1]}" = "$FAKE" ]]
}

@test "CLAW_PROFILE_CD=0 disables relocation entirely" {
  zrun_i "cd \$HOME; CLAW_PROFILE_CD=0 _claw_profile_cd vault; print -r -- \$PWD"
  [[ "${lines[-1]}" = "$FAKE" ]]
}

@test "CLAW_PROFILE_CD=home relocates only from \$HOME" {
  zrun_i "cd \$HOME/devops; CLAW_PROFILE_CD=home _claw_profile_cd vault; print -r -- \$PWD"
  [[ "${lines[-1]}" = "$FAKE/devops" ]]
  zrun_i "cd \$HOME; CLAW_PROFILE_CD=home _claw_profile_cd vault; print -r -- \$PWD"
  [[ "${lines[-1]}" = "$FAKE/hr-vault-main-pa" ]]
}

@test "a non-interactive shell is never relocated" {
  zrun "cd \$HOME; _claw_profile_cd vault; print -r -- \$PWD"
  [ "$output" = "$FAKE" ]
}

@test "CLAW_START_DIR overrides the profile's declaration for this shell" {
  zrun "CLAW_START_DIR=\$HOME/devops _claw_profile_start_dir vault"
  [ "$output" = "$FAKE/devops" ]
}

@test "the per-machine map overrides meta.zsh, and \$CLAW_START_DIR beats both" {
  mkdir -p "$FAKE/.config/claw" "$FAKE/custom-vault"
  printf '# machine-local\nvault = $HOME/custom-vault\n' > "$FAKE/.config/claw/start-dirs.conf"
  zrun '_claw_profile_start_dir vault'
  [ "$output" = "$FAKE/custom-vault" ]
  zrun "CLAW_START_DIR=\$HOME/devops _claw_profile_start_dir vault"
  [ "$output" = "$FAKE/devops" ]
  # a profile with no row in the map still falls through to its meta.zsh
  zrun '_claw_profile_start_dir security'
  [ "$output" = "$FAKE/pentest" ]
}

@test "claw profiles paths renders one row per profile" {
  HOME="$FAKE" XDG_CONFIG_HOME="$FAKE/.config" OBSIDIAN_ROOT="$FAKE" DOTFILES_DIR="$REPO" \
    run bash "$REPO/bin/claw" profiles paths
  [ "$status" -eq 0 ]
  [[ "$output" == *"vault"* ]]
  [[ "$output" == *"stays put"* ]]     # default's empty spec
  for meta in "$REPO"/shell/profiles/*/meta.zsh; do
    [[ "$output" == *"$(basename "$(dirname "$meta")")"* ]]
  done
}
