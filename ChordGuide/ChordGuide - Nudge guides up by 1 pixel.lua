--[[
  @author amenonegames
  @license MIT
  @noindex
  @about Moves the ChordGuide bands up by one pixel (kept across updates)
]]
local dir = debug.getinfo(1, 'S').source:match('^@?(.*[\\/])')
local CG = dofile(dir .. 'ChordGuide_lib.lua')
CG.Nudge(-1)
