--[[
  @description ChordGuide - Highlight chord tones in MIDI editor
  @author amenonegames
  @license MIT
  @version 0.1.0
  @provides
    [main=main,midi_editor] .
    [nomain] ChordGuide_lib.lua
    [main=midi_editor] ChordGuide - Move selected notes to chord tone above.lua
    [main=midi_editor] ChordGuide - Move selected notes to chord tone below.lua
    [main=midi_editor] ChordGuide - Snap selected notes to nearest chord tone.lua
  @about
    Highlights the chord tones of the chord track (or project regions) and
    the key snap scale as colored bands in the MIDI editor piano roll.

    Chords are read in the notation of FeedTheCat's Lil Chordbox.
    Requires js_ReaScriptAPI. Settings are at the top of the lib file.

    Editor view parsing is based on FeedTheCat's Lil Chordbox / MIDI Editor
    Magic (MIT License, Copyright (c) 2020 iliaspoulakis)
]]
local dir = debug.getinfo(1, 'S').source:match('^@?(.*[\\/])')
local CG = dofile(dir .. 'ChordGuide_lib.lua')
local config = CG.config

if not reaper.JS_Composite then
    reaper.MB('Please install js_ReaScriptAPI extension', 'ChordGuide', 0)
    if reaper.ReaPack_BrowsePackages then
        reaper.ReaPack_BrowsePackages('js_ReaScriptAPI')
    end
    return
end

-- Running the action again terminates the script (toggle behavior)
if reaper.set_action_options then reaper.set_action_options(1) end

local _, _, sec, cmd = reaper.get_action_context()

local os_name = reaper.GetOS()
local is_windows = os_name:match('Win')
local is_macos = os_name:match('OSX') or os_name:match('macOS')
-- Width of the piano pane at 100% scaling (used to detect UI scaling)
local piano_pane_scale1_w = is_windows and 128 or is_macos and 145 or 161
-- Height of the ruler at the top of the notes view at 100% scaling
local ruler_scale1_h = 62

local midi_editor_section = 32060
local cmd_show_all_rows = 40452

local bitmap
local bitmap_w, bitmap_h
local composite_view

local prev_hwnd
local notes_view
local piano_pane
local prev_poll_time
local prev_signature

local function Premultiply(color)
    local rgb, opacity = color[1], color[2]
    local a = math.floor(opacity * 255 + 0.5)
    local r = ((rgb >> 16) & 0xFF) * a // 255
    local g = ((rgb >> 8) & 0xFF) * a // 255
    local b = (rgb & 0xFF) * a // 255
    return (a << 24) | (r << 16) | (g << 8) | b
end

local function GetTakeChunk(take)
    local item = reaper.GetMediaItemTake_Item(take)
    local _, item_chunk = reaper.GetItemStateChunk(item, '', false)
    local tk = reaper.GetMediaItemTakeInfo_Value(take, 'IP_TAKENUMBER')

    local take_start_ptr = 0
    local take_end_ptr = 0
    for _ = 0, tk do
        take_start_ptr = take_end_ptr
        if take_start_ptr then
            take_end_ptr = item_chunk:find('\nTAKE[%s\n]', take_start_ptr + 1)
        end
    end
    if not take_start_ptr then return end
    return item_chunk:sub(take_start_ptr, take_end_ptr)
end

-- Reads scroll/zoom state of the piano roll from the take chunk
local function GetEditorView(take)
    local chunk = GetTakeChunk(take)
    if not chunk then return end

    local start_ppq, hzoom, voffset, row_h =
        chunk:match('CFGEDITVIEW (%S+) (%S+) (%S+) (%S+)')
    if not row_h then return end

    local view = {}
    view.start_ppq = tonumber(start_ppq)
    view.hzoom = tonumber(hzoom)
    view.top_pitch = 127 - tonumber(voffset)
    view.row_h = tonumber(row_h)
    -- 0 = Beats (proj) 1 = Project synced 2 = Time (proj) 4 = Beats (source)
    view.timebase = tonumber(chunk:match('CFGEDIT ' .. ('%S+ '):rep(18) ..
        '(%S+)')) or 0
    -- Total height of CC lanes at the bottom of the view
    view.lanes_h = 0
    for lane_h in chunk:gmatch('\nVELLANE %S+ (%d+)') do
        view.lanes_h = view.lanes_h + tonumber(lane_h)
    end
    return view
end

local function ReleaseBitmap()
    if bitmap then
        if composite_view and reaper.ValidatePtr(composite_view, 'HWND*') then
            reaper.JS_Composite_Unlink(composite_view, bitmap)
            reaper.JS_Window_InvalidateRect(composite_view, 0, 0, bitmap_w,
                bitmap_h, false)
        end
        reaper.JS_LICE_DestroyBitmap(bitmap)
    end
    bitmap = nil
    composite_view = nil
end

local function PrepareBitmap(w, h)
    if bitmap and w == bitmap_w and h == bitmap_h and
        composite_view == notes_view then
        return
    end
    ReleaseBitmap()
    bitmap = reaper.JS_LICE_CreateBitmap(true, w, h)
    bitmap_w, bitmap_h = w, h
    composite_view = notes_view
    reaper.JS_Composite(notes_view, 0, 0, w, h, bitmap, 0, 0, w, h)
    if reaper.JS_Composite_Delay then
        -- Reduces flickering
        reaper.JS_Composite_Delay(notes_view, 0.03, 0.03, 2)
    end
end

local function ClearOverlay()
    if not bitmap then return end
    reaper.JS_LICE_Clear(bitmap, 0)
    reaper.JS_Window_InvalidateRect(notes_view, 0, 0, bitmap_w, bitmap_h, false)
end

local function Draw(take, view, w, h, ui_scale)
    PrepareBitmap(w, h)
    reaper.JS_LICE_Clear(bitmap, 0)

    local ruler_h = config.ruler_height or
        math.floor(ruler_scale1_h * ui_scale + 0.5)
    local area_top = ruler_h
    local area_bottom = h - view.lanes_h
    local row_h = view.row_h
    local y_offs = ruler_h + config.y_offset

    local function FillRows(x1, x2, pitch_filter)
        x1 = math.max(0, math.floor(x1))
        x2 = math.min(w, math.floor(x2))
        if x2 <= x1 then return end
        local last_row = math.ceil((area_bottom - y_offs) / row_h)
        for row = 0, last_row do
            local pitch = view.top_pitch - row
            if pitch < 0 then break end
            local color = pitch <= 127 and pitch_filter(pitch % 12)
            if color then
                local y1 = math.max(area_top, y_offs + row * row_h)
                local y2 = math.min(area_bottom, y_offs + (row + 1) * row_h)
                if y2 > y1 then
                    reaper.JS_LICE_FillRect(bitmap, x1, y1, x2 - x1, y2 - y1,
                        color, 1, 'COPY')
                end
            end
        end
    end

    -- Scale tones (from key snap setting)
    local scale_pcs
    if config.show_scale then
        local is_key_snap, scale_root, scale_mask = reaper.MIDI_GetScale(take)
        if is_key_snap then
            scale_pcs = {}
            for i = 0, 11 do
                if scale_mask & (1 << i) ~= 0 then
                    scale_pcs[(scale_root + i) % 12] = true
                end
            end
            local scale_color = Premultiply(config.color_scale)
            FillRows(0, w, function(pc) return scale_pcs[pc] and scale_color end)
        end
    end

    -- Chord tones
    local is_beat_based = view.timebase == 0 or view.timebase == 4
    local view_start_time = reaper.MIDI_GetProjTimeFromPPQPos(take,
        view.start_ppq)
    local view_end_time
    if is_beat_based then
        view_end_time = reaper.MIDI_GetProjTimeFromPPQPos(take,
            view.start_ppq + w / view.hzoom)
    else
        view_end_time = view_start_time + w / view.hzoom
    end

    local function TimeToX(time)
        local x
        if is_beat_based then
            local ppq = reaper.MIDI_GetPPQPosFromProjTime(take, time)
            x = (ppq - view.start_ppq) * view.hzoom
        else
            x = (time - view_start_time) * view.hzoom
        end
        return x + config.x_offset
    end

    local root_color = Premultiply(config.color_root)
    local chord_color = Premultiply(config.color_chord)

    local segments = CG.GetChordSegments(view_start_time, view_end_time)
    for _, seg in ipairs(segments) do
        local chord = seg.chord
        FillRows(TimeToX(seg.s), TimeToX(seg.e), function(pc)
            if pc == chord.root then return root_color end
            if chord.pcs[pc] then return chord_color end
        end)
    end

    reaper.JS_Window_InvalidateRect(notes_view, 0, 0, w, h, false)
end

local function Main()
    reaper.defer(Main)

    local hwnd = reaper.MIDIEditor_GetActive()
    if not hwnd then
        if prev_hwnd then
            ReleaseBitmap()
            prev_hwnd = nil
            prev_signature = nil
        end
        return
    end

    if hwnd ~= prev_hwnd then
        prev_hwnd = hwnd
        prev_signature = nil
        prev_poll_time = nil
        notes_view = reaper.JS_Window_FindChildByID(hwnd, 1001)
        piano_pane = reaper.JS_Window_FindChildByID(hwnd, 1003)
    end
    if not notes_view then return end

    local time = reaper.time_precise()
    if prev_poll_time and time < prev_poll_time + config.poll_interval then
        return
    end
    prev_poll_time = time

    local take = reaper.MIDIEditor_GetTake(hwnd)
    local is_valid_take = take and reaper.ValidatePtr(take, 'MediaItem_Take*')
    -- Only the piano roll with all note rows visible is supported
    local is_supported = is_valid_take and reaper.MIDIEditor_GetMode(hwnd) == 0
        and reaper.GetToggleCommandStateEx(midi_editor_section,
            cmd_show_all_rows) == 1

    local view = is_supported and GetEditorView(take)
    if not view or view.row_h <= 0 or view.hzoom <= 0 then
        if prev_signature ~= 'hidden' then
            prev_signature = 'hidden'
            ClearOverlay()
        end
        return
    end

    local _, w, h = reaper.JS_Window_GetClientSize(notes_view)
    local _, piano_pane_w = reaper.JS_Window_GetClientSize(piano_pane)
    if not w or w <= 0 or h <= 0 then return end
    local ui_scale = (piano_pane_w or 0) > 0 and
        piano_pane_w / piano_pane_scale1_w or 1

    local is_key_snap, scale_root, scale_mask = reaper.MIDI_GetScale(take)
    local signature = table.concat({
        tostring(take), w, h, piano_pane_w, view.start_ppq, view.hzoom,
        view.top_pitch, view.row_h, view.timebase, view.lanes_h,
        tostring(is_key_snap), tostring(scale_root), tostring(scale_mask),
        reaper.GetProjectStateChangeCount(0),
    }, ' ')

    if signature ~= prev_signature then
        prev_signature = signature
        Draw(take, view, w, h, ui_scale)
    end
end

local function Exit()
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.RefreshToolbar2(sec, cmd)
    ReleaseBitmap()
end

reaper.SetToggleCommandState(sec, cmd, 1)
reaper.RefreshToolbar2(sec, cmd)
reaper.atexit(Exit)
reaper.defer(Main)
