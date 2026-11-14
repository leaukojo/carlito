# 2026-11-14: `RayWheel.settled_drop`'s floor

A Fable session on the user's word ("apply your recommendations", little usage left): the
Queue's smallest ready item, tagged for Sonnet, fixed here.

## Finding: the `maxf(normal_up, 0.1)` floor is dead

- `settled_drop` has one caller outside tests, `RayWheel._contact_pass` (`wheel.gd`, the last
  branch), reached only after `if not rest.is_empty() and not carries(rest["normal"], up)`
  returned: `normal_up >= cos(deg_to_rad(LYING_DEG))` = cos 70 deg = 0.342 > 0.1.
- Its test (`test_the_settled_drop_backs_the_touching_stop_out_of_its_overlap`) passes 1.0 and
  0.5.
- `maxf(x, 0.1)` is `x` for every such `x`: the results are the same to the bit.

Fixed: the floor removed, the doc comment names the precondition. Full suite: 2506 cases, 0
failures.

Nothing deferred.
