# Branching & worktrees

How work reaches `master` in this repo. One page. The enforcing code is
`claw doctor repo` (`bin/claw`, `doctor_repo`) and `claw wt`
(`scripts/utils/worktree.sh`); this document is the contract they implement.

## The contract

1. **One long-lived branch.** `master` is the only permanent branch. No `dev`,
   no release branches, no tags. Trunk-based.

2. **The deployed tree only moves by fast-forward.** `~/.dotfiles` — this clone
   on every machine, symlinked into `$HOME` — stays checked out on `master`
   tracking `origin/master`. Nobody, human or agent, runs `git checkout <branch>`
   in it. `claw update` phase 1 (`scripts/utils/repo-sync.sh`) fast-forwards it;
   that is the only way it changes. Machine-local edits belong in the untracked
   files the shell already sources (`~/.zshrc.local`, `.env`,
   `~/.config/claw/`) — never in tracked files of the deployed tree.

3. **All work happens in a worktree.** Every change, agent sessions included,
   starts as a short-lived branch inside a worktree under
   `.claude/worktrees/<slug>` (`claw wt new <branch>`). The directory is
   git-ignored and is where Claude Code already puts its own session worktrees,
   so one convention covers both.

4. **Work lands by PR merge commit.** Push the branch, open a PR, CI runs
   (`.github/workflows/ci.yml`), merge with a merge commit — the history is 71
   PR merges deep and `git log --first-parent master` reads as the changelog.
   GitHub deletes the branch on merge. A one-file chore (a CHANGELOG line, a
   regenerated manifest) may skip the PR: from its worktree,
   `git push origin HEAD:master`, then `claw wt rm <branch>`.

5. **Guards, not discipline.**
   - `claw doctor repo` exits 1 when the deployed tree is off `master`, has no
     upstream, is ahead of it, or has tracked modifications — each a state in
     which `repo-sync.sh` silently skips the pull. `claw doctor` shows the same
     section inline, report-only.
   - GitHub ruleset `protect-master` blocks force-push and deletion of `master`.
     No required-checks rule: it would either block the chore path above or need
     an admin bypass that makes it decorative.
   - CI runs on every PR and every push to `master`; `delete_branch_on_merge`
     is on.

## Branch names

`<prefix>/<slug>` — lowercase, digits, `.`, `_`, `-`; no spaces, no second
slash. The rule is `_wt_valid_branch` in `scripts/utils/worktree.sh`, and
`claw wt new` refuses anything it rejects.

| Prefix    | Use                                                        |
|-----------|------------------------------------------------------------|
| `feat/`   | new capability or surface                                  |
| `fix/`    | bug, regression, hardening                                 |
| `docs/`   | documentation only                                         |
| `chore/`  | manifests, dependencies, CI, housekeeping                  |
| `claude/` | Claude Code session branches (auto-named `claude/<topic>-<id>`) |

## Daily flow

```bash
claw wt new fix/update-pty            # branch off origin/master → .claude/worktrees/fix-update-pty
cd "$(claw wt path fix/update-pty)"
# … work; commit named files at sensible boundaries …
git push -u origin fix/update-pty     # then: open a PR — or, one-file chore: git push origin HEAD:master
claw wt rm fix/update-pty             # after merge: drops the worktree and the local branch
claw update --repo                    # the deployed tree fast-forwards to the merged master
claw wt ls                            # what is still open, ahead/behind master, dirty or not
```

`claw wt new` fetches `origin` first so the branch starts at the current
`origin/master`; offline it falls back to local `master` and says so.

## Machines

Every machine's `~/.dotfiles` tracks `origin/master`. `CLAW_REPO_BRANCH`
(default `master`) is the one knob if a machine must ever track something
else, and `claw doctor repo` honours it. Nothing sets it today.

If a staged rollout is ever wanted — the MBP dogfoods first, the homelab
follows — the change is small and recorded here so the option stays cheap:
create `dev`, set `CLAW_REPO_BRANCH=dev` on the MBP, promote `dev → master` by
PR. Not built.

## Cleanup runbook

Quarterly, or whenever branches feel stale:

```bash
git fetch --all --prune
git branch -r --merged origin/master                                # remote branches with nothing left to merge
git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads   # local: [gone] = upstream already deleted
git worktree prune && claw wt ls
```

Orphaned commits (deleted branches, dropped stashes) stay recoverable for
roughly 90 days via `git fsck --unreachable --no-reflogs`. Before treating
anything as lost, check `git cherry master <sha>^ <sha>`: a leading `-` means
`master` already contains that patch under another SHA. The 2026-09-04 audit
classified 150 unreachable objects this way and found nothing dormant.

## Decisions (2026-09)

- **Trunk-based, no `dev`.** This repo is deployed, not released: every machine
  pulls whatever `master` is, and CI already gates every PR. A `dev` branch
  only earns its keep as a fleet gate (see Machines), which nobody needs today.
- **Merge commits, not squash.** `--first-parent` stays readable and the
  per-commit bats/receipt trail on each branch survives the merge.
- **`master`, not `main`.** A rename touches every clone, the bootstrap curl
  URL, the CI trigger and `init.defaultbranch`. Deferred; blocks nothing.
- **Never `git checkout` in `~/.dotfiles`.** Aug 31 → Sep 4 2026: the deployed
  tree sat on a no-upstream branch and `claw update` skipped four days of pulls
  without an error. `claw doctor repo` exists because of that.
