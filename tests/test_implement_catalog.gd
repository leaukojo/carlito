extends GdUnitTestSuite
## ImplementCatalog: V-cycle order for tractor implements. Detached is a real cycle entry.

const PloughScript := preload("res://src/vehicles/tractor/implements/plough.gd")
const HarrowScript := preload("res://src/vehicles/tractor/implements/harrow.gd")
const MowerScript := preload("res://src/vehicles/tractor/implements/mower.gd")
const SpreaderScript := preload("res://src/vehicles/tractor/implements/spreader.gd")
const ContractScript := preload("res://src/bridge/contract.gd")


# --- cycle order --------------------------------------------------------------

func test_cycle_includes_the_detached_state_and_wraps() -> void:
	var seen := PackedStringArray()
	var id := ImplementCatalog.first()
	for _i in ImplementCatalog.IMPLEMENTS.size():
		seen.append(id)
		id = ImplementCatalog.next(id)
	# One full lap returns to the start and visited every entry, detached included.
	assert_str(id).is_equal(ImplementCatalog.first())
	assert_int(seen.size()).is_equal(ImplementCatalog.IMPLEMENTS.size())
	assert_bool(seen.has(ImplementCatalog.DETACHED)).is_true()


func test_first_is_attached_so_the_tractor_spawns_with_an_implement() -> void:
	assert_str(ImplementCatalog.first()).is_not_equal(ImplementCatalog.DETACHED)
	assert_bool(ImplementCatalog.is_attached(ImplementCatalog.first())).is_true()
	assert_bool(ImplementCatalog.is_attached(ImplementCatalog.DETACHED)).is_false()


func test_unknown_id_restarts_the_cycle() -> void:
	assert_str(ImplementCatalog.next("res://nope.tscn")).is_equal(ImplementCatalog.IMPLEMENTS[0])


## The entries in the cycle that hang on the LINKAGE. Everything below is about three-point
## implements — visual children of the chassis, posed by the four-bar solve — and the cycle also
## carries a DRAWBAR trailer, which is a jointed RigidBody3D with collision, wheels and no device
## class at all. That machine has its own suite (tests/test_drawbar_trailer.gd), which ALSO sweeps
## this catalog and asserts the two kinds declare the connection they are routed by — so nothing
## falls between the two files by being skipped here.
func _three_point_entries() -> PackedStringArray:
	var out := PackedStringArray()
	for path in ImplementCatalog.IMPLEMENTS:
		if ImplementCatalog.is_attached(path) and not ImplementCatalog.is_towed(path):
			out.append(path)
	assert_int(out.size()).override_failure_message("no three-point implements left").is_greater(3)
	return out


func test_every_implement_scene_exists_and_extends_the_base() -> void:
	for path in _three_point_entries():
		assert_bool(ResourceLoader.exists(path)) \
			.override_failure_message("missing implement scene: %s" % path).is_true()
		var node := (load(path) as PackedScene).instantiate()
		assert_object(node).is_instanceof(ImplementBase)
		# Implements are visual only — a collision shape here would put physics on the hitch.
		assert_int(node.find_children("*", "CollisionShape3D", true, false).size()) \
			.override_failure_message("%s must stay collision-free" % path).is_equal(0)
		node.free()


# --- what an implement declares about itself ----------------------------------

func test_base_defaults_are_the_detached_reading() -> void:
	# The base is what "nothing useful attached" looks like: no connections, device class 0,
	# no draft.
	var base := ImplementBase.new()
	assert_int(base.connections()).is_equal(0)
	assert_int(base.device_class()).is_equal(ImplementBase.CLASS_NONE)
	assert_bool(base.uses(ImplementBase.Connection.THREE_POINT)).is_false()
	assert_bool(base.draft_relevant()).is_false()
	assert_float(base.tool_depth()).is_equal(0.0)
	base.free()


func test_a_draft_machine_declares_its_own_working_depth() -> void:
	# The two declarations have to agree, because the tractor multiplies them: draft_relevant()
	# switches the force on and tool_depth() is the span it ramps across, so a draft machine with
	# no declared depth would publish a permanent honest-looking zero and a machine that works
	# above the ground with a depth would be waiting for someone to flip the other flag.
	for path in _three_point_entries():
		var node: ImplementBase = (load(path) as PackedScene).instantiate()
		if node.draft_relevant():
			assert_float(node.tool_depth()) \
				.override_failure_message("%s is draft-relevant but declares no tool depth" % path) \
				.is_greater(0.0)
		else:
			assert_float(node.tool_depth()) \
				.override_failure_message("%s works above the ground but declares a depth" % path) \
				.is_equal(0.0)
		node.free()


func test_the_harrow_works_shallower_than_the_plough() -> void:
	# The reason working depth is per-implement rather than one constant: these two really do
	# reach different distances into the soil (measured off their scenes), so sharing a figure
	# had the harrow reporting draft with its tines already in the air.
	var plough: ImplementBase = PloughScript.new()
	var harrow: ImplementBase = HarrowScript.new()
	assert_float(harrow.tool_depth()).is_less(plough.tool_depth())
	plough.free()
	harrow.free()


func test_plough_is_three_point_only_and_the_deepest_draft_machine() -> void:
	# The plough's declaration that matters is a NEGATIVE: no PTO — it is pulled, not driven, the
	# only machine here with nothing on the shaft. Draft it shares with the harrow (which works the
	# soil too, just shallower and driven); what is its own is the depth its shares reach.
	var plough: ImplementBase = PloughScript.new()
	assert_bool(plough.uses(ImplementBase.Connection.THREE_POINT)).is_true()
	assert_bool(plough.uses(ImplementBase.Connection.ISOBUS_DATA)).is_true()
	assert_bool(plough.uses(ImplementBase.Connection.PTO)).is_false()
	assert_bool(plough.uses(ImplementBase.Connection.SCV)).is_false()
	assert_bool(plough.uses(ImplementBase.Connection.DRAWBAR)).is_false()
	assert_bool(plough.draft_relevant()).is_true()
	assert_int(plough.device_class()).is_equal(ImplementBase.CLASS_TILLAGE)
	plough.free()


func test_harrow_is_the_driven_tillage_machine() -> void:
	# The harrow is the plough's counterpart on the same job: also tillage, also in the soil,
	# but DRIVEN rather than dragged. Its two declarations that matter are therefore the PTO
	# the plough lacks and the device class the plough does not share.
	var harrow: ImplementBase = HarrowScript.new()
	assert_bool(harrow.uses(ImplementBase.Connection.THREE_POINT)).is_true()
	assert_bool(harrow.uses(ImplementBase.Connection.PTO)).is_true()
	assert_bool(harrow.uses(ImplementBase.Connection.ISOBUS_DATA)).is_true()
	assert_bool(harrow.uses(ImplementBase.Connection.DRAWBAR)).is_false()
	assert_bool(harrow.uses(ImplementBase.Connection.SCV)).is_false()
	assert_bool(harrow.draft_relevant()).is_true()
	assert_int(harrow.device_class()).is_equal(ImplementBase.CLASS_SECONDARY_TILLAGE)
	assert_int(harrow.device_class()).is_not_equal(ImplementBase.CLASS_TILLAGE)
	harrow.free()


func test_mower_is_pto_driven_and_carries_no_draft() -> void:
	var mower: ImplementBase = MowerScript.new()
	assert_bool(mower.uses(ImplementBase.Connection.THREE_POINT)).is_true()
	assert_bool(mower.uses(ImplementBase.Connection.PTO)).is_true()
	assert_bool(mower.uses(ImplementBase.Connection.ISOBUS_DATA)).is_true()
	# A deck on skids is neither towed nor hydraulically fed, and it rides ABOVE the ground.
	assert_bool(mower.uses(ImplementBase.Connection.DRAWBAR)).is_false()
	assert_bool(mower.uses(ImplementBase.Connection.SCV)).is_false()
	assert_bool(mower.draft_relevant()).is_false()
	assert_int(mower.device_class()).is_equal(ImplementBase.CLASS_FORAGE)
	mower.free()


func test_spreader_adds_the_hydraulic_remote() -> void:
	var spreader: ImplementBase = SpreaderScript.new()
	assert_bool(spreader.uses(ImplementBase.Connection.THREE_POINT)).is_true()
	assert_bool(spreader.uses(ImplementBase.Connection.PTO)).is_true()
	assert_bool(spreader.uses(ImplementBase.Connection.ISOBUS_DATA)).is_true()
	# The one machine with an SCV: the ram on its hopper gate (the scv_flow consumer).
	assert_bool(spreader.uses(ImplementBase.Connection.SCV)).is_true()
	assert_bool(spreader.uses(ImplementBase.Connection.DRAWBAR)).is_false()
	assert_bool(spreader.draft_relevant()).is_false()
	assert_int(spreader.device_class()).is_equal(ImplementBase.CLASS_FERTILIZER)
	spreader.free()


func test_every_implement_hangs_on_the_three_point_linkage() -> void:
	# There is one hitch and it is a three-point linkage: an implement in this cycle that did
	# not declare THREE_POINT would be hung off a connection the tractor does not have.
	for path in _three_point_entries():
		var node: ImplementBase = (load(path) as PackedScene).instantiate()
		assert_bool(node.uses(ImplementBase.Connection.THREE_POINT)) \
			.override_failure_message("%s is in the cycle but not three-point mounted" % path) \
			.is_true()
		node.free()


func test_no_two_implements_report_the_same_device_class() -> void:
	# implement_type is how the bus tells them apart; two machines sharing a class would make
	# the signal unable to answer "what is on the hitch".
	var seen := {}
	for path in _three_point_entries():
		var node: ImplementBase = (load(path) as PackedScene).instantiate()
		var cls := node.device_class()
		assert_bool(seen.has(cls)) \
			.override_failure_message("%s reports device class %d, already used by %s"
				% [path, cls, seen.get(cls, "")]) \
			.is_false()
		assert_int(cls).is_not_equal(ImplementBase.CLASS_NONE)
		seen[cls] = path
		node.free()


func test_device_classes_are_declared_by_the_contract() -> void:
	# Rule 4: the contract owns the implement_type enum. Every device class an implement can
	# report must decode to a label there — a class the contract has never heard of would
	# publish as an unlabelled number.
	var file := FileAccess.open(ContractScript.CONTRACT_PATH, FileAccess.READ)
	assert_object(file).is_not_null()
	var contract := ContractScript.ContractData.parse(file.get_as_text())
	var sig := contract.get_signal_def("implement_type", "out")
	assert_object(sig).is_not_null()
	assert_str(sig.flavor).is_equal("isobus")
	assert_str(sig.enum_label(ImplementBase.CLASS_NONE)).is_equal("None")
	for path in _three_point_entries():
		var node: ImplementBase = (load(path) as PackedScene).instantiate()
		assert_str(sig.enum_label(node.device_class())) \
			.override_failure_message("contract has no implement_type label for %s" % path) \
			.is_not_equal("")
		node.free()
