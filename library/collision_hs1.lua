-- collision_hs1.lua
-- A hard-sphere, elastic, ion-neutral collision model for SIMION 8.
-- REVISION-6-2009-10-02
--
-- The code implements a rather complete hard-sphere collision model.
-- Collision models are useful for simulating non-vacuum conditions, in
-- which case ions collide against a background gas and are deflected
-- randomly.
--
-- Features and assumptions of the model:
-- - Ion collisions follow the hard-sphere collision model.
--     Energy transfers occur solely via these collisions.
-- - Ion collisions are elastic.
-- - Background gas is assumed neutral in charge.
-- - Background gas velocity follows the Maxwell-Boltzmann distribution.
-- - Background gas mean velocity may be non-zero.
-- - Kinetic cooling and heating of ions due to collisions
-- -   are simulated.
-- - Kinetic cooling and heating of background gas is assumed
--     negligible over many collisions.
--
-- Note on time-steps: each individual ion-gas collision is modeled,
-- which requires the time-step to be some fraction of mean-free-path.
-- Therefore, simulations with frequent collisions (i.e. higher
-- pressure) can be computationally intensive.
--
-- This code does not account for absorptions (e.g. when using electrons
-- rather than ions).  That can be easily supported by setting ion_splat,
-- likely as a function of impact_offset.
--
-- The code has been influenced by a variety of prior SIMION hard-sphere
-- collision models:
--   [Dahl] _Trap/INJECT.PRG in SIMION 7.0
--   [Dahl2] http://www.simion.com/examples/dahl_drag.prg
--   [Appelhans2001] http://dx.doi.org/10.1016/S1387-3806(02)00627-9
--   [Ding2002] http://dx.doi.org/10.1016/S1387-3806(02)00921-1
--   [Ling1997]
--   http://dx.doi.org/10.1002/(SICI)1097-0231(19970830)11:13<1467::AID-RCM54>3.0.CO;2-X
-- See also ( http://www.simion.com/info/Ion-Gas_Collisions ).
--
-- Additional mathematic derivations are in notes.pdf.
--
-- Author David Manura, 2005-06/2011
-- (c) 2006-2011 Scientific Instrument Services, Inc. (Licensed under SIMION 8.0)
--
-- Updated by X. Chen on some fundamental constants
simion.workbench_program()

local HS1 = {}
HS1.segment = {}

-- Mean free path (MFP) (mm) between collisions.
-- Set to -1 (recommended) to calculate this automatically from
-- pressure and temperature.
adjustable _mean_free_path_mm = -1

-- Mass of background gas particle (amu)
adjustable _gas_mass_amu = 4.0

-- Background gas temperature (K)
adjustable _temperature_k = 273.0

-- Background gas pressure (Pa)
-- Note: (Pa/mtorr) = 0.13328.
-- One of the benchmarks uses 0.53 Pa (4 mTorr) here.
adjustable _pressure_pa = 0.53

-- Collision-cross section (m^2)
-- (The diameter of the cross-sectional area is roughly
--  the sum of the diameters of the colliding ion and buffer gas particles.)
-- (2.1E-19 is roughly for two Helium atoms--Atkins1998-Table 1.3)
-- (Note: the Van der Waals radius for He is 140 pm = 1.40 angstrom.
--   -- http://www.webelements.com and http://en.wikipedia.org/wiki/Helium --
--   i.e. 2.46e-19 collision cross-section)
-- (2.27E-18 is for collision between He and some 200 amu ion with combined
--  collision diameter of 2 + 15 angstroms.  It is used in some benchmarks.)
adjustable _sigma_m2 = 2.27E-18 

-- Mean background gas velocity (mm/usec) in x,y,z directions.
-- Normally, these are zero.
adjustable _vx_bar_gas_mmusec = 0
adjustable _vy_bar_gas_mmusec = 0
adjustable _vz_bar_gas_mmusec = 0

-- Mean number of time steps per MFP.
-- Typically this default is ok.  We want sufficient number of
-- time-steps per mean-free path for this code to be reliable.
adjustable _steps_per_MFP = 20.0

-- This controls the reproducibility of the random number generator,
-- which affects whether runs are repeatable.
--   0 - don't seed random number generator (default), so that
--       runs give different results.
--   n > 1 - seed random number generator with n-1, allowing runs to be repeatable.
-- Note: if using n > 1, also make sure particle definitions are not randomized
-- (convert to "How are particles defined?" = "Individually (.ION)" if necessary).
adjustable _random_seed = 1

-- Collision marker flag.
-- If non-zero, markers will be placed at the collisions.
-- Warning: if flying ions grouped, dots will be placed
--   on *all* ions whenever *any* ion has a collision (this
--   is not really what we want, but it's how the mark()
--   command works).
adjustable _mark_collisions = 1

-- How much trace data (average KE) to output.
-- (0=none, 1=at each splat, 2=at each collision)
adjustable _trace_level = 0
-- If _trace_level is 2, this is the number of collisions before each trace.
-- This reduces the verbosity of the trace.
adjustable _trace_skip = 100


---- Internal variables

-- Currently used mean-free path (-1 = undefined).
local effective_mean_free_path_mm = -1

-- Maximum time step (usec) that fast_adjust should permit.
-- This is continually updated so that the _steps_per_MFP setting
-- remains meaningful.
local max_timestep

-- Define constants
local k = 1.380649e-23       -- Boltzmann constant (J/K)
-- local R = 8.3145           -- Ideal gas constant (J/(mol*K))
local kg_amu = 1.6605390666e-27  -- (kg/amu) conversion factor
local pi = math.pi            -- PI constant
local J_eV = 1.602176634e-19    -- (J/eV) conversion factor


-- Error function (erf).
--   erf(z) = (2/sqrt(pi)) * integral[0..z] exp(-t^2) dt
-- This algorithm is quite accurate.  It is based on
-- "Q-Function Handout" by Keith Chugg:
--   http://tesla.csl.uiuc.edu/~koetter/ece361/Q-function.pdf
-- See also http://www.theorie.physik.uni-muenchen.de/~serge/erf-approx.pdf
-- I also find that the following makes a reasonable approximation:
--   1 - exp(-(2/sqrt(pi))x - (2/pi)x^2)
local function erf(z)
    local z2 = abs(z)
    local t = 1 / (1 + 0.32759109962 * z2)
    local res = (    - 1.061405429 ) * t
    res = (res + 1.453152027 ) * t
    res = (res - 1.421413741 ) * t
    res = (res + 0.2844966736) * t
    res =((res - 0.254829592 ) * t) * exp(-z2*z2)
    res = res + 1
    if z < 0 then res = -res end
    return res
end


-- Return a normalized Gaussian random variable (-inf, +inf).
-- [ http://en.wikipedia.org/wiki/Normal_distribution ]
local function gaussian_random()
    -- Using the Box-Muller algorithm.
    local s = 1
    local v1, v2
    while s >= 1 do
        v1 = 2*rand() - 1
        v2 = 2*rand() - 1
        s = v1*v1 + v2*v2
    end
    local rand1 = v1*sqrt(-2*ln(s) / s)  -- (assume divide by zero improbable?)
    return rand1
end


-- OPTIONAL - for debugging purposes
--
-- Compute running average of KE.  This is for statistical reporting only.
-- At thermal equilibrium, KE of the ion and KE of the gas would
-- be approximately equal according to theory.
-- Designed to be called from an other_actions and terminate segments respectively.
--
--
local ke_averages = {}          -- current running average of KE for each
                                --   particle.  maps ion_number --> KE.
local last_collision_times = {} -- last collision time for each particle.
                                --   maps ion_number --> time.
local trace_count = 0           -- Count relative to _trace_skip
local function record_ke_other_actions()
    if not(_trace_level >= 1) then return end

    -- Compute new ion speed and KE.
    local speed_ion2 = sqrt(ion_vx_mm^2 + ion_vy_mm^2 + ion_vz_mm^2)
    local ke2_ion = speed_to_ke(speed_ion2, ion_mass)

    -- To average ion KE somewhat reliably, we do a running (exponential decay)
    -- average of ion KE over time.  The reset time of the exponential decay
    -- is set to some fraction of the total time-of-flight, so the average
    -- will become more steady as the run progresses (we assume this is a
    -- system that approaches equilibrium).
    -- Note: exp(-x) can be approximated with 1-x for small x.

    -- time between most recent collisions
    local dt = ion_time_of_flight - (last_collision_times[ion_number] or 0)
    -- average over some fraction of TOF
    reset_time = ion_time_of_flight * 0.5
    -- weight for averaging.
    local w = 1 - (dt / reset_time)  -- ~= exp(-dt / reset_time)
    -- update average ion KE
    ke_averages[ion_number] = w * (ke_averages[ion_number] or ke2_ion)
                            + (1-w) * ke2_ion
    if _trace_level >= 2 then -- more detail
        local T_ion = ke_averages[ion_number] * J_eV / (1.5 * k)
        if trace_count % _trace_skip == 0 then
            print(string.format(
                "n=%d, TOF=%0.3g, ion KE (eV)=%0.3e, ion mean KE (eV)=" ..
                "%0.3e, ion mean temp (K)=%0.3e",
                ion_number, ion_time_of_flight, ke2_ion,
                ke_averages[ion_number], T_ion))
        end
        trace_count = (trace_count + 1) % _trace_skip
    end
    last_collision_times[ion_number] = ion_time_of_flight
end
local function record_ke_terminate()
    if _trace_level >= 1 and ke_averages[ion_number] then
        -- ion temperature
        local T_ion = ke_averages[ion_number] * J_eV / (1.5 * k)
        print(string.format(
            "n=%d, TOF=%0.3g, ion mean KE (eV)=%0.3e, ion mean temp (K)=%0.3e",
            ion_number, ion_time_of_flight, ke_averages[ion_number], T_ion))
    end
end

local is_initialized = false
local function init()
    if _random_seed ~= 0 then seed(_random_seed-1) end
    
    if HS1.init then HS1.init() end
    is_initialized = true
end

-- SIMION intiialize segment. Called on particle creation.
function HS1.segment.initialize()
    if not is_initialized then init() end
end


-- SIMION time step adjust segment. Adjusts time step sizes.
function HS1.segment.tstep_adjust()
    -- Ensure time steps are sufficiently small.  They should be some
    -- fraction of mean-free-path so that collisions are not missed.
    if max_timestep and ion_time_step > max_timestep then
        ion_time_step = max_timestep
    end
end


-- SIMION other actions segment. Called on every time step.
function HS1.segment.other_actions()
    -- if not is_initialized then init() end

    -- Obtain pressure, temperature, and velocity at current "local"
    -- particle position.  Normally, these are obtained from the adjustable
    -- variables (_pressure_pa, _temperature_k, _vx_bar_gas_mmusec,
    -- _vy_bar_gas_mmusec, and _vz_bar_gas_mmusec adjustable variables).
    -- They may be individually overridden by defining HS1.pressure,
    -- HS1.temperature, and HS1.velocity functions.  The components of
    -- HS1.velocity may alternately defined individually: HS1.velocity_x,
    -- HS1.velocity_y, and HS1.velocity_z.  These functions are passed
    -- the current particle position x, y, and z in array volume units
    -- (grid units); however, you may alternately ignore the arguments and
    -- use ion_px_mm, ion_py_mm, and ion_pz_mm variables in these functions.
    local local_pressure_pa = HS1.pressure and
        HS1.pressure(ion_px_gu, ion_py_gu, ion_pz_gu) or _pressure_pa
    local local_temperature_k = HS1.temperature and
        HS1.temperature(ion_px_gu, ion_py_gu, ion_pz_gu) or _temperature_k
    local local_velocity_x_mmusec,local_velocity_y_mmusec,local_velocity_z_mmusec
    if HS1.velocity then
        local_velocity_x_mmusec,local_velocity_y_mmusec,local_velocity_z_mmusec
            = HS1.velocity(ion_px_gu, ion_py_gu, ion_pz_gu)
    else
        local_velocity_x_mmusec = HS1.velocity_x and
            HS1.velocity_x(ion_px_gu, ion_py_gu, ion_pz_gu) or _vx_bar_gas_mmusec
        local_velocity_y_mmusec = HS1.velocity_y and
            HS1.velocity_y(ion_px_gu, ion_py_gu, ion_pz_gu) or _vy_bar_gas_mmusec
        local_velocity_z_mmusec = HS1.velocity_z and
            HS1.velocity_z(ion_px_gu, ion_py_gu, ion_pz_gu) or _vz_bar_gas_mmusec
    end

    if local_pressure_pa == 0 then  -- collisions disabled
        return
    end

    -- Temporarily translate ion velocity (mm/us) frame of
    -- reference such that mean background gas velocity is zero.
    -- This simplifies the subsequent analysis.
    local vx = ion_vx_mm - local_velocity_x_mmusec
    local vy = ion_vy_mm - local_velocity_y_mmusec
    local vz = ion_vz_mm - local_velocity_z_mmusec

    -- Obtain ion speed (relative to mean background gas velocity).
    local speed_ion = sqrt(vx^2 + vy^2 + vz^2)
    if speed_ion < 1E-7 then
         speed_ion = 1E-7  -- prevent divide by zero and such effects later on
    end

    -- Compute mean-free-path.
    -- > See notes.pdf for discussion on the math.
    if _mean_free_path_mm > 0 then -- explicitly specified
        effective_mean_free_path_mm = _mean_free_path_mm
    else  -- calculate from current ion velocity
        -- Note: in some cases, mean-free-path will not change significantly, so
        -- we don't need to recompute it on every time step.  But it is simpler
        -- and less error prone to do so and doesn't affect run times much.
        do
            -- Compute mean gas speed (mm/us)
            local c_bar_gas = sqrt(8*k*local_temperature_k/pi/(_gas_mass_amu * kg_amu)) / 1000

            -- Compute median gas speed (mm/us)
            local c_star_gas = sqrt(2*k*local_temperature_k/(_gas_mass_amu * kg_amu)) / 1000

            -- Compute mean relative speed (mm/us) between gas and ion.
            local s = speed_ion / c_star_gas
            local c_bar_rel = c_bar_gas * (
                (s + 1/(2*s)) * 0.5 * sqrt(pi) * erf(s) + 0.5 * exp(-s*s))

            -- Compute mean-free-path (mm)
            effective_mean_free_path_mm = 1000 * k * local_temperature_k *
                (speed_ion / c_bar_rel) / (local_pressure_pa * _sigma_m2)


            --print("DEBUG:ion[c],gas[c_bar],c_bar_rel,MFP=",
            --      speed_ion, c_bar_gas, c_bar_rel, effective_mean_free_path_mm)

            -- Note: The following is a simpler and almost as suitable
            -- approximation for c_bar_rel, which you may use instead:
            -- c_bar_rel = sqrt(speed_ion^2 + c_bar_gas^2)
        end
    end

    -- Limit time-step size to a fraction of the MFP.
    max_timestep = effective_mean_free_path_mm / speed_ion / _steps_per_MFP

    -- Compute probability of collision in current time-step.
    -- > For an infinitesimal distance (dx) traveled, the increase in the
    --   fraction (f) of collided particles relative to the number
    --   of yet uncollided particles (1-f) is equal to the distance
    --   traveled (dx) over the mean-free-path (lambda):
    --     df/(1-f) = dx / lambda
    --   Solving this differential equation gives
    --     f = 1 - exp(- dx / lambda) = 1 - exp(- v dt / lambda)
    --   This f can be interpreted as the probability that a single
    --   particle collides in the distance traveled.
    local collision_prob = 1 -
        exp(- speed_ion * ion_time_step / effective_mean_free_path_mm)

    -- Test for collision.
    if rand() > collision_prob then
        return -- no collision
    end

    ----- Handle collision.

    -- Compute standard deviation of background gas velocity in
    -- one dimension (mm/us).
    -- > From kinetic gas theory (Maxwell-Boltzmann), velocity in
    --   one dimension is normally distributed with standard
    --   deviation sqrt(kT/m).
    local vr_stdev_gas =
        sqrt(k * local_temperature_k / (_gas_mass_amu * kg_amu)) / 1000

    -- Compute velocity of colliding background gas particle.
    -- > For the population of background gas particles that collide with the
    --   ion, their velocities are not entirely Maxwell (Gaussian) but
    --   are also proportional to the relative velocities the ion and
    --   background gas particles:
    --     p(v_gas) = |v_gas - v_ion| f(v_gas)
    --   See notes.pdf for discussion.
    -- > To generate random velocities in this distribution, we may
    --   use a rejection method (http://en.wikipedia.org/wiki/Rejection_sampling)
    --   approach:
    --   > Pick a gas velocity from the Maxwell distribution.
    --   > Accept with probability proportional to its
    --     speed relative to the ion.
    local vx_gas, vy_gas, vz_gas -- computed velocities
    -- > scale is an approximate upper-bound for "len" calculated below.
    --   We'll use three standard deviations of the three dimensional gas velocity.
    local scale = speed_ion + vr_stdev_gas * 1.732 * 3  --sqrt(3)=~1.732
    repeat
        vx_gas = gaussian_random() * vr_stdev_gas
        vy_gas = gaussian_random() * vr_stdev_gas
        vz_gas = gaussian_random() * vr_stdev_gas
        local len = sqrt((vx_gas - vx)^2 + (vy_gas - vy)^2 + (vz_gas - vz)^2)
        --assert(len <= scale) -- true at least ~99% of the time.
    until rand() < len / scale

    -- Alernately, for greater performance and as an approximation, you might
    -- replace the above with a simple Maxwell distribution:
    --  vx_gas = gaussian_random() * vr_stdev_gas
    --  vy_gas = gaussian_random() * vr_stdev_gas
    --  vz_gas = gaussian_random() * vr_stdev_gas

    -- Translate velocity reference frame so that colliding
    -- background gas particle is stationary.
    -- > This simplifies the subsequent analysis.
    vx = vx - vx_gas
    vy = vy - vy_gas
    vz = vz - vz_gas

    -- > Notes on collision orientation
    --   A collision of the ion in 3D can now be reasoned in 2D since
    --   the ion remains in some 2D plane before and after collision.
    --   The ion collides with an gas particle initially at rest (in the
    --   current velocity reference frame).
    --   For convenience, we define a coordinate system (r, t) on the
    --   collision plane.  r is the radial axis through the centers of
    --   the colliding particles, with the positive direction indicating
    --   approaching particles.  t is the tangential axis perpendicular to r.
    --   An additional coordinate theta defines the the rotation of the
    --   collision plane around the ion velocity axis.

    -- Compute randomized impact offset [0, 1) as a fraction
    -- of collisional cross-section diameter.
    -- 0 is a head-on collision; 1 would be a near miss.
    -- > You can imaging this as the gas particle being a stationary
    --   dart board of radius 1 unit (representing twice the actual radius
    --   of the gas particle) and the ion center is a dart
    --   with velocity perpendicular to the dart board.
    --   The dart has equal probability of hitting anywhere on the
    --   dart board.  Since a radius "d" from the center represents
    --   a ring with circumference proportional to "d", this implies
    --   that the probability of hitting at a distance "d" from the
    --   center is proportional to "d".
    -- > Formally, the normalized probability density function is
    --   f(d) = 2*d for d in [0,1].  From the fundamental transformation
    --   law of probabilities, we have
    --   integral[0..impact_offset] f(d) dd = impact_offset^2 = U,
    --   where U is a uniform random variable.  That is,
    --   impact_offset = sqrt(U).  Decrease it it slightly
    --   to prevent overflow in asin later.
    local impact_offset = sqrt(0.999999999 * rand())

    -- Convert impact offset to impact angle [0, +pi/2) (radians).
    -- Do this since the target is really a sphere (not flat dartboard).
    -- This is the angle between the relative velocity
    -- between the two colliding particles (i.e. the velocity of the dart
    -- imagined perpendicular to the dart board) and the r axis
    -- (i.e. a vector from the center of the gas particle to the location
    -- on its surface where the ion hits).
    -- 0 is a head-on collision; +pi/2 would be a near miss.
    local impact_angle = asin(impact_offset)

    -- In other words, the effect of the above is that impact_angle has
    -- a distribution of p(impact_angle) = sin(2 * impact_angle).

    -- Compute randomized angle [0, 2*pi] for rotation of collision
    -- plane around radial axis.  The is the angle around the
    -- center of the dart board.
    -- Note: all angles are equally likely to hit.
    -- The effect is that impact_theta has a distribution
    -- of p(impact_theta) = 1/(2*pi).
    local impact_theta = 2*pi*rand()

    -- Compute polar coordinates in current velocity reference frame.
    local speed_ion_r, az_ion_r, el_ion_r = rect3d_to_polar3d(vx, vy, vz)

    -- Compute ion velocity components (mm/us).
    local vr_ion = speed_ion_r * cos(impact_angle)    -- radial velocity
    local vt_ion = speed_ion_r * sin(impact_angle)    -- normal velocity

    -- Attenuate ion velocity due to elastic collision.
    -- This is the standard equation for a one-dimensional
    -- elastic collision, assuming the other particle is initially at rest
    -- (in the current reference frame).
    -- Note that the force acts only in the radial direction, which is
    -- normal to the surfaces at the point of contact.
    local vr_ion2 = (vr_ion * (ion_mass - _gas_mass_amu))
                  / (ion_mass + _gas_mass_amu)

    -- Rotate velocity reference frame so that original ion velocity
    -- vector is on the +y axis.
    -- Note: The angle of the new velocity vector with respect to the
    -- +y axis then represents the deflection angle.
    vx, vy, vz = elevation_rotate(90 - deg(impact_angle), vr_ion2, vt_ion, 0)

    -- Rotate velocity reference frame around +y axis.
    -- This rotates the deflection angle and in effect selects the
    -- randomized impact_theta.
    vx, vy, vz = azimuth_rotate(deg(impact_theta), vx, vy, vz)

    -- Rotate velocity reference frame back to the original.
    -- For the incident ion velocity, this would have the effect
    -- of restoring it.
    vx, vy, vz = elevation_rotate(-90 + el_ion_r, vx, vy, vz)
    vx, vy, vz = azimuth_rotate(az_ion_r, vx, vy, vz)

    -- Translate velocity reference frame back to original.
    -- This undoes the prior two translations that make velocity
    -- relative to the colliding gas particle.
    vx = vx + vx_gas + local_velocity_x_mmusec
    vy = vy + vy_gas + local_velocity_y_mmusec
    vz = vz + vz_gas + local_velocity_z_mmusec

    -- Set new velocity vector of deflected ion.
    ion_vx_mm, ion_vy_mm, ion_vz_mm = vx, vy, vz

    -- Now lets compute some statistics...

    -- Compute running average of KE.  This is for statistical reporting only.
    -- At thermal equilibrium, KE of the ion and KE of the gas would
    -- be approximately equal according to theory.
    if _trace_level ~= 0 then record_ke_other_actions() end

    if _mark_collisions ~= 0 then
        mark() -- draw dot at collision point
    end
end


-- SIMION terminate segment. Called on particle termination.
function HS1.segment.terminate()
    -- Display some statistics.
    -- Note: At equilibrium, the ion and gas KE become roughly equal.
    if trace_level ~= 0 then record_ke_terminate() end
end


--OPTIONAL, for testing
--[[commented out, unused
function segment.efield_adjust()
     -- For testing, apply a quadratic potential well
     -- to trap ions in.  The kinetic cooling of the buffer
     -- gas causes ions to collect near the center of the well.
     --   V(x,y,z) = x*x + y*y* + z*z = r*r
     --   E(x,y,z) = -(2*x, 2*y, 2*z)
    r_max = 100   -- radius
    V_max = 10    -- voltage at r_max
    a = 2 * V_max / (r_max * r_max)
    ion_dvoltsx_gu = ion_px_gu * a
    ion_dvoltsy_gu = ion_py_gu * a
    ion_dvoltsz_gu = ion_pz_gu * a
end
HS1.segment.efield_adjust = segment.efield_adjust
]]

return HS1
