#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

readonly PINNED_VERSION="0.65.1"
readonly BASELINE="Scripts/lint-baseline.json"

if ! command -v swiftlint >/dev/null; then
  echo "swiftlint not found. Install it with: brew install swiftlint" >&2
  exit 1
fi

installed="$(swiftlint version)"
if [[ "$installed" != "$PINNED_VERSION" ]]; then
  echo "warning: swiftlint $installed installed, baseline was written with $PINNED_VERSION" >&2
fi

if [[ "${1:-}" != "--update-baseline" ]]; then
  exec swiftlint lint --quiet --strict --baseline "$BASELINE" "$@"
fi

candidate="$(mktemp)"
trap 'rm -f "$candidate"' EXIT
swiftlint lint --quiet --no-cache --write-baseline "$candidate" >/dev/null || true

python3 - "$BASELINE" "$candidate" <<'PY'
import collections
import json
import sys

baseline_path, candidate_path = sys.argv[1], sys.argv[2]

def load(path):
    with open(path) as handle:
        return json.load(handle)

def per_rule(entries):
    return collections.Counter(e["violation"]["ruleIdentifier"] for e in entries)

def sort_key(entry):
    location = entry["violation"]["location"]
    return (
        location["file"],
        location.get("line") or 0,
        location.get("character") or 0,
        entry["violation"]["ruleIdentifier"],
        entry["violation"]["reason"],
    )

old, new = load(baseline_path), load(candidate_path)
before, after = per_rule(old), per_rule(new)
grown = {rule: (before[rule], count) for rule, count in after.items() if count > before[rule]}
if grown:
    for rule, (was, now) in sorted(grown.items()):
        print(f"refused: {rule} grew from {was} to {now}", file=sys.stderr)
    sys.exit(1)

lines = ",\n".join(json.dumps(e, sort_keys=True, separators=(",", ":")) for e in sorted(new, key=sort_key))
with open(baseline_path, "w") as handle:
    handle.write(f"[\n{lines}\n]\n")
print(f"baseline {len(old)} -> {len(new)} violations")
PY
