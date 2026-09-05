class_name FifthWheel
extends TowHost
## The tractor unit's fifth wheel: a plate under a locked kingpin, and the TowHost profile that
## says what such a plate allows. Everything the coupling DOES is TowHost's — this class is the
## three angles, the coupling datum and the three sentences the driver is told, which is the whole
## of what makes a fifth wheel not a drawbar.
##
## Its opposite number is src/vehicles/tractor/drawbar.gd; read the two side by side and the
## difference is four numbers.

## Fifth-wheel plate top in body space (y=1.05 up). Runtime value read off the scene's Kingpin
## marker in TowHost._ready and pinned against the marker by test_trailer. Every trailer authored
## for this Y; moving it floats or buries them.
const KINGPIN_LOCAL := Vector3(0.0, 1.05, 0.75)

## Yaw is free to the jackknife stop and roll is a hair of compliance, which lets the solver
## settle. Pitch travel must cover a grade break rather than bound it: once on its stop the two
## bodies are rigid, so a level trailer levers the climbing tractor's drive axle off the road. A
## sharp break onto the climbable 25% grade swings the joint -9.0 to +12.8 deg, so 15 clears it.
##
## Known compromise: the rig rests ~5.9 deg nose-up on flat ground, because the kingpin rides
## 1.306 m over the road on springs while trailers are authored for a 1.05 m plate. That is a
## coupling-datum mismatch, not a joint setting, and fixing it means moving one of the two datums.
const PITCH_LIMIT_DEG := 15.0
const ROLL_LIMIT_DEG := 1.5

## Labelled model of trailer-against-cab contact, not a property of the plate (a real fifth wheel
## turns freely). Cannot be left to collision: the gooseneck sweeps through the chassis around 60°
## of articulation, so `exclude_nodes_from_collision` must stay true. Without a limit, reversing on
## full lock folded the rig to 130° and swung the trailer through the cab.
## Articulation.JACKKNIFE_MAX_DEG is the one constant the joint AND the kinematic fallback use.
const YAW_LIMIT_DEG := Articulation.JACKKNIFE_MAX_DEG

## Told to the driver when E is pressed with the rig rolling: coupling at speed lays the trailer at
## a pose the tractor has already left, so the fit check then finds it inside whatever was driven
## past.
const HITCH_SPEED_NOTICE := "STOP WHERE THERE IS ROOM TO ATTACH"
const NO_ROOM_NOTICE := "NO ROOM FOR A TRAILER - PULL FORWARD"

static var _profile: CouplingProfile = null


func profile() -> CouplingProfile:
	if _profile == null:
		_profile = CouplingProfile.new()
		_profile.pitch_deg = PITCH_LIMIT_DEG
		_profile.yaw_deg = YAW_LIMIT_DEG
		_profile.roll_deg = ROLL_LIMIT_DEG
		# Not "FifthWheel": that name clashes with this coupler node (both children of the
		# chassis), which would have Godot silently rename the joint.
		_profile.joint_name = &"KingpinLock"
		_profile.marker_path = ^"Kingpin"
		_profile.speed_notice = HITCH_SPEED_NOTICE
		_profile.no_room_notice = NO_ROOM_NOTICE
		# Same text as the refuse arm's interlock notice; TruckVehicle owns the words.
		_profile.tip_notice = TruckVehicle.BODY_INTERLOCK_NOTICE
	return _profile


func default_marker_local() -> Vector3:
	return KINGPIN_LOCAL
