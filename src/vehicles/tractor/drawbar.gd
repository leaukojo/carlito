class_name Drawbar
extends TowHost
## The tractor's rear drawbar: tractor anatomy like ThreePointHitch, and the coupler for whatever
## is hitched to it. The pin is fixed rather than swinging, so the joint's articulation matches
## what is drawn.
##
## The joint, gates and two-body housekeeping are TowHost's. This class is only the pin's geometry
## and the numbers that make a drawbar rather than a fifth wheel.

## Where the pin sits in the chassis frame. TowHost._ready reads the `Pin` marker off the scene;
## test_drawbar_trailer sweeps the trailer corners about this value, so keep it in step: 1.9935 is
## the Drawbar node's +0.3935 mount on tractor-kenney.tscn plus `Pin`'s own 1.60.
##
## The pin sits 0.40 m over the road, clear of the lowered lower-link balls at y 0.21. That height
## is the datum farm_tipper is authored against (`src/vehicles/tractor/CLAUDE.md`).
const PIN_LOCAL := Vector3(0.0, 0.40, 1.9935)

## Yaw stop, degrees each side. Not Articulation.JACKKNIFE_MAX_DEG, which models a semi-trailer
## against a cab: this is the trailer's front corners against the rear tyres, which on the tractor's
## 1.79 m track meet them just past 80 deg. test_drawbar_trailer sweeps every BoxMesh corner over it.
const SWING_MAX_DEG := 80.0

## Pitch stop, degrees each side. It must cover the steepest grade break rather than bound it: at
## the stop the bodies go rigid and lever the drive axle off the ground. 20 gives headroom over the
## fifth wheel's 15 for a steeper climb and shorter bar.
const PITCH_LIMIT_DEG := 20.0

## Roll stop, degrees each side. A fifth wheel holds roll to ~1.5 deg; a drawbar eye lets a farm
## trailer roll on its own wheels, so a rut does not lever the tractor. Wide rather than unlimited:
## an unbounded 6DOF axis has nothing to catch a body past upright.
const ROLL_LIMIT_DEG := 25.0

## Shown when E asks for a trailer while still rolling. Gates only the towed cycle entries.
const HITCH_SPEED_NOTICE := "STOP WHERE THERE IS ROOM TO HITCH"
const NO_ROOM_NOTICE := "NO ROOM FOR A TRAILER - PULL FORWARD"
## Why the SCV did nothing, in the raise direction only. No PTO: a farm trailer's ram runs off the
## tractor's own pump.
const TIP_INTERLOCK_NOTICE := "SET THE HANDBRAKE FIRST"

static var _profile: CouplingProfile = null


func _ready() -> void:
	super._ready()
	# Nothing here moves, so the six meshes merge into one; Pin is a Marker3D.
	StaticMeshMerge.merge_subtree(self)


func profile() -> CouplingProfile:
	if _profile == null:
		_profile = CouplingProfile.new()
		_profile.pitch_deg = PITCH_LIMIT_DEG
		_profile.yaw_deg = SWING_MAX_DEG
		_profile.roll_deg = ROLL_LIMIT_DEG
		_profile.joint_name = &"DrawbarPin"
		_profile.marker_path = ^"Pin"
		_profile.speed_notice = HITCH_SPEED_NOTICE
		_profile.no_room_notice = NO_ROOM_NOTICE
		_profile.tip_notice = TIP_INTERLOCK_NOTICE
	return _profile


func default_marker_local() -> Vector3:
	return PIN_LOCAL
