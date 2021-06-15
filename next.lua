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
----------                          [e-field]   =   V/mm                                  ----------
----------                          [angle]     =   °                                     ----------
----------                          [pressure]  =   Pa                                    ----------
----------      License     :   GNU GPLv3                                                 ----------
----------------------------------------------------------------------------------------------------


simion.workbench_program()

-- dependent libraries
local Stat  =   require "simionx.Statistics"

local TP    =   simion.import "library/testplanelib.lua"
local SO    =   simion.import "library/simplexoptimiser.lua"


----------------------------------------------------------------------------------------------------
----------                                   Preparation                                  ----------
----------------------------------------------------------------------------------------------------

-- specify the simulating object
local object = "einzel_lens"

-- define the potential array number and dimensions of each component
local var                   =   {}

var.cylinder_inner_radius   =   30
var.cylinder_thickness      =   2
var.cylinder_blend          =   var.cylinder_thickness / 2
var.cylinder_gap            =   var.cylinder_inner_radius / 2

var.cylinder_outer_pa_num   =   1
var.cylinder_outer_length   =   var.cylinder_inner_radius

var.cylinder_middle_pa_num  =   var.cylinder_outer_pa_num + 1
var.cylinder_middle_length  =   var.cylinder_inner_radius

var.tube_pa_num             =   var.cylinder_middle_pa_num + 1
var.tube_inner_radius       =   1
var.tube_thickness          =   1
var.tube_blend              =   var.tube_thickness / 2
var.tube_length             =   10

var.pipe_pa_num             =   var.tube_pa_num + 1
var.pipe_inner_radius       =   50
var.pipe_thickness          =   2
var.pipe_left_gap           =   var.cylinder_inner_radius
var.pipe_right_gap          =   300 - var.pipe_left_gap - var.cylinder_outer_length * 2 - var.cylinder_gap * 2 - var.cylinder_middle_length
var.pipe_extension          =   15

var.pulsed_tube_pa_num      =   1
var.lens_pa_num             =   var.pulsed_tube_pa_num + 1
var.ground_pa_num           =   var.lens_pa_num + 1

var.grid_size               =   5e-2

-- calculate the range for cropping potential array; values are in grid units
local lens_length = var.cylinder_gap * 2 + var.cylinder_outer_length * 2 + var.cylinder_middle_length
local crop_axial_start  =   math.ceil(( var.pipe_extension + var.pipe_thickness )              / var.grid_size)
local crop_axial_span   =   math.ceil(( lens_length + var.pipe_left_gap + var.pipe_right_gap ) / var.grid_size)
local crop_radial_span  =   math.ceil(( var.cylinder_inner_radius + var.cylinder_thickness )   / var.grid_size)
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
local particle_definition = "einzel_lens_injection"

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
                    tob         =   tonumber(tob);
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

-- define the static potentials of electrodes
local pulse_voltage =   2.5e3
local lens_voltage  =   2e3

-- register the fate of each ion
local die_from  = {}
local causes    = {
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

-- sample the ion states after they are accelerated
local remaining_samples = 300

local function sample_ion_state()
    -- simion.mark()
    local speed, az, el = simion.rect3d_to_polar3d(ion_vx_mm, ion_vy_mm, ion_vz_mm)
    local ke = simion.speed_to_ke(speed, ion_mass)
    file_handler:write( ion_time_of_flight..','..ion_mass..','..ion_charge..
                        ','..ion_px_mm..','..ion_py_mm..','..ion_pz_mm..
                        ','..az..','..el..','..ke..",,\n")
    remaining_samples = remaining_samples - 1
end

-- set a virtual screen on the right end boundary to monitor the beam kinetic parameters
local emittance_ycoord  =   {}
local emittance_yprime  =   {}
local emittance_zcoord  =   {}
local emittance_zprime  =   {}
local radial_size       =   {}
local axial_angle       =   {}
local time_of_flight    =   {}

local function monitor_boundary()
    -- simion.mark()
    local k = #radial_size + 1
    radial_size[k]      =   math.sqrt(ion_py_mm^2 + ion_pz_mm^2)
    axial_angle[k]      =   math.sqrt(ion_vy_mm^2 + ion_vz_mm^2) / ion_vx_mm * 1e3
    time_of_flight[k]   =   ion_time_of_flight
    sample_ion_state()
end

local screen_boundary = TP(bound_axial_span, 0, 0, 1, 0, 0, monitor_boundary)

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

-- gear up the simplex optimiser
local objective_function
local optimiser =   SO {
    start       =   { 145, 100, 100, 85 };
    step        =   { 5, 5, 5, 5 };
    precision   =   1;
}

----------------------------------------------------------------------------------------------------
----------                                  Fly particles                                 ----------
----------------------------------------------------------------------------------------------------

function segment.load()
    simion.window.state = "maximized"
    sim_trajectory_image_control = 1
end

function segment.flym()
    generate_particles(particle_definition)

    -- file_handler = io.open(("einzel_lens_parameters%s.txt"):format(file_id or ''), 'w')
    -- file_handler:write("start point,outer length,middle length,gap,voltage,ion number,beam size,beam parallelity\n")
    -- for plg = var.cylinder_inner_radius - 15, var.cylinder_inner_radius + 45, 15 do var.pipe_left_gap = plg
    --     for col = var.cylinder_inner_radius - 5, var.cylinder_inner_radius + 15, 5 do var.cylinder_outer_length = col
    --         for cml = var.cylinder_inner_radius - 5, var.cylinder_inner_radius + 15, 5 do var.cylinder_middle_length = cml
    --             for cg = var.cylinder_inner_radius - 15, var.cylinder_inner_radius + 5, 5 do var.cylinder_gap = cg
    --                 var.pipe_right_gap = 300 - var.pipe_left_gap - var.cylinder_outer_length * 2 - var.cylinder_gap * 2 - var.cylinder_middle_length
    --                 generate_potential_array(object)
    --                 for lv = 2, 2.5, .1 do lens_voltage = lv * 1e3
    --                     run()
    --                 end
    --             end
    --         end
    --     end
    -- end
    -- file_handler:close()

    file_handler = io.open(("einzel_lens_ion_states%s.txt"):format(file_id or ''), 'w')
    file_handler:write("# tob, mass, charge, x, y, z, az, el, ke, cwf, color\n")
    var.pipe_left_gap, var.cylinder_outer_length, var.cylinder_middle_length, var.cylinder_gap, lens_voltage = unpack {15, 25, 45, 20, 2300}
    var.pipe_right_gap = 300 - var.pipe_left_gap - var.cylinder_outer_length * 2 - var.cylinder_gap * 2 - var.cylinder_middle_length
    generate_potential_array(object)
    run()
    file_handler:close()
end

function segment.initialize_run()
    -- sim_rerun_flym = 0
    -- sim_trajectory_image_control = 0
    -- simion.printer.filename = ("screenshot%s.png"):format(file_id or '')
end

function segment.init_p_values()
    simion.wb.instances[1].pa:fast_adjust {
        [var.pulsed_tube_pa_num]    =   pulse_voltage;
        [var.lens_pa_num]           =   lens_voltage;
        [var.ground_pa_num]         =   0;
    }
end

function segment.tstep_adjust()
    screen_boundary.tstep_adjust()
end

function segment.other_actions()
    screen_boundary.other_actions()
end

function segment.terminate_run()
    beam_size, beam_parallelity = Stat.array_mean(radial_size), Stat.array_mean(axial_angle)

    -- file_handler:write(table.concat({
    --     var.pipe_left_gap, var.cylinder_outer_length, var.cylinder_middle_length, var.cylinder_gap, lens_voltage, #radial_size, beam_size, beam_parallelity}, ',')..'\n')
    -- file_handler:flush()

    print(table.concat({#radial_size, beam_size, beam_parallelity}, ','))
    print(table.concat({#time_of_flight, Stat.array_mean(time_of_flight), Stat.array_min(time_of_flight), Stat.array_max(time_of_flight)}, ','))

    radial_size     =   {}
    axial_angle     =   {}
    time_of_flight  =   {}

    -- simion.print_screen()
    -- sim_rerun_flym = 1
end
