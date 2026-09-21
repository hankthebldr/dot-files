#!/usr/bin/env bash
# claw registry — the ONE source of truth for "what can claw do".
#
# audit 2026-09-20 F-15/F-17: the 18-profile list was copied six times and the
# menus carried five disagreeing taxonomies. Everything downstream — the fzf
# palette, `claw help`, zsh completion, `claw tui-stats` classification — is
# generated from here instead.
#
# Two sources, one row stream:
#   1. shell/profiles/<p>/meta.zsh   (one awk pass; grammar lint-enforced by
#      scripts/utils/profiles-lint.sh — one PROFILE_X="value" per line, at most
#      a trailing comment, values RAW and UNEXPANDED)
#   2. config/claw/actions.tsv       (8 columns, '#' comments, '-' = empty)
#
# Subcommands: rows | palette | help | completion | ids | run | show | check
#
# Env: DOTFILES_DIR · XDG_STATE_HOME (frecency) · CLAW_NOW (test clock; BSD awk
# has no systime()) · CLAW_RGB_* (help colours) · NO_COLOR.
# Portability: bash + POSIX awk only (no systime/gensub) — macOS and mawk CI.
# Never on the login path.
set -uo pipefail

DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
PROFILES_DIR="$DOTFILES/shell/profiles"
ACTIONS_TSV="$DOTFILES/config/claw/actions.tsv"
CLAW_BIN="$DOTFILES/bin/claw"
FRECENCY="${XDG_STATE_HOME:-$HOME/.local/state}/claw/frecency.tsv"
TAB=$'\t'

# Dispatch arms the design spec (2026-09-20-tui-redesign-design.md, Components)
# commits bin/claw to growing in T1-09. Their rows exist here first so the
# palette and completion can be generated ahead of the arms; drop this list
# once `claw registry|pin|ack|dash` are real case arms.
PENDING_ARMS="registry pin ack dash"

usage() {
    cat >&2 <<'USAGE'
usage: registry.sh <command>
  rows                                kind id aliases group glyph label desc run flags
  palette                             id kind "<glyph> <label>" desc group (frecency-sorted)
  help                                grouped, themed reference text
  completion                          id:desc lines (ids + aliases + profiles)
  ids [--with-aliases] [profiles|actions]
  run <id>                            the run snippet ('profile:'/'action:' prefix forces a kind)
  show <id>                           a pretty single row
  check                               silent on success; one line per violation, exit 1
USAGE
}

# ---------------------------------------------------------------- sources ---

_meta_files() {
    local f
    for f in "$PROFILES_DIR"/*/meta.zsh; do
        [ -f "$f" ] && printf '%s\n' "$f"
    done
}

# _meta_awk <program> — run ONE awk process over every meta.zsh. The profile
# half of the registry is a single pass by contract (the grammar is
# lint-enforced, so the pass is total and lossless); dirof() is prepended so
# callers can key on the profile directory name.
_meta_awk() {
    local -a files=()
    local f
    while IFS= read -r f; do files+=("$f"); done < <(_meta_files)
    [ "${#files[@]}" -gt 0 ] || return 0
    awk -v OFS="$TAB" '
      function dirof(p,   n, a) { n = split(p, a, "/"); return a[n-1] }
    '"$1" "${files[@]}"
}

# profile rows, sorted by tier then name. The sort keys are emitted as two
# leading columns and cut back off, so the ordering never depends on locale
# collation of the glyph column.
_profile_rows() {
    _meta_awk '
      function grp(t) {
          if (t == "1") return "core"
          if (t == "2") return "domain"
          if (t == "3") return "agent"
          if (t == "4") return "knowledge"
          if (t == "5") return "customer"
          if (t == "6") return "hardware"
          return "other"
      }
      function flush(   k, name, help) {
          if (cur == "") return
          name = (f["NAME"] != "") ? f["NAME"] : cur
          help = (f["HELP_CMD"] != "") ? f["HELP_CMD"] : name "-help"
          print f["TIER"], name, "profile", name, "-", grp(f["TIER"]), f["GLYPH"], name, f["DESC"], \
                "claw load " name, \
                "theme=" f["THEME_DEFAULT"] ";start=" f["START_DIR"] ";class=" f["CLASS"] ";help=" help
          for (k in f) delete f[k]
      }
      FNR == 1 { flush(); cur = dirof(FILENAME) }
      /^PROFILE_[A-Z_]+="/ {
          eq  = index($0, "=")
          key = substr($0, 9, eq - 9)
          rest = substr($0, eq + 2)
          q = index(rest, "\"")
          f[key] = (q > 0) ? substr(rest, 1, q - 1) : ""
      }
      END { flush() }
    ' | sort -t"$TAB" -k1,1n -k2,2 | cut -f3-
}

# action rows, in file order (the palette's tie-break is deliberately the
# author's order, not an alphabetical one).
_action_rows() {
    [ -f "$ACTIONS_TSV" ] || return 0
    awk -F"$TAB" -v OFS="$TAB" '
      /^[ \t]*#/ { next }
      NF < 2     { next }
      { print "action", $1, $2, $3, $4, $5, $6, $7, $8 }
    ' "$ACTIONS_TSV"
}

cmd_rows() { _profile_rows; _action_rows; }

# ---------------------------------------------------------------- palette ---

cmd_palette() {
    local now="${CLAW_NOW:-$(date +%s)}"
    cmd_rows | awk -F"$TAB" -v OFS="$TAB" -v now="$now" -v frec="$FRECENCY" '
      BEGIN {
          # score = count x w(age): 4 <1h · 2 <1d · 1 <7d · 0.5 <30d · 0.25 older.
          # Scaled by 100 so the sort key stays an integer on every awk.
          while ((getline line < frec) > 0) {
              n = split(line, a, "\t")
              if (n < 3 || a[1] == "") continue
              age = now - a[3]
              w = 25
              if (age < 2592000) w = 50
              if (age < 604800)  w = 100
              if (age < 86400)   w = 200
              if (age < 3600)    w = 400
              score[a[1]] = a[2] * w
          }
          close(frec)
      }
      $9 ~ /(^|,)hidden(,|$)/ { next }
      {
          ord++
          s = ($2 in score) ? score[$2] : 0
          glyph = ($5 == "-" || $5 == "") ? "" : $5 " "
          print s, ord, $2, $1, glyph $6, $7, $4
      }
    ' | sort -t"$TAB" -k1,1nr -k2,2n | cut -f3-
}

# ------------------------------------------------------------------- help ---

cmd_help() {
    local r="" c_hd="" c_id="" c_ds="" c_mt=""
    if [ -z "${NO_COLOR:-}" ]; then
        r=$'\033[0m'
        c_hd=$'\033[1;38;2;'"${CLAW_RGB_PURPLE:-188;140;255}"'m'
        c_id=$'\033[38;2;'"${CLAW_RGB_BLUE:-88;166;255}"'m'
        c_ds=$'\033[38;2;'"${CLAW_RGB_MUTED:-139;148;158}"'m'
        c_mt=$'\033[38;2;'"${CLAW_RGB_GREEN:-63;185;80}"'m'
    fi
    cmd_rows | awk -F"$TAB" \
        -v r="$r" -v c_hd="$c_hd" -v c_id="$c_id" -v c_ds="$c_ds" -v c_mt="$c_mt" '
      BEGIN {
          split("core domain agent knowledge customer hardware system tools", ord, " ")
          for (i in ord) rank[ord[i]] = i
      }
      {
          g = $4
          if (!(g in rank)) { rank[g] = 99; }
          if (!(g in seen)) { seen[g] = 1; order[++ng] = g; rk[ng] = rank[g] }
          if ($9 ~ /(^|,)hidden(,|$)/) { more = more (more == "" ? "" : " · ") $2; next }
          glyph = ($5 == "-" || $5 == "") ? " " : $5
          body[g] = body[g] sprintf("   %s %s%-14s%s %s%s%s\n", glyph, c_id, $2, r, c_ds, $7, r)
      }
      END {
          for (i = 1; i <= ng; i++)
              for (j = i + 1; j <= ng; j++)
                  if (rk[j] < rk[i]) { t = rk[i]; rk[i] = rk[j]; rk[j] = t
                                       s = order[i]; order[i] = order[j]; order[j] = s }
          for (i = 1; i <= ng; i++) {
              g = order[i]
              if (body[g] == "") continue
              printf "\n %s%s%s\n", c_hd, g, r
              printf "%s", body[g]
          }
          if (more != "") printf "\n %smore%s\n   %s%s%s\n", c_hd, r, c_mt, more, r
      }
    '
}

cmd_completion() {
    cmd_rows | awk -F"$TAB" '
      {
          print $2 ":" $7
          if ($3 != "-" && $3 != "") { n = split($3, a, "|"); for (i = 1; i <= n; i++) print a[i] ":" $7 }
      }
    '
}

cmd_ids() {
    local with_aliases=0 kind="" a
    for a in "$@"; do
        case "$a" in
            --with-aliases) with_aliases=1 ;;
            profiles|profile) kind="profile" ;;
            actions|action)   kind="action" ;;
            *) printf 'registry: unknown ids argument: %s\n' "$a" >&2; return 2 ;;
        esac
    done
    cmd_rows | awk -F"$TAB" -v k="$kind" -v wa="$with_aliases" '
      (k == "" || $1 == k) {
          print $2
          if (wa && $3 != "-" && $3 != "") { n = split($3, a, "|"); for (i = 1; i <= n; i++) print a[i] }
      }
    '
}

# A bare id resolves in `rows` order — profiles first, then actions in file
# order. `profile:<id>` / `action:<id>` force a kind (the two namespaces
# legitimately overlap: `ai` and `homelab` are both a profile and a verb).
_find_row() {
    local q="$1" kind=""
    case "$q" in
        profile:*) kind="profile"; q="${q#profile:}" ;;
        action:*)  kind="action";  q="${q#action:}"  ;;
    esac
    cmd_rows | awk -F"$TAB" -v q="$q" -v k="$kind" '(k == "" || $1 == k) && $2 == q { print; exit }'
}

cmd_run() {
    local row
    row="$(_find_row "$1")"
    [ -n "$row" ] || { printf 'registry: no such id: %s\n' "$1" >&2; return 1; }
    printf '%s\n' "$row" | cut -f8
}

cmd_show() {
    local row
    row="$(_find_row "$1")"
    [ -n "$row" ] || { printf 'registry: no such id: %s\n' "$1" >&2; return 1; }
    printf '%s\n' "$row" | awk -F"$TAB" '{
        glyph = ($5 == "-" || $5 == "") ? " " : $5
        printf "  %s %s\n", glyph, $6
        printf "  %-8s %s\n", "kind",    $1
        printf "  %-8s %s\n", "id",      $2
        printf "  %-8s %s\n", "group",   $4
        printf "  %-8s %s\n", "desc",    $7
        printf "  %-8s %s\n", "run",     $8
        printf "  %-8s %s\n", "aliases", $3
        printf "  %-8s %s\n", "flags",   $9
    }'
}

# ------------------------------------------------------------------ check ---

_dispatch_arms() {
    [ -f "$CLAW_BIN" ] || return 0
    awk '/^case "\$\{1:-menu\}" in/          { f = 1; next }
         f && /^esac/                        { exit }
         f && /^    [^ #].*\)/               { sub(/\).*/, ""); gsub(/^ +/, ""); print }' "$CLAW_BIN" \
    | tr '|' '\n' | sed 's/^"//; s/"$//' | grep -vx -e '' -e '\*' -e '-h' -e '--help'
}

cmd_check() {
    local bad=0 arms="" line

    if [ -f "$CLAW_BIN" ]; then
        arms=" $(_dispatch_arms | tr '\n' ' ')$PENDING_ARMS "
    fi

    # --- actions.tsv: columns, flags, name collisions, claw-subcommand runs ---
    if [ -f "$ACTIONS_TSV" ]; then
        while IFS= read -r line; do
            printf '%s\n' "$line" >&2
            bad=1
        done < <(awk -F"$TAB" -v arms="$arms" -v have_bin="${arms:+1}" '
          /^[ \t]*#/ { next }
          NF < 1 || ($0 ~ /^[ \t]*$/) { next }
          {
              if (NF != 8) { printf "actions.tsv:%d: %d columns, want 8\n", FNR, NF; next }
              if ($1 == "" || $1 == "-") { printf "actions.tsv:%d: empty id\n", FNR; next }
              if ($1 in name) printf "actions.tsv:%d: duplicate action id %c%s%c\n", FNR, 39, $1, 39
              name[$1] = FNR
              if ($3 == "" || $3 == "-") printf "actions.tsv:%d: empty group\n", FNR
              if ($5 == "" || $5 == "-") printf "actions.tsv:%d: empty label\n", FNR
              if ($6 == "" || $6 == "-") printf "actions.tsv:%d: empty desc\n", FNR
              if ($7 == "" || $7 == "-") printf "actions.tsv:%d: empty run\n", FNR
              if ($2 != "-" && $2 != "") {
                  n = split($2, a, "|")
                  for (i = 1; i <= n; i++) {
                      if (a[i] in name) printf "actions.tsv:%d: duplicate action name %c%s%c\n", FNR, 39, a[i], 39
                      name[a[i]] = FNR
                  }
              }
              if ($8 == "" ) printf "actions.tsv:%d: empty flags (use -)\n", FNR
              else if ($8 != "-") {
                  n = split($8, fl, ",")
                  for (i = 1; i <= n; i++)
                      if (fl[i] != "!" && fl[i] != "x" && fl[i] != "hidden" && fl[i] !~ /^l:[a-z0-9_-]+$/)
                          printf "actions.tsv:%d: unknown flag %c%s%c\n", FNR, 39, fl[i], 39
              }
              if (have_bin && $7 ~ /^command claw /) {
                  split($7, w, " ")
                  if (index(arms, " " w[3] " ") == 0)
                      printf "actions.tsv:%d: %crun%c calls claw %s, which is not a bin/claw dispatch arm\n", \
                             FNR, 39, 39, w[3]
              }
          }
        ' "$ACTIONS_TSV")
    fi

    # --- profiles: required identity fields + duplicate ids -------------------
    while IFS= read -r line; do
        printf '%s\n' "$line" >&2
        bad=1
    done < <(_meta_awk '
      function report(p,   k) {
          if (!("GLYPH" in seen))      printf "%s/meta.zsh: no PROFILE_GLYPH\n", p
          else if (val["GLYPH"] == "") printf "%s/meta.zsh: empty PROFILE_GLYPH\n", p
          if (!("DESC" in seen))       printf "%s/meta.zsh: no PROFILE_DESC\n", p
          else if (val["DESC"] == "")  printf "%s/meta.zsh: empty PROFILE_DESC\n", p
          for (k in seen) delete seen[k]
          for (k in val)  delete val[k]
      }
      FNR == 1 { if (cur != "") report(cur); cur = dirof(FILENAME) }
      /^PROFILE_[A-Z_]+="/ {
          eq = index($0, "="); key = substr($0, 9, eq - 9)
          rest = substr($0, eq + 2); q = index(rest, "\"")
          seen[key] = 1; val[key] = (q > 0) ? substr(rest, 1, q - 1) : ""
      }
      END { if (cur != "") report(cur) }
    ')

    while IFS= read -r line; do
        printf '%s\n' "$line" >&2
        bad=1
    done < <(cmd_rows | awk -F"$TAB" '
      $1 == "profile" {
          if ($2 in pid) printf "duplicate profile id %c%s%c\n", 39, $2, 39
          pid[$2] = 1
      }
      $5 != "-" && $5 != "" {
          if ($5 in gl) printf "duplicate glyph %c%s%c (%s and %s)\n", 39, $5, 39, gl[$5], $2
          else gl[$5] = $2
      }
    ')

    return "$bad"
}

# ----------------------------------------------------------------- dispatch --

case "${1:-}" in
    rows)       cmd_rows ;;
    palette)    cmd_palette ;;
    help)       cmd_help ;;
    completion) cmd_completion ;;
    ids)        shift; cmd_ids "$@" ;;
    run)        shift; [ $# -ge 1 ] || { usage; exit 2; }; cmd_run "$1" ;;
    show)       shift; [ $# -ge 1 ] || { usage; exit 2; }; cmd_show "$1" ;;
    check)      cmd_check ;;
    -h|--help|help-usage) usage; exit 0 ;;
    *)          usage; exit 2 ;;
esac
