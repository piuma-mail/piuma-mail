#!/usr/bin/env python3
"""Known vulnerabilities in the Dart packages the app and the watch ship.

Reads pubspec.lock files and asks OSV (https://osv.dev, which carries the
GitHub advisories for the Pub ecosystem) about every hosted package at its
locked version. Fails, listing them, when any has an advisory not in
IGNORED. Dev dependencies are checked too: they run on every build.

    python3 tools/pub_advisories.py app/pubspec.lock wear/pubspec.lock
"""

import json
import re
import sys
import urllib.request

# Advisories checked and found not to apply: id -> why, with the date.
IGNORED: dict[str, str] = {}

OSV = "https://api.osv.dev/v1/querybatch"


def locked(path):
    """(name, version) of every package from pub.dev in a pubspec.lock."""
    text = open(path, encoding="utf-8").read()
    packages = []
    for block in re.split(r"\n  (?=[A-Za-z0-9_]+:\n)", text.split("packages:", 1)[1]):
        name = re.match(r"\s*([A-Za-z0-9_]+):", block)
        version = re.search(r'\n    version: "([^"]+)"', block)
        if name and version and 'source: hosted' in block:
            packages.append((name.group(1), version.group(1)))
    return packages


def query(packages):
    body = json.dumps(
        {"queries": [{"package": {"ecosystem": "Pub", "name": n}, "version": v} for n, v in packages]}
    ).encode()
    req = urllib.request.Request(OSV, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)["results"]


def main(paths):
    packages = sorted({p for path in paths for p in locked(path)})
    if not packages:
        sys.exit("No hosted packages found: is this a pubspec.lock?")
    found = []
    for (name, version), result in zip(packages, query(packages)):
        for vuln in result.get("vulns") or []:
            if vuln["id"] in IGNORED:
                print(f"ignored {vuln['id']} on {name} {version}: {IGNORED[vuln['id']]}")
            else:
                found.append(f"{name} {version}: {vuln['id']} https://osv.dev/vulnerability/{vuln['id']}")
    print(f"{len(packages)} Dart packages checked.")
    if found:
        print("Known vulnerabilities:\n" + "\n".join(found))
        sys.exit(1)


if __name__ == "__main__":
    main(sys.argv[1:] or ["app/pubspec.lock", "wear/pubspec.lock"])
