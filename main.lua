--[[
File: main.lua
Author: X. Chen
Description: entry portal of the repository
License: GNU GPLv3
--]]

-- [[ define parameters
a = 10 -- mm
grid_unit = .1 -- mm

if pcall(debug.getlocal, 4, 1) then -- acting as an imported module
    return { a = a }
end
--]]

-- [[ build potential arrays
if not pcall(debug.getlocal, 4, 1) then -- acting as a main file
    local fname = "monitor_screen"
    simion.command(string.format("gem2pa %s.gem %s.pa0", fname, fname))
end
--]]
