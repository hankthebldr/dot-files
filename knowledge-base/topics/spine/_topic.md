# Spine

The three consolidation contracts everything in Open Claw hangs off. When
adding a capability, wire it into the spine — never add a parallel
dispatcher, palette source, or dashboard.

- [One dispatcher](one-dispatcher.md) — the single claw() function and routing.
- [One theme engine](one-theme-engine.md) — theme.sh and the color precedence chain.
- [One render path](one-render-path.md) — claw-dashboard.py and its fallbacks.
