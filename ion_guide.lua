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

local HS1 = simion.import "collision_hs1.lua"
adjustable _pressure_pa = 0.5 -- set 0 to disable buffer gas, Pa
adjustable _trace_level = 0 -- don't keep an eye on ion's kinetic energy
adjustable _random_seed = 1 -- set 0 to let SIMION select the seed

local WAVE_F = simion.import "waveformlib.lua"

local TP = simion.import "testplanelib.lua"

local SO = simion.import "simplexoptimiser.lua"

local mode = "record" -- chosen from {"optimise", "record"}

local focal_y = {} -- mm, y-position of ions at the focal plane
local focal_z = {} -- mm, z-position of ions at the focal plane
local focal_tof = {} -- micro-s, time-of-flight of ions at the focal plane
local focal_ke = {} -- eV, kinetic energy of ions at the focal plane

local file -- handler for recording simulation result

local function monitor()
    local speed = math.sqrt(ion_vx_mm^2 + ion_vy_mm^2 + ion_vz_mm^2) -- mm/micro-s
    local ke = simion.speed_to_ke(speed, ion_mass) -- eV
    focal_y[#focal_y+1] = ion_py_mm
    focal_z[#focal_z+1] = ion_pz_mm
    focal_tof[#focal_tof+1] = ion_time_of_flight
    focal_ke[#focal_ke+1] = ke
    -- ion_splat = 1 --  prevent backwards crossing
    if mode == "record" then
        file:write(string.format("%d,%.5f,%.5f,%.5f,%.5f\n",
            ion_number, ion_py_mm, ion_pz_mm, ion_time_of_flight, ke))
    end
end
local screen = TP(focal_plane, 0, 0, 1, 0, 0, monitor) -- on-plane point and normal vector

local V1, V2, V3, V4 -- V, voltages of ring lens that need to be optimised
local metric -- objective function of the optimisation
local opt = SO {
    start = {20, 30, 10, 0}; -- V
    step = {20, 20, -20, -20}; -- V
    precision = 0; -- number of decimal places which the values are rounded to
}

local is_pulsed -- whether the drift tube is pulsed to high voltage
local t_pulse = 6.801 -- micro-s, starting timestamp of the pulse
local V_t = 3000 -- V, high voltage of the drift tube

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
    if mode == "optimise" then -- optimise the lens voltages and record the optimal result
        while opt:running() do
            print("=== try another parameter set ===")
            V1, V2, V3, V4 = opt:values()
            print("Lens voltages are " .. table.concat({V1, V2, V3, V4}, ", ") .. " V.")
            run()
            opt:result(metric)
        end
        print("=== replay the optimal run ===")
        mode = "record"
        V1, V2, V3, V4 = opt:optimal_values()
        run()
    elseif mode == "record" then -- record the result with the given lens voltages
        V1, V2, V3, V4 = unpack {36, 29, -4, 20} -- V
        run()
    end
end

function segment.initialize_run()
    -- [[ reset the seed to get consistent results over different runs
    if _random_seed ~=0 then
        simion.seed(_random_seed-1)
    end
    --]]
    if mode == "optimise" then -- refresh trajectory at each run but not retain
        sim_trajectory_image_control = 1
    elseif mode == "record" then -- view and retain trajectory for screenshot in the end
        sim_rerun_flym = 0
        sim_trajectory_image_control = 0
        print("Lens voltages are " .. table.concat({V1, V2, V3, V4}, ", ") .. " V.")
        file = io.open("result.txt", 'w')
        file:write("# ID,y(mm),z(mm),ToF(micro-s),KE(eV)\n")
        file:write(string.format("# x = %g mm\n", focal_plane))
        simion.printer.type = "png"
        simion.printer.filename = "screenshot.png"
        simion.printer.scale = 1
    end
end

function segment.initialize()
    if HS1.segment.initialize then
        HS1.segment.initialize()
    end
end

function segment.init_p_values()
    adj_elect[9] = 0
    adj_elect[10] = 0
end

function segment.tstep_adjust()
    if HS1.segment.tstep_adjust and ion_px_mm < focal_plane then
        HS1.segment.tstep_adjust()
    end
    if WAVE_F.segment.tstep_adjust then
        WAVE_F.segment.tstep_adjust()
    end
    if screen.tstep_adjust then
        screen.tstep_adjust()
    end
    -- [[
    if not is_pulsed then
        local dt = t_pulse - ion_time_of_flight
        ion_time_step = math.min(dt, ion_time_step)
    end
    --]]
end

function segment.fast_adjust()
    if WAVE_F.segment.fast_adjust then
        WAVE_F.segment.fast_adjust()
    end
    -- [[ lenses for ion ejection
    adj_elect[4] = adj_elect[4] + _V_l -- left blocking ring is always at high
    adj_elect[5] = adj_elect[5] + V1
    adj_elect[6] = adj_elect[6] + V2
    adj_elect[7] = adj_elect[7] + V3
    adj_elect[8] = adj_elect[8] + V4
    --]]
    -- [[
    if ion_time_of_flight < t_pulse then
        is_pulsed = false
    else
        adj_elect[9] = V_t
        is_pulsed = true
    end
    --]]
end

function segment.other_actions()
    if HS1.segment.other_actions and ion_px_mm < focal_plane then
        HS1.segment.other_actions()
    end
    if WAVE_F.segment.other_actions then
        WAVE_F.segment.other_actions()
    end
    if screen.other_actions then
        screen.other_actions()
    end
    -- [[ selectively fly every tenth ion 
    if ion_number % 10 ~= 0 then
        ion_splat = 1
    end
    --]]
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
    if #focal_y >= 60 then -- at least 60 entries to get reliable variances
        local mean_y, var_y = Stat.array_mean_and_variance(focal_y)
        local mean_z, var_z = Stat.array_mean_and_variance(focal_z)
        local mean_tof, var_tof = Stat.array_mean_and_variance(focal_tof)
        local mean_ke, var_ke = Stat.array_mean_and_variance(focal_ke)
        metric = math.sqrt((var_y+var_z)/2)
        print("Objective function is " .. metric .. '.')
        if mode == "record" then
            local str_r = string.format("<r> = %.3f%+.3fi mm, dr = %.3f mm", mean_y, mean_z, math.sqrt((var_y+var_z)/2)) 
            local str_tof = string.format("<tof> = %.3f micro-s, dtof = %.3f micro-s", mean_tof, math.sqrt(var_tof))
            local str_ke = string.format("<ke> = %.3f eV, dke = %.3f eV", mean_ke, math.sqrt(var_ke))
            file:write("# " .. str_r .. '\n'); print(str_r)
            file:write("# " .. str_tof .. '\n'); print(str_tof)
            file:write("# " .. str_ke .. '\n'); print(str_ke)
            file:close()
            simion.print_screen()
            sim_rerun_flym = 1 -- clear trajectory for the next run
        end
    else -- exception handling
        print("Warning: too few ions.")
        if mode == "optimise" then
            metric = math.huge
        elseif mode == "record" then
            file:close()
            simion.print_screen()
            sim_rerun_flym = 1 -- clear trajectory for the next run
        end
    end
    -- [[ reset arrays for the next run
    focal_y = {}
    focal_z = {}
    focal_tof = {}
    focal_ke = {}
    --]]
end
