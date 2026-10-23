# 17 — Compliance steer: a rear axle's steer under side force

Shared context: `00_README.md`. Root cause: the sim steers a rear wheel only through roll
(`RayWheel.roll_steer`); a real axle also steers under the side force its bushings and spring ends
carry. Size: medium, one per-axle mechanism and a body-by-body fit.

Builds on `docs/handling.md` § Balance (roll steer, the stated shortfall in linear K, the
COMPROMISE bodies), `docs/sources.md` § Roll steer, § Compliance steer, § Linear understeer, and
`docs/vehicle_measurements.md` § Step steer.

## 1. What is missing

- **The subject is a rear axle's steer under side force, either sign**: a per-axle coefficient,
  deg of wheel steer per kN of that axle's side force, + = toward understeer (the rear into the
  turn), the convention roll steer uses. It is a wheel angle beside `RayWheel.roll_steer`, never a
  grip, read off the axle's own tyre force, not the body's lateral g.
- **The stock axles comply toward oversteer** (`docs/sources.md` § Compliance steer):
  - the twist beam: a parallel side load toes both rear wheels away from it, −0.05 to −0.075 deg/kN
    a wheel (A/SP's OEM baseline, Fig. 37, ADAMS correlated with a K&C rig; read off a figure);
  - the leaf-sprung rigid axle: with a bushed front eye and a rear shackle, the cornering force
    deflects each spring's rear end more than its front, "lateral force oversteer" (US 4,919,449;
    no size);
  - multi-link rears, fronts, trucks: no figure found.
- **Rear toe-in under side force is a designed axle, never a class default.** It is the classic
  cure for lift-off oversteer (the patent's rocker gives "lateral force understeer"), so a body
  takes it only where its real axle is built for it, with a source.

## 2. What it may retire, body by body

| Body | Rear axle | Sign it takes | Where the sign is from |
| --- | --- | --- | --- |
| `sedan`, `taxi`, `hatchback-sports` | twist beam | − (oversteer) | A/SP Fig. 37, sized |
| `sedan-sports`, `suv`, `suv-luxury`, `police` | multi-link | none until a figure is sourced | — |
| `van`, `pickup`, `pickup-flat`, `delivery`, `delivery-flat`, `ambulance` | leaf | − (oversteer) | US 4,919,449, no size |
| `garbage-truck`, `firetruck`, the semis | leaf | − (oversteer) | US 4,919,449, no size |
| `race`, `race-future`, the tractor | — | 0 | no figure; race kinematics laid out for minimal toe |

- **The lift-off cases** are the `rear_lat_grip` 1.08 that the COMPROMISE bodies carry
  (`sedan-sports`, `suv`, `pickup`, `pickup-flat`; `docs/handling.md` § Balance) and the `police` /
  `suv-luxury` lifted spins at the fastest 30 % step. A patch retires on measurement only
  (`00_README.md` § Agreed philosophy).
- **The leaf pickups take the stock oversteer sign**, which cannot retire their 1.08: it makes the
  lift-off worse, so their compromise stays or moves on a different lever. The same sign on the
  twist-beam saloons and the leaf vans can open lifted spins they do not have now: every body that
  takes it is re-judged on its lifted cells.
- **A cure on the multi-link bodies needs a sourced multi-link figure**, which the handling
  research did not find (UMTRI and NHTSA's VRTC reports refuse automated fetching; Gillespie ch. 6
  was not reachable). Without one, those four bodies take 0 and their compromises stand.
- The leaf trucks' fitted roll steer (`TRUCK_BASE`, a COMPROMISE fitted to Woodrooffe &
  El-Gindy's criterion) is judged again with the oversteer sign in: compliance steer moves K down.

## 3. The size

- **Its linear-K share is small:** compliance steer is 0.5 of Bundorf's illustrative 4.1 deg/g
  budget, side force 0.4 of it (`docs/sources.md` § Linear understeer); roll camber, 1.2, is the
  larger share still unmodelled. At 0.5 g a ~1150 kg saloon's rear wheel carries ~1.1 kN of side
  force, so the twist beam steers it ~0.06-0.08 deg toward oversteer (computed): the order of its
  roll steer there, 0.036 × ~2.5 deg of roll.
- **It matters on the lift-off transient more than in K:** lateral-force steer acts as the force
  builds, without roll understeer's lag (US 4,919,449). The step pass's lifted cells are where it
  shows.
- **The 60 Hz loop:** the angle follows the tyre force it changes, a tighter loop than roll
  steer's (no roll inertia between them). The step pass's `chatter_runs` is the guard, as for roll
  steer (`docs/handling.md` § Balance). A coefficient that rings is the plan's to solve, never with
  a filter: a lag removes the transient that is the point.

## 4. Done when

- Each body's rear axle carries its sourced sign and size, or 0 with the reason; `BalanceModel`
  predicts the K share and the step pass reads it within the roll-steer tolerance.
- The lifted step cells are re-measured on every body that moved (`measure_vehicles -- doc=steer`
  plus the COMPROMISE bodies' `-- <variant> 60 step`), with no new spun or tipped cell and no
  chatter.
- Every COMPROMISE that section 2 names is either retired on measurement or restated with what
  still holds it.

## Planning

Planning effort: high (the multi-link figure is unsourced, the loop is tighter than roll steer's,
and every retirement is a measurement). One plan.
