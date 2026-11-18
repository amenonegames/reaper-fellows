# Development checks

REAPER and ReaImGui are mocked so the panel's logic can be run from a terminal
(Lua 5.3 or newer):

    lua "$(pwd)/dev/run_test.lua" "$(pwd)/dev/fakeclaude"

Use absolute paths, as above. `fakeclaude` stands in for the Claude Code CLI and
streams a canned reply; pass the path of the real `claude` instead to check that
the command line the panel builds is accepted.

This covers context building, the request lifecycle and stream parsing. It does
not cover the real ReaImGui rendering or the Windows batch launcher.
