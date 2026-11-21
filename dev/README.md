# Development checks

REAPER and ReaImGui are mocked so the panel's logic can be run from a terminal
(Lua 5.3 or newer):

    lua "$(pwd)/dev/run_test.lua" "$(pwd)/dev/fakeclaude"

Use absolute paths, as above. `fakeclaude` stands in for the Claude Code CLI and
streams a canned reply; pass the path of the real `claude` instead to check that
the command line the panel builds is accepted.

Acting on the project is checked end to end with the real MCP server:

    lua "$(pwd)/dev/run_mcp_test.lua"            # scripts run straight away
    lua "$(pwd)/dev/run_mcp_test.lua" confirm    # ask-first mode

`fakeclaude_mcp.js` plays the CLI here: it starts `reaper_mcp_server.js` from the
config the panel wrote, calls every tool and reports what came back. Needs Node.js.

This covers context building, the request lifecycle, stream parsing, the bridge
and tool execution. It does not cover the real ReaImGui rendering, the Windows
batch launcher, or what the real ReaScript API does with a script.

## ChordGuide

    lua "$(pwd)/dev/run_chordguide_test.lua"

Checks chord name parsing against every name in the chord table, the note target
logic, the settings changed by actions, and the keyboard and note area geometry with
REAPER and js_ReaScriptAPI mocked. It does not
cover what the real MIDI editor looks like: ruler height, CC lane heights and
UI scaling are assumptions until checked in REAPER.
