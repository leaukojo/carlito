class_name FamilyGearbox
extends RefCounted
## Whether a family offers a gearbox mode: a contract question, asked by the garage, the challenge
## data and its validator. Kept out of VehicleCatalog, which `--script` tools reach through the
## baker and so must not name the `Contract` autoload.


## Whether the family's contract takes a gear byte, the only thing a gearbox mode acts on (rule 4:
## read, not listed here). Plane and train still carry that byte on the wire (reverser N/D/R),
## but their own code only ever reads it through Drivetrain.is_drive/is_reverse, which collapse
## every D1-D24 alike — so manual vs. automatic (literal byte vs. auto-shifted) changes nothing
## either can feel, and the picker would offer a choice with no effect (the plane is single-speed
## by construction: plane_spec.tres, test_plane).
static func has_gearbox(family: String) -> bool:
	if family == "plane" or family == "train":
		return false
	if Contract.data == null or not Contract.data.is_valid():
		return false
	var gear := Contract.data.get_signal_def("gear", "in")
	return gear != null and gear.vehicles.has(family)
