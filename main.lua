--[[
File: main.lua
Author: X. Chen
Description: entry portal of the repository
License: GNU GPLv3
--]]

-- [[ define parameters
n_ring = 3
r_0 = 1 -- mm
r_m = r_0 * 2 -- mm
d = 1 -- mm
grid_unit = 1e-3-- mm
--]]

-- [[ calculate potential arrays and export them
local fname = "electrode_thickness"
local n_z = math.ceil(d/2 / grid_unit)
local n_r = math.ceil(r_0 / grid_unit)

for percent=45,70,1 do
    s = percent / 100 * d -- mm
    simion.command(string.format("gem2pa %s.gem %s.pa#", fname, fname))
    simion.command(string.format("refine %s.pa#", fname))
    simion.command(string.format("fastadj %s.pa0 1=1", fname))
    local pa = simion.pas:open(string.format("%s.pa0", fname))
    local f = io.open(string.format("%s_%d_percent.txt", fname, percent), 'w')

    for j = 0,n_r do
        for i=0,n_z do
            local phi = pa:potential(i, j, 0)
            f:write(string.format("%g ", phi))
        end
        f:write('\n')
    end

    f:close()
    pa:close()
end
--]]
