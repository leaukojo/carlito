# 2026-11-20: roll-over control on `garbage-truck` and `firetruck`

Item: the Queue's approved line (user, 2026-11-20). Plan: measure each body's first-lift g in
`measure_vehicles`' `corner` pass (ESC off), write the tables in the generator, regen.

Why not `measure_semi_launch`'s `ramp`: it casts to `SemiTractor` and its P2-P6 are fifth-wheel
launch phases; `measure_vehicles`' corner pass already holds speed, winds the lock on, takes
`noesc` and `mass=` on any body.

## Baseline at HEAD (0097c7d)

`measure_vehicles -- <variant> 60 step speeds=70` (ESC on, yaw part only), the 30 % cells:

| Body | 30 % held | 30 % lifted | 20 % held / lifted |
| --- | --- | --- | --- |
| `firetruck` 12 t | ROLLED 2.48 s, 4 wheels up, ESC 75 % | ROLLED 2.32 s | 0.44 / 0.50 g, no lift |
| `garbage-truck` 8 t | 0.66 g, 1 wheel up, ESC 89 % | 0.68 g, none up | 0.44 / 0.51 g |
| `garbage-truck` 13 t (`mass=13000`) | 0.61 g, none up | 0.63 g, none up | 0.42 / 0.47 g |

## First lift, `measure_vehicles -- <variant> 60 track corner noesc [mass=<kg>]` (40 km/h, 10 s wind-on)

`acc_lat` at the first wheel off the road (the corner pass's new line, uncommitted until the plan's
step 2 commit):

| Body, kg | first lift | corner peak |
| --- | --- | --- |
| `firetruck` 12000 | 0.546 g (45 % of the ramp) | 0.80 g, ROLLED |
| `garbage-truck` 8000 | 0.655 g | 0.71 g |
| 8625 | 0.638 g | 0.69 g |
| 9250 | 0.623 g | 0.67 g |
| 9875 | 0.611 g | 0.66 g |
| 10500 | 0.628 g | 0.65 g |
| 11125 | 0.625 g | 0.65 g |
| 11750 | 0.624 g | 0.65 g |
| 12375 | never (front saturates, ploughs at 0.65 g) | 0.65 g |
| 13000 | never | 0.65 g |

Stop condition hit (plan step 3): the two fullest levels never lift. Asked the user ("whatever is
realistic, not a dirty fix, not over-engineered"): the table ends at 11750 and `roll_lift_g` holds
its last point (0.624 g) past it, as a real unit estimates its threshold from the load. No new
code; `test_vehicle_catalog` checks every point sits on a live mass, not that every mass has one.

## After (ESC on, `step speeds=70`)

| Body | 20 % held / lifted | 30 % held / lifted |
| --- | --- | --- |
| `firetruck` | 0.33 / 0.39 g, 1 wheel up, roll braking 47 / 83 %, peak 0.89 / 0.84 | **holds**: 0.38 / 0.38 g, roll 5.6 deg, 1 wheel up, roll braking 75 / 86 %, peak 1.00 |
| `garbage-truck` 8 t | 0.37 / 0.48 g, 1 up, 29 / 73 % | 0.44 / 0.47 g, 1 up, 80 / 73 %; chatter 2 on the held cell |
| 11.75 t | 0.34 / 0.43 g, 0 / 1 up | 0.43 / 0.45 g, 1 up |
| 13 t | 0.35 / 0.39 g, none up | 0.43 / 0.46 g, 1 up |

Pass criterion met: the firetruck no longer rolls at 70 km/h 30 %. Roll braking now acts from
~0.38-0.46 g and slows the trucks in the 20 / 30 % cells, as roll stability does. Seen, not
chased: a held 20 % step on the firetruck and the empty garbage truck now lifts one wheel briefly
(the full brake in a turn, 63 % / 48 % yaw overshoot), and the empty garbage truck's 30 % held cell
reads roll chatter 2. Both are for the drive check; neither rolls.

Unchanged: `doc=steer` / `doc=cornering` set `noesc`, which returns early from `esc_step`. The
per-body `step noesc` runs match `doc=steer`'s garbage-truck row (K 0.60 at 30 km/h, 0.96 / 1.00);
the corner `noesc` runs match `doc=cornering`'s rows (0.71 g / 0.80 g overturned). `doc=esc` skips
bodies over 4536 kg.

## Commits

- 5b55309 measure_vehicles: the corner pass reads the first wheel lift (`acc_lat`).
- d023668 the two tables in the generator, regen (two `.tres` lines), `test_vehicle_catalog`'s
  roll test on every ESC truck. `test_kenney_variants`' honoured-key guard failed on it until:
- 6c0bdb9 `MACHINE_TABLES` (honoured, shipped as declared).
- c3978df docs: handling, the guide (anchor renamed `#roll-stability-on-the-trucks`, its two links),
  `vehicle_measurements` (gap line dropped, the corner row), two comments.

Full suite: 2541 cases, 0 failures. `check_docs` passes (15 characters of docs headroom left).

## Noted, not done

- Heavy vans (`delivery` 4.2 t, `ambulance` 4.8 t) are N2 under R13 (5.2.1.32) too, with no roll
  table: a candidate proposal, outside this item.
