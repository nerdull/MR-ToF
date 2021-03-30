----------------------------------------------------------------------------------------------------
----------      File        :   next.lua                                                  ----------
----------      Author      :   X. Chen                                                   ----------
----------      Description :   manager of the whole simulation                           ----------
----------      Note        :   the following units are adopted throughout the code       ----------
----------                          [length]    =   mm                                    ----------
----------                          [time]      =   µs                                    ----------
----------                          [frequency] =   MHz                                   ----------
----------                          [mass]      =   u                                     ----------
----------                          [charge]    =   e                                     ----------
----------                          [voltage]   =   V                                     ----------
----------                          [energy]    =   eV                                    ----------
----------                          [angle]     =   °                                     ----------
----------                          [tan angle] =   mrad                                  ----------
----------                          [pressure]  =   Pa                                    ----------
----------      License     :   GNU GPLv3                                                 ----------
----------------------------------------------------------------------------------------------------


simion.workbench_program()

-- dependent libraries
local Stat  =   require "simionx.Statistics"

local WAV_C =   simion.import "library/waveformlib.lua"
local HS1   =   simion.import "library/collision_hs1.lua"
local TP    =   simion.import "library/testplanelib.lua"


----------------------------------------------------------------------------------------------------
----------                                   Preparation                                  ----------
----------------------------------------------------------------------------------------------------

-- specify the simulating object
local object = "ion_guide"

-- define the potential array number and dimensions of each component
local var                   =   {}

var.ring_small_pa_num       =   1
var.ring_small_inner_radius =   2
var.ring_small_pitch        =   2.1
var.ring_small_thickness    =   1.1
var.ring_small_number       =   5

var.ring_blend              =   .5
var.ring_outer_radius       =   15

var.cap_pa_num              =   var.ring_small_pa_num + var.ring_small_number
var.cap_thickness           =   .5
var.cap_blend               =   var.cap_thickness / 2
var.cap_gap                 =   var.cap_thickness - (var.ring_small_pitch - var.ring_small_thickness) / 2
var.cap_inner_radius        =   var.ring_small_inner_radius
var.cap_outer_radius        =   var.ring_outer_radius

var.pipe_pa_num             =   var.cap_pa_num + 2
var.pipe_inner_radius       =   50
var.pipe_thickness          =   2
var.pipe_left_gap           =   5
var.pipe_right_gap          =   15

var.confine_rf_pa_num       =   var.ring_small_pa_num + var.ring_small_number
var.ground_pa_num           =   var.confine_rf_pa_num + 1

var.grid_size               =   5e-2

-- calculate the range for cropping potential array; values are in grid units
local crop_axial_start  =   math.ceil((    var.pipe_thickness + var.pipe_left_gap )                    / var.grid_size)
local crop_axial_span   =   math.ceil((    var.ring_small_pitch * var.ring_small_number
                                        + (var.cap_thickness + var.cap_gap) * 2 + var.pipe_right_gap ) / var.grid_size)
local crop_radial_span  =   math.ceil(     var.ring_outer_radius                                       / var.grid_size)
local crop_range        =   { crop_axial_start, 0, 0; crop_axial_span, crop_radial_span, 0 }

-- calculate the corresponding workbench bounds
local bound_axial_span  =   crop_axial_span  * var.grid_size
local bound_radial_span =   crop_radial_span * var.grid_size
local workbench_bounds  =   {
    xl  =   0                ,  xr  =   bound_axial_span ;
    yl  =  -bound_radial_span,  yr  =   bound_radial_span;
    zl  =  -bound_radial_span,  zr  =   bound_radial_span;
}

-- recursively compare whether the contents of two tables are identical
local function deep_compare(obj_1, obj_2)
    local type_1, type_2 = type(obj_1), type(obj_2)
    if type_1 ~= type_2 then return false end
    if type_1 ~= "table" then return obj_1 == obj_2 end
    if not deep_compare( getmetatable(obj_1), getmetatable(obj_2) ) then return false end
    for key_1, value_1 in next, obj_1, nil do
        local value_2 = obj_2[key_1]
        if value_2 == nil or not deep_compare(value_1, value_2) then return false end
    end
    return true
end

-- recursively copy the contents in a table
local function deep_copy(original)
    local copy
    if type(original) == "table" then
        copy = {}
        for original_key, original_value in next, original, nil do
            copy[ deep_copy(original_key) ] = deep_copy(original_value)
        end
        setmetatable( copy, deep_copy(getmetatable(original)) )
    else
        copy = original
    end
    return copy
end

-- build the potential array from .gem file, then refine and crop it
local function generate_potential_array(fname, force, conv)
    if not force and deep_compare(_G.shared_table, var) then return end
    _G.shared_table = deep_copy(var)

    local gem_file = "geometry/"..fname..".gem"
    local pa_file  = "geometry/"..fname..".pa#"
    simion.command( "gem2pa "..gem_file..' '..pa_file )

    local inst = simion.wb.instances[1]
    inst.pa:load(pa_file)
    inst.pa:refine { convergence = conv or 5e-3 }
    inst.pa.filename = pa_file:sub(1,-4).."pa0"

    inst.pa:crop( unpack(crop_range) )
    inst:_debug_update_size()
    simion.redraw_screen()
    simion.wb.bounds = workbench_bounds
end

-- specify test particles
local particle_definition = {
    mass        =   202.984;
    charge      =   1;
    ke          =   2.673;
    az          =   0;
    el          =   17.257;
    position    =   simion.fly2.vector(1e-7, .63, 0);
}
local particle_definition = "ion_guide_ejection" -- alternative
local sample_px_offset = var.cap_thickness + var.cap_gap -- relative to the first 2-mm ring

-- conversion from .ion format to .fly2 format
local function ion_to_fly2(fname, stride)
    local count = 0
    local t = { coordinates = 0 }
    for line in io.lines( "particle/"..fname..".txt" ) do
        if not line:match "^#" and line ~= '' then
            count = count + 1
            if count % (stride or 1) == 0 then
                local tob, mass, charge, x, y, z, az, el, ke, cwf, color = line:match
                    "([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)"
                t[#t+1]         =   simion.fly2.standard_beam {
                    mass        =   tonumber(mass);
                    charge      =   tonumber(charge);
                    ke          =   tonumber(ke);
                    az          =   tonumber(az);
                    el          =   tonumber(el);
                    tob         =   tonumber(tob)   or  0;
                    cwf         =   tonumber(cwf)   or  1;
                    color       =   tonumber(color) or  0;
                    position    =   simion.fly2.vector( tonumber(x) + sample_px_offset, tonumber(y), tonumber(z) );
                }
            end
        end
    end
    return simion.fly2.particles(t)
end

-- define test particles in .fly2 format
local function generate_particles(obj, stride)
    local key
    for k, v in next, debug.getregistry(), nil do
        if type(v) == "table" and v.iterator then key = k; break end
    end

    local fly2
    if type(obj) == "table" then
        fly2 = simion.fly2.particles { 
            coordinates = 0;
            simion.fly2.standard_beam(obj);
        }
    elseif type(obj) == "string" then
        fly2 = ion_to_fly2(obj, stride)
    end

    debug.getregistry()[key] = fly2
end

-- define RF parameters for radial confinement
local confine_frequency   =   3.73
local confine_voltage     =   80

-- generate the confining square-wave RF
local function generate_confine_rf(freq, amp)
    local wav = WAV_C.waveforms {
        WAV_C.electrode(var.confine_rf_pa_num) { WAV_C.lines {
            { time  =   0           ,   potential   =   amp };
            { time  =   1/freq * 1/2,   potential   =   amp };
            { time  =   1/freq * 1/2,   potential   =  -amp };
            { time  =   1/freq      ,   potential   =  -amp };
        }};
    }
    WAV_C.install {
        waves       =   wav;
        frequency   =   freq;
    }
end

-- ejection only takes place when the first 2-mm ring is at high
local lifting_voltage  = 2.9

-- ion-neutral collisional parameters
adjustable _gas_mass_amu    =   4.00260325413   -- helium
adjustable _temperature_k   =   295             -- room temperature
adjustable _pressure_pa     =   1e-1            -- set 0 to disable buffer gas
adjustable _trace_level     =   0               -- don't keep an eye on ion's kinetic energy
adjustable _mark_collisions =   0               -- don't place a red dot on each collision

-- freeze the random state for reproducible simulation results, set 0 to thaw
local random_seed = 0

-- round off the number to a given decimal place
local function round(x, decimal)
    return tonumber(("%%.%df"):format(decimal or 0):format(x))
end

-- get ion's equilibrium position by means of exponetial moving average
local ion_px_average        =   {}
local ion_px_equilibrium    =   {}
local ion_px_check_time     =   {}
local average_time          =   100 / confine_frequency
local revisit_interval      =   average_time

-- return true if the ion reaches its equilibrium
local function get_ion_px_equilibrium()
    local average_factor        =   ion_time_step / average_time
    ion_px_average[ion_number]  =   average_factor * ion_px_mm + (1 - average_factor) * (ion_px_average[ion_number] or ion_px_mm)
    if ion_time_of_flight - (ion_px_check_time[ion_number] or 0) < revisit_interval then return end

    local ion_px_average_round = round(ion_px_average[ion_number], 1)
    if ion_px_equilibrium[ion_number] ~= ion_px_average_round then
        ion_px_equilibrium[ion_number] = ion_px_average_round
        ion_px_check_time[ion_number]  = ion_time_of_flight
    else
        return true
    end
end

-- register the fate of each ion
local die_from  = {}
local causes    = {
        [1]     =   "ready for ejection";
        [-1]    =   "hitting electrode";
        [-2]    =   "dead in water";
        [-3]    =   "outside workbench";
        [-4]    =   "ion killed";
}

-- record simulation results
local file_handler
local file_id
simion.printer.type  = "png"
simion.printer.scale = 1

-- ejection voltages for last 4 rings, respectively
local v1, v2, v3, v4

-- set a virtual screen to monitor the beam emittance
local emittance_ycoord  =   {}
local emittance_yprime  =   {}
local emittance_zcoord  =   {}
local emittance_zprime  =   {}

local function monitor()
    k = #emittance_ycoord + 1
    emittance_ycoord[k] =   ion_py_mm
    emittance_yprime[k] =   ion_vy_mm / ion_vx_mm * 1e3
    emittance_zcoord[k] =   ion_pz_mm
    emittance_zprime[k] =   ion_vz_mm / ion_vx_mm * 1e3
end

local screen = TP(bound_axial_span, 0, 0, 1, 0, 0, monitor)

-- compute the (co)variance of an array(s)
local function array_variance(a1, a2)
    if a2 == nil then a2 = a1 end
    assert(#a1 == #a2)

    local m1    =   Stat.array_mean(a1)
    local m2    =   Stat.array_mean(a2)
    local sum   =   0
    for k, v1 in next, a1, nil do
        local v2 = a2[k]
        sum = sum + (v1 - m1) * (v2 - m2)
    end
    return sum / #a1
end


----------------------------------------------------------------------------------------------------
----------                                  Fly particles                                 ----------
----------------------------------------------------------------------------------------------------

function segment.load()
    simion.window.state = "maximized"
    sim_trajectory_image_control = 1
end

function segment.flym()
    generate_potential_array(object)
    generate_particles(particle_definition)

    file_handler = io.open(("result%s.txt"):format(file_id or ''), 'w')
    file_handler:write("v1,v2,v3,v4,y emittance,z emittance\n")
    v2, v3, v4 = 10, -20, -25
    for v = 20, 23 do
        v1 = v
        run()
    end
    file_handler:close()
end

function segment.initialize_run()
    if random_seed ~= 0 then simion.seed(random_seed - 1) end
end

function segment.init_p_values()
    simion.wb.instances[1].pa:fast_adjust {
        [var.ring_small_pa_num] = lifting_voltage;
        [var.ground_pa_num]     = 0;
    }
    generate_confine_rf(confine_frequency, confine_voltage)
end

function segment.tstep_adjust()
    WAV_C.segment.tstep_adjust()
    HS1.segment.tstep_adjust()
    screen.tstep_adjust()
end

function segment.fast_adjust()
    WAV_C.segment.fast_adjust()
    adj_elect[var.ring_small_pa_num + 1] = v1
    adj_elect[var.ring_small_pa_num + 2] = v2
    adj_elect[var.ring_small_pa_num + 3] = v3
    adj_elect[var.ring_small_pa_num + 4] = v4
end

function segment.other_actions()
    HS1.segment.other_actions()
    screen.other_actions()
end

function segment.terminate()
    HS1.segment.terminate()
end

function segment.terminate_run()
    emittance_y = 4 * math.sqrt(array_variance(emittance_ycoord) * array_variance(emittance_yprime) - array_variance(emittance_ycoord, emittance_yprime)^2)
    emittance_z = 4 * math.sqrt(array_variance(emittance_zcoord) * array_variance(emittance_zprime) - array_variance(emittance_zcoord, emittance_zprime)^2)
    file_handler:write(table.concat({v1, v2, v3, v4, emittance_y, emittance_z}, ',')..'\n')
    emittance_ycoord    =   {}
    emittance_yprime    =   {}
    emittance_zcoord    =   {}
    emittance_zprime    =   {}
end
