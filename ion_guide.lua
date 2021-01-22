--[[
File: ion_guide.lua
Author: X. Chen
Description: THE workbench program
License: GNU GPLv3
--]]

simion.workbench_program()

local M = simion.import "main.lua"
adjustable _freq_f = M.freq_f -- MHz
adjustable _freq_ratio = M.freq_ratio
adjustable _V_0 = M.V_0 -- V
adjustable _V_l = M.V_l -- V

local HS1 = simion.import "collision_hs1.lua"
adjustable _pressure_pa = 0.5 -- set 0 to disable buffer gas, Pa
adjustable _trace_level = 2 -- keep an eye on ion's kinetic energy

local WAVE_F = simion.import "waveformlib.lua"
local WAVE_S = simion.import "waveformlib.lua"

local freq_s = nil -- MHz
local n_step = {} -- count the number of steps that the travelling wave has advanced

function segment.initialize_run()
    -- put it here so that it can be properly updated once _freq_ratio is set manually
    freq_s = _freq_f / (2*_freq_ratio) -- MHz
    -- [[ fast RF for radial confinement
    WAVE_F.install {
        waves = WAVE_F.waveforms {
            WAVE_F.electrode(1) {
                WAVE_F.lines {
                    {time=0, potential=_V_0}; -- micro-s, V
                    {time=1/(2*_freq_f), potential=_V_0};
                    {time=1/(2*_freq_f), potential=-_V_0};
                    {time=1/_freq_f, potential=-_V_0};
                };
            };
            WAVE_F.electrode(2) {
                WAVE_F.lines {
                    {time=0, potential=-_V_0}; -- micro-s, V
                    {time=1/(2*_freq_f), potential=-_V_0};
                    {time=1/(2*_freq_f), potential=_V_0};
                    {time=1/_freq_f, potential=_V_0};
                };
            };
            WAVE_F.electrode(3) {
                WAVE_F.lines {
                    {time=0, potential=_V_0}; -- micro-s, V
                    {time=1/(2*_freq_f), potential=_V_0};
                    {time=1/(2*_freq_f), potential=-_V_0};
                    {time=1/_freq_f, potential=-_V_0};
                };
            };
            WAVE_F.electrode(4) {
                WAVE_F.lines {
                    {time=0, potential=-_V_0}; -- micro-s, V
                    {time=1/(2*_freq_f), potential=-_V_0};
                    {time=1/(2*_freq_f), potential=_V_0};
                    {time=1/_freq_f, potential=_V_0};
                };
            };
            WAVE_F.electrode(5) {
                WAVE_F.lines {
                    {time=0, potential=_V_0}; -- micro-s, V
                    {time=1/(2*_freq_f), potential=_V_0};
                    {time=1/(2*_freq_f), potential=-_V_0};
                    {time=1/_freq_f, potential=-_V_0};
                };
            };
            WAVE_F.electrode(6) {
                WAVE_F.lines {
                    {time=0, potential=-_V_0}; -- micro-s, V
                    {time=1/(2*_freq_f), potential=-_V_0};
                    {time=1/(2*_freq_f), potential=_V_0};
                    {time=1/_freq_f, potential=_V_0};
                };
            };
        };
        frequency = _freq_f; -- MHz
    }
    --]]
    -- [[ slow RF for axial transport
    WAVE_S.install {
        waves = WAVE_S.waveforms {
            WAVE_S.electrode(1) {
                WAVE_S.lines {
                    {time=0, potential=_V_l}; -- micro-s, V
                    {time=1/(4*freq_s), potential=_V_l};
                    {time=1/(4*freq_s), potential=0};
                    {time=1/freq_s, potential=0};
                };
            };
            WAVE_S.electrode(2) {
                WAVE_S.lines {
                    {time=0, potential=0}; -- micro-s, V
                    {time=1/(4*freq_s), potential=0};
                    {time=1/(4*freq_s), potential=_V_l};
                    {time=1/(2*freq_s), potential=_V_l};
                    {time=1/(2*freq_s), potential=0};
                    {time=1/freq_s, potential=0};
                };
            };
            WAVE_S.electrode(3) {
                WAVE_S.lines {
                    {time=0, potential=0}; -- micro-s, V
                    {time=1/(2*freq_s), potential=0};
                    {time=1/(2*freq_s), potential=_V_l};
                    {time=3/(4*freq_s), potential=_V_l};
                    {time=3/(4*freq_s), potential=0};
                    {time=1/freq_s, potential=0};
                };
            };
            WAVE_S.electrode(4) {
                WAVE_S.lines {
                    {time=0, potential=0}; -- micro-s, V
                    {time=3/(4*freq_s), potential=0};
                    {time=3/(4*freq_s), potential=_V_l};
                    {time=1/freq_s, potential=_V_l};
                };
            };
        };
        frequency = freq_s; -- MHz
    }
    --]]
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
    if WAVE_F.segment.tstep_adjust then
        WAVE_F.segment.tstep_adjust()
    end
end

function segment.fast_adjust()
    if WAVE_F.segment.fast_adjust then
        WAVE_F.segment.fast_adjust()
    end
    if WAVE_S.segment.fast_adjust then
        WAVE_S.segment.fast_adjust("append")
    end
    -- blocking barrier on the end ring
    adj_elect[6] = adj_elect[6] + _V_l
end

function segment.other_actions()
    if HS1.segment.other_actions then
        HS1.segment.other_actions()
    end
    if WAVE_F.segment.other_actions then
        WAVE_F.segment.other_actions()
    end
    if WAVE_S.segment.other_actions then
        WAVE_S.segment.other_actions()
    end
    -- [[ count the travelling wave's steps
    local steps = ion_time_of_flight * 4*freq_s
    local steps_int = math.floor(steps)
    if steps-steps_int < 1e-11 and n_step[ion_number] ~= steps_int then -- overshoot
        n_step[ion_number] = steps_int
        print(string.format("Ion %d: finished %d steps at %.3f ms, now ring %d is high.",
            ion_number, n_step[ion_number], ion_time_of_flight/1e3, n_step[ion_number]%4+1))
    elseif steps-steps_int > 1-1e-11 and n_step ~= steps_int+1 then -- undershoot
        n_step[ion_number] = steps_int + 1
        print(string.format("Ion %d: finished %d steps at %.3f ms, now ring %d is high.",
            ion_number, n_step[ion_number], ion_time_of_flight/1e3, n_step[ion_number]%4+1))
    end
    --]]
end

function segment.terminate()
    if HS1.segment.terminate then
        HS1.segment.terminate()
    end
end
