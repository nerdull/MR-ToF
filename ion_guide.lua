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
adjustable _random_seed = 1 -- set 0 to let SIMION select the seed

local WAVE_F = simion.import "waveformlib.lua"
local WAVE_S = simion.import "waveformlib.lua"

local freq_s = nil -- MHz
local n_step = {} -- count the number of steps that the travelling wave has advanced
local file = io.open("ion_guide_ejection.ion", 'w') -- file handler to record ion state at equilibrium
local last_retrieval = nil -- micro-s
local n_state = 0 -- count the number of retrieved ion states
file:write
[[
;File: ion_guide_ejection.ion
;Author: X. Chen
;Description: definition of individual ions for ejection
;License: GNU GPLv3

;0
]]

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
            WAVE_F.electrode(7) {
                WAVE_F.lines {
                    {time=0, potential=_V_0}; -- micro-s, V
                    {time=1/(2*_freq_f), potential=_V_0};
                    {time=1/(2*_freq_f), potential=-_V_0};
                    {time=1/_freq_f, potential=-_V_0};
                };
            };
            WAVE_F.electrode(8) {
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
    adj_elect[8] = adj_elect[8] + _V_l
end

function retrieve()
    local speed, az, el = simion.rect3d_to_polar3d(ion_vx_mm, ion_vy_mm, ion_vz_mm)
    local ke = simion.speed_to_ke(speed, ion_mass)
    file:write(string.format(",%g,%d,%g,%g,%g,%g,%g,%g,,\n", ion_mass, ion_charge,
        ion_px_mm, ion_py_mm, ion_pz_mm, az, el, ke))
    last_retrieval = ion_time_of_flight
    n_state = n_state + 1
    print(string.format("retrieved %d states at %.3f ms", n_state, last_retrieval/1e3))
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
        print(string.format("Ion %d finished %d steps at %.3f ms, now ring %d is high.",
            ion_number, n_step[ion_number], ion_time_of_flight/1e3, n_step[ion_number]%4+1))
    elseif steps-steps_int > 1-1e-11 and n_step ~= steps_int+1 then -- undershoot
        n_step[ion_number] = steps_int + 1
        print(string.format("Ion %d finished %d steps at %.3f ms, now ring %d is high.",
            ion_number, n_step[ion_number], ion_time_of_flight/1e3, n_step[ion_number]%4+1))
    end
    --]]
    -- [[ record ion state at equilibrium
    if ion_time_of_flight >= 5000 then -- ion should have long been in equilibrium by 5 ms
        if n_state < 2000 then -- in total retrieve 2000 ion states over 10 ms
            if not last_retrieval then -- first time retrieval
                retrieve()
            elseif ion_time_of_flight - last_retrieval >= 5 then -- retrieve ion state every 5 micro-s
                retrieve()
            end
        else
            ion_splat = -5 -- kill the ion
        end
    end
    --]]
end

function segment.terminate()
    if HS1.segment.terminate then
        HS1.segment.terminate()
    end
end

function segment.terminate_run()
    file:close()
end
