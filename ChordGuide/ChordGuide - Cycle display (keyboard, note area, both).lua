--[[
  @author amenonegames
  @license MIT
  @noindex
  @about Switches where ChordGuide shows chord tones
]]
local dir = debug.getinfo(1, 'S').source:match('^@?(.*[\\/])')
local CG = dofile(dir .. 'ChordGuide_lib.lua')
CG.CycleDisplayMode()
