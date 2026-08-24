#!/usr/bin/env python3
"""Engagement construction, shared by every adapter.

Adapters translate a protocol; they do not decide who is authorized and they
do not read the scope file themselves. Building the engagement — resolving the
global allowlist, layering the engagement overlay, loading the registry — lives
here so there is one way it happens and the adapters stay free of it.
"""
from __future__ import annotations

import os
from pathlib import Path

import lint as L
import registry as R
import scope as S

REPO = Path(__file__).resolve().parents[2]
DEFAULT_SCOPE = os.path.join("~", ".claude", "scope.txt")
DEFAULT_REGISTRY = REPO / "config" / "security" / "tools.yaml"
OVERLAY_NAME = "scope.local"

__all__ = ["build", "DEFAULT_SCOPE", "DEFAULT_REGISTRY"]


def build(root, run_id: str, scope_path=None, registry_path=None,
          allow_invasive: bool = False, allow_disclosure: bool = False,
          actor: str = "model") -> R.Engagement:
    """Effective scope = global allowlist ∪ engagement overlay (§5.7).

    A deny in either layer wins, so an overlay can add an on-demand lab host
    but can never re-authorize something the durable file denies.
    """
    root = Path(root)
    overlay = root / OVERLAY_NAME
    sc = S.Scope.from_files(os.path.expanduser(scope_path or DEFAULT_SCOPE),
                            overlay if overlay.exists() else None)
    return R.Engagement(
        root=root,
        run_id=run_id,
        scope=sc,
        registry=L.load_registry(registry_path or DEFAULT_REGISTRY),
        allow_invasive=allow_invasive,
        allow_disclosure=allow_disclosure,
        actor=actor,
    )
