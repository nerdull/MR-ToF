-- waveformlib.lua
-- Library for defining SIMION electrode potentials as segmented
-- waveforms of line segments.
--
-- Note: times are in units of microseconds.
--
-- (c) 2007-2008 Scientific Instrument Services, Inc. (Licensed under SIMION 8.1)
--
-- Modified by X. Chen to add periodicity to waveforms,
-- and to add flexibility to the adjustment of electrode potential.

-- checkglobals()

local WAVE = {}

local TYPE = require "simionx.Type"

-- Current waveforms to use.
-- Defined by user.
WAVE.waves = {}

-- PE surface updates are triggered every this number
-- of microseconds.  Set to nil to disable PE surface updates.
-- These are useful for display and for debugging to ensure
-- potentials are oscillating as expected.
-- Defined by user.
WAVE.pe_update_period = nil

-- Table to install segments into.
-- By default, segments are NOT installed into SIMION's segment table.
-- Defined by user.
WAVE.segment = {}

-- Frequency of the periodic waveform.
-- By default, it is 1 MHz.
-- Defined by user.
WAVE.frequency = 1 -- MHz


function WAVE.create_excel_plotter()
  local excel,wb,ws,chart,rows,rowe,xlabel,ylabel,title
  return function(...)
    if not excel then
      xlabel,ylabel,title = ...
      excel = luacom.CreateObject("Excel.Application")
      excel.Visible = true
      wb = excel.Workbooks:Add()
      ws = wb.Worksheets(1)
      chart = excel.Charts:Add()
      chart.ChartType = 74  -- xlXYScatterLines
      chart.HasLegend = true
      rows,rowe = 1,0
    else
      local first = ...
      if type(first) == 'string' then
        rowe = rowe + 1
        for i=1,select('#', ...) do
          ws.Cells(rowe,i).Value2 = select(i, ...)
        end
      elseif first then
        local x,y = ...
        rowe = rowe + 1
        ws.Cells(rowe,1).Value2 = x
        ws.Cells(rowe,2).Value2 = y
      else
        local series = chart.SeriesCollection(chart):NewSeries()
        series.XValues = "=Sheet1!R" .. rows+1 .. "C1:R" .. rowe .. "C1"
        series.Values = "=Sheet1!R" .. rows+1 .. "C2:R" .. rowe .. "C2"
        series.Name = "=Sheet1!R" .. rows .. "C2:R" .. rows .. "C2"

        chart.HasTitle = true
        chart.ChartTitle:Characters().Text = title
        chart.Axes(1,1).HasTitle = true
        chart.Axes(1,1).AxisTitle:Characters().Text = xlabel
        chart.Axes(1,2).HasTitle = true
        chart.Axes(1,2).AxisTitle:Characters().Text = ylabel

        rows,rowe = rowe + 1, rowe
        wb.Saved = true  -- don't warn on close
      end
    end
  end
end


-- Plots given waveforms.
-- (e.g. to Excel and/or log window).
-- This is for display/debugging purposes only.
function WAVE.plot_waveform(waves)
  waves = waves or WAVE.waves

  local plot_excel = WAVE.create_excel_plotter()

  local function plot_log(time, potential)
    if time then
      print('time=', time, 'potential=', potential)
    end
  end

  local function plot(time, potential)
    plot_excel(time, potential)
    plot_log(time, potential)
  end

  plot('time (usec)', 'potential', 'Waveforms')
  for ielectrode,wave in pairs(waves) do
    plot('time ' .. ielectrode ,
         'potential ' .. ielectrode)
    for i,part in ipairs(wave) do
      plot(part.time, part.potential)
    end
    plot()
  end
end


-- for debugging.
local function record_potentials(t, potentials)
  local vs = ''
  for i,v in pairs(potentials) do
    vs = vs .. ',' .. v
  end
  print('DEBUG:t=' .. t .. ',v=' .. vs)
end


-- Gets index n of piece of waveform (wave) containing time t.
-- That is, waves[n].time <= t < waves[n+1].time,
-- provided we conventionally define waves[0] = -infinity and
-- wave[#waves+1] = infinity.
local function get_piece(wave, t)
  local n = 0
  for m = 1, #wave do
    if wave[m].time > t + 1e-11 then break end -- this small number accounts for the machine precision
    n = m
  end
  return n
end


-- Gets potential at time t for waveform (wave).
function WAVE.get_potential(wave, t)
  -- Locate current line piece [n, n+1] of the waveform.
  local n = get_piece(wave, t)

  local v  -- potential
  if n == 0 then
    v = wave[1].potential
  elseif n == #wave then
    v = wave[n].potential
  else
    -- Obtain points (t1,v1) and (t2,v2) of that line segment.
    local wm,wp = wave[n],wave[n+1]
    local t1,t2, v1,v2 = wm.time,wp.time, wm.potential,wp.potential

    -- Linearly interpolate potential over the line segment.
    v = v1 + (t - t1) * ((v2-v1)/(t2-t1))
  end
  return v
end
local get_potential = WAVE.get_potential


-- SIMION segment called to override time-step size.
--
-- Ensures time-step stops precisely on end of current waveform part.
-- This is not essential (i.e. can be omitted) but does improve
-- accuracy for stepped waveforms.
local min = math.min
function WAVE.tstep_adjust()
  local t_frac = ion_time_of_flight - math.floor(ion_time_of_flight*WAVE.frequency)/WAVE.frequency
  for i,wave in pairs(WAVE.waves) do
    local n = get_piece(wave, t_frac)
    if n < #wave then
      local dt = wave[n+1].time - t_frac
      if dt > 0 then
        ion_time_step = min(ion_time_step, dt)
      end
    end
  end
end


-- SIMION segment called to adjust electrode potentials.
--
-- Updates each electrode potential.
local lastv = {}  -- store potentials for debugging only
function WAVE.fast_adjust(mode) -- mode to be selected from {"set", "append"}
  local t_frac = ion_time_of_flight - math.floor(ion_time_of_flight*WAVE.frequency)/WAVE.frequency
  for i,wave in pairs(WAVE.waves) do
    local v = get_potential(wave, t_frac)
    -- print('DEBUG:',t_frac, v)
    if mode == nil or mode == "set" then
        adj_elect[i] = v   -- set potential
    elseif mode == "append" then
        adj_elect[i] = adj_elect[i] + v   -- append potential
    end
    lastv[i] = v
  end
end


-- SIMION segment called on each time step.
--
-- Updates PE surface display and print potentials.  This is done
-- periodically and also whenever transition between parts of a
-- waveform are done.  This is not essential (i.e. can be omitted) but
-- can be useful for display and debugging.
local piece_last = {}
local last_tof = -math.huge
local abs = math.abs
function WAVE.other_actions()
  local period = WAVE.pe_update_period
  local is_update
  if abs(ion_time_of_flight - last_tof) > period then
    is_update = true
  else
    local t_frac = ion_time_of_flight - math.floor(ion_time_of_flight*WAVE.frequency)/WAVE.frequency
    for i,wave in pairs(WAVE.waves) do
      local n = get_piece(wave, t_frac - ion_time_step * 0.5)
      if n ~= piece_last[i] then
        piece_last[i] = n
        is_update = true
      end
    end
  end
  if is_update then
    sim_update_pe_surface = 1
    last_tof = ion_time_of_flight
    if debug then
      -- record_potentials(ion_time_of_flight - ion_time_step, lastv)
    end
  end
end


-- Install SIMION segments.
-- This may be passed a table of name-value pairs of parameters
-- defined above: waves, pe_update_period and segment.
function WAVE.install(t)
  t = t or {}
  for k,v in pairs(t) do
    WAVE[k] = v
  end

  local segment = WAVE.segment
  segment.fast_adjust = WAVE.fast_adjust
  segment.tstep_adjust = WAVE.tstep_adjust
  if WAVE.pe_update_period then
    segment.other_actions = WAVE.other_actions
  end
end


-- Defines a series of lines segment in a waveform.
-- Example:
--   WAVE.lines {
--     {time=0,  potential=0};
--     {time=10, potential=3};
--     {time=30, potential=-3};
--     {time=40, potential=0};
--   }
local T
function WAVE.lines(t)
  -- param check
  if not TYPE.is_array(t) then
    error("lines not passed array", 2)
  end
  T = T or {
    time = TYPE.number;
    potential = TYPE.number;
  }
  for i,v in ipairs(t) do
    local ok,message = TYPE.is_param_table(T, v)
    if not ok then
      error(message, 2)
    end
  end
 
  return {'lines', t}
end


-- Defines an electrode in a waveform.
-- Example:
--    WAVE.electrode(2) {
--      WAVE.lines { ..... }
--    }
function WAVE.electrode(n, ...)
  -- param check
  if select('#', ...) ~= 0 then
    error('extra parameters to electrode', 2)
  end
  if not TYPE.is_nonnegative_integer(n) then
    error('electrode number not non-negative integer', 2)
  end

  return function(t)
    -- param check
    if not TYPE.is_array(t) then
      error('electrode not passed an array', 2)
    end
    for k,v in ipairs(t) do
      if type(v) ~= 'table' or type(v[1]) ~= 'string' then
        error('invalid object in electrode', 2)
      end
    end

    local t0 = 0

    local result = {}
    for k,v in ipairs(t) do
      local lines = v[2]
      for _,v in ipairs(lines) do
        result[#result+1] = {time=t0 + v.time, potential=v.potential}
      end
      if #lines > 0 then
        t0 = t0 + lines[#lines].time
      end
    end
    return {'electrode', n, result}
  end
end


-- Defines waveforms for multiple electrodes.
-- Example:
--   WAVE.waveforms {
--     WAVE.electrode(1) { ..... };
--     WAVE.electrode(2) { ..... };
--     ...
--   }
function WAVE.waveforms(t)
  -- param check
  if not TYPE.is_array(t) then
    error('electrode not passed an array', 2)
  end
  for i,v in ipairs(t) do
    if type(v) ~= 'table' or v[1] ~= 'electrode' then
      error('invalid object in waveform (expected electrode)', 2)
    end
  end

  local result = {}
  for i,v in ipairs(t) do
    local ielectrode, electrode = v[2], v[3]
    result[ielectrode] = electrode
  end
  return result
end


return WAVE
