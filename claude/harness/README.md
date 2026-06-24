# `claude/harness/` — custom agentic harness tools

This is the home for **the agentic tooling Henry builds himself** — skills,
plugins, slash commands, and subagents — as opposed to the security skills in
`claude/skills/` or the third-party/marketplace skills in `claude/agent-skills/`.

Everything here is tracked in the dotfiles repo, and `claw harness deploy`
symlinks it into `~/.claude/` so Claude Code picks it up. Nothing here is
clobbered by the managed-skill marketplace: deploys are item-level and
back up any real-file collisions first.

## Layout

```
claude/harness/
├── skills/      # custom Claude skills    → ~/.claude/skills/<name>
│   └── _template/SKILL.md   (copy this to start a new skill)
├── commands/    # custom slash commands   → ~/.claude/commands/<name>.md
├── agents/      # custom subagents        → ~/.claude/agents/<name>.md
└── plugins/     # custom plugin bundles   (referenced, not auto-linked)
```

| Kind     | Source dir                  | Deploy target            | What it is |
|----------|-----------------------------|--------------------------|------------|
| Skill    | `harness/skills/<name>/`    | `~/.claude/skills/<name>`| A `SKILL.md` (+ optional `references/`, `scripts/`) the model loads on demand |
| Command  | `harness/commands/<name>.md`| `~/.claude/commands/<name>.md` | A `/<name>` slash command |
| Agent    | `harness/agents/<name>.md`  | `~/.claude/agents/<name>.md`  | A subagent definition with `when to use` frontmatter |
| Plugin   | `harness/plugins/<name>/`   | (manual)                 | A plugin bundle — register via its own manifest |

Directory names starting with `_` (e.g. `_template`) are skipped by the
deployer — use them for scaffolding and notes.

## Workflow

```bash
claw harness new <kind> <name>   # scaffold skill|command|agent|plugin from _templates/
claw harness new <name>          # bare = skill (back-compat)
claw harness list [--all] [--fzf]# names + descriptions + deploy state
claw harness sync [--dry-run]    # git pull --ff-only + redeploy in one step
claw harness deploy [--dry-run]  # symlink it all into ~/.claude (idempotent)
claw harness path                # print the harness root
```

Templates live in `_templates/` (skipped by the deployer). The engine is `scripts/utils/harness.sh`; `cmd_harness` in `bin/claw` is a thin dispatch to it.

## Conventions

- **One skill, one job.** Keep `SKILL.md` focused; push detail into
  `references/` files the model can open when needed (progressive disclosure).
- **Frontmatter `description` is the trigger.** It's how the model decides
  whether the skill is relevant — write it as "Use when …".
- **Cross-platform.** Any shell a skill ships must follow the repo's
  `platform.zsh` shim conventions (no raw `pbcopy`/`open`/`ipconfig`).
- **No secrets.** Reference API keys by env var or 1Password CLI, never inline.
