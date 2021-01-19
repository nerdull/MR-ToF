--[[
File: main.lua
Author: X. Chen
Description: entry portal of the repository
License: GNU GPLv3
--]]

-- [[ define parameters
n_ring = 13
r_0 = 2 -- mm
r_m = r_0 * 2 -- mm
d = 2 -- mm
s = 1.1 -- mm
grid_unit = 2e-3-- mm

local V_0 = 1 -- V
local charged_ring = {
    side = 1;
    next_to_side = 2;
    middle = (n_ring+1)/2;
}
--]]

-- [[ calculate potential arrays and export them
local fname = "single_electrode"
local n_z = math.ceil(d*3 / grid_unit)
local n_r = math.ceil(r_0 / grid_unit)

for k,v in pairs(charged_ring) do
    charged = v
    local m_z = math.ceil((s/2+d*(v-1)) / grid_unit)

    simion.command(string.format("gem2pa %s.gem %s.pa#", fname, fname))
    simion.command(string.format("refine %s.pa#", fname))
    simion.command(string.format("fastadj %s.pa0 1=1,2=0", fname))

    local pa = simion.pas:open(string.format("%s.pa0", fname))
    local f = io.open(string.format("%s_potential_%s.txt", fname, k), 'w')

    for j = 0,n_r do
        for i=m_z,n_z+m_z do
            local phi = pa:potential(i, j, 0)
            f:write(string.format("%g ", phi))
        end
        f:write('\n')
    end

    f:close()
    pa:close()
end

--]]
