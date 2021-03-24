----------------------------------------------------------------------------------------------------
----------      File        :   next.lua                                                  ----------
----------      Author      :   X. Chen                                                   ----------
----------      Description :   manager of the whole simulation                           ----------
----------      Note        :   the following units are adopted throughout the code       ----------
----------                          [length]    =   mm                                    ----------
----------                          [voltage]   =   V                                     ----------
----------      License     :   GNU GPLv3                                                 ----------
----------------------------------------------------------------------------------------------------


simion.workbench_program()


----------------------------------------------------------------------------------------------------
----------                                   Preparation                                  ----------
----------------------------------------------------------------------------------------------------

-- specify the simulating object
local object = "ring_electrode"

-- define the potential array number and dimensions of each component
local var               =   {}

var.ring_pa_num         =   1
var.ring_inner_radius   =   2
var.ring_pitch          =   2.1
var.ring_blend          =   .5
var.ring_outer_radius   =   15

var.pipe_pa_num         =   2
var.pipe_inner_radius   =   50
var.pipe_thickness      =   .5

var.grid_size           =   5e-3

-- calculate the range for cropping potential array; values are in grid units
local crop_axial_span   =   math.ceil(var.ring_pitch / 2 / var.grid_size)
local crop_radial_span  =   math.ceil(var.ring_inner_radius / var.grid_size)
local crop_range        =   { 0, 0, 0; crop_axial_span, crop_radial_span, 0 }

-- calculate the corresponding workbench bounds
local bound_axial_span  =   crop_axial_span  * var.grid_size
local bound_radial_span =   crop_radial_span * var.grid_size
local workbench_bounds  =   {
    xl  =  -bound_axial_span ,  xr  =   bound_axial_span ;
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
local function generate_potential_array(fname, force)
    if not force and deep_compare(_G.shared_table, var) then return end
    _G.shared_table = deep_copy(var)

    local gem_file = "geometry/"..fname..".gem"
    local pa_file  = "geometry/"..fname..".pa#"
    simion.command( "gem2pa "..gem_file..' '..pa_file )

    local inst = simion.wb.instances[1]
    inst.pa:load(pa_file)
    inst.pa:refine { convergence = 1e-7 }
    inst.pa.filename = pa_file:sub(1,-4).."pa0"

    inst.pa:crop( unpack(crop_range) )
    inst:_debug_update_size()
    simion.redraw_screen()
    simion.wb.bounds = workbench_bounds
end

-- write the potential array of the region of interest as binary data to disk
local function export_potential_array(file_id)
    local file_handler = io.open("ring_thickness_"..file_id..".txt", "w")
    file_handler:write( "# "..var.ring_inner_radius..' '..var.ring_pitch..' '..var.grid_size..'\n' )
    local inst = simion.wb.instances[1]
    inst.pa:fast_adjust { [var.ring_pa_num] = 1e4; [var.pipe_pa_num] = 0 }
    for j = 0, crop_radial_span do
        for i = 0, crop_axial_span do
            local phi = inst.pa:potential(i, j, 0)
            file_handler:write(phi..' ')
        end
        file_handler:write('\n')
    end
    file_handler:close()
end


----------------------------------------------------------------------------------------------------
----------                                  Fly particles                                 ----------
----------------------------------------------------------------------------------------------------

function segment.load()
    simion.window.state = "maximized"
    sim_trajectory_image_control = 1
end

function segment.flym()
    for s = 1, var.ring_pitch, .1 do
        var.ring_thickness = s
        generate_potential_array(object)
        export_potential_array(("%.1f"):format(var.ring_thickness))
    end
end
