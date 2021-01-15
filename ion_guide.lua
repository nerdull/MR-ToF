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

local HS1 = simion.import "collision_hs1.lua"
adjustable _pressure_pa = 0.5 -- set 0 to disable buffer gas, Pa
adjustable _trace_level = 2 -- keep an eye on ion's kinetic energy

local WAVE = simion.import "waveformlib.lua"

local last_pos_print = 0 -- micro-s
local teleport_dist = 0 -- accumulated distance over which ion has been teleported so far, mm
-- print ion's x-pos every this number of micro-s, or when it is teleported
-- set 0 to print every ion_time_step
-- set an negative value to disable print
adjustable _pos_print_period = 100

function segment.initialize_run()
    WAVE.install {
        waves = WAVE.waveforms {
            WAVE.electrode(1) {
                WAVE.lines {
                    -- [[ square wave
                    {time=0, potential=_V_0}; -- micro-s, V
                    {time=1/(2*_freq), potential=_V_0};
                    {time=1/(2*_freq), potential=-_V_0};
                    {time=1/_freq, potential=-_V_0};
                    --]]
                    --[[ sawtooth wave
                    {time=0, potential=_V_0}; -- micro-s, V
                    {time=1/_freq, potential=-_V_0};
                    --]]
                    --[[ pulse wave
                    {time=0, potential=_V_0}; -- micro-s, V
                    {time=1/(4*_freq), potential=_V_0};
                    {time=1/(4*_freq), potential=-_V_0/3};
                    {time=1/_freq, potential=-_V_0/3};
                    --]]
                };
            };
        };
        frequency = _freq; -- MHz
    }
    -- WAVE.plot_waveform() -- plot the waveform in Excel
end

function segment.initialize()
    if HS1.segment.initialize then
        HS1.segment.initialize()
    end
end

function segment.tstep_adjust()
    if HS1.segment.tstep_adjust then
        HS1.segment.tstep_adjust()
    end
    if WAVE.segment.tstep_adjust then
        WAVE.segment.tstep_adjust()
    end
end

function segment.fast_adjust()
    if WAVE.segment.fast_adjust then
        WAVE.segment.fast_adjust()
    end
end

function segment.other_actions()
    if HS1.segment.other_actions then
        HS1.segment.other_actions()
    end
    if WAVE.segment.other_actions then
        WAVE.segment.other_actions()
    end
    -- [[ regularly print x-position
    function pos_print()
        if _pos_print_period < 0 then return end
        print("position = " .. ion_px_mm-teleport_dist .. " mm")
        last_pos_print = ion_time_of_flight
    end
    if ion_time_of_flight - last_pos_print > _pos_print_period then pos_print() end
    --]]
    -- [[ periodic boundary condition
    local left_boundary = -d * (n_ring-2) -- mm
    local right_boundary = d * (n_ring-2) -- mm
    local teleportation = right_boundary - left_boundary -- mm
    if ion_px_mm < left_boundary then
        ion_px_mm = ion_px_mm + teleportation
        teleport_dist = teleport_dist + teleportation
        pos_print()
    elseif ion_px_mm > right_boundary then
        ion_px_mm = ion_px_mm - teleportation
        teleport_dist = teleport_dist - teleportation
        pos_print()
    end
    --]]
end

function segment.terminate()
    if HS1.segment.terminate then
        HS1.segment.terminate()
    end
end
