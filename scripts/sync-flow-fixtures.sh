#!/bin/sh
# Copy the shared flow-node fixtures from the React Native SDK into the test
# resources (Tests/Resources/flows), and note the RN revision they came from.
#
#   scripts/sync-flow-fixtures.sh [path/to/conferbot-react-native]
#
# The fixtures are made by running the web widget's own code
# (conferbot-react-native/scripts/parity/flows, README.md). Run this after
# they change there, then run the tests (FlowFixtureTests).
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
rn=${1:-"$here/../conferbot-react-native"}
src="$rn/scripts/parity/flows/fixtures"
dst="$here/Tests/Resources/flows"

[ -f "$src/index.json" ] || { echo "No fixtures at $src" >&2; exit 1; }

rm -rf "$dst"
mkdir -p "$dst"
cp "$src"/*.json "$dst"/
rev=$(git -C "$rn" rev-parse --short HEAD 2>/dev/null || echo unknown)
echo "$rev" > "$dst/REVISION"
echo "Copied $(ls "$dst"/*.json | wc -l | tr -d ' ') files from conferbot-react-native $rev"
