--[[
  @description ChordGuide - Highlight chord tones in MIDI editor
  @author amenonegames
  @license MIT
  @version 0.2.0
  @provides
    [main=main,midi_editor] .
    [nomain] ChordGuide_lib.lua
    [main=midi_editor] ChordGuide - Move selected notes to chord tone above.lua
    [main=midi_editor] ChordGuide - Move selected notes to chord tone below.lua
    [main=midi_editor] ChordGuide - Snap selected notes to nearest chord tone.lua
    [main=midi_editor] ChordGuide - Cycle display (keyboard, note area, both).lua
    [main=midi_editor] ChordGuide - Nudge guides up by 1 pixel.lua
    [main=midi_editor] ChordGuide - Nudge guides down by 1 pixel.lua
  @about
    Highlights the chord tones of the chord track (or project regions) and
    the key snap scale in the MIDI editor: on the piano keyboard for the chord
    at the cursor, and/or as bands in the note area.

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

local midi_editor_section = 32060
local cmd_show_all_rows = 40452

local prev_hwnd
local notes_view
local piano_pane
local prev_poll_time

-- One overlay per window: {window, bitmap, w, h, signature}
local keys_overlay = {}
local notes_overlay = {}

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

local function ReleaseOverlay(overlay)
    if overlay.bitmap then
        local window = overlay.window
        if window and reaper.ValidatePtr(window, 'HWND*') then
            reaper.JS_Composite_Unlink(window, overlay.bitmap)
            reaper.JS_Window_InvalidateRect(window, 0, 0, overlay.w,
                overlay.h, false)
        end
        reaper.JS_LICE_DestroyBitmap(overlay.bitmap)
    end
    overlay.bitmap = nil
    overlay.window = nil
    overlay.signature = nil
end

-- Clears the overlay and makes sure its bitmap matches the window
local function BeginDraw(overlay, window, w, h)
    if not overlay.bitmap or w ~= overlay.w or h ~= overlay.h or
        window ~= overlay.window then
        ReleaseOverlay(overlay)
        overlay.bitmap = reaper.JS_LICE_CreateBitmap(true, w, h)
        overlay.w, overlay.h = w, h
        overlay.window = window
        reaper.JS_Composite(window, 0, 0, w, h, overlay.bitmap, 0, 0, w, h)
        if reaper.JS_Composite_Delay then
            -- Reduces flickering
            reaper.JS_Composite_Delay(window, 0.03, 0.03, 2)
        end
    end
    reaper.JS_LICE_Clear(overlay.bitmap, 0)
end

local function EndDraw(overlay)
    reaper.JS_Window_InvalidateRect(overlay.window, 0, 0, overlay.w,
        overlay.h, false)
end

local function HideOverlay(overlay)
    if overlay.signature == 'hidden' then return end
    if overlay.bitmap then
        reaper.JS_LICE_Clear(overlay.bitmap, 0)
        EndDraw(overlay)
    end
    overlay.signature = 'hidden'
end

-- Fills the note rows for which get_color(pitch class) returns a color
-- rows: {top_pitch, row_h, y, top, bottom} (pixel positions in the window)
local function FillRows(overlay, rows, x1, x2, get_color)
    x1 = math.max(0, math.floor(x1))
    x2 = math.min(overlay.w, math.floor(x2))
    if x2 <= x1 then return end
    local last_row = math.ceil((rows.bottom - rows.y) / rows.row_h)
    for row = 0, last_row do
        local pitch = rows.top_pitch - row
        if pitch < 0 then break end
        local color = pitch <= 127 and get_color(pitch % 12)
        if color then
            local y1 = math.max(rows.top, rows.y + row * rows.row_h)
            local y2 = math.min(rows.bottom, rows.y + (row + 1) * rows.row_h)
            if y2 > y1 then
                reaper.JS_LICE_FillRect(overlay.bitmap, x1, y1, x2 - x1,
                    y2 - y1, color, 1, 'COPY')
            end
        end
    end
end

-- Scale tones from the key snap setting, as {[pitch class] = true}
local function GetScalePitchClasses(take)
    if not config.show_scale then return end
    local is_key_snap, scale_root, scale_mask = reaper.MIDI_GetScale(take)
    if not is_key_snap then return end
    local scale_pcs = {}
    for i = 0, 11 do
        if scale_mask & (1 << i) ~= 0 then
            scale_pcs[(scale_root + i) % 12] = true
        end
    end
    return scale_pcs
end

-- Keyboard: chord tones of the chord at the play/edit cursor
local function DrawKeys(rows, w, h, chord, scale_pcs)
    local overlay = keys_overlay
    BeginDraw(overlay, piano_pane, w, h)

    local root_color = Premultiply(config.key_color_root)
    local chord_color = Premultiply(config.key_color_chord)
    local scale_color = Premultiply(config.key_color_scale)

    FillRows(overlay, rows, 0, w, function(pc)
        if chord then
            if pc == chord.root then return root_color end
            if chord.pcs[pc] then return chord_color end
        end
        if scale_pcs and scale_pcs[pc] then return scale_color end
    end)
    EndDraw(overlay)
end

-- Note area: chord tones for each chord's time range
local function DrawNotes(take, view, rows, w, h, scale_pcs)
    local overlay = notes_overlay
    BeginDraw(overlay, notes_view, w, h)

    if scale_pcs then
        local scale_color = Premultiply(config.color_scale)
        FillRows(overlay, rows, 0, w, function(pc)
            return scale_pcs[pc] and scale_color
        end)
    end

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
        FillRows(overlay, rows, TimeToX(seg.s), TimeToX(seg.e), function(pc)
            if pc == chord.root then return root_color end
            if chord.pcs[pc] then return chord_color end
        end)
    end
    EndDraw(overlay)
end

local function GetRows(view, y, h)
    return {
        top_pitch = view.top_pitch,
        row_h = view.row_h,
        y = y,
        top = y,
        bottom = h - view.lanes_h,
    }
end

local function Main()
    reaper.defer(Main)

    local hwnd = reaper.MIDIEditor_GetActive()
    if not hwnd then
        if prev_hwnd then
            ReleaseOverlay(keys_overlay)
            ReleaseOverlay(notes_overlay)
            prev_hwnd = nil
        end
        return
    end

    if hwnd ~= prev_hwnd then
        prev_hwnd = hwnd
        prev_poll_time = nil
        ReleaseOverlay(keys_overlay)
        ReleaseOverlay(notes_overlay)
        notes_view = reaper.JS_Window_FindChildByID(hwnd, 1001)
        piano_pane = reaper.JS_Window_FindChildByID(hwnd, 1003)
    end
    if not notes_view or not piano_pane then return end

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
        HideOverlay(keys_overlay)
        HideOverlay(notes_overlay)
        return
    end

    local mode = CG.GetDisplayMode()
    local y = config.ruler_height + CG.GetNudge()
    local is_key_snap, scale_root, scale_mask = reaper.MIDI_GetScale(take)
    local common_signature = table.concat({
        tostring(take), y, view.top_pitch, view.row_h, view.lanes_h,
        tostring(config.show_scale and is_key_snap), tostring(scale_root),
        tostring(scale_mask),
    }, ' ')

    if mode == 'notes' then
        HideOverlay(keys_overlay)
    else
        local _, w, h = reaper.JS_Window_GetClientSize(piano_pane)
        if w and w > 0 and h > 0 then
            local is_playing = reaper.GetPlayState() & 1 == 1
            local pos = is_playing and reaper.GetPlayPosition() or
                reaper.GetCursorPosition()
            local chord = CG.GetChordAt(pos)
            local signature = table.concat({
                common_signature, w, h, tostring(chord),
            }, ' ')
            if signature ~= keys_overlay.signature then
                DrawKeys(GetRows(view, y, h), w, h, chord,
                    GetScalePitchClasses(take))
                keys_overlay.signature = signature
            end
        end
    end

    if mode == 'keys' then
        HideOverlay(notes_overlay)
    else
        local _, w, h = reaper.JS_Window_GetClientSize(notes_view)
        if w and w > 0 and h > 0 then
            local signature = table.concat({
                common_signature, w, h, view.start_ppq, view.hzoom,
                view.timebase, reaper.GetProjectStateChangeCount(0),
            }, ' ')
            if signature ~= notes_overlay.signature then
                DrawNotes(take, view, GetRows(view, y, h), w, h,
                    GetScalePitchClasses(take))
                notes_overlay.signature = signature
            end
        end
    end
end

local function Exit()
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.RefreshToolbar2(sec, cmd)
    ReleaseOverlay(keys_overlay)
    ReleaseOverlay(notes_overlay)
end

reaper.SetToggleCommandState(sec, cmd, 1)
reaper.RefreshToolbar2(sec, cmd)
reaper.atexit(Exit)
reaper.defer(Main)
