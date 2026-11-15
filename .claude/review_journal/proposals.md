# Proposals

Changes that need the user's decision. One entry each: what, evidence, cost, risk. An approved
entry moves to the Queue in `summary.md`; a refused one is deleted.

## Converter creep on a grade, once the rolling resistance is a moment (holds Queue A3)

- **What.** With the rolling moment (approved 2026-11-15, variant A) a body in D creeps back on
  grades it "held" before. `sedan`: holds still to 5.8 %, slides back at about 3 cm/s from there
  to 7.2 %, rolls away above. Before: creeps up to about 6 %, slides at up to 2 cm/s to 7.2 %.
  The creep table's held grade (`measure_grade -- all creep`) falls 0.4 to 1.3 points on every
  converter body, because its gate
  (0.25 m in 10 s) counts the faster slide as a roll.
- **Evidence.** `sessions/2026-11-16-rolling-moment-diagnosis.md` § 2: both trees carry the same
  force (783 N on 7.0 %) and have the same capacity (811 N, 7.17 %); the old slide was slower by
  exactly `g sin dt`, the credit of the `taken` fault the moment removes; under 5.8 % the moment
  opposes the driven wheels' slow turn, where the old drag helped.
- **Choice.** (a) Land A3 with the creep as measured: the table and `docs/drivetrain.md` say the
  figure is a slide speed against a gate. Recommended: the old figure owed 1.4 points to a fault.
  (b) Hold A3 until a wheel that stands is held by its patch whatever stood it (brake, lock or
  moment), which would hold a grade still up to its capacity, as a real car does: a restructuring
  of the wheel's hold, diagnosed first (Fable), then its own fix.
- **Cost.** (a) none beyond A3. (b) one diagnose session and one fix on Opus before A3, and
  `handbrake_fade.md` waits on both.
- **Risk.** (a) a player in D on a 6 to 7 % grade rolls back about 30 cm in 10 s where it was
  under 20. (b) the hold logic is where F1's standing rock lived.
