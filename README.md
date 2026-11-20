# reaper-fellows

Tools that bring Claude into [REAPER](https://www.reaper.fm/).

| Tool | Folder | What it is |
| --- | --- | --- |
| [Claude Panel](#claude-panel) | repository root | Chat with Claude inside REAPER, and let it act on the project |
| [ChordGuide](#chordguide) | [`ChordGuide/`](ChordGuide) | Chord tone guides and snapping in the MIDI editor. Plain ReaScript; does not use Claude |

## Claude Panel

A dockable chat window inside REAPER. Each message carries a text description of
what is selected -- tracks, items, MIDI notes, the time selection -- so you can ask
about the project in front of you without describing it first.

It talks to Claude through the [Claude Code](https://claude.com/claude-code) command
line (`claude -p`), signed in with your Claude plan. No API key is involved.

**Status: 0.2.0.** The chat panel (0.1.x) is confirmed working in REAPER on Windows.
Acting on the project (0.2.0) is checked end to end against a mocked REAPER and the
real MCP server, and the real Claude Code CLI connects to that server -- but it has
not yet run inside a real REAPER. Save your project before trying it.

### What it does

- Chat with Claude; replies stream in as they are written, and the conversation
  continues across messages until you press **New chat**
- Attaches the current selection to each message. The **Attached** button at the top
  shows exactly what will be sent, and lets you choose what is included:
  selected tracks (volume, pan, FX chain), selected items, MIDI notes (up to 400
  per message), markers and regions, an overview of all tracks
- If notes are selected in the MIDI editor, those notes are what gets listed
- Choice dialogs: when Claude needs you to pick between options it can show
  buttons (pick one) or checkboxes (pick several); your pick is sent as the next
  message. You can always type a reply instead
- Code in replies is set in monospace with its own Copy button
- Optional web search

### Acting on the project

With Node.js installed, Claude can also work in the project. The panel ships a small
MCP server (`reaper_mcp_server.js`) that Claude Code starts for each message; it gives
Claude four tools:

| Tool | What it does |
| --- | --- |
| `get_selection` | Reads the project state again (after a change, for example) |
| `find_api` | Looks up which ReaScript functions exist in your REAPER, extensions included |
| `run_lua` | Runs a ReaScript (Lua) in REAPER. This is how anything gets changed |
| `ask_user` | Asks you a question in the panel and waits, with buttons or checkboxes |

How edits are handled:

- **Each script is one undo step**, named `Claude: <what it does>`. Ctrl+Z takes it
  back; the newest script also has an **Undo** button in the panel for as long as
  it is still the latest undo step
- Scripts run **without asking** by default. **Settings > Ask me before each change**
  shows each script with **Run** / **Skip** first
- **Settings > Let Claude change the project** turns all of this off; the panel is
  then read-only, as in 0.1
- Every script that ran is listed in the conversation with **Show script**
- The line under the input always says which mode is active: `Edits: on`,
  `Edits: ask first` or `Edits: off`

Scripts run on REAPER's main thread, are stopped after 10 seconds, and have no `io`,
`os.execute`, `require` or `reaper.ExecProcess`. That keeps a script from wandering
into the file system by accident; it is not a security boundary. The full ReaScript
API is available to them, so a script can delete or overwrite things in the project.
Undo is the safety net -- and a saved project.

### Requirements

- REAPER 7 (6.x probably works)
- [ReaImGui](https://github.com/cfillion/reaimgui) 0.9 or newer -- install it from ReaPack
- Claude Code installed and signed in: running `claude` in a terminal must work
- [Node.js](https://nodejs.org/) 16 or newer, for acting on the project (the chat
  works without it)

### Install

1. **Extensions > ReaPack > Import repositories...** and paste
   `https://raw.githubusercontent.com/amenonegames/reaper-fellows/main/index.xml`
2. **Extensions > ReaPack > Browse packages**, search "Claude Panel", install
3. **Actions > Show action list**, run **Script: ClaudePanel.lua**

Press **Settings** in the panel, then **Test**. It should print the Claude Code
version. If it does not, put the full path of the `claude` executable in
**Claude Code command** (on Windows, `where claude` in a terminal prints it). The
second **Test** button, under *Acting on the project*, does the same for `node`.

### Usage

Select something in REAPER, type a question, press **Send** or **Ctrl+Enter**.

### Notes

- Usage counts against your Claude plan's limits, like any other Claude Code use.
  A large selection makes each message bigger.
- Requests run in `<REAPER resource path>/Data/ClaudePanel`, where the prompt and
  the reply of the latest request are kept as plain files. Tool calls travel through
  the `bridge` folder inside it: the MCP server cannot reach REAPER itself, so it
  writes each call as a file and the panel answers with another.
- Typing Japanese (or any IME input) on Windows shows the text being composed in a
  separate box until it is confirmed. That box is drawn by ReaImGui, which hands
  composition to the system IME window; the panel cannot draw it inline.
- If Japanese text shows as boxes, set **font** in Settings to a font that has the
  glyphs (for example `Yu Gothic UI`) and reopen the panel.
- macOS and Linux code paths exist but are untested.

## ChordGuide

Shows the chord tones of your chord progression as colored bands in the MIDI editor
piano roll, and moves notes onto them. It lives in [`ChordGuide/`](ChordGuide) and is
independent of Claude Panel: plain ReaScript, no Claude involved.

**Status: 0.1.0, not yet run inside a real REAPER.** Chord name parsing and the band
geometry are checked against a mocked REAPER (`dev/run_chordguide_test.lua`). The
pixel positions rest on assumptions about the MIDI editor layout (see
[Calibration](#calibration)), so expect to adjust them.

### What it does

- **Bands per chord**: for each chord's time range, the root is drawn in orange and
  the other chord tones in blue, across all octaves
- **Scale**: if key snap is on in the MIDI editor, its scale tones get a faint band
- **Three actions** for selected notes: move to the chord tone above, to the chord
  tone below, or snap to the nearest one (a tie goes down). Each note uses the chord
  it overlaps the most, not the cursor position

### Where chords come from

Chords are read in the notation of FeedTheCat's
[Lil Chordbox](https://github.com/iliaspoulakis/Reaper-Tools), which can write the
chords of a MIDI item to a chord track or to project regions:

1. the chord track -- a track named `Chords` (or the name set in Lil Chordbox) with
   empty items whose notes hold the chord name
2. project regions named after chords, if there is no chord track with items

Both of Lil Chordbox's notation styles are understood (`CM7` / `Cmaj7`), with
inversions (`Am7/G`) and scale degrees (`Am7 - vi`), plus common hand-typed spellings
(`C△7`, `Dm7-5`, `Cadd9`). Names that are not chords are ignored.

### Requirements

- REAPER 7 (6.x probably works)
- [js_ReaScriptAPI](https://github.com/juliansader/js_ReaScriptAPI) -- install it
  from ReaPack

### Install

1. Import this repository in ReaPack, as described for
   [Claude Panel](#install), if you have not already
2. **Extensions > ReaPack > Browse packages**, search "ChordGuide", install
3. In the action list, the **MIDI Editor** section now has:
   - **Script: ChordGuide.lua** -- starts the bands; run it again to stop
   - the three **Script: ChordGuide - ...** actions

ReaPack puts the files in `Scripts/reaper-fellows/ChordGuide/`.

### Calibration

Settings are at the top of `ChordGuide_lib.lua` (`CG.config`): colors, the chord
source, and pixel corrections. A ReaPack update of ChordGuide overwrites that file,
so note your values.

- Bands shifted vertically: set `ruler_height` (assumed 62 px at 100 % scaling) or
  `y_offset`
- Bands shifted horizontally: `x_offset`
- Bands lag behind scrolling: lower `poll_interval`

### Limits

- Bands are drawn only in the piano roll with **all note rows shown**. With unused
  rows hidden, or in other editor modes, they are switched off
- Regions named like a section letter (`A`, `B`) read as chords. Use the chord track
  to avoid this
- Solfege note names (`Do`, `Re`) are not supported

The chord name table and the way the editor view is read come from Lil Chordbox and
MIDI Editor Magic (MIT License, Copyright (c) 2020 iliaspoulakis).

## License

MIT
