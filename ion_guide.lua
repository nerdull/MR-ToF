--[[
File: ion_guide.lua
Author: X. Chen
Description: THE workbench program
License: GNU GPLv3
--]]

simion.workbench_program()

local M = simion.import "main.lua"
local n_ring = M.n_ring
local d = M.d -- mm
adjustable _freq = M.freq -- MHz
adjustable _V_0 = M.V_0 -- V

function segment.fast_adjust()
    -- [[ sine wave
    adj_elect[1] = _V_0 * math.sin(2*math.pi * _freq * ion_time_of_flight) -- V
    --]]
end


function segment.other_actions()
    -- [[ periodic boundary condition
    local left_boundary = -d * (n_ring-2) -- mm
    local right_boundary = d * (n_ring-2) -- mm
    local teleportation = right_boundary - left_boundary -- mm
    ion_px_mm = ion_px_mm + (ion_px_mm<left_boundary and teleportation or ion_px_mm>right_boundary and -teleportation or 0)
    --]]
end
