"""Summarize `az deployment group what-if --no-pretty-print` output as change paths only.

Never prints before/after values: env vars hold secrets, and GitHub's log masking only
catches exact matches, not a fragment of a secret inside a diff.

Usage: python3 tools/whatif-summary.py whatif.json   (prints nothing when nothing changes)
"""
import json
import sys


def walk(changes, prefix):
    for change in changes:
        path = prefix + str(change["path"])
        children = change.get("children") or []
        if children:
            yield from walk(children, path + ".")
        else:
            yield f"  {change['propertyChangeType']:<8} {path}{note(change)}"


def note(change):
    """Say what kind of difference this is, without revealing either value."""
    if change["propertyChangeType"] != "Modify":
        return ""
    before, after = change.get("before"), change.get("after")
    if before == after:
        return "  (identical value)"
    if isinstance(after, str) and after.startswith("[") and "parameters(" in after:
        # A secure parameter: what-if leaves it unevaluated, so it cannot compare it.
        return "  (secure value: what-if cannot compare it)"
    if isinstance(before, str) and isinstance(after, str):
        # The length difference (not the lengths) spots a stray newline or space.
        return f"  (values differ; length {len(after) - len(before):+d})"
    return "  (values differ)"


def main(path):
    with open(path, encoding="utf-8") as f:
        result = json.load(f)
    for change in result.get("changes", []):
        if change["changeType"] in ("NoChange", "Ignore"):
            continue
        name = "/".join(change["resourceId"].split("/")[-2:])
        print(f"{change['changeType']}  {name}")
        for line in walk(change.get("delta") or [], ""):
            print(line)


if __name__ == "__main__":
    main(sys.argv[1])
