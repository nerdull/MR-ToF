--[[
File: parallel_plates.lua
Author: X. Chen
Description: THE workbench program
License: GNU GPLv3
--]]

simion.workbench_program()

local M = simion.import "main.lua"
adjustable _freq = M.freq -- MHz
adjustable _V_0 = M.V_0 -- V

local HS1 = simion.import "collision_hs1.lua"
adjustable _pressure_pa = 0 -- disable buffer gas
adjustable _trace_level = 2 -- keep an eye on ion's kinetic energy

local WAVE = simion.import "waveformlib.lua"

function segment.initialize_run()
    WAVE.install {
        waves = WAVE.waveforms {
            WAVE.electrode(1) {
                WAVE.lines {
                    {time=0, potential=0}; -- micro-s, V
                    {time=1/(10*_freq), potential=-3*_V_0};
                    {time=3/(10*_freq), potential=3*_V_0};
                    {time=2/(5*_freq), potential=0};
                    {time=1/_freq, potential=0};
                };
            };
            WAVE.electrode(2) {
                WAVE.lines {
                    {time=0, potential=0}; -- micro-s, V
                    {time=3/(5*_freq), potential=0};
                    {time=3/(5*_freq), potential=-2*_V_0};
                    {time=4/(5*_freq), potential=-2*_V_0};
                    {time=4/(5*_freq), potential=4*_V_0};
                    {time=9/(10*_freq), potential=4*_V_0};
                    {time=9/(10*_freq), potential=0};
                    {time=1/_freq, potential=0};
                };
            };
        };
        frequency = _freq; -- MHz
        pe_update_period = 1/(10*_freq); -- micro-s, set to nil to disable updating PE surface
    }
    WAVE.plot_waveform() -- plot the waveform in Excel
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
end

function segment.terminate()
    if HS1.segment.terminate then
        HS1.segment.terminate()
    end
end
