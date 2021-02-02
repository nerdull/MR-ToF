--[[
File: ion_guide.lua
Author: X. Chen
Description: THE workbench program
License: GNU GPLv3
--]]

simion.workbench_program()

local Stat = require "simionx.Statistics"

local M = simion.import "main.lua"
adjustable _freq_f = M.freq_f -- MHz
adjustable _freq_ratio = M.freq_ratio
adjustable _V_0 = M.V_0 -- V
adjustable _V_l = M.V_l -- V
local focal_plane = M.focal_plane -- mm
local r_f = M.r_f -- mm

local HS1 = simion.import "collision_hs1.lua"
adjustable _pressure_pa = 0.5 -- set 0 to disable buffer gas, Pa
adjustable _trace_level = 2 -- keep an eye on ion's kinetic energy
adjustable _random_seed = 1 -- set 0 to let SIMION select the seed

local WAVE_F = simion.import "waveformlib.lua"

local TP = simion.import "testplanelib.lua"

local file -- handler to record ion's final kinetic state
local splat_y = {} -- mm, y-position of splashed ions at the focal plane
local splat_z = {} -- mm, z-position of splashed ions at the focal plane
local splat_tof = {} -- micro-s, time-of-flight of splashed ions
local splat_ke = {} -- eV, kinetic energy of splashed ions

local function monitor()
    local r, _ = simion.rect_to_polar(ion_py_mm, ion_pz_mm) -- mm, degree
    if r <= r_f then -- focused nicely
        local speed = math.sqrt(ion_vx_mm^2 + ion_vy_mm^2 + ion_vz_mm^2) -- mm/micro-s
        local ke = simion.speed_to_ke(speed, ion_mass) -- eV
        splat_y[#splat_y+1] = ion_py_mm
        splat_z[#splat_z+1] = ion_pz_mm
        splat_tof[#splat_tof+1] = ion_time_of_flight
        splat_ke[#splat_ke+1] = ke
        file:write(string.format("%d,%.5f,%.5f,%.5f,%.5f,%.5f\n",
            ion_number, ion_py_mm, ion_pz_mm, r, ion_time_of_flight, ke))
    end
end
local screen = TP(focal_plane, 0, 0, 1, 0, 0, monitor) -- on-plane point and normal vector

function segment.flym()
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
    file = io.open("result.txt", 'w')
    file:write("# ID,y(mm),z(mm),r(mm),ToF(micro-s),KE(eV)\n")
    run()
    file:close()
end

function segment.initialize_run()
    -- [[ reset the seed to get consistent results over different runs
    if _random_seed ~=0 then
        simion.seed(_random_seed-1)
    end
    --]]
    -- [[ view and retain trajectory for screenshot in the end
    sim_rerun_flym = 0
    sim_trajectory_image_control = 0
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
    if screen.tstep_adjust then
        screen.tstep_adjust()
    end
end

function segment.fast_adjust()
    if WAVE_F.segment.fast_adjust then
        WAVE_F.segment.fast_adjust()
    end
    -- [[ ejection
    adj_elect[4] = adj_elect[4] + _V_l -- left blocking ring is always at high
    adj_elect[5] = adj_elect[5] + _V_l/10*16.82
    adj_elect[6] = adj_elect[6] - _V_l/10*1.25
    adj_elect[7] = adj_elect[7] - _V_l/10*3.2
    adj_elect[8] = adj_elect[8] - _V_l/10*25
    adj_elect[9] = -_V_l/10*20
    --]]
end

function segment.other_actions()
    if HS1.segment.other_actions then
        HS1.segment.other_actions()
    end
    if WAVE_F.segment.other_actions then
        WAVE_F.segment.other_actions()
    end
    if screen.other_actions then
        screen.other_actions()
    end
    -- [[ forcibly kill trapped ions
    if ion_time_of_flight >= 30 then
        ion_splat = 1
    end
    --]]
end

function segment.terminate()
    if HS1.segment.terminate then
        HS1.segment.terminate()
    end
end

function segment.terminate_run()
    -- [[ result summary
    if #splat_y > 0 then
        local mean_y, var_y = Stat.array_mean_and_variance(splat_y)
        local mean_z, var_z = Stat.array_mean_and_variance(splat_z)
        local mean_tof, var_tof = Stat.array_mean_and_variance(splat_tof)
        local mean_ke, var_ke = Stat.array_mean_and_variance(splat_ke)
        local str_r = string.format("<r> = %.3f%+.3fi mm, dr = %.3f mm", mean_y, mean_z, math.sqrt(var_y+var_z)) 
        local str_tof = string.format("<tof> = %.3f micro-s, dtof = %.3f micro-s", mean_tof, math.sqrt(var_tof))
        local str_ke = string.format("<ke> = %.3f eV, dke = %.3f eV", mean_ke, math.sqrt(var_ke))
        print(str_r)
        print(str_tof)
        print(str_ke)
        file:write("# " .. str_r .. '\n')
        file:write("# " .. str_tof .. '\n')
        file:write("# " .. str_ke .. '\n')
    end
    --]]
    -- [[ reset arrays for the next run
    splat_y = {}
    splat_z = {}
    splat_tof = {}
    splat_ke = {}
    --]]
    -- [[ take a screenshot, then clear trajectory for the next run
    simion.printer.type = "png"
    simion.printer.filename = "screenshot.png"
    simion.printer.scale = 1
    simion.print_screen()
    sim_rerun_flym = 1
    --]]
end
