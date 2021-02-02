--[[
File: main.lua
Author: X. Chen
Description: entry portal of the repository
License: GNU GPLv3
--]]

-- [[ define parameters
m_ring = 9 * 4 -- rings in transport section
n_ring = m_ring + 4 -- plus 4 rings in storage/ejection section
r_0 = 2 -- mm
r_m = r_0 * 2 -- mm
d = 2.3 -- mm
s = 1.4 -- mm
focus = 10 -- mm, distance relative to the exit of the ion guide
grid_unit = 5e-3-- mm

local freq_f = 3.15 -- MHz
local freq_ratio = 1575 -- integer, freq_s = (2*freq_f) / (4*freq_ratio)
local V_0 = 70 -- V
local V_l = 2.9 -- V
local r_f = r_0 -- mm, beam spot size in radius at the focal plane

if pcall(debug.getlocal, 4, 1) then -- acting as an imported module
    local M = {}
    M.freq_f = freq_f
    M.freq_ratio = freq_ratio
    M.V_0 = V_0
    M.V_l = V_l
    M.focal_plane = d*(n_ring-1) + s + focus
    M.r_f = r_f
    return M
end
--]]

-- [[ build potential arrays
if not pcall(debug.getlocal, 4, 1) then -- acting as a main file
    local fname = "ion_guide"
    simion.command(string.format("gem2pa %s.gem %s.pa#", fname, fname))
    simion.command(string.format("refine --convergence=5e-3 %s.pa#", fname)) -- default: 5e-3, lowest: 1e-7
end
--]]
