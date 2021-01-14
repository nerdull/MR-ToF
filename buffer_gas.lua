--[[
File: buffer_gas.lua
Author: X. Chen
Description: THE workbench program
License: GNU GPLv3
--]]

simion.workbench_program()

local M = simion.import "main.lua"
local a = M.a -- mm

local HS1 = simion.import "collision_hs1.lua"
adjustable _pressure_pa = 0.5 -- Pa
adjustable _trace_level = 2 -- keep an eye on ion's kinetic energy

function segment.initialize()
    if HS1.segment.initialize then
        HS1.segment.initialize()
    end
end

function segment.tstep_adjust()
    if HS1.segment.tstep_adjust then
        HS1.segment.tstep_adjust()
    end
end

function segment.other_actions()
    if HS1.segment.other_actions then
        HS1.segment.other_actions()
    end
    -- [[ periodic boundary condition
    ion_px_mm = ion_px_mm + 2*a * (ion_px_mm<-a and 1 or ion_px_mm>a and -1 or 0)
    ion_py_mm = ion_py_mm + 2*a * (ion_py_mm<-a and 1 or ion_py_mm>a and -1 or 0)
    ion_pz_mm = ion_pz_mm + 2*a * (ion_pz_mm<-a and 1 or ion_pz_mm>a and -1 or 0)
    --]]
end

function segment.terminate()
    if HS1.segment.terminate then
        HS1.segment.terminate()
    end
end
