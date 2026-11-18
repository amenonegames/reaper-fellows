-- End-to-end check of acting on the project: panel <-> bridge files <-> the real
-- MCP server, driven by a stand-in CLI that speaks MCP (fakeclaude_mcp.js).
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local M = dofile(here .. "/mock.lua")
M.ext.claude_path = here .. "/fakeclaude_mcp"
if arg[1] == "confirm" then M.ext.confirm_edits = "1" end
os.execute('rm -rf "' .. here .. '/res"')
local path = here .. "/../ClaudePanel.lua"
local src = io.open(path):read("a")
src = src:gsub("reaper%.defer%(loop%)%s*$", "reaper.defer(loop)\nreturn { chat = chat, messageText = messageText, getReq = function() return req end, bridge = bridge }")
local P = assert(load(src, "@" .. path))()
M.step(2)
M.input = arg[1] == "confirm" and "CONFIRM please" or "do things"; M.step(1); M.press["Send"] = true; M.step(1)
local t0 = os.time()
local answered = {}
while P.getReq() and os.time() - t0 < 60 do
  M.sleep(0.03); M.drawn = {}; M.step(1)
  local p = P.bridge.pending
  if p and p.kind == "ask" and not answered[p.id] then
    answered[p.id] = true
    if #p.entry.dialog.options > 0 then M.press["Chorus"] = true
    else M.input = "Bass line"; M.step(1); M.press["Send"] = true end
  elseif p and p.kind == "confirm" and not answered[p.id] then
    answered[p.id] = true
    print("waiting for approval, Run button shown: " .. tostring(M.drawn["Run"]) .. ", undo steps so far: " .. tostring(M.undo or 0))
    M.press["Run"] = true
  end
end
print("request finished: " .. tostring(P.getReq() == nil))
for i, m in ipairs(P.chat.messages) do
  if m.role == "action" then print(i, "action", m.state, m.description, "| undo name:", m.undoName)
  elseif m.role == "ask" then print(i, "ask", m.dialog.question, "->", tostring(m.dialog.answer))
  else print(i, m.role, (P.messageText(m):gsub("\n", "\n      "))) end
end
print("undo blocks opened: " .. tostring(M.undo) .. ", last undo name: " .. tostring(M.lastUndo))
-- Undo button on the newest script that ran cleanly
M.drawn = {}; M.step(1)
print("Undo offered on the newest action: " .. tostring(M.drawn["Undo"]))
