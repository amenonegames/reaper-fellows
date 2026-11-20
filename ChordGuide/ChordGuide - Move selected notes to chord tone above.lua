--[[
  @author amenonegames
  @license MIT
  @noindex
  @about Moves selected notes to the next chord tone above (chord track / regions)
]]
local dir = debug.getinfo(1, 'S').source:match('^@?(.*[\\/])')
local CG = dofile(dir .. 'ChordGuide_lib.lua')
CG.MoveSelectedNotes('up')
