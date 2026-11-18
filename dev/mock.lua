-- Mock of REAPER + ReaImGui, enough to run ClaudePanel.lua headless on Linux.
local M = { frames = {}, press = {}, ext = {}, input = nil, opened = true }
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local function now() return os.gettimeofday and os.gettimeofday() or os.time() end

local imgui = setmetatable({}, { __index = function(t, k)
  if k:match("^%u%a*_") then return 1 end           -- constants: Col_Text, Mod_Ctrl ...
  local fns = {
    Begin = function() return true, M.opened end,
    BeginChild = function() return true end, CollapsingHeader = function() return true end,
    BeginCombo = function() return true end, Selectable = function() return false end,
    Checkbox = function(_, _, v) return false, v end,
    InputText = function(_, _, buf) return false, buf end,
    InputTextMultiline = function(_, _, buf) if M.input then local v = M.input; M.input = nil; return true, v end return false, buf end,
    Button = function(_, label) if M.press[label] then M.press[label] = nil; return true end return false end,
    GetContentRegionAvail = function() return 460, 600 end,
    GetKeyMods = function() return 0 end, IsKeyPressed = function() return false end,
    IsWindowFocused = function() return true end,
    CreateContext = function() return {} end, CreateFont = function() return {} end,
  }
  fns.SmallButton = fns.Button
  return fns[k] or function() end
end })
package.preload["imgui"] = function() return function(version) M.apiVersion = version; return imgui end end

local notes = { {true,false,0,480,0,60,96}, {false,false,480,960,0,63,90}, {true,true,960,1920,1,67,80} }
local R = {
  ImGui_GetBuiltinPath = function() return "." end,
  GetOS = function() return "Other" end,
  GetResourcePath = function() return here .. "/res" end,
  RecursiveCreateDirectory = function(p) os.execute('mkdir -p "' .. p .. '"') end,
  HasExtState = function(_, k) return M.ext[k] ~= nil end,
  GetExtState = function(_, k) return M.ext[k] end,
  SetExtState = function(_, k, v) M.ext[k] = v end,
  time_precise = now, defer = function(f) M.frames[#M.frames+1] = f end,
  MB = function(msg) print("MB: " .. msg) end,
  ExecProcess = function(cmd, timeout)
    M.lastExec = cmd
    if timeout < 0 then os.execute(cmd .. " &"); return "0\n" end
    local p = io.popen(cmd); local out = p:read("a"); local ok, _, code = p:close()
    return tostring(code or 0) .. "\n" .. out
  end,
  format_timestr_pos = function(t) return string.format("%d.%d.00", math.floor(t/2)+1, math.floor(t*2)%4+1) end,
  GetProjectName = function() return "song.rpp" end, GetCursorPosition = function() return 4 end,
  TimeMap_GetTimeSigAtTime = function() return 4, 4, 120 end, GetPlayState = function() return 0 end,
  GetSet_LoopTimeRange = function() return 2, 6 end, CountTracks = function() return 2 end,
  CountSelectedTracks = function() return 1 end, GetSelectedTrack = function() return "T1" end,
  GetTrack = function(_, i) return "T" .. (i+1) end,
  GetTrackName = function(tr) return true, tr == "T1" and "Piano \227\131\148\227\130\162\227\131\142" or "Bass" end,
  GetMediaTrackInfo_Value = function(tr, k) local v = { IP_TRACKNUMBER = tr == "T1" and 1 or 2, D_VOL = 0.5, D_PAN = -0.25, B_MUTE = 0, I_SOLO = 0, I_RECARM = 1, I_FOLDERDEPTH = 0 } return v[k] end,
  CountTrackMediaItems = function() return 2 end, TrackFX_GetCount = function() return 2 end,
  TrackFX_GetFXName = function(_, i) return true, i == 0 and "VST3i: Pianoteq" or "VST: ReaEQ (Cockos)" end,
  TrackFX_GetEnabled = function(_, i) return i == 0 end,
  CountSelectedMediaItems = function() return 2 end, GetSelectedMediaItem = function(_, i) return "I" .. i end,
  GetMediaItemInfo_Value = function(_, k) return ({ D_POSITION = 2, D_LENGTH = 4, B_MUTE = 0 })[k] end,
  GetActiveTake = function(it) return it == "I0" and "MIDITAKE" or "AUDIOTAKE" end,
  GetMediaItem_Track = function() return "T1" end, TakeIsMIDI = function(tk) return tk == "MIDITAKE" end,
  GetTakeName = function(tk) return tk == "MIDITAKE" and "chords" or "vox.wav" end,
  MIDI_CountEvts = function() return true, #notes, 0, 0 end,
  MIDI_GetNote = function(_, i) local n = notes[i+1]; return true, n[1], n[2], n[3], n[4], n[5], n[6], n[7] end,
  MIDI_GetProjQNFromPPQPos = function(_, ppq) return ppq / 480 end,
  MIDI_GetProjTimeFromPPQPos = function(_, ppq) return 2 + ppq / 960 end,
  GetMediaItemTake_Source = function() return "SRC" end,
  GetMediaSourceFileName = function() return "C:\\audio\\takes\\vox.wav" end,
  GetMediaItemTakeInfo_Value = function(_, k) return k == "D_PLAYRATE" and 1 or -2 end,
  MIDIEditor_GetActive = function() return M.editor end, MIDIEditor_GetTake = function() return "MIDITAKE" end,
  ValidatePtr = function() return true end, GetMediaItemTake_Item = function() return "I0" end,
  IsMediaItemSelected = function() return true end,
  CountProjectMarkers = function() return 2, 1, 1 end,
  EnumProjectMarkers = function(i) if i == 0 then return 1, false, 0, 0, "Intro", 1 end return 2, true, 2, 10, "Verse", 1 end,
}
reaper = setmetatable(R, { __index = function(_, k) error("reaper." .. k .. " is not mocked", 2) end })
function M.step(n) for _ = 1, (n or 1) do local f = table.remove(M.frames, 1); if f then f() end end end
function M.sleep(s) os.execute("sleep " .. s) end
return M
