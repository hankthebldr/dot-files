#!/usr/bin/env python3
"""Scope parsing and authorization for the Open Claw security harness.

Single source of truth for the scope grammar (spec §5.3). `pre_tool_use.py`
imports this rather than keeping a second parser — one grammar, no drift.

Authorization is on the *resolved address*, not the name (§5.1): a name that
CNAMEs into a third party is a third party, and scanning it is unauthorized
however the allowlist reads.

No network, no DNS, no disk beyond reading the scope files. Resolution is the
caller's job; `authorize()` is handed addresses that were already resolved.
"""
from __future__ import annotations

import hashlib
import ipaddress
import re
from dataclasses import dataclass
from pathlib import Path

__all__ = [
    "Scope", "Verdict", "ScopeParseError", "authorize",
    "SCOPE_CLASSES", "GATED_CLASSES", "POLICIES",
]

SCOPE_CLASSES = ("local", "passive", "active-light", "active", "active-invasive")
GATED_CLASSES = ("active-light", "active", "active-invasive")
POLICIES = ("enforce", "warn", "off")

_DIRECTIVE_RE = re.compile(r"^([A-Za-z][A-Za-z0-9_-]*)\s*:\s*(.*)$")
_LABEL_RE = re.compile(r"^[A-Za-z0-9_](?:[A-Za-z0-9_-]*[A-Za-z0-9_])?$")


class ScopeParseError(ValueError):
    """A scope file did not parse. Never downgrade to a warning — a typo'd
    directive that is silently ignored is a security control switched off."""


@dataclass(frozen=True)
class Verdict:
    allowed: bool
    reason: str
    proposal: str | None       # ready-to-paste /scope amendment, or None
    policy: str                # "enforce" | "warn" | "off"
    unverified_addr: bool      # True when allowed without address verification


# --------------------------------------------------------------------------
# Grammar
# --------------------------------------------------------------------------
def _norm_host(host: str) -> str:
    return host.strip().rstrip(".").lower()


def _as_network(token: str):
    """Return an ip_network for an address or CIDR token, else None."""
    try:
        return ipaddress.ip_network(token, strict=False)
    except ValueError:
        return None


def _validate_name(token: str, lineno: int) -> str:
    name = token.lower().rstrip(".")
    body = name[2:] if name.startswith("*.") else name
    if not body:
        raise ScopeParseError(f"line {lineno}: empty name entry {token!r}")
    for label in body.split("."):
        if not _LABEL_RE.match(label):
            raise ScopeParseError(
                f"line {lineno}: {token!r} is neither a valid address/CIDR nor a hostname"
            )
    return name


class Scope:
    """An effective scope: the global allowlist unioned with an engagement
    overlay (§5.7). A deny in *either* layer wins."""

    def __init__(self, allow_names, deny_names, allow_addrs, deny_addrs, declared_policy):
        self.allow_names = list(allow_names)
        self.deny_names = list(deny_names)
        self.allow_addrs = list(allow_addrs)
        self.deny_addrs = list(deny_addrs)
        self.declared_policy = declared_policy
        # §5.2: a scope that declares at least one authorized address can and
        # must verify addresses; one that lists only names cannot.
        self.policy = declared_policy or ("enforce" if self.allow_addrs else "warn")
        self.global_sha256 = None  # set by from_text/from_files

    def facts(self) -> dict:
        """The structural summary resumption compares against (§11)."""
        return {
            "policy": self.policy,
            "global_sha256": self.global_sha256,
            "scope_sha256": self.sha256(),
            "allow_names": sorted(set(self.allow_names)),
            "allow_addrs": sorted({str(n) for n in self.allow_addrs}),
            "deny_names": sorted(set(self.deny_names)),
            "deny_addrs": sorted({str(n) for n in self.deny_addrs}),
        }

    # -- construction ------------------------------------------------------
    @classmethod
    def from_text(cls, text: str, overlay_text: str | None = None) -> "Scope":
        allow_names, deny_names, allow_addrs, deny_addrs = [], [], [], []
        declared = None
        for source in (text, overlay_text):
            if source is None:
                continue
            declared = cls._parse_into(
                source, allow_names, deny_names, allow_addrs, deny_addrs, declared
            )
        scope = cls(allow_names, deny_names, allow_addrs, deny_addrs, declared)
        # The durable layer is tracked separately: an engagement overlay churns
        # by design (§5.7), the global file does not, and resumption treats the
        # two differently (§11).
        scope.global_sha256 = (cls.from_text(text).sha256() if overlay_text is not None
                               else scope.sha256())
        return scope

    @classmethod
    def from_files(cls, global_path, overlay_path=None) -> "Scope":
        gp = Path(global_path)
        text = gp.read_text(encoding="utf-8") if gp.exists() else ""
        overlay = None
        if overlay_path is not None:
            op = Path(overlay_path)
            overlay = op.read_text(encoding="utf-8") if op.exists() else None
        return cls.from_text(text, overlay_text=overlay)

    @staticmethod
    def _parse_into(text, allow_names, deny_names, allow_addrs, deny_addrs, declared):
        for lineno, raw in enumerate(text.splitlines(), start=1):
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue

            deny = line.startswith("!")
            if deny:
                line = line[1:].strip()
                if not line:
                    raise ScopeParseError(f"line {lineno}: bare '!' denies nothing")

            net = _as_network(line)
            if net is not None:
                (deny_addrs if deny else allow_addrs).append(net)
                continue

            m = _DIRECTIVE_RE.match(line)
            if m:
                key, value = m.group(1).lower(), m.group(2).strip()
                if key != "resolve-policy":
                    raise ScopeParseError(f"line {lineno}: unknown directive {key!r}")
                if deny:
                    raise ScopeParseError(f"line {lineno}: directives cannot be denied")
                if value not in POLICIES:
                    raise ScopeParseError(
                        f"line {lineno}: resolve-policy must be one of "
                        f"{', '.join(POLICIES)} (got {value!r})"
                    )
                declared = value
                continue

            name = _validate_name(line, lineno)
            (deny_names if deny else allow_names).append(name)
        return declared

    # -- canonical form ----------------------------------------------------
    def to_text(self) -> str:
        """Canonical, comment-free serialization. Two scopes that authorize
        identically serialize identically, so the SHA-256 snapshot (§5.5) is
        insensitive to formatting but sensitive to authority."""
        lines = []
        if self.declared_policy:
            lines.append(f"resolve-policy: {self.declared_policy}")
        lines += sorted(set(self.allow_names))
        lines += sorted({str(n) for n in self.allow_addrs})
        lines += [f"!{n}" for n in sorted(set(self.deny_names))]
        lines += [f"!{n}" for n in sorted({str(n) for n in self.deny_addrs})]
        return "\n".join(lines) + "\n"

    def sha256(self) -> str:
        return hashlib.sha256(self.to_text().encode("utf-8")).hexdigest()

    # -- matching ----------------------------------------------------------
    @staticmethod
    def _name_matches(patterns, host: str) -> bool:
        host = _norm_host(host)
        for pat in patterns:
            if pat.startswith("*."):
                if host.endswith("." + pat[2:]):
                    return True
            elif host == pat:
                return True
        return False

    def addr_allows(self, addr) -> bool:
        try:
            ip = ipaddress.ip_address(str(addr))
        except ValueError:
            return False
        return any(ip in net for net in self.allow_addrs)

    def addr_denies(self, addr) -> bool:
        try:
            ip = ipaddress.ip_address(str(addr))
        except ValueError:
            return False
        return any(ip in net for net in self.deny_addrs)

    def name_allows(self, host: str) -> bool:
        if self._name_matches(self.allow_names, host):
            return True
        # A bare address as target: the address entries are its name entries.
        return self.addr_allows(host)

    def denied(self, host: str, addrs) -> bool:
        if self._name_matches(self.deny_names, host):
            return True
        if self.addr_denies(host):
            return True
        return any(self.addr_denies(a) for a in addrs)


# --------------------------------------------------------------------------
# Proposals — surfaced to the operator, never auto-applied
# --------------------------------------------------------------------------
def propose_name(host: str) -> str:
    return f"/scope add {_norm_host(host)}"


def propose_cidr(addrs) -> str:
    return " ; ".join(f"/scope add {a}" for a in addrs)


# --------------------------------------------------------------------------
# The gate
# --------------------------------------------------------------------------
def authorize(host, addrs, scope: Scope, scope_class: str = "active") -> Verdict:
    """Default-deny authorization. Deny is evaluated first so a deny entry can
    never be shadowed by a broad allow."""
    if scope_class not in SCOPE_CLASSES:
        raise ValueError(
            f"unknown scope_class {scope_class!r}; expected one of {', '.join(SCOPE_CLASSES)}"
        )

    policy = scope.policy

    if scope_class not in GATED_CLASSES:
        return Verdict(True, f"{scope_class} tool: no target to authorize", None, policy, False)

    addrs = [str(a) for a in (addrs or [])]

    # 1. explicit deny beats every allow, on name or address
    if scope.denied(host, addrs):
        return Verdict(False, "explicit deny entry", None, policy, False)

    # 2. exploitation requires address-verified authorization, always (§5.2)
    if scope_class == "active-invasive" and policy != "enforce":
        return Verdict(
            False,
            f"active-invasive requires resolve-policy 'enforce'; scope resolves to {policy!r}",
            None, policy, False,
        )

    # 3. name must match an allow pattern
    if not scope.name_allows(host):
        return Verdict(False, f"name {host!r} not in scope", propose_name(host), policy, False)

    # 4. address check, governed by resolve-policy (§5.2)
    if policy == "off":
        return Verdict(True, "name allowed; address check disabled", None, "off", True)

    if policy == "enforce" and not addrs:
        return Verdict(False, f"{host!r} resolved to no addresses; nothing to verify",
                       None, "enforce", False)

    stray = [a for a in addrs if not scope.addr_allows(a)]
    if not stray:
        return Verdict(True, "name and address authorized", None, policy, False)

    if policy == "warn":
        return Verdict(True, f"address unverified: {', '.join(stray)}",
                       propose_cidr(stray), "warn", True)

    return Verdict(False, f"{host!r} resolves off-scope: {', '.join(stray)}",
                   propose_cidr(stray), "enforce", False)
