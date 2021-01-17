--[[
File: ion_guide.lua
Author: X. Chen
Description: THE workbench program
License: GNU GPLv3
--]]

simion.workbench_program()

local M = simion.import "main.lua"
adjustable _freq = M.freq -- MHz
adjustable _V_0 = M.V_0 -- V

local HS1 = simion.import "collision_hs1.lua"
adjustable _pressure_pa = 0.5 -- set 0 to disable buffer gas, Pa
adjustable _trace_level = 2 -- keep an eye on ion's kinetic energy

local WAVE = simion.import "waveformlib.lua"

function segment.initialize_run()
    WAVE.install {
        waves = WAVE.waveforms {
            WAVE.electrode(1) {
                WAVE.lines {
                    {time=0, potential=_V_0}; -- micro-s, V
                    {time=1/(2*_freq), potential=_V_0};
                    {time=1/(2*_freq), potential=-_V_0};
                    {time=1/_freq, potential=-_V_0};
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
end

function segment.terminate()
    if HS1.segment.terminate then
        HS1.segment.terminate()
    end
end
