--[[
File: main.lua
Author: X. Chen
Description: entry portal of the repository
License: GNU GPLv3
--]]

-- [[ define parameters
l_x = 15 -- mm
l_y = 5 -- mm
l_z = 5 -- mm
thickness = .2 -- mm
grid_unit = 2e-2 -- mm

local freq = 1 -- MHz
local V_0 = 1000 -- V

if pcall(debug.getlocal, 4, 1) then -- acting as an imported module
    local M = {}
    M.freq = freq
    M.V_0 = V_0
    return M
end
--]]

-- [[ build potential arrays
if not pcall(debug.getlocal, 4, 1) then -- acting as a main file
    local fname = "parallel_plates"
    simion.command(string.format("gem2pa %s.gem %s.pa#", fname, fname))
    simion.command(string.format("refine %s.pa#", fname))
end
--]]
