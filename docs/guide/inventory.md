# Inventory of modelled systems

This is the guide's checklist, not a player page. Each row is one mechanical system the game
models: which vehicles have it, where the code lives, and which guide page explains it. It was
built by reading the vehicle, water and input code and the developer docs (drivetrain, handling,
vehicles, truck, tractor, boat, flight, rail, systems). A page marked *(planned)* is not written
yet.

Families are the seven the signal contract knows: car, truck, tractor, boat, plane, drone, train.
"Car" includes the vans and the two racers; "truck" includes the garbage truck, the fire truck and
the two semi tractor units.

## The guide's pages

| Page | File | Covers |
| --- | --- | --- |
| Tyres and slip | [tyres.md](tyres.md) | slip ratio, slip angle, grip curve, combined slip, load sensitivity, the contact patch at rest |
| Steering and Ackermann | [steering.md](steering.md) | steering rate, lock and its speed taper, the bicycle angle, Ackermann, roll and compliance steer, auto-steer |
| Ground and tyre types | [surfaces.md](surfaces.md) | surfaces, tyre classes, rolling resistance on soft ground |
| Suspension | [suspension.md](suspension.md) | springs, dampers, anti-roll bars, anti-dive and anti-squat, the tractor's swinging front axle |
| Weight transfer and rollover | [weight-transfer.md](weight-transfer.md) | load moving between wheels, understeer and oversteer, rollover thresholds |
| The engine | [engine.md](engine.md) | torque curve, rpm, idle, limiter, governor, pedal map, engine braking, fuel burn |
| Clutch and torque converter | [coupling.md](coupling.md) | friction clutch, converter, creep, lock-up, launch |
| Gearbox and shifting | [gearbox.md](gearbox.md) | gear byte, automatic and manual, the shift policy, kickdown, AMT, powershift, CVT, park |
| Differentials and four-wheel drive | [differentials.md](differentials.md) | open, limited-slip and Torsen diffs, diff lock, MFWD, centre diffs |
| Brakes | [brakes.md](brakes.md) | brake hardware, bias, handbrake, heat and fade, retarder, spring brakes, air |
| ABS, traction and stability control *(planned)* | driver-aids.md | ABS, TC/ASR, ESC, roll stability, their lamps |
| Holding still *(planned)* | holding.md | hill-start assist, auto hold, the tractor's hill hold, park pawl, CVT standstill |
| Air and rolling resistance *(planned)* | resistance.md | drag, side force, downforce, rolling resistance |
| Towing *(planned)* | towing.md | fifth wheel and drawbar, trailers, articulation, jackknife, trailer brakes, trailer bus |
| Implements and the PTO *(planned)* | implements.md | three-point hitch, draft, PTO, hydraulic remote, ISOBUS |
| Floating and boats *(planned)* | floating.md | buoyancy, propeller thrust, rudder, trim, windage, sailing, autopilot |
| Wind, current and conditions *(planned)* | conditions.md | wind field, tide, CONDITIONS presets, day and night |
| Drone flight *(planned)* | drone-flight.md | rotors, mixer, arming, flight modes, failsafes, battery pack, sensors, bus nodes |
| Plane flight *(planned)* | plane-flight.md | lift, stall, drag, thrust, flaps, control surfaces |
| Trains *(planned)* | rail.md | tractive effort, running resistance, couplers, brake pipe, reverser, pantograph |
| Fuel, coolant, battery and air *(planned)* | aux.md | the simple labelled models |
| Position, heading and distance *(planned)* | position.md | GPS, heading, odometer, hour meter, acceleration and impact |
| Controls and who drives *(planned)* | controls.md | keyboard easing, ignition, bridge or local input, lamps and horn |
| Forces *(planned, phase 3)* | forces.md | every force on a body, together |
| Vehicle pages *(planned)* | car.md, truck.md, tractor.md, boat.md, plane.md, drone.md, train.md | which systems each family has |
| What the game simplifies *(planned)* | simplifications.md | compromises and things not modelled |

## Wheels and tyres

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| Wheel contact: a cylinder swept down the suspension travel | car, truck, tractor, plane (landing gear), trailers | `src/vehicles/base/wheel.gd` (`RayWheel`) | tyres |
| Slip ratio (wheel surface speed against road speed, floored at low speed) | car, truck, tractor, plane, trailers | `wheel.gd` `tick` | tyres |
| Side slip (slip angle as sideways over forward speed) | same | `wheel.gd` `tick` | tyres |
| Grip curve: rises to a peak at 0.12 slip, falls to 0.8 when sliding | same; one curve on every shipped body | `GroundDriveSpec.grip_curve`, `VehicleSpec.sample_curve` | tyres |
| Combined slip and the friction ellipse (braking or driving costs side grip) | same | `RayWheel.combined_slip_force`, `RayWheel.friction_ellipse` | tyres |
| Load sensitivity (grip per newton falls as load rises) | car, truck, tractor, trailers (0 on the plane) | `RayWheel.load_scaled_mu`, `GroundDriveSpec.load_sensitivity` | tyres |
| Cornering stiffness against load (where the side force peaks) | cars, vans, Kenney trucks, tractor (off on the semis) | `RayWheel.cornering_load_shape`, `RayWheel.lateral_peak_slip` | tyres |
| Twin rear tyres (half load each) | heavy vans | `GroundDriveSpec.rear_twin_tyres` | tyres |
| Static grip at rest (the contact patch spring) | every wheeled body | `RayWheel.stick_step` and neighbours | tyres |
| Wheel spin from drive, brake and road torque (semi-implicit step) | every wheeled body | `RayWheel._integrate_spin`, `RayWheel.settle_spin` | tyres (briefly), forces |
| Wheel radius per axle | every wheeled body | `GroundDriveSpec.axle_radius` | tyres |
| Surfaces (grip and added drag per painted ground) | every wheeled body | `src/levels/base/surface.gd`, `HeightmapTerrain.grip_at` / `drag_at` | surfaces |
| Tyre classes (all-season, summer, winter, studded, mud, M+S drive, lug, slick, trailer) | car, truck, tractor, trailers | `src/vehicles/base/tyre_class.gd`, `src/vehicles/tyres/` | surfaces |
| Rolling resistance (tyre's own plus the ground's) | every wheeled body | `RayWheel.surface_drag_force`, `GroundDriveSpec.rolling_resistance` | resistance, surfaces |

## Steering

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| Steering rate (how fast the wheels reach the request) | every steered family; also slews the boat's rudder and the plane's and drone's yaw | `VehicleSpec.steer_speed`, `base_vehicle.gd` `_physics_process` | steering |
| Keyboard steering easing (slower at speed) | local keys only | `src/input/key_shaper.gd` | steering, controls |
| Lock and its speed taper | car, truck, tractor | `WheelDrive.steer_lock_deg` | steering |
| Bicycle (mean) angle and turn radius | car, truck, tractor | `WheelDrive.mean_steer_angle` | steering |
| Ackermann split (inner wheel turns more) | car, truck, tractor (every one ships full Ackermann) | `WheelDrive.ackermann_angle` | steering |
| Parallel steer switch (LAB ▸ STEERING) | car, truck, tractor | `WheelDrive.ackermann_fraction` | steering |
| Roll steer (body roll turns the wheels a little) | cars, vans, trucks, semis (0 on racers and tractor) | `RayWheel.roll_steer` | steering |
| Compliance steer (side force bends the rear a little) | the front-drive saloons' twist beam only | `RayWheel.compliance_steer` | steering |
| Auto-steer from a curvature command | tractor | `WheelDrive.steer_angle_from_curvature`, `guidance_steer_unit` | steering |
| Articulated (frame) steering | not modelled: every wheeled vehicle steers its front wheels | none | steering, simplifications |

## The body on its wheels

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| Springs and dampers per axle, sized to a ride frequency | cars, vans; trucks hand-tuned; tractor's tyres are its suspension | `GroundDriveSpec`, `RayWheel.tick` | suspension |
| Anti-roll bars | most road bodies, every trailer axle | `RayWheel.bar_force`, `latch_bar` | suspension |
| Anti-dive and anti-squat (link geometry) | cars, vans; anti-squat only on trucks | `GroundDriveSpec.anti_dive_slope`, `anti_squat_slope` | suspension |
| Swinging front axle (beam on a pivot) | tractor | `GroundDriveSpec.front_axle_swing_deg`, `RayWheel.swing_step` | suspension |
| Body inertia (yaw declared, roll and pitch from the shapes) | every wheeled body | `VehicleMath`, `yaw_dynamic_index` | weight-transfer |
| Weight transfer (braking, accelerating, cornering) | every wheeled body | emergent from the suspension forces | weight-transfer |
| Understeer and oversteer balance | every wheeled body | `src/vehicles/base/balance_model.gd` (prediction), the tyres (behaviour) | weight-transfer |
| Rollover and wheel lift; overturn detection | every wheeled body | emergent; `BaseVehicle.is_overturned` | weight-transfer |

## Engine, coupling and gearbox

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| Torque curve and the crank as a spinning mass | car, truck, tractor (the boat, plane, drone and train keep a simpler rigid crank) | `src/vehicles/base/drivetrain.gd` | engine |
| Idle control, rev limiter | car, truck, tractor, boat, plane | `Drivetrain` | engine |
| Engine friction and engine braking (motoring) | car, truck, tractor | `Drivetrain.motoring_torque` | engine |
| Pedal maps: petrol torque request, linear diesel, all-speed governor | petrol cars; diesel vans and trucks; tractor | `src/vehicles/base/pedal_map.gd` | engine |
| Road-speed governor | vans, trucks, semis | `VehicleSpec.speed_limit_kmh`, `Drivetrain` | engine |
| Hand throttle | tractor | `PedalMap.demand` | engine, implements |
| Stall | not modelled as a game event: the controller opens the clutch first (see open questions) | `drivetrain.gd` header | engine |
| Friction clutch, launch slip | racers, semis (AMT), tractor (powershift) | `Drivetrain.coupling_step` | coupling |
| Torque converter, creep, lock-up | cars, vans, garbage truck, fire truck | `src/vehicles/base/torque_converter.gd` | coupling |
| Gear byte, P/R/N/D, automatic or manual | car, truck, tractor, plane, train (reverser) | `Drivetrain`, `InputRouter.arbitrate_bridge` | gearbox |
| Shift policy (shift points, kickdown, skip shifts, grade logic, start gear) | car, truck, tractor | `src/vehicles/base/shift_policy.gd` | gearbox |
| Shift handover (clutch-to-clutch, AMT cut, powershift, sequential cut) | car, truck, tractor | `Drivetrain.handover_rate`, `handover_fuel` | gearbox |
| Continuously variable transmission | tractor-cvt | `Drivetrain.cvt_ratio_step`, `_solve_cvt` | gearbox |
| Park pawl | cars, vans, tractor powershift | `WheelDrive.pawl_torque` | holding, gearbox |

## Differentials and four-wheel drive

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| Open differential (and one-wheel peel) | most bodies | `src/vehicles/base/differential.gd` | differentials |
| Limited-slip and Torsen-type diffs | `race`, `race-future`, `hatchback-sports`; centre on `suv`, `suv-luxury`, `race-future` | `Differential.bias_capacity` | differentials |
| Rear diff lock | tractor (also LAB ▸ DIFFERENTIALS on any driven axle) | `WheelDrive._couple_differentials` | differentials |
| Front-wheel drive engagement (MFWD) | tractor | `GroundDriveSpec.front_axle_engageable` | differentials |

## Brakes and driver aids

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| Brake hardware per body, front/rear split | every wheeled body | `GroundDriveSpec.brake_torque`, `brake_bias_front` | brakes |
| Brake sizing checks | every wheeled body | `src/vehicles/base/brake_sizing.gd` | brakes |
| Pedal feel anchored per body | every wheeled body | `WheelDrive.brake_application` | brakes |
| Handbrake (rear lock, drift, J-turn) | car, truck, tractor | `GroundDriveSpec.handbrake_torque` | brakes |
| Brake heat and fade | every wheeled body (trailers heat unpublished) | `src/vehicles/base/brake_thermal.gd` | brakes |
| Retarder | trucks, semis | `Drivetrain.retarder_rating`, `GroundDriveSpec.retarder_equipped` | brakes |
| Air reservoirs and spring brakes | trucks, semis | `src/vehicles/truck/truck_telemetry.gd`, `WheelDrive.spring_brake` | brakes, aux |
| ABS (ideal: holds the slip at the grip peak) | every road body but the racers; trailers | `RayWheel.ABS_SLIP`, `WheelDrive.anti_lock_on` | driver-aids |
| Traction control / ASR | cars but `race-future`; trucks, semis | `RayWheel.TCS_SLIP`, `GroundDriveSpec.tcs_equipped` | driver-aids |
| Stability control (yaw) | every road body with ABS | `src/vehicles/base/stability_control.gd` | driver-aids |
| Roll stability (rig and trailer) | semis and their semi-trailers | `StabilityControl.trailer_roll_step` | driver-aids, towing |
| Dashboard lamps for the aids (ESC, TC, ABS OFF, trailer ABS, VDC) | as fitted | `src/ui/dashboard.gd` | driver-aids |
| Hill-start assist | every ABS body | `src/vehicles/base/hill_hold.gd` | holding |
| Tractor powershift hill hold | tractor-kenney | `HillHold.Kind` STANDSTILL | holding |
| Auto hold (setting) | wheel-driving bodies, keys and touch only | `InputRouter.auto_hold` | holding |
| Active standstill | tractor-cvt | `Drivetrain.standstill_hold` | holding |
| Cruise control | not modelled on any road vehicle (the word appears only in measure tools and the plane's notes) | none | simplifications |

## Resistance and air

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| Aerodynamic drag and side force against the level's wind | car, truck, tractor, trailers | `VehicleMath.air_force` | resistance |
| Downforce | the two racers | `VehicleMath.aero_downforce` | resistance |
| Crosswind | car, truck, tractor | `WindField.at`, `VehicleMath.air_force` | resistance, conditions |

## Towing and implements

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| Tow host, coupling profiles (fifth wheel, drawbar) | semis; tractor | `src/vehicles/base/tow_host.gd`, `coupling_profile.gd`, `src/vehicles/truck/fifth_wheel.gd`, `src/vehicles/tractor/drawbar.gd` | towing |
| Towed body on its own wheels, articulation, jackknife stop | semi-trailers, farm tipper | `src/vehicles/base/towed_body.gd`, `articulation.gd` | towing |
| Trailer brakes (demand, lag, own ABS, spring brakes) | semi-trailers, farm tipper | `TowedBody` | towing |
| Trailer bus (ISO 11992) and its absence (J2497) | `semi` has it, `semi-conventional` does not | `semi.gd` | towing |
| Trailer loads: tipper body, tanker surge | tipper and tanker trailers | `src/vehicles/truck/trailers/` | towing |
| Three-point hitch and its four-bar linkage | tractor | `three_point_hitch.gd`, `hitch_linkage.gd` | implements |
| Draft force in soil | tractor with plough or harrow | `TractorVehicle._apply_draft`, `ImplementBase.draft_rating` | implements |
| PTO as engine load | tractor; garbage truck body pump | `Drivetrain.accessory_torque`, `src/vehicles/truck/refuse_body.gd` | implements, truck |
| Hydraulic remote (SCV) | tractor | `ThreePointHitch.set_scv`, `Drawbar.set_scv` | implements |
| Implement weight on the axles | tractor | `TractorVehicle._apply_implement_mass` | implements |
| ISOBUS implement claim | tractor | `src/vehicles/tractor/implement_base.gd` | implements |
| Refuse body over a gateway (CANopen) | garbage truck | `refuse_body.gd` | truck |

## Water

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| Water surface (flat height; waves are drawn only) and drown respawn | every level with sea | `src/water/water_surface.gd` | floating |
| Buoyancy probes | boat | `src/vehicles/boat/boat.gd` | floating |
| Propeller thrust, rudder authority, prop wash | boat | `boat.gd` | floating |
| Hull drag through the water, windage above it | boat | `boat.gd` | floating |
| Trim | boat | `boat.gd` | floating |
| Sail (lift and drag polar, sheet) | `boat-sail-a` | `src/vehicles/boat/boat_sail.gd` | floating |
| Autopilot (heading hold) | boat | `src/vehicles/boat/boat_autopilot.gd` | floating |
| Depth under the hull, aground | boat | `BoatTelemetry`, `BoatVehicle.aground_now` | floating |
| Tide (current) | boat | `src/levels/base/current_field.gd` | conditions |

## Flight

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| Rotor thrust, motor spool, quad-X mixer, yaw from prop torque | drone | `src/vehicles/drone/drone_propulsion.gd`, `drone_motors.gd` | drone-flight |
| Arming and pre-arm checks | drone | `drone_arming.gd` | drone-flight |
| Flight modes, geofence, return to launch, failsafes | drone | `drone_modes.gd` | drone-flight |
| Battery pack (voltage sag, charge, temperature) | drone | `drone_power.gd`, `drone_pack.gd` | drone-flight |
| Sensors: satellites, fix, height above ground, barometer, air data | drone | `drone_sensors.gd`, `drone_air_data.gd` | drone-flight |
| Bus nodes and node failure | drone | `drone_bus.gd` | drone-flight |
| Cargo hook and gimbal | drone (`drone-mk2` draws them) | `drone_payload.gd`, `drone_hook.gd`, `drone_gimbal.gd` | drone-flight |
| Lift against airspeed and angle of attack, stall fade | plane | `src/vehicles/plane/plane.gd` | plane-flight |
| Prop thrust with spool lag, reverse thrust | plane | `plane.gd` | plane-flight |
| Body-frame drag, weathervane, flaps | plane | `plane.gd` | plane-flight |
| Controls: steer banks and yaws, elevator pitches, authority scales with airspeed | plane | `plane.gd` | plane-flight |
| Ground roll on three wheels | plane | `plane_spec.tres`, `RayWheel` | plane-flight |

## Rail

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| Consist on a spline: point masses and spring couplers | train | `src/vehicles/train/train_sim.gd` | rail |
| Tractive effort (constant, then power-limited) | train | `TrainSim` | rail |
| Running resistance (Davis terms) and grade | train | `TrainSim` | rail |
| Brake pipe, motor current, catenary voltage | train | `src/vehicles/train/train.gd` | rail, aux |
| Reverser, pantograph, doors | train | `train.gd` | rail |

## Aux models, position and conditions

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| Fuel burn from the crank, game-scale tank | car, truck, tractor (boat and plane: a throttle model) | `VehicleTelemetry.fuel_rate_lph` | aux |
| Coolant temperature | car, truck, tractor, boat, plane | `VehicleTelemetry.coolant_target` | aux |
| Battery voltage and alternator | every family; the drone has its own pack | `VehicleTelemetry.battery_volts` | aux |
| Engine load | tractor, truck | `VehicleTelemetry.engine_load_pct` | engine, aux |
| Boat oil pressure, tanks | boat | `src/vehicles/boat/boat_telemetry.gd` | aux |
| GPS from world position, heading | every family | `VehicleTelemetry.gps_lat`, `gps_lon`, `heading_from_forward` | position |
| Odometer and hour meter | every family (hours published on truck, tractor, boat) | `VehicleTelemetry.odo_step`, `hours_step` | position |
| Acceleration, yaw rate, impact | every family | `BaseVehicle._update_telemetry` | position |
| Axle load read off the springs | truck, tractor | `VehicleTelemetry.axle_load_kg` | truck, implements |
| Wind field with gusts | every family but the train | `src/levels/base/wind_field.gd` | conditions |
| CONDITIONS presets (wind, current, direction, time of day) | session-wide | `src/levels/base/world_conditions.gd` | conditions |
| Rain or weather | not modelled; a painted "Wet" ground exists | `Surface` | surfaces, simplifications |

## Input

| System | Vehicles | Code | Page |
| --- | --- | --- | --- |
| One input per tick from keyboard, touch, gamepad or sloppyCAN | every family | `src/input/input_router.gd`, `vehicle_input.gd` | controls |
| Key easing (KEY RESPONSE) | local keys | `src/input/key_shaper.gd` | controls |
| Ignition gates the throttle; brake then reverse at a stop | every family | `InputRouter` | controls |
| LAB switches (ABS off, diffs, parallel steer) | wheeled bodies with the hardware | `InputRouter.lab_raw` | controls, and each system's page |
| Lamps mirrored from the bridge, horn | every family | `src/vehicles/base/lamp_set.gd`, `horn.gd` | controls |
