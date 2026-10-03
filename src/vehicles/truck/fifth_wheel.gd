class_name FifthWheel
extends TowHost
## The tractor unit's fifth wheel: a plate under a locked kingpin, and the TowHost profile that
## says what such a plate allows. Everything the coupling DOES is TowHost's; this class is the
## three angles, the coupling datum, the yaw friction and the notices. Its counterpart is
## `src/vehicles/tractor/drawbar.gd`.

## Fifth-wheel plate top in body space. TowHost._ready reads the scene's Kingpin marker; test_trailer
## pins this against it. Every trailer is authored for this Y; moving it floats or buries them.
const KINGPIN_LOCAL := Vector3(0.0, 1.05, 0.45)

## Roll is a hair of compliance, which lets the solver settle. Pitch travel must cover a grade
## break rather than bound it: on its stop the bodies are rigid and a level trailer levers the
## climbing drive axle off the road. A sharp break onto a 25% grade swings the joint -9.0 to
## +12.8 deg, so 15 clears it. The rig meets one only rolling or with speed: from rest the box rig
## pulls away on 16% at most (docs/vehicles.md § Gradeability).
##
## The coupled rig rests slightly tractor nose-up (rear axle at more spring travel than the steer
## axle), so KINGPIN_LOCAL.y cannot level the tractor; it only sets the trailer's own pitch.
## Wheelbases that keep the steer axle loaded through a launch: docs/heavy_vehicles.md § Truck
## sizing.
const PITCH_LIMIT_DEG := 15.0
const ROLL_LIMIT_DEG := 1.5

## Labelled model of trailer-against-cab contact, not a property of the plate (a real fifth wheel
## turns freely). Collision cannot do it: the gooseneck sweeps through the chassis around 60 deg, so
## `exclude_nodes_from_collision` must stay true, and without a limit reversing on full lock folds
## the rig through the cab. Articulation.JACKKNIFE_MAX_DEG is the one constant the joint AND the
## kinematic fallback use.
const YAW_LIMIT_DEG := Articulation.JACKKNIFE_MAX_DEG

## Dry friction about the kingpin (N*m): a greased plate is not a free hinge, and 2000 is the middle
## of the 1-3 kN*m such a plate carries. With tyre lateral grip it is all that damps trailer sway,
## and it is Coulomb (see TowHost._apply_yaw_friction). The drawbar leaves the profile default 0.
const YAW_FRICTION_NM := 2000.0

## Told to the driver when E is pressed with the rig rolling (the trailer would be laid at a pose
## the tractor has already left).
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
