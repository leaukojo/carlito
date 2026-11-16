# 2026-11-16: the contact's reading steps fixed (Queue A2, the fix)

Started at 605da78, in the diagnosing session's context on the user's word ("apply your
recommendations"), so on Fable; the brief is `2026-11-16-contact-reading-steps.md` § Brief.
Continued on Opus from 4c28c56 (the user: "continue what it was doing").

## Findings and commits

- **Item 1, 4c28c56** (Fable): `settled_drop` takes `reach`; `_contact_pass` passes the sharp
  less the rounded support over `n_up`. Test `test_a_leaned_wheel_reads_no_step_at_a_sweep_stop`
  (leans 0.00621, 0.035, 0.1 on the ramp slab; 8 m slab). The brief's after-runs are not on
  record: every log in `rm-logs/a2/` predates the commit (12:47 vs 13:33).
- **Item 2, the deciding measurement** (Opus; probe kept as
  `rm-logs/a2/test_a2_probe_far_ground.gd`, removed from `tests/`). Body raked -0.5255 deg, hub
  stepped 0.24 um x 240; "level" = the query turned about its axle onto world up (the collider's
  up for these fixtures: identity basis):

  | ground | today: worst / distinct | level frame |
  | --- | --- | --- |
  | trimesh near, 10 % | 0.21 um / 240 | 0.15 / 240 |
  | trimesh 500 m out, 10 % | 3.81 um / 15 | 3.81 / 16 |
  | trimesh 500 m out, flat | 0.30 um / 122 | 0.05 / 240 |
  | trimesh 500 m out, 30 % | 18.7 um / 4 | 14.6 / 5 |
  | trimesh 2000 m out, 10 % | 10.8 um / 5 | 10.8 / 5 |
  | heightmap near, 10 % | 0.15 um / 240 | 0.12 / 240 |
  | heightmap 480 m out, 10 % | 3.81 um / 15 | 2.55 / 16 |
  | heightmap 480 m out, 30 % | 15.3 um / 3 | 19.4 / 5 |

  On a grade the grid is ulp of the hub's WORLD height (48-50 m: 2^-18 = 3.81 um; 150 m: 15.3
  um): the query's origin is float32 before any frame applies, so no frame removes it. The brief's
  prediction (`ulp(D * sin(grade))` from the frame, gone with a level one) is wrong in its cause;
  the size matched because the hub's height is `D * sin(grade)`. Flat and far, the frame does
  act, on a 0.3 um step. So item 2's frame serves the box case only (the tools' strip, Flatland's
  `InfiniteGround`): the brief's branch "asks the user whether the frame or a shorter strip".
- Seen, not acted on: the first probe run had the wheel on the quad's shared diagonal (two
  coplanar triangles, `backface_collision`): 88 um near, 153 um at 500 m. Off the edge it reads
  as above. An internal edge of a flat welded mesh steps the reading; not measured further.

- **Item 2, the frame** (the user chose it over a shorter strip): `query_basis(wheel_basis,
  frame_up)`, `_frame_up` read off the contact's collider when `contact_collider` changes.
  `test_a_raked_wheel_reads_a_long_box_off_no_grid`: the 6 km strip reads 33 distinct of 240 at
  4c28c56, >= 200 after. The pitched 10 % ramp read 1.01 um worst until the fixture ticked once
  in place first: the first touch is posed on world up (no collider yet), and the next tick's
  turn onto the ramp's up moves the reading by float noise once. With the settling tick: passes
  under 1 um. `test_wheel_spin` 164/164.
- **Item 3**: `_contact_query`'s and `cylinder_support`'s comments, the 4 m slab's test comment,
  `docs/vehicles.md` § the sweep's paragraph (replaced, within the cap).

## After-runs (605da78, before A2, vs items 1-3; `--fixed-fps 60`, scratch worktrees)

- Suite: 2526 / 2526. `test_wheel_spin`: 164 / 164.
- Bobtail `rest reading:` axle-load step 0.11 -> 0.01 kg a tick (stop condition: not over HEAD's).
- `semi 20 rest`: rear axle 0.6 -> 0.0 kg a tick, p-p 2.2 -> 0.0 kg; contact speed 0.13 -> 0.02
  mm/s; drag 11 -> 2 N a wheel.
- `semi 20 kerb`: every pass's outcome and time the same (the 20 cm crawl at 30 deg STUCK on both);
  per-wheel peaks within 3 kN, lean within 3 deg.
- `semi 20 scrape`: the same but 1 N.
- Cross cell (`doc=park park_cell=semi:cross:5.7`, `probe_head.diff`; its `tools/probe_rm.gd` was
  never kept, so a stand-in writing `band2.py`'s fields: `rm-logs/a2/probe_rm_standin.gd`): no
  band. The least read drop over a stop is 0.0007 to 0.0028 mm on the unit (0.096 to 0.105 mm
  before, `e` 0.095 to 0.108) and 0.0001 to 0.0105 mm on the trailer (0.255 to 0.294 before).
- No committed `doc=` figure moved. Logs: `rm-logs/a2/*_base.log`, `*_after.log`.

## For A3

Its stop condition on the patch (bobtail over 0.11 kg, or the cross cell's FL alternating over
2 N) is checked there.
