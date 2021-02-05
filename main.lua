--[[
File: main.lua
Author: X. Chen
Description: entry portal of the repository
License: GNU GPLv3
--]]

--[[ SIMION's Nelder-Mead optimiser
local SO = require "simionx.SimplexOptimizer"
--]]
-- [[ the improved Nelder-Mead optimiser
local SO = simion.import "simplexoptimiser.lua"
--]]

local function Rosenbrock(x, y, z) -- the global minimum is at (1, 1, 1)
    return (1-x)^2 + 100*(y-x^2)^2 + (1-y)^2 + 100*(z-y^2)^2
end

local opt = SO {
    start = {10, -10, 10};
    func = Rosenbrock;
}

opt:run()

print(string.format("After %d iterations, the minimum is found at (%.7f, %.7f, %.7f).", opt:ncalls(), opt:values()))
