local here = arg[0]:match("^(.*)/[^/]*$") or "."
local M = dofile(here .. "/mock.lua")
local claude = arg[1]
M.ext.claude_path = claude; M.ext.inc_markers = "1"
os.execute('rm -rf "' .. here .. '/res"')
local src = io.open(here .. "/../ClaudePanel.lua"):read("a")
src = src:gsub("reaper%.defer%(loop%)%s*$", "reaper.defer(loop)\nreturn { chat = chat, messageText = messageText, buildContext = buildContext, json = json, getReq = function() return req end, testClaude = testClaude }")
local P = assert(load(src, "@" .. here .. "/../ClaudePanel.lua"))()
print("ReaImGui API requested: " .. tostring(M.apiVersion))
M.step(2)
print("--- context ---"); print((P.buildContext()))
local function ask(text, label)
  M.input = text; M.step(1); M.press["Send"] = true; M.step(1)
  local t0, statuses = os.time(), {}
  while P.getReq() and os.time() - t0 < 60 do
    local s = P.getReq().status; if statuses[#statuses] ~= s then statuses[#statuses+1] = s end
    M.sleep(0.05); M.step(1)
  end
  local m = P.chat.messages[#P.chat.messages]
  print("--- " .. label .. " ---")
  print("statuses: " .. table.concat(statuses, " > "))
  print("role=" .. m.role .. " session=" .. tostring(P.chat.sessionId) .. " messages=" .. #P.chat.messages)
  print("text: " .. P.messageText(m):sub(1, 300))
end
ask("この選択のコード進行を教えて", "first message")
print("user message context label: " .. tostring(P.chat.messages[1].context))
ask("second question", "second message (should resume)")

-- Choice dialogs: single choice answers on one click, multiple choice is ticked then sent
local function waitIdle() local t0 = os.time(); while P.getReq() and os.time() - t0 < 30 do M.sleep(0.05); M.step(1) end end
local function lastUser() for i = #P.chat.messages, 1, -1 do if P.chat.messages[i].role == "user" then return P.chat.messages[i].text end end end
ask("ASKME", "single choice dialog")
M.drawn = {}; M.step(1)
print("buttons shown: Verse=" .. tostring(M.drawn["Verse"]) .. " Chorus=" .. tostring(M.drawn["Chorus"]) .. " question=" .. tostring(M.drawn["Which section?"]))
M.press["Chorus"] = true; M.step(1); waitIdle()
print("answer sent as: " .. tostring(lastUser()))
ask("ASKMULTI", "multiple choice dialog")
M.tick["EQ"] = true; M.tick["Reverb"] = true; M.step(1)
M.press["Send choice"] = true; M.step(1); waitIdle()
print("answer sent as: " .. tostring(lastUser()))
M.drawn = {}; M.step(1); print("old dialog shows the pick: " .. tostring(M.drawn["You answered: EQ, Reverb"]))
print("--- test button ---"); print(P.testClaude())
