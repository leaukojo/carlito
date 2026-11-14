# 2026-11-14: `docs/drivetrain.md`, the laden semis' roll-back sentence

A Fable session on the user's word; the item was tagged for Sonnet.

## Finding: the sentence is wrong for one of the two semis

The doc: "The laden semis roll back far on 25 % with or without the hold, and with `nohold`
never pull away."

`measure_grade -- <variant> rollback [nohold]`, `--fixed-fps 60`, asphalt, +24000 kg towed,
pedal 100 % 0.50 s after the release:

| variant | hold | 10 % back, forward | 25 % back, forward |
|---|---|---|---|
| `semi` | as fitted | -0.0 mm, 1.17 s | 0.1 mm, 3.10 s |
| `semi` | `nohold` | 6.0 mm, 1.08 s | 927.3 mm, never |
| `semi-conventional` | as fitted | -0.0 mm, 1.23 s | 824.5 mm, never |
| `semi-conventional` | `nohold` | 6.7 mm, 1.13 s | 3573.0 mm, never |

Not read: what the "back mm" of a run that never goes forward covers (the run's length bounds
it), so the sentence carries no distance.

Fixed: the sentence says which semi holds and which rolls back.

## Not traced

`semi-conventional` with its hold (held 0.62 s) rolls back 824.5 mm on 25 % and never pulls
away, where `semi` holds and goes at 3.10 s. Whether that is the body's gearing or a fault is
not looked at here.
