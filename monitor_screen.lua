--[[
File: monitor_screen.lua
Author: X. Chen
Description: THE workbench program
License: GNU GPLv3
--]]

simion.workbench_program()

local TP =  simion.import "testplanelib.lua"

local function trigger()
    print(string.format("Ion hits the screen at (%.1f, %.1f, %.1f) mm",
        ion_px_mm, ion_py_mm, ion_pz_mm))
    mark()
end

local monitor_screen = TP(8, 8, 8, 1, 1, 1, trigger) -- point coordinates and normal vector

function segment.tstep_adjust()
    if monitor_screen.tstep_adjust then
        monitor_screen.tstep_adjust()
    end
end

function segment.other_actions()
    if monitor_screen.other_actions then
        monitor_screen.other_actions()
    end
end
