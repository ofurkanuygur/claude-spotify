# Spotify Plugin for Claude Code — Design

**Date:** 2026-06-24
**Status:** Approved (design), pending implementation plan

## Purpose

A Claude Code plugin (distributable via a GitHub marketplace) that:
1. Shows the currently-playing Spotify track in the statusline.
2. Lets the user control Spotify playback from Claude Code (next/prev/play-pause, play a playlist or track, named "modes").
3. Changes the statusline appearance based on playback state and the active mode.

Phase 1 (this spec) is **AppleScript-only, macOS-only, no auth**. Spotify Web API (search, recommendations, queue, cross-device) is explicitly deferred to a later phase.

## Hard technical constraint

Spotify's AppleScript dictionary exposes the current **track** (name, artist, album), **player state** (playing/paused/stopped), volume, shuffle, and repeat — but **NOT the playlist/context currently playing**. Detecting "which playlist is auto-playing" requires the Web API.

Therefore statusline appearance keys off three things that *are* available:
1. Player state (playing / paused).
2. The **active mode** — set explicitly when the user runs `/spotify mode <name>`, persisted to user config, read by the statusline.
3. (Optional) keyword rules matching artist/album text.

## Components

All shipped inside one plugin, except user config which lives outside the plugin dir (so a plugin update never wipes it).

| Component | Responsibility | Location |
|-----------|----------------|----------|
| `bin/spotify.sh` | All control verbs: `next`, `prev`, `toggle`, `play <uri>`, `mode <name>`, `vol <n>`, `status`. Thin AppleScript wrapper. Reads `~/.claude/spotify.json` for mode definitions; writes the active mode back. | plugin |
| `bin/spotify-status.sh` | Statusline **segment** only. Reads current track + player state + active mode, prints `emoji artist – track` with an ANSI color. Guarded so it never launches Spotify if it's closed. Empty output when nothing is playing. | plugin |
| `commands/spotify.md` | The `/spotify <args>` slash command. Invokes `bin/spotify.sh` with the arguments. | plugin |
| `~/.claude/spotify.json` | **User config.** Mode definitions (name → playlist URI, volume, emoji, color) and the current active mode. Lives outside the plugin so updates don't clobber it. | user home |
| `.claude-plugin/plugin.json` | Plugin manifest (name `spotify`, description, version, author). | repo root |
| `.claude-plugin/marketplace.json` | Marketplace listing the plugin from this same repo. | repo root |
| `README.md` | Install instructions, statusline wiring (manual settings.json step, since plugins can't declare `statusLine`), config format, a ready-made full-statusline example for new users. | repo root |

### Single-responsibility note
`bin/spotify-status.sh` does exactly one thing: print the Spotify segment. It does not own the whole statusline. The user (Oktay) already has a custom `~/.claude/statusline-command.sh`; he calls the segment script from there. New users get a ready-made full statusline example in the README.

## Control surface

One slash command, argument-dispatched:

```
/spotify next                                  → next track
/spotify prev                                  → previous track
/spotify toggle                                → play/pause
/spotify play spotify:playlist:37i9dQ...       → play a playlist/track by URI
/spotify mode focus                            → play config's "focus" playlist, set its volume, mark mode active
/spotify vol 40                                → set volume 0–100
/spotify status                                → print what's playing
```

**Not in Phase 1:** play-by-name / search ("play some chill music") — requires Web API. In Phase 1 you play by URI or by a predefined mode name.

## User config format (`~/.claude/spotify.json`)

```json
{
  "modes": {
    "focus": { "uri": "spotify:playlist:XXXX", "volume": 40, "emoji": "🎯", "color": "blue" },
    "chill": { "uri": "spotify:playlist:YYYY", "volume": 60, "emoji": "🌙", "color": "cyan" }
  },
  "active": null
}
```

`/spotify mode focus` → reads `modes.focus`, plays its URI, sets volume, writes `active: "focus"`. The statusline reads `active` to pick emoji/color. Mode stays active until changed.

## Statusline appearance

```
Playing (no mode):   🎵 Artist – Track     (magenta)
Paused:              ⏸ Artist – Track      (dim grey)
focus mode active:   🎯 Artist – Track     (blue)
chill mode active:   🌙 Artist – Track     (cyan)
Nothing playing:     (empty — segment prints nothing)
```

## Distribution

- Repo: `~/claude-spotify`, a new git repo, pushed to GitHub.
- `marketplace.json` lists the plugin from this same repo (`source: github, repo: <user>/claude-spotify`).
- Install flow for end users:
  ```
  /plugin marketplace add <github-user>/claude-spotify
  /plugin install spotify
  ```
  then add the statusline line to `settings.json` (documented in README, references `${CLAUDE_PLUGIN_ROOT}`).
- GitHub username / repo name confirmed at publish time.

## Error handling

- `spotify-status.sh`: if Spotify isn't running (checked via System Events before any `tell application "Spotify"`), print nothing and exit 0 — never launch Spotify, never error into the statusline.
- `spotify.sh`: if Spotify isn't running, control verbs report a friendly message rather than launching it silently; `mode <name>` with an unknown name or missing config reports the available modes.
- Malformed/missing `~/.claude/spotify.json`: treated as "no modes defined"; control still works for direct URIs and raw verbs.

## Testing

- A runnable self-check for the non-trivial logic: parsing `~/.claude/spotify.json` and resolving a mode name → URI/volume/color, plus the statusline state→appearance mapping. An `assert`-based shell check (no framework) that fails if mode resolution or the appearance mapping breaks.

## Out of scope (later phases)

- Spotify Web API / OAuth: search, recommendations, queue, device selection, playlist creation.
- MCP server (conversational control: "play my focus playlist and dim the volume").
- Detecting the currently-playing playlist (needs Web API).
- Non-macOS platforms.
