class_name FifthWheel
extends TowHost
## The tractor unit's fifth wheel: a plate under a locked kingpin, and the TowHost profile that
## says what such a plate allows; everything the coupling DOES is TowHost's.

## Fifth-wheel plate top in body space (test_trailer pins the Kingpin marker to it). Every trailer
## is authored for this Y; moving it floats or buries them.
const KINGPIN_LOCAL := Vector3(0.0, 1.05, 0.45)

## Pitch must cover a grade break, not bound it: on the stop a level trailer levers the climbing
## drive axle off the road (a sharp break onto 25% swings -9.0 to +12.8 deg). Roll: solver slack.
const PITCH_LIMIT_DEG := 15.0
const ROLL_LIMIT_DEG := 1.5

## Labelled model of trailer-against-cab contact: the gooseneck sweeps through the chassis, so
## collision stays excluded and only this limit stops the rig folding through the cab.
const YAW_LIMIT_DEG := Articulation.JACKKNIFE_MAX_DEG

## Dry plate friction about the kingpin (N*m), mid of a greased plate's 1-3 kN*m; with tyre grip,
## all that damps trailer sway.
const YAW_FRICTION_NM := 2000.0

## Told to the driver when E is pressed with the rig rolling.
const HITCH_SPEED_NOTICE := "STOP WHERE THERE IS ROOM TO ATTACH"
const NO_ROOM_NOTICE := "NO ROOM FOR A TRAILER - PULL FORWARD"

static var _profile: CouplingProfile = null


func profile() -> CouplingProfile:
	if _profile == null:
		_profile = CouplingProfile.new()
		_profile.pitch_deg = PITCH_LIMIT_DEG
		_profile.yaw_deg = YAW_LIMIT_DEG
		_profile.roll_deg = ROLL_LIMIT_DEG
		_profile.yaw_friction_nm = YAW_FRICTION_NM
		# Not "FifthWheel": it clashes with this coupler node (both children of the chassis), and Godot
		# would silently rename the joint.
		_profile.joint_name = &"KingpinLock"
		_profile.marker_path = ^"Kingpin"
		_profile.speed_notice = HITCH_SPEED_NOTICE
		_profile.no_room_notice = NO_ROOM_NOTICE
		# Same text as the refuse arm's interlock notice; TruckVehicle owns the words.
		_profile.tip_notice = TruckVehicle.BODY_INTERLOCK_NOTICE
	return _profile


func default_marker_local() -> Vector3:
	return KINGPIN_LOCAL
