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
            yield f"  {change['propertyChangeType']:<8} {path}"


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
