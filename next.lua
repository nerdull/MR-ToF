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
----------                          [pressure]  =   Pa                                    ----------
----------      License     :   GNU GPLv3                                                 ----------
----------------------------------------------------------------------------------------------------


simion.workbench_program()

-- dependent libraries
local WAV_C =   simion.import "library/waveformlib.lua"
local WAV_T =   simion.import "library/waveformlib.lua"
local HS1   =   simion.import "library/collision_hs1.lua"


----------------------------------------------------------------------------------------------------
----------                                   Preparation                                  ----------
----------------------------------------------------------------------------------------------------

-- specify the simulating object
local object = "ion_guide"

-- define the potential array number and dimensions of each component
local var                   =   {}

var.ring_focus_pa_num       =   1
var.ring_focus_inner_radii  =   { 7.00, 7.00, 7.00, 6.50, 6.00, 5.50, 4.75, 4.00 }
var.ring_focus_pitches      =   { 2.50, 2.50, 2.50, 2.50, 2.50, 2.50, 2.40, 2.40 }
var.ring_focus_thicknesses  =   { 1.30, 1.30, 1.30, 1.30, 1.30, 1.30, 1.20, 1.20 }
var.ring_focus_number       =   #var.ring_focus_inner_radii

var.ring_big_pa_num         =   var.ring_focus_pa_num + var.ring_focus_number
var.ring_big_inner_radius   =   7
var.ring_big_pitch          =   2.5
var.ring_big_thickness      =   1.3
var.ring_big_number         =   84

var.ring_taper_pa_num       =   var.ring_big_pa_num + var.ring_big_number
var.ring_taper_inner_radii  =   { 6.00, 4.75, 3.75, 2.75, 2.25, 2.00 }
var.ring_taper_pitches      =   { 2.50, 2.40, 2.40, 2.30, 2.20, 2.10 }
var.ring_taper_thicknesses  =   { 1.30, 1.20, 1.20, 1.20, 1.10, 1.10 }
var.ring_taper_number       =   #var.ring_taper_inner_radii

var.ring_small_pa_num       =   var.ring_taper_pa_num + var.ring_taper_number
var.ring_small_inner_radius =   2
var.ring_small_pitch        =   2.1
var.ring_small_thickness    =   1.1
var.ring_small_number       =   4

var.ring_blend              =   .5
var.ring_outer_radius       =   15

var.cap_pa_num              =   var.ring_small_pa_num + var.ring_small_number
var.cap_thickness           =   .5
var.cap_blend               =   var.cap_thickness / 2
var.cap_left_gap            =   var.cap_thickness - (var.ring_focus_pitches[1] - var.ring_focus_thicknesses[1]) / 2
var.cap_left_inner_radius   =   var.ring_focus_inner_radii[1]
var.cap_right_gap           =   var.cap_thickness - (var.ring_small_pitch - var.ring_small_thickness) / 2
var.cap_right_inner_radius  =   var.ring_small_inner_radius
var.cap_outer_radius        =   var.ring_outer_radius

var.pipe_pa_num             =   var.cap_pa_num + 2
var.pipe_inner_radius       =   50
var.pipe_thickness          =   2
var.pipe_left_gap           =   15
var.pipe_right_gap          =   5

var.confine_rf_pa_num       =   1
var.travel_wave_pa_num      =   var.confine_rf_pa_num + 1
var.travel_wave_length      =   4
var.threshold_pa_num        =   var.travel_wave_pa_num + var.travel_wave_length
var.block_pa_num            =   var.threshold_pa_num + 1
var.ground_pa_num           =   var.block_pa_num + 1

var.grid_size               =   1e-2

-- calculate the range for cropping potential array; values are in grid units
local ring_length =   var.ring_big_pitch * var.ring_big_number + var.ring_small_pitch * var.ring_small_number + var.cap_left_gap + var.cap_right_gap
for k, ring_focus_pitch in next, var.ring_focus_pitches, nil do ring_length = ring_length + ring_focus_pitch end
for k, ring_taper_pitch in next, var.ring_taper_pitches, nil do ring_length = ring_length + ring_taper_pitch end

local crop_axial_start  =   math.ceil(  var.pipe_thickness                                        / var.grid_size)
local crop_axial_span   =   math.ceil(( ring_length + var.cap_thickness * 2 + var.pipe_left_gap ) / var.grid_size)
local crop_radial_span  =   math.ceil(  var.ring_outer_radius                                     / var.grid_size)
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
local particle_definition = "ion_guide_injection" -- alternative

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
                    position    =   simion.fly2.vector( tonumber(x), tonumber(y), tonumber(z) );
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
local confine_frequency   =   3.82
local confine_voltage     =   82

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

-- define travelling wave parameters for axial transport
-- the phase is chosen from { 0, ..., wave_length - 1 }
local lifting_duration  =   750
local lifting_voltage   =   2.5
local lifting_phase     =   0

-- generate the travelling square wave
local function generate_travel_wave(t, amp, phase)
    local wav = {}
    for i = 0, var.travel_wave_length - 1 do
        local j = (i + (phase or 0) ) % var.travel_wave_length
        wav[#wav+1] = WAV_T.electrode(var.travel_wave_pa_num + j) { WAV_T.lines {
            { time  =   0                         , potential   =   0   };
            { time  =   t *  i                    , potential   =   0   };
            { time  =   t *  i                    , potential   =   amp };
            { time  =   t * (i + 1)               , potential   =   amp };
            { time  =   t * (i + 1)               , potential   =   0   };
            { time  =   t * var.travel_wave_length, potential   =   0   };
        }}
    end
    WAV_T.install {
        waves       =   WAV_T.waveforms(wav);
        frequency   =   1/t * 1/4;
    }
end

-- empoly a thresholding potential to bring back in reflected ions
local threshold_voltage = 1.3

-- employ another blocking potential to guard the exit gate
local block_voltage = lifting_voltage

-- ion-neutral collisional parameters
adjustable _gas_mass_amu    =   4.00260325413   -- helium
adjustable _temperature_k   =   295             -- room temperature
adjustable _pressure_pa     =   1e-1            -- set 0 to disable buffer gas
adjustable _trace_level     =   0               -- don't keep an eye on ion's kinetic energy
adjustable _trace_skip      =   1               -- don't skip any mean kinetic energy value
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
local average_time          =   lifting_duration / 15
local revisit_interval      =   average_time

-- return true if the ion reaches its equilibrium
local function get_ion_px_equilibrium(decimal)
    local average_factor        =   ion_time_step / average_time
    ion_px_average[ion_number]  =   average_factor * ion_px_mm + (1 - average_factor) * (ion_px_average[ion_number] or ion_px_mm)
    if ion_time_of_flight - (ion_px_check_time[ion_number] or 0) < revisit_interval then return end

    local ion_px_average_round = round(ion_px_average[ion_number], decimal or 1)
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
        [3]     =   "flying through";
        [2]     =   "reflected";
        [1]     =   "trapped";
        [-1]    =   "hitting electrode";
        [-2]    =   "dead in water";
        [-3]    =   "outside workbench";
        [-4]    =   "ion killed";
}

-- counter for different ion splats
local count_trapped, count_reflected, count_escaped, count_blocked

-- record simulation results
local file_handler
local file_id
simion.printer.type  = "png"
simion.printer.scale = 1

-- x-position of the waiting point for final ejection
local waiting_point = var.pipe_left_gap + var.cap_thickness + var.cap_left_gap
for k, ring_focus_pitch in next, var.ring_focus_pitches, nil do waiting_point = waiting_point + ring_focus_pitch end
waiting_point = waiting_point + var.ring_big_pitch * var.ring_big_number
for k, ring_taper_pitch in next, var.ring_taper_pitches, nil do waiting_point = waiting_point + ring_taper_pitch end
waiting_point = waiting_point + var.ring_small_pitch * 1.5

-- sample the ion states when it has been thermalised
local next_sample_time
local sample_px_offset
local remaining_samples = 300
local function next_sample_interval() return 10 * simion.rand() / confine_frequency end

local function sample_ion_state()
    simion.mark()
    local speed, az, el = simion.rect3d_to_polar3d(ion_vx_mm, ion_vy_mm, ion_vz_mm)
    local ke = simion.speed_to_ke(speed, ion_mass)
    file_handler:write( ','..ion_mass..','..ion_charge..
                        ','..ion_px_mm - sample_px_offset..','..ion_py_mm..','..ion_pz_mm..
                        ','..az..','..el..','..ke..",,\n")
end

-- ending position of the thermalisation region
local thermalisation_end = var.pipe_left_gap + var.cap_thickness + var.cap_left_gap
for k, ring_focus_pitch in next, var.ring_focus_pitches, nil do thermalisation_end = thermalisation_end + ring_focus_pitch end
thermalisation_end = thermalisation_end + var.ring_big_pitch * var.ring_big_number


----------------------------------------------------------------------------------------------------
----------                                  Fly particles                                 ----------
----------------------------------------------------------------------------------------------------

function segment.load()
    simion.window.state = "maximized"
    sim_trajectory_image_control = 1
end

function segment.flym()
    generate_particles(particle_definition)
    generate_potential_array(object)

    for i = 0, 3 do
        lifting_phase = i
        print("phase "..i)
        run()
    end
end

function segment.initialize_run()
    count_trapped   =   0
    count_reflected =   0
    count_escaped   =   0
    count_blocked   =   0

    -- file_handler    =   io.open(("result%s.txt"):format(file_id or ''), 'w')
    -- file_handler:write("ion,px,pr,splat\n")

    -- sim_rerun_flym = 0
    -- sim_trajectory_image_control = 0
    -- simion.printer.filename = ("screenshot%s.png"):format(file_id or '')

    if random_seed ~= 0 then
        simion.seed(random_seed - 1)
    else
        simion.seed(math.floor(simion.rand() * 1e4))
    end
end

function segment.init_p_values()
    simion.wb.instances[1].pa:fast_adjust {
        [var.threshold_pa_num]  =   threshold_voltage;
        [var.block_pa_num]      =   block_voltage;
        [var.ground_pa_num]     =   0;
    }
    generate_confine_rf(confine_frequency, confine_voltage)
    generate_travel_wave(lifting_duration, lifting_voltage, lifting_phase)
end

function segment.tstep_adjust()
    WAV_C.segment.tstep_adjust()
    WAV_T.segment.tstep_adjust()
    HS1.segment.tstep_adjust()
end

function segment.fast_adjust()
    WAV_C.segment.fast_adjust()
    WAV_T.segment.fast_adjust()
end

function segment.other_actions()
    HS1.segment.other_actions()

    if get_ion_px_equilibrium(0) then ion_splat = 1 end
    if ion_splat == -1 then print("hit electrode at "..ion_px_mm) end
    if ion_splat == -3 then
        if ion_px_mm < var.pipe_left_gap then ion_splat = 2 else ion_splat = 3 end
    end

    if ion_splat ~= 0 then
        die_from[ion_number] = causes[ion_splat]
        simion.redraw_screen()
    end
end

function segment.terminate()
    HS1.segment.terminate()
end

function segment.terminate_run()
    for k, cause in next, die_from, nil do
        if     cause == "trapped"           then count_trapped      =   count_trapped   + 1
        elseif cause == "reflected"         then count_reflected    =   count_reflected + 1
        elseif cause == "flying through"    then count_escaped      =   count_escaped   + 1
        elseif cause == "hitting electrode" then count_blocked      =   count_blocked   + 1 end
    end

    print("trapped: "..count_trapped..", reflected: "..count_reflected..", escaped: "..count_escaped..", blocked: "..count_blocked)
    -- file_handler:write( "trapped: "..count_trapped..", blocked: "..count_blocked..", escaped: "..count_escaped..'\n' )
    -- file_handler:close()

    -- simion.print_screen()
    -- sim_rerun_flym = 1
end
