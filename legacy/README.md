# legacy/

Superseded or uncalled scripts, archived during the architecture consolidation
(P1, 2026-06). Nothing here is sourced, aliased, or dispatched. Restore with
`git mv` if a capability is wanted again — wire it into `bin/claw` when you do.

| File | Superseded by / reason |
|------|------------------------|
| `openclaw.sh` | `bin/claw` (this was the pre-claw dispatcher; `openclaw`/`oc` aliases removed) |
| `backup/` | unreferenced; `claw integrity` + git cover the use case |
| `security-hardening.sh` | unreferenced one-shot; security toolchain lives in `scripts/install/security-toolchain.sh` |
