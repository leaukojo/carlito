class_name ChallengeConstraint
extends ChallengeCheck
## Holds for the attempt and is stepped every tick: RUNNING while it holds, FAIL (or RESET, for a
## fail zone) on the tick it breaks. A constraint never returns PASS.

## The goal index from which this constraint is judged; 0 is the whole attempt. It lets goal 0
## engage something (the boat's HEADING HOLD) that a constraint then forbids leaving.
@export var from_goal := 0
