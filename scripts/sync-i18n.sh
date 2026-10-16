#!/bin/sh
# Copy the widget's words in its five languages from the React Native SDK
# into the SDK's bundled resource (Sources/Conferbot/Resources/i18n-strings.json),
# read at run time by Core/I18n/I18n.swift.
#
#   scripts/sync-i18n.sh [path/to/conferbot-react-native]
#
# strings.json is generated there from the web widget's ts/i18n/*.ts and the
# SDK-only words (conferbot-react-native/scripts/parity/i18n/gen.js). Pull RN
# first, run this after it changes, then run the tests (I18nTests checks the
# copy is the same file).
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
rn=${1:-"$here/../conferbot-react-native"}
src="$rn/scripts/parity/i18n/strings.json"
dst="$here/Sources/Conferbot/Resources/i18n-strings.json"

[ -f "$src" ] || { echo "No strings at $src" >&2; exit 1; }

mkdir -p "$(dirname "$dst")"
cp "$src" "$dst"
rev=$(git -C "$rn" rev-parse --short HEAD 2>/dev/null || echo unknown)
echo "Copied strings.json from conferbot-react-native $rev"
