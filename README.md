# reaper-fellows

Tools that bring Claude into [REAPER](https://www.reaper.fm/).

## Claude Panel

A dockable chat window inside REAPER. Each message carries a text description of
what is selected -- tracks, items, MIDI notes, the time selection -- so you can ask
about the project in front of you without describing it first.

It talks to Claude through the [Claude Code](https://claude.com/claude-code) command
line (`claude -p`), signed in with your Claude plan. No API key is involved.

**Status: 0.1.1.** 0.1.0 was confirmed working in REAPER on Windows. The 0.1.1
redesign and the choice dialogs are checked against a mocked REAPER only (see `dev/`).

### What 0.1 does

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
- Read-only: Claude cannot change the project. Operating REAPER through MCP is
  planned for 0.2

### Requirements

- REAPER 7 (6.x probably works)
- [ReaImGui](https://github.com/cfillion/reaimgui) 0.9 or newer -- install it from ReaPack
- Claude Code installed and signed in: running `claude` in a terminal must work

### Install

1. **Extensions > ReaPack > Import repositories...** and paste
   `https://raw.githubusercontent.com/amenonegames/reaper-fellows/main/index.xml`
2. **Extensions > ReaPack > Browse packages**, search "Claude Panel", install
3. **Actions > Show action list**, run **Script: ClaudePanel.lua**

Press **Settings** in the panel, then **Test**. It should print the Claude Code
version. If it does not, put the full path of the `claude` executable in
**claude path** (on Windows, `where claude` in a terminal prints it).

### Usage

Select something in REAPER, type a question, press **Send** or **Ctrl+Enter**.

### Notes

- Usage counts against your Claude plan's limits, like any other Claude Code use.
  A large selection makes each message bigger.
- Requests run in `<REAPER resource path>/Data/ClaudePanel`, where the prompt and
  the reply of the latest request are kept as plain files.
- Typing Japanese (or any IME input) on Windows shows the text being composed in a
  separate box until it is confirmed. That box is drawn by ReaImGui, which hands
  composition to the system IME window; the panel cannot draw it inline.
- If Japanese text shows as boxes, set **font** in Settings to a font that has the
  glyphs (for example `Yu Gothic UI`) and reopen the panel.
- macOS and Linux code paths exist but are untested.

## License

MIT
