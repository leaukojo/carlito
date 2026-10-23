# TODO

## Compass and wind direction on the land dashboards

From the crosswind drive check: on a land vehicle you can't see your heading or where the wind
comes from, so drift under CONDITIONS wind is hard to read. Only the boat has a wind rose
(`src/ui/wind_rose.gd`). The dashboard builds it when the vehicle's out-signals carry the whole
`Dashboard.WIND_ROSE_SIGNALS` set (`awa`/`aws`/`twd`/`tws`/`cog`/`sog`), and the contract declares
those for the boat only. Two routes:
- **Contract:** declare a heading and true-wind pair for car, truck and tractor, read from the sim
  (`WindField.at`, the body's basis; `BoatTelemetry.true_wind` already does the FROM conversion),
  and have the dashboard build a compass rose off them. Follow the `contract-edit` skill (version
  bump, sloppyCAN copy). This also puts wind on the bus.
- **UI only:** a compass rose with a wind arrow fed from the level, not the contract. It is
  cheaper, but it would be the first dashboard widget the contract doesn't declare (rule 4).

## Handling follow-ups

From the roll-steer work (`docs/vehicles.md` § Balance):
- **The corner pass's limit in `BalanceModel`:** the pass runs driven at 9-23 deg of lock, where
  the turn's drive spends a driven axle's ellipse, a front-driven axle's tilted drive carries side
  force, and a rear-driven body's front makes a few points over its static share. The drive alone
  makes the calls worse (it flips `firetruck` and the tractor): model the pass's geometry whole,
  calibrate it on every body against the pass's `pred`, then judge `delivery` (rear-first there).
- **Compliance steer** (a brief): rear toe-in under side force, the classic cure for lift-off
  oversteer. The four COMPROMISE bodies' 1.08 and the `police` / `suv-luxury` lifted spins are
  lift-off cases, so it is the candidate to retire them. Its linear-K share is small (0.5 of
  Bundorf's illustrative 4.1 deg/g); roll camber (1.2) is the larger share left.
- **Truck understeer:** with no angular damping the Kenney trucks read neutral to slightly
  oversteer at the slowest step (`garbage-truck` K -0.01 deg/g); a real truck understeers. A
  leaf-sprung axle's roll understeer is the candidate once a figure is sourced; the semis'
  COMPROMISE goes with it.
- **Primary sources:** Gillespie ch. 6, SAE 1999-01-1323 and NHTSA's SPMD data, to upgrade the
  multi-link and leaf estimates, confirm the rear band's sign and replace the population K band
  with class bands (`docs/sources.md` § Roll steer).
- **`measure_rough` probes:** `rollsteer=` and `angdamp=`, as `measure_vehicles` has; attributing
  a rough-ground cell takes a hand edit of the body's `.tres` today.
