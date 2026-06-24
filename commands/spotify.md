---
description: Control Spotify (next, prev, toggle, play <uri>, mode <name>, vol <0-100>, status)
argument-hint: "[next|prev|toggle|play <uri>|mode <name>|vol <0-100>|status]"
---

Ran the Spotify control command. Output:

!`P="${CLAUDE_PLUGIN_ROOT}/bin/spotify.sh"; if [ -x "$P" ]; then bash "$P" $ARGUMENTS; else spotify.sh $ARGUMENTS; fi`

Relay the output above to the user briefly; don't add commentary.
