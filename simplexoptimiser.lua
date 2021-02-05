-- simplexoptimiser.lua
-- originally was simionx.SimplexOptimizer
--
-- This module is documented in the SIMION supplemental documentation.
-- version: 20080116
-- (c) 2007 Scientific Instrument Services, Inc. (SIMION 8.0 License)
--
-- Modified by X. Chen to improve the convergence rate in higher dimensions,
-- and more importantly, not to toss the minimum that is already found.

local Sup = require "simionx.Support"
local Type = require "simionx.Type"

local M = {}; M.__index = M

-- Get maximum radius of a set of points p.
-- That is, the maximum distance from any point to
-- the centroid of the points.
-- points is a table of tables.
-- Assume #points >= 1 and #points[1] >= 1.
local function get_radius(points)
  assert(#points >= 1 and #points[1] >= 1)
  local mmax = # points[1]
  local centroid = {}  -- mean of all points
  for m=1,mmax do
    local sum = 0
    for n=1,#points do
      sum = sum + points[n][m]
    end
    centroid[m] = sum / #points
  end
  local radius = 0
  for n=1,#points do
    local sum2 = 0
    for m=1,mmax do
      local delta = points[n][m] - centroid[m]
      sum2 = sum2 + delta*delta
    end
    if sum2 > radius then radius = sum2 end
  end
  radius = math.sqrt(radius)
  return radius
end


local argtypes
local function create(_, t)
  argtypes = argtypes or Type {
    start = Type.number_array,
    step = Type.number_array + Type['nil'],
    func = Type['function'] + Type['nil'],
    maxcalls = Type.positive_integer + Type['nil'],
    minradius = Type.positive_number + Type['nil']
  }
  argtypes:check(t, 2)
  if t.step and #t.start ~= #t.step then
    error("Length of start and step must be equal", 2)
  end
  if #t.start == 0 then
    error("Length of start must be non-zero", 2)
  end

  local self = {
    _start = t.start,
    _step = t.step,
    _func = t.func,
    _maxcalls = t.maxcalls,
    _minradius = t.minradius or 1e-7,
    _points = {},
    _values = {},
    _co = nil,
    _test_value = {},
    _callcount = 0,
    _radius = nil
  }
  setmetatable(self, M)

  if not self._step then
    local step = {}
    for m=1,#self._start do step[m] = 1 end
    self._step = step
  end

  -- Create N+1 vertices of initial polytope.
  local points = self._points
  for i=1,#self._start+1 do
    local newpoint = {}
    for j=1,#self._start do newpoint[j] = self._start[j] end
    if i > 1 then
      local im = i-1
      newpoint[im] = newpoint[im] + self._step[im]
    end
    points[i] = newpoint
  end

  self._radius = get_radius(self._points)

  -- Create coroutine function by default.
  -- This evaluates function through the result() and values()
  -- methods.
  if not self._func then
    self._co = coroutine.create(M.run)
    local function func(...)
      return coroutine.yield(self._co)
    end
    self._func = func
    assert(coroutine.resume(self._co, self))
  end

  return self
end
setmetatable(M, {
  __call = create
})

function M:result(...)
   if not self:running() then
    error("optimization terminated", 2)
  end

  assert(coroutine.resume(self._co, ...))
end

function M:running()
  return coroutine.status(self._co) == "suspended"
end

function M:values()
  return unpack(self._test_value)
end

function M:radius()
  return self._radius
end

function M:ncalls()
  return self._callcount
end

function M:run()
  local start = self._start
  local points = self._points
  local values = self._values
  local func = self._func

  self._callcount = 0

  -- Wrapper around func.
  local function f(v)
    self._callcount = self._callcount + 1
    if self._maxcalls and self._callcount > self._maxcalls then
      return
    end
    self._test_value = {unpack(v)}
    local t = func(unpack(v))
    return t
  end

  -- Compute function values at initial points.
  for n=1,#self._points do
    values[n] = f(points[n])
    if not values[n] then
      return
    end
  end

  while true do
    -- print("DEBUG", unpack(self._test_value))

    -- Find indices of best, worst, and next-to-worst points.
    local ibest = 1 -- B
    local iworst = 1 -- W
    local inextworst = 1 -- G
    for n=2,#points do
      local val = values[n]
      if val >= values[iworst] then
        inextworst = iworst
        iworst = n
      elseif val >= values[inextworst] then
        inextworst = n
      elseif val < values[ibest] then
        if n == 2 then
          inextworst = n
        end
        ibest = n
      end
    end
    assert(#points ~= 2 or ibest == inextworst)

    local midpoint = {}  -- M = (B + ... + G)/(#points-1)
    for n=1,#start do
        for m=1,#points do
            if m ~= iworst then
                midpoint[n] = (midpoint[n] or 0) + points[m][n]
            end
        end
        midpoint[n] = midpoint[n] / (#points-1)
    end

    local reflectpoint = {}  -- R = 2*M - W
    for n=1,#start do
      reflectpoint[n] = 2*midpoint[n] - points[iworst][n]
    end

    local fr = f(reflectpoint)
    if not fr then break end

    if fr < values[inextworst] then
      -- reflect or expand

      local is_improve = false
      if fr < values[ibest] then
        local expandpoint = {} -- E = 2*R - M
        for n=1,#start do
          expandpoint[n] = 2*reflectpoint[n] - midpoint[n]
        end

        local fe = f(expandpoint)
        if not fe then break end

        if fe < fr then
          points[iworst] = expandpoint
          values[iworst] = fe
          is_improve = true
        end
      end
      if not is_improve then
        points[iworst] = reflectpoint
        values[iworst] = fr
      end
    else
      -- contract or shrink

      local contractpoint = {}  -- C = (W + M)/2
      for n=1,#start do
        contractpoint[n] = (points[iworst][n] + midpoint[n]) * 0.5
      end

      local fc = f(contractpoint)
      if not fc then break end

      if fc < values[iworst] then
        points[iworst] = contractpoint
        values[iworst] = fc
      else
        -- shrink

        local is_valid = true

        for m=1,#points do
            if m ~= ibest then
                for n=1,#start do -- S = (B + S)/2
                    points[m][n] = (points[ibest][n] + points[m][n]) * 0.5
                end

                local fs = f(points[m])
                if not fs then
                    is_valid = false
                    break
                end
                values[m] = fs
            end
        end

        if not is_valid then break end

      end
    end

    -- Check whether polytope radius target reached.
    self._radius = get_radius(points)
    if self._minradius and self._radius < self._minradius then
      break
    end

  end  -- while
end

return M
