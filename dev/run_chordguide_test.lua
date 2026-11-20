-- Checks for ChordGuide: chord name parsing, settings and overlay geometry.
-- REAPER and js_ReaScriptAPI are mocked. Usage (absolute path):
--   lua "$(pwd)/dev/run_chordguide_test.lua"
local root = arg[0]:match('^(.*)[\\/]dev[\\/][^\\/]*$')
if not root then error('Run with an absolute path to this file') end
local dir = root .. '/ChordGuide/'

local failures = 0
local function Check(cond, msg)
    if not cond then
        failures = failures + 1
        print('FAIL: ' .. msg)
    end
end

local fills = {}
local state = {time = 0, cursor = 1, ext = {}}
local items = {
    {0, 2, 'CM7 - I'}, {2, 2, 'Am7/G'}, {4, 2, 'F6/9'}, {6, 2, 'G7b9(no5)'},
    {8, 2, 'Chorus'},
}
-- One take: 10 px per 100 ppq, top row = pitch 72, rows 12 px high,
-- two CC lanes (120 + 80 px). 1920 ppq per second
local chunk = '<ITEM\nNAME x\n<SOURCE MIDI\nE 0 90 3c 60\n' ..
    'CFGEDIT 1 1 0 1 0 0 1 1 1 1 1 0.25 0 0 1920 1080 0 0 0 0 0 0 0 0 0 ' ..
    '0.5 0 0 1 64\nCFGEDITVIEW 0 0.1 55 12 0 -1 0 0 0 0.5\n' ..
    'VELLANE -1 120 0\nVELLANE 1 80 0\n>\n>\n'

reaper = setmetatable({
    GetExtState = function(section, key)
        return state.ext[section .. '/' .. key] or ''
    end,
    SetExtState = function(section, key, value)
        state.ext[section .. '/' .. key] = value
    end,
    GetPlayState = function() return 0 end,
    GetCursorPosition = function() return state.cursor end,
    CountTracks = function() return 1 end,
    GetTrack = function() return 'TRACK' end,
    GetTrackName = function() return true, 'Chords' end,
    CountTrackMediaItems = function() return #items end,
    GetTrackMediaItem = function(_, i) return items[i + 1] end,
    GetMediaItemInfo_Value = function(item, key)
        return key == 'D_POSITION' and item[1] or item[2]
    end,
    GetSetMediaItemInfo_String = function(item) return true, item[3] end,
    JS_Composite = function() return 1 end,
    JS_Composite_Delay = function() end,
    JS_Composite_Unlink = function() end,
    set_action_options = function() end,
    get_action_context = function() return true, 'x', 32060, 1 end,
    GetOS = function() return 'Win64' end,
    SetToggleCommandState = function() end,
    RefreshToolbar2 = function() end,
    atexit = function(f) state.exit = f end,
    defer = function(f) state.main = f end,
    MIDIEditor_GetActive = function() return 'HWND' end,
    JS_Window_FindChildByID = function(_, id) return 'child' .. id end,
    time_precise = function()
        state.time = state.time + 1
        return state.time
    end,
    MIDIEditor_GetTake = function() return 'TAKE' end,
    ValidatePtr = function() return true end,
    MIDIEditor_GetMode = function() return 0 end,
    GetToggleCommandStateEx = function() return 1 end,
    GetMediaItemTake_Item = function() return 'ITEM' end,
    GetItemStateChunk = function() return true, chunk end,
    GetMediaItemTakeInfo_Value = function() return 0 end,
    JS_Window_GetClientSize = function(view)
        if view == 'child1003' then return true, 150, 800 end
        return true, 1000, 800
    end,
    MIDI_GetScale = function() return true, 0, 0xAB5 end,
    GetProjectStateChangeCount = function() return 1 end,
    -- Bitmaps are named after their size: 150 px wide = keyboard
    JS_LICE_CreateBitmap = function(_, w) return w == 150 and 'keys' or 'notes' end,
    JS_LICE_DestroyBitmap = function() end,
    JS_LICE_Clear = function(bitmap) fills[bitmap] = {} end,
    JS_LICE_FillRect = function(bitmap, x, y, w, h, color)
        local list = fills[bitmap]
        list[#list + 1] = {x = x, y = y, w = w, h = h, color = color}
    end,
    JS_Window_InvalidateRect = function() end,
    MIDI_GetProjTimeFromPPQPos = function(_, ppq) return ppq / 1920 end,
    MIDI_GetPPQPosFromProjTime = function(_, time) return time * 1920 end,
}, {__index = function(_, key) error('unmocked reaper.' .. key) end})

local CG = dofile(dir .. 'ChordGuide_lib.lua')

-- 1. Every name of the chord table, in both styles, on every root,
--    with inversion and with scale degree
local file = assert(io.open(dir .. 'ChordGuide_lib.lua'))
local source = file:read('a')
file:close()
local roots = {'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'}
local pattern = "chord_names%['([%d ]+)'%] = {expanded = '([^']*)', " ..
    "compact = '([^']*)'}"
local cnt = 0
for key, expanded, compact in source:gmatch(pattern) do
    for _, add in ipairs {expanded, compact} do
        for root = 0, 11 do
            local name = roots[root + 1] .. add
            if key == '1' then name = roots[root + 1] .. '4' .. add end
            local bass = (root + 7) % 12
            local inv = CG.ParseChord(name .. '/' .. roots[bass + 1])
            local deg = CG.ParseChord(name .. ' - IV')
            local ok = deg and deg.is_known and deg.root == root and inv and
                inv.bass == bass
            local want = {}
            for n in key:gmatch('%d+') do want[(root + n - 1) % 12] = true end
            for pc = 0, 11 do
                if ok and (deg.pcs[pc] or false) ~= (want[pc] or false) then
                    ok = false
                end
            end
            cnt = cnt + 1
            Check(ok, 'round trip of "' .. name .. '" (' .. key .. ')')
        end
    end
end
Check(cnt > 2000, 'chord table was not found in the lib')

-- 2. Option variants, hand-typed names and non-chords
local function Pcs(text)
    local chord = CG.ParseChord(text)
    if not chord then return 'nil' end
    local list = {}
    for pc = 0, 11 do if chord.pcs[pc] then list[#list + 1] = pc end end
    return table.concat(list, ',') .. (chord.is_known and '' or '?')
end
local cases = {
    {'C', '0,4,7'}, {'Cmaj', '0,4,7'}, {'C add9', '0,2,4,7'},
    {'Cadd9', '0,2,4,7'}, {'F#m7b5', '0,4,6,9'}, {'Bb△7', '2,5,9,10'},
    {'Dm7-5', '0,2,5,8'}, {'G7sus', '0,2,5,7'}, {'C6/9', '0,2,4,7,9'},
    {'Cm6/9/Eb', '0,2,3,7,9'}, {'E♭M7', '2,3,7,10'}, {'Asus4/D', '2,4,9'},
    {'C m6', '0,8'}, {'Cm6', '0,3,7,9'}, {'D major 3rd', '2,6'},
    {'C4 note', '0'}, {'Verse 1', 'nil'}, {'Intro', 'nil'}, {'vi', 'nil'},
    {'Chorus', '0?'}, {'Bridge', '11?'},
}
for _, case in ipairs(cases) do
    local got = Pcs(case[1])
    Check(got == case[2], ('"%s": expected %s, got %s'):format(case[1],
        case[2], got))
end

-- 3. Target pitches
local c_major = {[0] = true, [4] = true, [7] = true}
Check(CG.GetTargetPitch(61, c_major, 'up') == 64, 'up from 61')
Check(CG.GetTargetPitch(61, c_major, 'down') == 60, 'down from 61')
Check(CG.GetTargetPitch(62, c_major, 'nearest') == 60, 'nearest tie goes down')
Check(CG.GetTargetPitch(64, c_major, 'nearest') == nil, 'chord tone stays')
Check(CG.GetTargetPitch(64, c_major, 'up') == 67, 'up from chord tone')

-- 4. Unparseable names are not used as chords
Check(#CG.GetChordSegments(0, 100) == 4, 'segment count')

-- 5. Settings changed by actions
Check(CG.GetDisplayMode() == 'keys', 'default display mode')
Check(CG.CycleDisplayMode() == 'notes', 'cycle to notes')
Check(CG.CycleDisplayMode() == 'both', 'cycle to both')
Check(CG.Nudge(1) == 1 and CG.Nudge(-1) == 0, 'nudge')
Check(CG.GetChordAt(1).name == 'CM7', 'chord at 1 s')
Check(CG.GetChordAt(2).name == 'Am7/G', 'chord at boundary')
Check(CG.GetChordAt(9) == nil, 'no chord at 9 s')

-- 6. Overlay geometry (ruler 80 px, CC lanes 200 px, rows 12 px,
--    top row = pitch 72), display mode 'both'
dofile(dir .. 'ChordGuide.lua')
state.main()

local function Summarize(list)
    local sum = {min_y = math.huge, max_y = 0, spans = {}, rows = {}}
    for _, fill in ipairs(list or {}) do
        sum.min_y = math.min(sum.min_y, fill.y)
        sum.max_y = math.max(sum.max_y, fill.y + fill.h)
        sum.spans[fill.x .. '+' .. fill.w] = true
        sum.rows[fill.y] = fill.color
    end
    return sum
end

local notes = Summarize(fills.notes)
Check(notes.min_y == 80, 'bands start below the ruler, got ' .. notes.min_y)
Check(notes.max_y == 600, 'bands end above the CC lanes, got ' .. notes.max_y)
-- Chords last 2 s = 3840 ppq = 384 px, the view ends at 1000 px
Check(notes.spans['0+384'] and notes.spans['384+384'] and
    notes.spans['768+232'], 'chord band positions')
Check(notes.spans['0+1000'], 'scale bands span the view')

-- Keyboard, cursor at 1 s = CM7: C5 is the top row, B4 the next one
local keys = Summarize(fills.keys)
local root_color, chord_color, scale_color = 0x9E9E4B10, 0x7A0E4A7A, 0x330A2715
Check(keys.spans['0+150'], 'key bands span the keyboard')
Check(keys.rows[80] == root_color, 'C5 is drawn as root')
Check(keys.rows[92] == chord_color, 'B4 is drawn as chord tone')
Check(keys.rows[104] == nil, 'Bb4 is not drawn')
Check(keys.rows[116] == scale_color, 'A4 is drawn as scale tone')
Check(keys.max_y == 600, 'key bands end above the CC lanes')

-- Nothing is redrawn without a change
local prev_keys, prev_notes = fills.keys, fills.notes
state.main()
Check(fills.keys == prev_keys and fills.notes == prev_notes,
    'redraw without a change')

-- Moving the cursor to Am7/G redraws the keyboard only
state.cursor = 3
state.main()
Check(fills.keys ~= prev_keys and fills.notes == prev_notes,
    'cursor move redraws keyboard only')
keys = Summarize(fills.keys)
Check(keys.rows[80] == chord_color, 'C5 is a chord tone of Am7')
Check(keys.rows[116] == root_color, 'A4 is the root of Am7')

-- Nudging moves the rows, display mode 'keys' clears the note area
CG.Nudge(3)
CG.CycleDisplayMode()
Check(CG.GetDisplayMode() == 'keys', 'cycle back to keys')
state.main()
keys = Summarize(fills.keys)
Check(keys.min_y == 83, 'nudge moves the rows, got ' .. keys.min_y)
Check(#fills.notes == 0, 'note area is cleared in keys mode')
state.exit()

if failures > 0 then
    print(failures .. ' check(s) failed')
    os.exit(1)
end
print('ChordGuide: all checks passed (' .. cnt .. ' chord names)')
