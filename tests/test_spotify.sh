#!/bin/bash
# Self-check for the Spotify plugin's pure logic. No Spotify app required.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../bin/spotify-lib.sh"

fail=0
check() { if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FAIL: $1 — got [$2] want [$3]"; fail=1; fi; }

tmp=$(mktemp)
cat > "$tmp" <<'JSON'
{ "modes": {
    "focus": { "uri": "spotify:playlist:F", "volume": 40, "emoji": "🎯", "color": "blue" },
    "chill": { "uri": "spotify:playlist:C", "volume": 60, "emoji": "🌙", "color": "cyan" }
  },
  "active": "focus" }
JSON

check "color blue"    "$(spotify_color_code blue)" "34"
check "color unknown" "$(spotify_color_code wat)"  "35"
check "color grey"    "$(spotify_color_code grey)" "90"

IFS=$'\t' read -r uri vol emoji color < <(resolve_mode "$tmp" focus)
check "resolve uri"   "$uri"   "spotify:playlist:F"
check "resolve vol"   "$vol"   "40"
check "resolve emoji" "$emoji" "🎯"
check "resolve color" "$color" "blue"

if resolve_mode "$tmp" nope >/dev/null 2>&1; then check "unknown mode fails" "ok" "fail"; else check "unknown mode fails" "fail" "fail"; fi

check "list modes" "$(list_modes "$tmp")" "focus, chill"

IFS=$'\t' read -r e c < <(appearance paused "$tmp")
check "paused emoji" "$e" "⏸"
check "paused color" "$c" "90"

IFS=$'\t' read -r e c < <(appearance playing "$tmp")
check "active emoji" "$e" "🎯"
check "active color" "$c" "34"

# AppleScript escaping (C1: prevents play-track URI injection → RCE)
check "esc quote"     "$(applescript_escape 'a"b')" 'a\"b'
check "esc backslash" "$(applescript_escape 'a\b')" 'a\\b'
check "esc injection" "$(applescript_escape 'x" & (do shell script "id") & "')" 'x\" & (do shell script \"id\") & \"'

rm -f "$tmp"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }
