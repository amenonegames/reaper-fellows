--[[
  @author amenonegames
  @license MIT
  @noindex
  @about Snaps selected notes to the nearest chord tone (chord track / regions)
]]
local dir = debug.getinfo(1, 'S').source:match('^@?(.*[\\/])')
local CG = dofile(dir .. 'ChordGuide_lib.lua')
CG.MoveSelectedNotes('nearest')
