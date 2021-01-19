--[[
File: main.lua
Author: X. Chen
Description: entry portal of the repository
License: GNU GPLv3
--]]

-- [[ define parameters
local length = 260 -- mm
r_0 = 2 -- mm
r_m = r_0 * 2 -- mm
d = 2 -- mm
s = 1.1 -- mm
n_ring = math.ceil(length/d) + 1
grid_unit = 5e-3-- mm

local freq = 5.43 -- MHz
local V_0 = 108 -- V

if pcall(debug.getlocal, 4, 1) then -- acting as an imported module
    local M = {}
    M.freq = freq
    M.V_0 = V_0
    return M
end
--]]

-- [[ build potential arrays
if not pcall(debug.getlocal, 4, 1) then -- acting as a main file
    local fname = "ion_guide"
    simion.command(string.format("gem2pa %s.gem %s.pa#", fname, fname))
    simion.command(string.format("refine %s.pa#", fname))
end
--]]
