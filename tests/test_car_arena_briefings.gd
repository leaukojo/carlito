extends GdUnitTestSuite
## Tripwire for `tools/gen_car_arena.gd`'s header rule: the briefings in
## src/challenges/defs/car_*.tres quote these constants (often derived: the "160 m trap" is
## TRAP_TO_X - TRAP_FROM_X), so the text cannot be matched mechanically. A failure here means: edit
## the briefing that quotes the constant, re-measure the par the generator header names for it,
## then update the pinned value below.

const Gen := preload("res://tools/gen_car_arena.gd")


func test_the_constants_the_briefings_quote_are_unchanged() -> void:
	var pinned := {
		"STRIP_START_X": Gen.STRIP_START_X == -160.0,
		"START_UP_SPAWN_X": Gen.START_UP_SPAWN_X == -150.0,
		"START_UP_FINISH_X": Gen.START_UP_FINISH_X == 50.0,
		"BOX_GATE_X": Gen.BOX_GATE_X == 20.0,
		"BOX_GATE_TO_BOX": Gen.BOX_GATE_TO_BOX == 8.0,
		"BOX_LENGTH": Gen.BOX_LENGTH == 18.0,
		"BOX_WIDTH": Gen.BOX_WIDTH == 6.0,
		"TRAP_FROM_X": Gen.TRAP_FROM_X == -40.0,
		"TRAP_TO_X": Gen.TRAP_TO_X == 120.0,
		"SIGNAL_LENGTH": Gen.SIGNAL_LENGTH == 30.0,
		"WINDING_R": Gen.WINDING_R == 35.0,
		"CORNER_TURNS": Gen.CORNER_TURNS == [-90.0, 90.0, 90.0, -90.0],
		"BAY_WIDTH": Gen.BAY_WIDTH == 2.4,
		"BAY_LENGTH": Gen.BAY_LENGTH == 4.6,
		"BAY_HEADING": Gen.BAY_HEADING == 180.0,
		"ICE_R": Gen.ICE_R == 35.0,
		"ICE_SWEEP": Gen.ICE_SWEEP == 70.0,
	}
	for key in pinned:
		assert_bool(pinned[key]).override_failure_message(
				("gen_car_arena.%s moved: edit the car_*.tres briefing quoting it (and re-measure par"
				+ " per the generator header), then re-pin it here") % key).is_true()
