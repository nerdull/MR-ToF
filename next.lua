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

-- global tables to be shared across files
_G.ion_guide = _G.ion_guide or {}

-- dependent libraries
local WAVE  =   simion.import "library/waveformlib.lua"
local HS1   =   simion.import "library/collision_hs1.lua"

----------------------------------------------------------------------------------------------------
----------                                   Preparation                                  ----------
----------------------------------------------------------------------------------------------------

-- specify the simulating object
local object = "ion_guide"
local shared_table = _G.ion_guide

-- define the dimensions of each component
local var               =   {}

var.ring_num            =   4*10
var.ring_pitch          =   5.8
var.ring_thickness      =   3.4
var.ring_inner_radius   =   5
var.ring_outer_radius   =   10

var.pipe_inner_radius   =   50
var.pipe_thickness      =   2

var.gap_left            =   5
var.gap_right           =   10

var.grid_size           =   2e-2

-- calculate the range for cropping potential array; values are in grid units
local crop_axial_start  =   math.ceil(    var.pipe_thickness                                    / var.grid_size)
local crop_axial_span   =   math.ceil((   var.ring_pitch*(var.ring_num-1) + var.ring_thickness
                                        + var.gap_left + var.gap_right)                         / var.grid_size)
local crop_radial_span  =   math.ceil(    var.ring_outer_radius                                 / var.grid_size)

local crop_range        =   { crop_axial_start, 0, 0; crop_axial_span, crop_radial_span, 0 }

-- calculate the corresponding workbench bounds
local bound_axial_span  =   crop_axial_span  * var.grid_size
local bound_radial_span =   crop_radial_span * var.grid_size

local workbench_bounds  =   {
                    xl  =   0                ,  xr  =   bound_axial_span ;
                    yl  =  -bound_radial_span,  yr  =   bound_radial_span;
                    zl  =  -bound_radial_span,  zr  =   bound_radial_span;
}

-- build the potential array from .gem file, then refine and crop it
local function generate_potential_array(fname, conv, force)
    local need_rebuild = false
    if force or next(shared_table) == nil then need_rebuild = true else
        for k,v in pairs(var) do
            if shared_table[k] ~= v then need_rebuild = true; break end
        end
    end
    if not need_rebuild then return end

    for k,v in pairs(var) do shared_table[k] = v end
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
-- local particle_definition = "ion_guide_injection" -- alternative

-- conversion from .ion format to .fly2 format
local function ion_to_fly2(fname)
    local t = { coordinates = 0 }
    for line in io.lines( "particle/"..fname..".txt" ) do
        if not line:match "^#" and line ~= '' then
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
    return simion.fly2.particles(t)
end

-- define test particles in .fly2 format
local function generate_particles(obj)
    local key
    for k,v in pairs(debug.getregistry()) do
        if type(v) == "table" and v.iterator then key = k; break end
    end

    local fly2
    if type(obj) == "table" then
        fly2 = simion.fly2.particles { 
            coordinates = 0;
            simion.fly2.standard_beam(obj);
        }
    elseif type(obj) == "string" then fly2 = ion_to_fly2(obj) end

    debug.getregistry()[key] = fly2
end

-- define RF parameters for radial confinement
local confining_frequency   =   1.25
local confining_voltage     =   69

-- generate the confining square-wave RF
local function generate_square_wave_rf(freq, amp)
    local wav = WAVE.waveforms {
        WAVE.electrode(1) { WAVE.lines {
            { time  =   0           ,   potential   =   amp };
            { time  =   1/freq * 1/2,   potential   =   amp };
            { time  =   1/freq * 1/2,   potential   =  -amp };
            { time  =   1/freq      ,   potential   =  -amp };
        }};
    }
    WAVE.install {
        waves       =   wav;
        frequency   =   freq;
    }
end

-- ion-neutral collisional parameters
adjustable _gas_mass_amu    =   4.00260325413   -- helium
adjustable _temperature_k   =   295             -- room temperature
adjustable _pressure_pa     =   1e-1            -- set 0 to disable buffer gas
adjustable _trace_level     =   0               -- don't keep an eye on ion's kinetic energy
adjustable _mark_collisions =   0               -- don't place a red dot on each collision

-- freeze the random state for reproducible simulation results, set 0 to thaw
local random_seed = 1


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
    run()
end

function segment.init_p_values()
    -- the potential of the vacuum pipe is always at the ground level
    simion.wb.instances[1].pa:fast_adjust { [23] = 0 }
    generate_square_wave_rf(confining_frequency, confining_voltage)
end

function segment.initialize_run()
    if random_seed ~= 0 then simion.seed(random_seed - 1) end
end

function segment.tstep_adjust()
    WAVE.segment.tstep_adjust()
    HS1.segment.tstep_adjust()
end

function segment.fast_adjust()
    WAVE.segment.fast_adjust()
end

function segment.other_actions()
    HS1.segment.other_actions()
end

function segment.terminate()
    HS1.segment.terminate()
end
