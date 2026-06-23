# Spotify Plugin (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A distributable Claude Code plugin that shows the now-playing Spotify track in the statusline and controls playback (next/prev/toggle/play-by-URI/named-modes/volume) via slash command, macOS/AppleScript only.

**Architecture:** All testable logic (config parsing, mode resolution, statusline appearance mapping) lives in a pure, sourced `bin/spotify-lib.sh` with no Spotify interaction, so it has an automated self-check that runs without Spotify. Thin osascript wrappers (`bin/spotify.sh` control CLI, `bin/spotify-status.sh` statusline segment) source the lib and are verified by running them against the live Spotify app. A single `/spotify <args>` slash command invokes the control CLI. User config lives at `~/.claude/spotify.json`, outside the plugin, so updates never wipe it.

**Tech Stack:** bash, AppleScript (osascript), jq (already installed). Claude Code plugin format (`.claude-plugin/plugin.json` + `marketplace.json`).

## Global Constraints

- Platform: macOS only; requires the Spotify **desktop** app and `jq`.
- No Spotify scripts may launch Spotify: always guard with a `System Events` "exists process Spotify" check before any `tell application "Spotify"`.
- No auth, no network, no Web API in Phase 1. Play-by-name/search is explicitly out of scope.
- User config path: `"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/spotify.json"` — never inside the plugin dir.
- Plugin name: `spotify`. Repo: `~/claude-spotify`.
- Statusline appearance keys off player state + active mode only (AppleScript cannot read the playing playlist).
- ANSI colors: red=31 green=32 yellow=33 blue=34 magenta=35 cyan=36 grey/gray=90; unknown/empty → 35 (magenta). Paused → ⏸ + 90.

---

### Task 1: Plugin manifest + marketplace listing

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`
- Create: `.gitignore`

**Interfaces:**
- Produces: a plugin named `spotify`; a marketplace listing it from this repo. Later tasks add `bin/`, `commands/`, `README.md`.

- [ ] **Step 1: Create `.claude-plugin/plugin.json`**

```json
{
  "name": "spotify",
  "description": "Control Spotify and show now-playing in the statusline (macOS, AppleScript).",
  "version": "0.1.0",
  "author": { "name": "Oktay Furkan Uygur" }
}
```

- [ ] **Step 2: Create `.claude-plugin/marketplace.json`**

(The `repo` slug is a placeholder filled in at publish time — Task 8.)

```json
{
  "version": "1",
  "name": "Oktay's Plugins",
  "description": "Personal Claude Code plugins",
  "plugins": [
    {
      "name": "spotify",
      "description": "Control Spotify and show now-playing in the statusline (macOS).",
      "source": { "source": "github", "repo": "REPLACE_ME/claude-spotify" }
    }
  ]
}
```

- [ ] **Step 3: Create `.gitignore`**

```
*.tmp
.DS_Store
```

- [ ] **Step 4: Verify both JSON files parse**

Run: `jq . .claude-plugin/plugin.json .claude-plugin/marketplace.json >/dev/null && echo OK`
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json .gitignore
git commit -m "feat: add Spotify plugin manifest and marketplace listing"
```

---

### Task 2: Pure logic library + self-check test (TDD)

**Files:**
- Create: `tests/test_spotify.sh`
- Create: `bin/spotify-lib.sh`

**Interfaces:**
- Produces (sourced functions consumed by Tasks 3 & 4):
  - `spotify_config` → prints config path `"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/spotify.json"`.
  - `spotify_color_code <name>` → prints ANSI code (string).
  - `resolve_mode <config> <name>` → prints `uri<TAB>volume<TAB>emoji<TAB>color`, returns 1 if config missing or mode unknown.
  - `list_modes <config>` → prints comma-separated mode names (empty if none).
  - `appearance <state> <config>` → prints `emoji<TAB>colorcode`; `paused` → `⏸<TAB>90`; `playing` uses `.active` mode if set, else `🎵<TAB>35`.

- [ ] **Step 1: Write the failing test** — create `tests/test_spotify.sh`

```bash
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

rm -f "$tmp"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_spotify.sh`
Expected: FAIL — `spotify-lib.sh` does not exist yet (source error / functions not found).

- [ ] **Step 3: Write `bin/spotify-lib.sh`**

```bash
#!/bin/bash
# Pure helpers for the Spotify plugin. No osascript, no side effects on Spotify.
# Sourced by spotify.sh and spotify-status.sh; exercised directly by tests.

spotify_config() { echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/spotify.json"; }

# Map a color name to an ANSI SGR code. Unknown/empty → 35 (magenta).
spotify_color_code() {
  case "$1" in
    red) echo 31;; green) echo 32;; yellow) echo 33;;
    blue) echo 34;; magenta) echo 35;; cyan) echo 36;;
    grey|gray) echo 90;; *) echo 35;;
  esac
}

# resolve_mode <config> <name> → "uri<TAB>volume<TAB>emoji<TAB>color"; returns 1 if missing/unknown.
resolve_mode() {
  local config="$1" name="$2" uri vol emoji color
  [ -f "$config" ] || return 1
  uri=$(jq -r --arg m "$name" '.modes[$m].uri // empty' "$config" 2>/dev/null)
  [ -n "$uri" ] || return 1
  vol=$(jq -r --arg m "$name" '.modes[$m].volume // empty' "$config" 2>/dev/null)
  emoji=$(jq -r --arg m "$name" '.modes[$m].emoji // "🎵"' "$config" 2>/dev/null)
  color=$(jq -r --arg m "$name" '.modes[$m].color // empty' "$config" 2>/dev/null)
  printf '%s\t%s\t%s\t%s\n' "$uri" "$vol" "$emoji" "$color"
}

# list_modes <config> → comma-separated mode names (empty if none).
list_modes() {
  local config="$1"
  [ -f "$config" ] || return 0
  jq -r '(.modes // {}) | keys | join(", ")' "$config" 2>/dev/null
}

# appearance <state> <config> → "emoji<TAB>colorcode".
# paused → dim grey ⏸; playing → active mode's emoji/color if set, else 🎵/35.
appearance() {
  local state="$1" config="$2" active emoji color
  if [ "$state" = "paused" ]; then printf '⏸\t90\n'; return 0; fi
  active=""
  [ -f "$config" ] && active=$(jq -r '.active // empty' "$config" 2>/dev/null)
  if [ -n "$active" ] && [ -f "$config" ]; then
    emoji=$(jq -r --arg m "$active" '.modes[$m].emoji // "🎵"' "$config" 2>/dev/null)
    color=$(jq -r --arg m "$active" '.modes[$m].color // empty' "$config" 2>/dev/null)
    printf '%s\t%s\n' "$emoji" "$(spotify_color_code "$color")"
    return 0
  fi
  printf '🎵\t35\n'
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_spotify.sh`
Expected: every line `ok: ...` then `ALL PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add bin/spotify-lib.sh tests/test_spotify.sh
git commit -m "feat: add pure logic lib with self-check (mode resolution, appearance)"
```

---

### Task 3: Control CLI `bin/spotify.sh`

**Files:**
- Create: `bin/spotify.sh`

**Interfaces:**
- Consumes: `spotify_config`, `resolve_mode`, `list_modes` from `bin/spotify-lib.sh`.
- Produces: a CLI `spotify.sh <next|prev|toggle|play <uri>|vol <0-100>|mode <name>|status|resolve <name>>`. The slash command (Task 5) invokes it. `resolve` is a hidden, Spotify-free subcommand used for debugging/tests.

- [ ] **Step 1: Write `bin/spotify.sh`**

```bash
#!/bin/bash
# Spotify control via AppleScript (macOS). No auth. Never launches Spotify.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/spotify-lib.sh"
CONFIG="$(spotify_config)"

spotify_running() {
  [ "$(osascript -e 'tell application "System Events" to (exists process "Spotify")' 2>/dev/null)" = "true" ]
}
osa() { osascript -e "tell application \"Spotify\" to $1" 2>/dev/null; }
require_running() { spotify_running || { echo "Spotify çalışmıyor. Önce Spotify'ı aç." >&2; exit 1; }; }

now_playing() {
  spotify_running || { echo "Spotify kapalı."; return 0; }
  local state; state=$(osa 'player state as string')
  case "$state" in
    playing|paused) echo "$state: $(osa 'artist of current track') – $(osa 'name of current track')" ;;
    *) echo "Çalan bir şey yok." ;;
  esac
}

cmd="${1:-status}"; [ $# -gt 0 ] && shift

case "$cmd" in
  next)   require_running; osa 'next track' >/dev/null; now_playing ;;
  prev)   require_running; osa 'previous track' >/dev/null; now_playing ;;
  toggle) require_running; osa 'playpause' >/dev/null; now_playing ;;
  play)
    require_running
    [ -n "${1:-}" ] || { echo "Kullanım: /spotify play <spotify:uri>" >&2; exit 1; }
    osa "play track \"$1\"" >/dev/null; now_playing ;;
  vol)
    require_running
    { [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "$1" -le 100 ]; } || { echo "Kullanım: /spotify vol <0-100>" >&2; exit 1; }
    osa "set sound volume to $1" >/dev/null; echo "Ses: $1" ;;
  mode)
    require_running
    name="${1:-}"
    [ -n "$name" ] || { echo "Kullanım: /spotify mode <ad>" >&2; exit 1; }
    if ! resolved=$(resolve_mode "$CONFIG" "$name"); then
      echo "Bilinmeyen mod: $name. Tanımlılar: $(list_modes "$CONFIG")" >&2; exit 1
    fi
    IFS=$'\t' read -r uri vol _emoji _color <<<"$resolved"
    osa "play track \"$uri\"" >/dev/null
    [ -n "$vol" ] && osa "set sound volume to $vol" >/dev/null
    tmp=$(mktemp); jq --arg m "$name" '.active = $m' "$CONFIG" > "$tmp" && mv "$tmp" "$CONFIG"
    echo "Mod: $name"; now_playing ;;
  resolve) resolve_mode "$CONFIG" "${1:-}" ;;
  status)  now_playing ;;
  *) echo "Bilinmeyen komut: $cmd (next|prev|toggle|play|vol|mode|status)" >&2; exit 1 ;;
esac
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x bin/spotify.sh`

- [ ] **Step 3: Verify dispatch with Spotify CLOSED (no launch, no error)**

Run (only if Spotify is not running): `bash bin/spotify.sh status`
Expected: `Spotify kapalı.` and Spotify does NOT open.

- [ ] **Step 4: Verify against live Spotify**

Open Spotify, start a track, then:
Run: `bash bin/spotify.sh status`
Expected: `playing: <artist> – <track>`
Run: `bash bin/spotify.sh vol 55`
Expected: `Ses: 55` (and Spotify volume changes)
Run: `bash bin/spotify.sh toggle`
Expected: prints `paused: ...` (and playback pauses); run again to resume.

- [ ] **Step 5: Commit**

```bash
git add bin/spotify.sh
git commit -m "feat: add Spotify control CLI (next/prev/toggle/play/vol/mode/status)"
```

---

### Task 4: Statusline segment `bin/spotify-status.sh`

**Files:**
- Create: `bin/spotify-status.sh`

**Interfaces:**
- Consumes: `spotify_config`, `appearance` from `bin/spotify-lib.sh`.
- Produces: a script that prints one ANSI-colored segment `emoji artist – track` to stdout, or nothing if Spotify is closed/stopped. Ignores stdin (statusline JSON not needed). Consumed by the user's statusline command (Task 7) and the README example.

- [ ] **Step 1: Write `bin/spotify-status.sh`**

```bash
#!/bin/bash
# Statusline segment: now-playing + mode-based color. Prints nothing if Spotify closed/stopped.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/spotify-lib.sh"
CONFIG="$(spotify_config)"

[ "$(osascript -e 'tell application "System Events" to (exists process "Spotify")' 2>/dev/null)" = "true" ] || exit 0

out=$(osascript 2>/dev/null <<'OSA'
tell application "Spotify"
  set s to player state as string
  if s is "stopped" then return "stopped"
  return s & tab & artist of current track & tab & name of current track
end tell
OSA
)
[ -z "$out" ] && exit 0
state="${out%%$'\t'*}"
[ "$state" = "stopped" ] && exit 0
rest="${out#*$'\t'}"
artist="${rest%%$'\t'*}"
track="${rest#*$'\t'}"

IFS=$'\t' read -r emoji color < <(appearance "$state" "$CONFIG")
printf '\033[%sm%s %s – %s\033[0m' "$color" "$emoji" "$artist" "$track"
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x bin/spotify-status.sh`

- [ ] **Step 3: Verify while a track is playing**

Run: `bash bin/spotify-status.sh; echo`
Expected: a colored line like `🎵 <artist> – <track>` (magenta when no active mode set).

- [ ] **Step 4: Verify when stopped/closed prints nothing**

Quit Spotify, then:
Run: `bash bin/spotify-status.sh; echo "[end]"`
Expected: just `[end]` (empty segment, no error, Spotify stays closed).

- [ ] **Step 5: Commit**

```bash
git add bin/spotify-status.sh
git commit -m "feat: add statusline segment with mode-based appearance"
```

---

### Task 5: Slash command `commands/spotify.md`

**Files:**
- Create: `commands/spotify.md`

**Interfaces:**
- Consumes: `bin/spotify.sh` via `${CLAUDE_PLUGIN_ROOT}`.
- Produces: the `/spotify <args>` slash command.

- [ ] **Step 1: Write `commands/spotify.md`**

```markdown
---
description: Spotify'ı kontrol et (next, prev, toggle, play <uri>, mode <ad>, vol <0-100>, status)
argument-hint: "[next|prev|toggle|play <uri>|mode <ad>|vol <0-100>|status]"
---

Spotify kontrol komutu çalıştırıldı. Çıktı:

!`bash "${CLAUDE_PLUGIN_ROOT}/bin/spotify.sh" $ARGUMENTS`

Yukarıdaki çıktıyı kullanıcıya kısaca ilet; ekstra yorum yapma.
```

- [ ] **Step 2: Verify `${CLAUDE_PLUGIN_ROOT}` expansion path (sanity check before install)**

The `!` line runs `bash "${CLAUDE_PLUGIN_ROOT}/bin/spotify.sh" $ARGUMENTS`. `${CLAUDE_PLUGIN_ROOT}` is set by Claude Code to the plugin's install dir when the command runs. This is verified end-to-end in Task 7 (`/spotify status` after local install). No standalone run here.

- [ ] **Step 3: Commit**

```bash
git add commands/spotify.md
git commit -m "feat: add /spotify slash command"
```

---

### Task 6: README + sample config

**Files:**
- Create: `README.md`
- Create: `spotify.example.json`

**Interfaces:**
- Produces: install + statusline-wiring docs; an example config users copy to `~/.claude/spotify.json`.

- [ ] **Step 1: Create `spotify.example.json`**

```json
{
  "modes": {
    "focus": { "uri": "spotify:playlist:37i9dQZF1DWZeKCadgRdKQ", "volume": 40, "emoji": "🎯", "color": "blue" },
    "chill": { "uri": "spotify:playlist:37i9dQZF1DX4WYpdgoIcn6", "volume": 60, "emoji": "🌙", "color": "cyan" }
  },
  "active": null
}
```

- [ ] **Step 2: Create `README.md`**

````markdown
# Spotify plugin for Claude Code

Show the now-playing Spotify track in your statusline and control playback from Claude Code. **macOS only** (uses AppleScript), no login required. Requires the Spotify desktop app and `jq`.

## Install

```
/plugin marketplace add <github-user>/claude-spotify
/plugin install spotify
```

## Control

```
/spotify status                              # what's playing
/spotify next                                # next track
/spotify prev                                # previous track
/spotify toggle                              # play / pause
/spotify play spotify:playlist:37i9dQ...     # play a playlist or track by URI
/spotify vol 40                              # set volume 0–100
/spotify mode focus                          # play a named mode (see config) + set its volume
```

To get a playlist/track URI: in Spotify, right-click → Share → Copy Spotify URI.

> Play-by-name / search ("play some chill music") needs the Spotify Web API and is not in this version. Play by URI or by a named mode instead.

## Modes

Copy `spotify.example.json` to `~/.claude/spotify.json` and edit. Each mode has a playlist/track `uri`, optional `volume`, `emoji`, and `color` (red/green/yellow/blue/magenta/cyan/grey). `/spotify mode <name>` plays it and marks it active; the statusline then uses that mode's emoji/color.

## Statusline

Plugins can't set the statusline automatically — add it to your `settings.json` once.

**If you don't have a statusline yet**, this shows the directory plus now-playing:

```json
"statusLine": {
  "type": "command",
  "command": "printf '%s ' \"$(basename \"$(jq -r .workspace.current_dir)\")\"; bash \"${CLAUDE_PLUGIN_ROOT}/bin/spotify-status.sh\""
}
```

**If you already have a statusline**, call the segment from your own script and append its output:

```bash
spotify=$(bash "${CLAUDE_PLUGIN_ROOT}/bin/spotify-status.sh")
[ -n "$spotify" ] && printf '  %s' "$spotify"
```

If `${CLAUDE_PLUGIN_ROOT}` doesn't expand in your statusline context, use the absolute install path printed by `/plugin` (e.g. `~/.claude/plugins/cache/<marketplace>/spotify/<version>/bin/spotify-status.sh`).

## Scope

Phase 1: AppleScript, macOS, no auth. Later: Spotify Web API (search, recommendations, queue, cross-device), MCP server for conversational control.
````

- [ ] **Step 3: Verify JSON + markdown sanity**

Run: `jq . spotify.example.json >/dev/null && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add README.md spotify.example.json
git commit -m "docs: add README and example mode config"
```

---

### Task 7: Local install validation + integrate into Oktay's statusline

**Files:**
- Modify: `/Users/oktayfurkanuygur/.claude/statusline-command.sh` (replace the inline Spotify block added earlier with a call to the plugin segment)
- Create: `/Users/oktayfurkanuygur/.claude/spotify.json` (from the example, real playlist URIs optional)

**Interfaces:**
- Consumes: the installed plugin (`/spotify` command) and `bin/spotify-status.sh`.

- [ ] **Step 1: Add the local marketplace and install the plugin**

In Claude Code:
```
/plugin marketplace add /Users/oktayfurkanuygur/claude-spotify
/plugin install spotify
```
Expected: plugin `spotify` installs without error; `/spotify` appears in the command list.

- [ ] **Step 2: Verify the slash command end-to-end**

With Spotify playing, run `/spotify status` in Claude Code.
Expected: Claude relays `playing: <artist> – <track>`. Then `/spotify next` advances the track.

- [ ] **Step 3: Create the user config**

```bash
cp /Users/oktayfurkanuygur/claude-spotify/spotify.example.json /Users/oktayfurkanuygur/.claude/spotify.json
```
(Edit the playlist URIs later to real ones; `/spotify mode focus` will then work.)

- [ ] **Step 4: Replace the inline Spotify block in the statusline with the plugin segment**

In `/Users/oktayfurkanuygur/.claude/statusline-command.sh`, replace the previously-added inline `spotify=$(osascript ... )` block (the one tagged `# ponytail: osascript adds ~50-100ms ...`) with:

```bash
# Now playing on Spotify (delegated to the spotify plugin segment script)
spotify=$(bash /Users/oktayfurkanuygur/claude-spotify/bin/spotify-status.sh 2>/dev/null)
```

Leave the existing append block at the end unchanged:

```bash
if [ -n "$spotify" ]; then
    printf "  %s" "$spotify"
fi
```

(The segment script already emits its own ANSI color, so drop the extra `\033[35m` wrapper that the old inline block relied on.)

- [ ] **Step 5: Verify the statusline renders the segment**

Run: `echo '{"workspace":{"current_dir":"/Users/oktayfurkanuygur"}}' | /bin/bash /Users/oktayfurkanuygur/.claude/statusline-command.sh; echo`
Expected: the robbyrussell prefix followed by a colored `🎵 <artist> – <track>` (or no Spotify segment if nothing is playing).

- [ ] **Step 6: Commit (plugin repo only — `~/.claude` is not under this repo)**

No plugin-repo files changed in this task. If you keep your `~/.claude` under version control separately, commit there; otherwise nothing to commit here.

---

### Task 8: Publish to GitHub

**Files:**
- Modify: `.claude-plugin/marketplace.json` (set real repo slug)

**Interfaces:** none (distribution step).

- [ ] **Step 1: Get the GitHub repo slug from the user**

Ask for `<github-user>` (and confirm repo name `claude-spotify`).

- [ ] **Step 2: Set the real repo in `marketplace.json`**

Replace `"repo": "REPLACE_ME/claude-spotify"` with `"repo": "<github-user>/claude-spotify"`.

- [ ] **Step 3: Commit the slug**

```bash
git add .claude-plugin/marketplace.json
git commit -m "chore: set marketplace repo slug for publishing"
```

- [ ] **Step 4: Create the GitHub repo and push**

```bash
gh repo create <github-user>/claude-spotify --public --source=. --remote=origin --push
```
Expected: repo created, default branch pushed.

- [ ] **Step 5: Verify install from GitHub (optional, on a clean machine or after removing the local marketplace)**

```
/plugin marketplace add <github-user>/claude-spotify
/plugin install spotify
```
Expected: installs from GitHub.

---

## Self-Review

**Spec coverage:**
- Now-playing statusline → Task 4 (segment) + Task 7 (integration). ✓
- Control verbs (next/prev/toggle/play-uri/mode/vol/status) → Task 3. ✓
- Named modes + user config `~/.claude/spotify.json` outside plugin → Task 2 (resolve), Task 3 (mode + persist active), Task 6 (example), Task 7 (install config). ✓
- Statusline appearance by state + active mode → Task 2 (`appearance`) + Task 4. ✓
- AppleScript-can't-read-playlist constraint → honored: appearance keys off state + active mode only. ✓
- Never launches Spotify → guarded in Task 3 & 4. ✓
- plugin.json + marketplace.json + README → Tasks 1, 6. ✓
- Distribution / marketplace install → Tasks 7 (local), 8 (GitHub). ✓
- Error handling (Spotify closed, unknown mode, malformed config) → Task 3 (require_running, unknown-mode message), lib returns 1 on missing config. ✓
- One automated self-check for non-trivial logic → Task 2. ✓
- Out-of-scope (Web API, MCP, search) → not implemented; noted in README. ✓

**Placeholder scan:** `REPLACE_ME` / `<github-user>` are intentional, resolved in Task 8. Example playlist URIs are real Spotify editorial playlist IDs. No TBD/TODO/"handle edge cases" left.

**Type consistency:** `resolve_mode` emits `uri<TAB>vol<TAB>emoji<TAB>color` and is read with matching field order in test (Task 2) and in `spotify.sh` mode case (Task 3). `appearance` emits `emoji<TAB>colorcode`, read identically in test (Task 2) and `spotify-status.sh` (Task 4). `spotify_color_code` mapping matches the Global Constraints table. Consistent.
