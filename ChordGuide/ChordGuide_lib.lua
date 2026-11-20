--[[
  ChordGuide library (v0.1.0)
  @author amenonegames
  @license MIT
  @noindex

  Shared code for the ChordGuide scripts:
    - parses chord names as written by FeedTheCat's "Lil Chordbox"
    - reads chords from the chord track ("Chords") or from project regions
    - moves selected MIDI notes to chord tones

  The chord name table below is taken from "Lil Chordbox.lua"
  (https://github.com/iliaspoulakis/Reaper-Tools), MIT License,
  Copyright (c) 2020 iliaspoulakis
]]
local CG = {}

------------------------------- SETTINGS -------------------------------

CG.config = {
    -- Name of the chord track. nil = use the name set in Lil Chordbox
    -- (falls back to 'Chords')
    chord_track_name = nil,
    -- 'auto'   = chord track if it exists and has items, otherwise regions
    -- 'track'  = chord track only
    -- 'region' = project regions only
    source = 'auto',

    -- Overlay colors: {0xRRGGBB, opacity 0-1}
    color_root = {0xFF9A3C, 0.38},
    color_chord = {0x4CC2FF, 0.26},
    color_scale = {0xFFFFFF, 0.07},
    -- Draw scale tones (taken from the MIDI editor's key snap setting)
    show_scale = true,

    -- Geometry calibration (pixels). Change these if the bands are shifted.
    -- nil = automatic
    ruler_height = nil,
    y_offset = 0,
    x_offset = 0,
    -- How often the editor scroll/zoom state is polled (seconds)
    poll_interval = 0.05,
}

------------------------------ CHORD NAMES ------------------------------

-- Key: semitone offsets from root (1 = root, 5 = major 3rd, 8 = 5th ...)
local chord_names = {}
-- Single notes
chord_names['1'] = {expanded = ' note', compact = ' note'}
-- Dyads
chord_names['1 2'] = {expanded = ' minor 2nd', compact = ' m2'}
chord_names['1 3'] = {expanded = ' major 2nd', compact = ' M2'}
chord_names['1 4'] = {expanded = ' minor 3rd', compact = ' m3'}
chord_names['1 5'] = {expanded = ' major 3rd', compact = ' M3'}
chord_names['1 6'] = {expanded = ' perfect 4th', compact = ' P4'}
chord_names['1 7'] = {expanded = ' dim 5th', compact = ' d5'}
chord_names['1 8'] = {expanded = '5', compact = '5'}
chord_names['1 9'] = {expanded = ' minor 6th', compact = ' m6'}
chord_names['1 10'] = {expanded = ' major 6th', compact = ' M6'}
chord_names['1 11'] = {expanded = ' minor 7th', compact = ' m7'}
chord_names['1 12'] = {expanded = ' major 7th', compact = ' M7'}
chord_names['1 13'] = {expanded = ' octave', compact = ' P8'}
-- Compound intervals
chord_names['1 14'] = {expanded = ' minor 9th', compact = ' m9'}
chord_names['1 15'] = {expanded = ' major 9th', compact = ' M9'}
chord_names['1 16'] = {expanded = ' minor 10th', compact = ' m10'}
chord_names['1 17'] = {expanded = ' major 10th', compact = ' M10'}
chord_names['1 18'] = {expanded = ' perfect 11th', compact = ' P11'}
chord_names['1 19'] = {expanded = ' dim 12th', compact = ' d12'}
chord_names['1 20'] = {expanded = ' perfect 12th', compact = ' P12'}
chord_names['1 21'] = {expanded = ' minor 13th', compact = ' m13'}
chord_names['1 22'] = {expanded = ' major 13th', compact = ' M13'}
chord_names['1 23'] = {expanded = ' minor 14th', compact = ' m14'}
chord_names['1 24'] = {expanded = ' major 14th', compact = ' M14'}

-- Major chords
chord_names['1 5 8'] = {expanded = 'maj', compact = 'M'}
chord_names['1 5 7'] = {expanded = '(b5)', compact = '(b5)'}
chord_names['1 8 12'] = {expanded = 'maj7 omit3', compact = 'M7(no3)'}
chord_names['1 5 12'] = {expanded = 'maj7 omit5', compact = 'M7(no5)'}
chord_names['1 5 8 12'] = {expanded = 'maj7', compact = 'M7'}
chord_names['1 3 5 12'] = {expanded = 'maj9 omit5', compact = 'M9(no5)'}
chord_names['1 3 5 8 12'] = {expanded = 'maj9', compact = 'M9'}
chord_names['1 3 5 6 12'] = {expanded = 'maj11 omit5', compact = 'M11(no5)'}
chord_names['1 5 6 8 12'] = {expanded = 'maj11 omit9', compact = 'M11(no9)'}
chord_names['1 3 5 6 8 12'] = {expanded = 'maj11', compact = 'M11'}
chord_names['1 3 5 6 10 12'] = {expanded = 'maj13 omit5', compact = 'M13(no5)'}
chord_names['1 5 6 8 10 12'] = {expanded = 'maj13 omit9', compact = 'M13(no9)'}
chord_names['1 3 5 6 8 10 12'] = {expanded = 'maj13', compact = 'M13'}
chord_names['1 8 10'] = {expanded = '6 omit3', compact = '6(no3)'}
chord_names['1 5 8 10'] = {expanded = '6', compact = '6'}
chord_names['1 3 5 10'] = {expanded = '6/9 omit5', compact = '6/9(no5)'}
chord_names['1 3 5 8 10'] = {expanded = '6/9', compact = '6/9'}
chord_names['1 5 7 12'] = {expanded = 'maj7b5', compact = 'M7b5'}
chord_names['1 5 7 8 12'] = {expanded = 'maj7#11', compact = 'M7#11'}
chord_names['1 3 5 7 12'] = {expanded = 'maj9b5', compact = 'M9b5'}
chord_names['1 3 5 7 8 12'] = {expanded = 'maj9#11', compact = 'M9#11'}

-- Dominant/Seventh
chord_names['1 8 11'] = {expanded = '7 omit3', compact = '7(no3)'}
chord_names['1 5 11'] = {expanded = '7 omit5', compact = '7(no5)'}
chord_names['1 5 8 11'] = {expanded = '7', compact = '7'}
chord_names['1 3 8 11'] = {expanded = '9 omit3', compact = '9(no3)'}
chord_names['1 3 5 11'] = {expanded = '9 omit5', compact = '9(no5)'}
chord_names['1 3 5 8 11'] = {expanded = '9', compact = '9'}
chord_names['1 3 5 10 11'] = {expanded = '13 omit5', compact = '13(no5)'}
chord_names['1 5 8 10 11'] = {expanded = '13 omit9', compact = '13(no9)'}
chord_names['1 3 5 8 10 11'] = {expanded = '13', compact = '13'}
chord_names['1 5 7 11'] = {expanded = '7b5', compact = '7b5'}
chord_names['1 5 7 8 11'] = {expanded = '7#11', compact = '7#11'}
chord_names['1 3 5 7 11'] = {expanded = '9b5', compact = '9b5'}
chord_names['1 3 5 7 8 11'] = {expanded = '9#11', compact = '9#11'}

-- Altered
chord_names['1 2 5 11'] = {expanded = '7b9 omit5', compact = '7b9(no5)'}
chord_names['1 2 5 8 11'] = {expanded = '7b9', compact = '7b9'}
chord_names['1 2 5 7 8 11'] = {expanded = '7b9#11', compact = '7b9#11'}
chord_names['1 4 5 11'] = {expanded = '7#9 omit5', compact = '7#9(no5)'}
chord_names['1 4 5 8 11'] = {expanded = '7#9', compact = '7#9'}
chord_names['1 4 5 9 11'] = {expanded = '7#5#9', compact = '7#5#9'}
chord_names['1 4 5 7 8 11'] = {expanded = '7#9#11', compact = '7#9#11'}
chord_names['1 2 5 8 10 11'] = {expanded = '13b9', compact = '13b9'}
chord_names['1 3 5 7 8 10 11'] = {expanded = '13#11', compact = '13#11'}
chord_names['1 4 5 8 10 11'] = {expanded = '13#9', compact = '13#9'}
chord_names['1 3 5 9 11'] = {expanded = '9#5', compact = '9#5'}

-- Suspended
chord_names['1 6 8'] = {expanded = 'sus4', compact = 'sus4'}
chord_names['1 3 8'] = {expanded = 'sus2', compact = 'sus2'}
chord_names['1 6 11'] = {expanded = '7sus4 omit5', compact = '7sus4(no5)'}
chord_names['1 6 8 11'] = {expanded = '7sus4', compact = '7sus4'}
chord_names['1 3 6 11'] = {expanded = '11 omit5', compact = '11(no5)'}
chord_names['1 3 6 8 11'] = {expanded = '11', compact = '11'}

-- Minor
chord_names['1 4 8'] = {expanded = 'm', compact = 'm'}
chord_names['1 4 11'] = {expanded = 'm7 omit5', compact = 'm7(no5)'}
chord_names['1 4 8 11'] = {expanded = 'm7', compact = 'm7'}
chord_names['1 4 12'] = {expanded = 'm(maj7) omit5', compact = 'mM7(no5)'}
chord_names['1 4 8 12'] = {expanded = 'm(maj7)', compact = 'mM7'}
chord_names['1 3 4 12'] = {expanded = 'm(maj9) omit5', compact = 'mM9(no5)'}
chord_names['1 3 4 8 12'] = {expanded = 'm(maj9)', compact = 'mM9'}
chord_names['1 3 4 11'] = {expanded = 'm9 omit5', compact = 'm9(no5)'}
chord_names['1 3 4 8 11'] = {expanded = 'm9', compact = 'm9'}
chord_names['1 3 4 6 11'] = {expanded = 'm11 omit5', compact = 'm11(no5)'}
chord_names['1 4 6 8 11'] = {expanded = 'm11 omit9', compact = 'm11(no9)'}
chord_names['1 3 4 6 8 11'] = {expanded = 'm11', compact = 'm11'}
chord_names['1 3 4 6 10 11'] = {expanded = 'm13 omit5', compact = 'm13(no5)'}
chord_names['1 4 6 8 10 11'] = {expanded = 'm13 omit9', compact = 'm13(no9)'}
chord_names['1 3 4 6 8 10 11'] = {expanded = 'm13', compact = 'm13'}
chord_names['1 4 8 10'] = {expanded = 'm6', compact = 'm6'}
chord_names['1 3 4 10'] = {expanded = 'm6/9 omit5', compact = 'm6/9(no5)'}
chord_names['1 3 4 8 10'] = {expanded = 'm6/9', compact = 'm6/9'}

-- Diminished
chord_names['1 4 7'] = {expanded = 'dim', compact = 'dim'}
chord_names['1 4 7 10'] = {expanded = 'dim7', compact = 'dim7'}
chord_names['1 4 7 11'] = {expanded = 'm7b5', compact = 'm7b5'}
chord_names['1 4 7 12'] = {expanded = 'dim(maj7)', compact = 'dimM7'}
chord_names['1 2 4 8 11'] = {expanded = 'm7b9', compact = 'm7b9'}
chord_names['1 2 4 7 11'] = {expanded = 'm7b5b9', compact = 'm7b5b9'}
chord_names['1 2 4 11'] = {expanded = 'm7b9 omit5', compact = 'm7b9(no5)'}
chord_names['1 3 4 7 11'] = {expanded = 'm9b5', compact = 'm9b5'}
chord_names['1 3 4 6 7 11'] = {expanded = 'm11b5', compact = 'm11b5'}
chord_names['1 3 5 7 10 11'] = {expanded = '13b5', compact = '13b5'}

-- Augmented
chord_names['1 5 9'] = {expanded = 'aug', compact = 'aug'}
chord_names['1 5 9 11'] = {expanded = '7#5', compact = '7#5'}
chord_names['1 5 9 12'] = {expanded = 'maj7#5', compact = 'M7#5'}

-- Additions
chord_names['1 3 4'] = {expanded = 'm add9 omit5', compact = 'm add9(no5)'}
chord_names['1 3 4 8'] = {expanded = 'm add9', compact = 'm add9'}
chord_names['1 3 5'] = {expanded = 'maj add9 omit5', compact = 'M add9(no5)'}
chord_names['1 3 5 8'] = {expanded = 'maj add9', compact = 'M add9'}
chord_names['1 4 6 8'] = {expanded = 'm add11', compact = 'm add11'}
chord_names['1 5 6 8'] = {expanded = 'maj add11', compact = 'M add11'}
chord_names['1 5 10 11'] = {expanded = '7 add13 omit5', compact = '7 add13(no5)'}

-- Notations that Lil Chordbox does not produce, for hand-typed chords.
-- Maps to a name from the table above (compact style).
local aliases = {
    ['△'] = 'M', ['Δ'] = 'M', ['maj'] = 'M', ['major'] = 'M',
    ['△7'] = 'M7', ['Δ7'] = 'M7', ['Maj7'] = 'M7', ['MA7'] = 'M7',
    ['△9'] = 'M9', ['Δ9'] = 'M9', ['Maj9'] = 'M9',
    ['min'] = 'm', ['-'] = 'm', ['mi'] = 'm',
    ['min7'] = 'm7', ['-7'] = 'm7', ['mi7'] = 'm7',
    ['min9'] = 'm9', ['-9'] = 'm9',
    ['m7-5'] = 'm7b5', ['m7(b5)'] = 'm7b5', ['ø'] = 'm7b5', ['ø7'] = 'm7b5',
    ['°'] = 'dim', ['°7'] = 'dim7',
    ['+'] = 'aug', ['+7'] = '7#5', ['aug7'] = '7#5', ['7+5'] = '7#5',
    ['7-5'] = '7b5', ['7(b5)'] = '7b5', ['7(#5)'] = '7#5',
    ['7(b9)'] = '7b9', ['7(#9)'] = '7#9', ['7(#11)'] = '7#11',
    ['sus'] = 'sus4', ['7sus'] = '7sus4',
    ['add9'] = 'M add9', ['(add9)'] = 'M add9', ['m(add9)'] = 'm add9',
    ['mM7'] = 'mM7', ['m(M7)'] = 'mM7', ['mMaj7'] = 'mM7', ['-M7'] = 'mM7',
    ['69'] = '6/9', ['m69'] = 'm6/9',
    ['M7(#11)'] = 'M7#11', ['M7(#5)'] = 'M7#5', ['aug M7'] = 'M7#5',
}

local function Trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end

local function KeyNoteCount(key)
    local _, cnt = key:gsub('%d+', '')
    return cnt
end

-- Reverse lookup: suffix -> key
-- Note: Interval names are only valid with their leading space, as they
-- collide with chord names otherwise (e.g. 'C m6' = interval, 'Cm6' = chord)
local interval_map = {}
local suffix_map = {}
local suffix_map_nospace = {}

local function BuildSuffixMaps()
    local loose = {}
    local function AddLoose(name, key)
        -- Prefer the chord with the most notes (e.g. 'M7' over 'M7(no5)')
        local prev = loose[name]
        if not prev or KeyNoteCount(key) > KeyNoteCount(prev) then
            loose[name] = key
        end
    end
    -- 1. Exact names (both expanded and compact style)
    for key, names in pairs(chord_names) do
        for _, name in ipairs {names.expanded, names.compact} do
            if name:match('^%s') then
                interval_map[name] = key
            else
                suffix_map[name] = key
            end
        end
    end
    -- 2. Names with hidden omissions / hidden major (Lil Chordbox options)
    for key, names in pairs(chord_names) do
        local is_interval = key:match('^1 %d*$')
        local variants = {
            {names.expanded, ' omit%d+', '^(%s?)majo?r?'},
            {names.compact, '%(no%d+%)', '^M(%s?)'},
        }
        for _, v in ipairs(variants) do
            local name, omit_pattern, major_pattern = v[1], v[2], v[3]
            local no_omit = name:gsub(omit_pattern, '')
            if not is_interval then
                AddLoose(Trim(no_omit), key)
                AddLoose(Trim((name:gsub(major_pattern, '%1'))), key)
                AddLoose(Trim((no_omit:gsub(major_pattern, '%1'))), key)
            end
        end
    end
    for name, key in pairs(loose) do
        if not suffix_map[name] then suffix_map[name] = key end
    end
    -- 3. Hand-typed aliases
    for alias, name in pairs(aliases) do
        if not suffix_map[alias] then suffix_map[alias] = suffix_map[name] end
    end
    -- 4. Lookup that ignores spaces (e.g. 'Cadd9', 'Cmadd9')
    for name, key in pairs(suffix_map) do
        local nospace = name:gsub('%s', '')
        if not suffix_map_nospace[nospace] then
            suffix_map_nospace[nospace] = key
        end
    end
end
BuildSuffixMaps()

local note_pcs = {C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11}

-- Returns pitch class and the rest of the string
-- Note: Solfège names (Do, Re, Mi) are not supported
local function ParseNoteName(str)
    local letter, rest = str:match('^([A-G])(.*)')
    if not letter then return end
    local pc = note_pcs[letter]
    local accidental = rest:sub(1, 1)
    if accidental == '#' then
        return (pc + 1) % 12, rest:sub(2)
    elseif accidental == 'b' then
        return (pc - 1) % 12, rest:sub(2)
    end
    return pc, rest
end

local parse_cache = {}

-- Parses a chord name. Returns nil if there is no recognizable root, else
--   { name, root = 0-11, bass = 0-11 or nil, pcs = {[0-11] = true},
--     is_known = false if only the root could be parsed }
function CG.ParseChord(text)
    if not text then return end
    local cached = parse_cache[text]
    if cached ~= nil then return cached or nil end

    local name = Trim(text:match('^[^\r\n]*') or '')
    name = name:gsub('♯', '#'):gsub('♭', 'b')
    -- Remove scale degree added by Lil Chordbox (e.g. 'Am7 - vi')
    name = name:gsub('%s+%-%s+%S+$', '')

    local root, rest = ParseNoteName(name)
    if not root then
        parse_cache[text] = false
        return
    end

    -- Slash chords. Note: Must not match the slash in '6/9'
    local bass
    local head, bass_str = rest:match('^(.-)%s*/%s*([A-G][#b]?)$')
    if head then
        local bass_pc, bass_rest = ParseNoteName(bass_str)
        if bass_pc and bass_rest == '' then
            bass = bass_pc
            rest = head
        end
    end

    local suffix = Trim(rest)
    local key = interval_map[(rest:gsub('%s+$', ''))] or suffix_map[suffix] or
        suffix_map_nospace[(suffix:gsub('%s', ''))]
    -- Single notes (e.g. 'C4 note')
    if not key and suffix:match('^%-?%d+ note$') then key = '1' end

    local chord = {name = name, root = root, bass = bass, pcs = {}}
    chord.is_known = key ~= nil
    for n in (key or '1'):gmatch('%d+') do
        chord.pcs[(root + n - 1) % 12] = true
    end
    if bass then chord.pcs[bass] = true end

    parse_cache[text] = chord
    return chord
end

------------------------------ CHORD SOURCE ------------------------------

function CG.GetChordTrackName()
    local name = CG.config.chord_track_name
    if not name or name == '' then
        name = reaper.GetExtState('FTC.LilChordBox', 'chord_track_name')
    end
    if not name or name == '' then name = 'Chords' end
    return name
end

function CG.FindChordTrack()
    local name = CG.GetChordTrackName()
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local _, track_name = reaper.GetTrackName(track)
        if track_name == name then return track end
    end
end

local function GetTrackSegments(track, start_time, end_time)
    local segments = {}
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local s = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
        local e = s + reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
        -- Note: Track items are sorted by position
        if s >= end_time then break end
        if e > start_time then
            local _, notes = reaper.GetSetMediaItemInfo_String(item, 'P_NOTES',
                '', false)
            local chord = CG.ParseChord(notes)
            if chord and chord.is_known then
                segments[#segments + 1] = {s = s, e = e, chord = chord}
            end
        end
    end
    return segments
end

local function GetRegionSegments(start_time, end_time)
    local segments = {}
    local i = 0
    while true do
        local ret, is_region, s, e, name = reaper.EnumProjectMarkers(i)
        if not ret or ret == 0 then break end
        if is_region and s < end_time and e > start_time then
            local chord = CG.ParseChord(name)
            if chord and chord.is_known then
                segments[#segments + 1] = {s = s, e = e, chord = chord}
            end
        end
        i = i + 1
    end
    table.sort(segments, function(a, b) return a.s < b.s end)
    return segments
end

-- Returns list of {s = start time, e = end time, chord = parsed chord}
function CG.GetChordSegments(start_time, end_time)
    local source = CG.config.source
    if source ~= 'region' then
        local track = CG.FindChordTrack()
        if track then
            if source == 'track' or reaper.CountTrackMediaItems(track) > 0 then
                return GetTrackSegments(track, start_time, end_time)
            end
        end
        if source == 'track' then return {} end
    end
    return GetRegionSegments(start_time, end_time)
end

-- Returns the chord that overlaps the given time range the most
function CG.GetChordForRange(start_time, end_time)
    if end_time <= start_time then end_time = start_time + 0.001 end
    local best_chord
    local best_overlap = 0
    for _, seg in ipairs(CG.GetChordSegments(start_time, end_time)) do
        local overlap = math.min(seg.e, end_time) - math.max(seg.s, start_time)
        if overlap > best_overlap then
            best_overlap = overlap
            best_chord = seg.chord
        end
    end
    return best_chord
end

------------------------------ NOTE ACTIONS ------------------------------

-- Returns the target pitch for a note, or nil if it should not move
-- mode: 'up', 'down' or 'nearest'
function CG.GetTargetPitch(pitch, pcs, mode)
    if mode == 'nearest' and pcs[pitch % 12] then return end
    for dist = 1, 11 do
        local lo, hi = pitch - dist, pitch + dist
        -- Note: 'nearest' prefers the lower pitch on ties
        if mode ~= 'up' and lo >= 0 and pcs[lo % 12] then return lo end
        if mode ~= 'down' and hi <= 127 and pcs[hi % 12] then return hi end
    end
end

function CG.MoveSelectedNotes(mode)
    local hwnd = reaper.MIDIEditor_GetActive()
    local take = hwnd and reaper.MIDIEditor_GetTake(hwnd)
    if not take or not reaper.ValidatePtr(take, 'MediaItem_Take*') then return end

    local undo_names = {
        up = 'Move selected notes to chord tone above',
        down = 'Move selected notes to chord tone below',
        nearest = 'Snap selected notes to nearest chord tone',
    }

    reaper.Undo_BeginBlock()
    local _, note_cnt = reaper.MIDI_CountEvts(take)
    local has_changed = false
    for i = 0, note_cnt - 1 do
        local _, is_sel, _, sppq, eppq, _, pitch = reaper.MIDI_GetNote(take, i)
        if is_sel then
            local s = reaper.MIDI_GetProjTimeFromPPQPos(take, sppq)
            local e = reaper.MIDI_GetProjTimeFromPPQPos(take, eppq)
            local chord = CG.GetChordForRange(s, e)
            if chord then
                local target = CG.GetTargetPitch(pitch, chord.pcs, mode)
                if target then
                    reaper.MIDI_SetNote(take, i, nil, nil, nil, nil, nil, target,
                        nil, true)
                    has_changed = true
                end
            end
        end
    end
    if has_changed then
        reaper.MIDI_Sort(take)
        local item = reaper.GetMediaItemTake_Item(take)
        reaper.MarkTrackItemsDirty(reaper.GetMediaItemTake_Track(take), item)
    end
    reaper.Undo_EndBlock(undo_names[mode], -1)
end

return CG
