[AI-GENERATED CONTENT AWAITING HUMAN REVIEW]

# How the simulation works

<p class="lead">This page explains how the simulator computes what the other pages teach, and lists
every parameter it uses, with where each is set.</p>

## Sixty steps a second

The physics runs 60 times a second, with a gravity of 9.8 m/s². At each step:
<!-- project.godot physics/3d/default_gravity, the engine default; BrakeSizing.G -->

- **Each wheel finds the ground** by sweeping the shape of its tyre down through its suspension
  travel. Where the tyre touches, the simulator works out how hard the tyre is pressed onto the
  ground, how fast the ground passes under it, and how fast the tyre itself is turning.
- **Each spring and damper pushes the body up** at its corner. A suspension can only push, never
  pull. Weight transfer and rollover are not calculated separately: they result from these forces.
- **Each tyre makes a force.** The slip along the wheel and across it are added into one combined
  slip, the grip curve is read once for it, and the force points along the direction in which the
  patch slides.
- **The engine, the coupling and the wheels are solved together**: the engine's speed, the wheels'
  speed and the torque passed between them.
<!-- wheel.gd header; RayWheel.combined_slip_force; src/vehicles/CLAUDE.md: the physics runs at 60 Hz; drivetrain.gd -->

## Where a parameter is set

Each section below matches one page of the guide, and sorts that page's parameters by where they
are set:

- **Simulation-wide**: one value in the code, the same for every vehicle.
- **Per vehicle**: each vehicle's own settings (its spec), named in backticks. A vehicle's tyre
  settings describe the tyres it is built with.
- **Per tyre class**: the tread fitted to a vehicle (all-season, winter, mud, etc.), as factors on
  that vehicle's own tyre settings.
- **Per surface**: the kind of ground under a tyre, the same on every level.
- **Per implement**: each of the tractor's tools (the plough, the harrow, the mower, the spreader).
- **Per level**: what the level's author chooses, such as the wind or where each surface is.

## Tyres and grip

Per surface (the same on every level):

- **Grip**: how well the all-season tyre grips each surface, against dry asphalt (asphalt 1, ice
  0.12; the full list is in [Ground and tyre types](#ground-and-tyre-types)).

Per vehicle:

- **Peak grip along and across the wheel** (`mu_long`, `mu_lat`): the tyres' μ, the height of the
  grip curve's peak on dry asphalt. The cars have about 1 along the wheel and a little under 1 sideways, the semis
  about 0.8, and the racing cars about 1.3.
  <!-- sedan_spec.tres mu_long 1.05, mu_lat 0.97; semi_spec.tres mu_long 0.8; race mu_long 1.35, race-future 1.25 -->
- **Wheel radius and tread width** (`wheel_radius`, `tyre_half_width`, and their `_rear`
  versions): the size of the tyre, which sets the shape that finds the ground.

Per tyre class:

- **Dry grip** (`dry`): the class's grip on dry asphalt against the all-season tyre's.

## Slip and the grip curve

Simulation-wide:

- **Low-speed floor** (`LOW_SPEED_FLOOR`): below about 5 km/h, the slip ratio is divided by this
  speed instead of the road speed, so it does not jump to huge numbers as the vehicle stops. A
  heavily loaded drive wheel (such as a semi's, under the fifth wheel) can use a higher floor.
  <!-- wheel.gd LOW_SPEED_FLOOR 1.5 m/s (5.4 km/h); RayWheel.slip_floor_for: "a heavy corner on a light cap mass (a drive axle under a fifth wheel)" -->

Per vehicle:

- **Grip curve** (`grip_curve`): grip against combined slip. Every vehicle has the same one: it
  peaks at a slip of 0.12, then falls to 0.8 of its peak.
  <!-- GroundDriveSpec.grip_curve, the same on every shipped spec: (0, 0), (0.12, 1), (0.4, 0.9), (1, 0.8) -->
- **Rear side grip** (`rear_lat_grip`): the rear tyres' side grip as a multiple of the front's,
  for wider rear tyres (the `suv` and the racing cars).
  <!-- suv_spec.tres 1.08; race_spec.tres, race-future_spec.tres 1.15; 1.0 elsewhere -->
- **Load sensitivity** (`load_sensitivity`): the share of μ a tyre loses each time its load
  doubles (a tenth on the cars, a little less on the trucks and trailers, a little more on the
  tractors).
  <!-- GroundDriveSpec.load_sensitivity: car 0.10, truck/van/trailers 0.08, tractor 0.12 -->
- **Where the sideways peak sits** (`cornering_peak_load`): how much a heavier load moves the
  sideways peak to a larger slip angle. It moves only the slip angle at which the peak comes, never
  the peak's height. Off on the `suv`, the semis and the trailers.
  <!-- GroundDriveSpec.cornering_peak_load; sedan_spec.tres 2.56; 0 (the default) on suv_spec.tres (gen_kenney_vehicles.gd sets 0.0), semi_spec.tres, conventional_spec.tres and every trailer spec -->
- **Twin rear tyres** (`rear_twin_tyres`): each tyre of a pair takes half its corner's load (the
  `delivery`, `delivery-flat` and `ambulance`).
- **The rear tyres' rated load** (`rear_tyre_rating`): a bigger rear tyre's rating against the
  front's, for the tractors' big rear tyres.
  <!-- tractor-kenney_spec.tres, tractor-cvt_spec.tres rear_tyre_rating 1.557 -->

## Ground and tyre types

Simulation-wide:

- **Paint reach** (`SURFACE_GRIP_REACH`): everything that is not painted terrain (roads, bridges,
  ramps, etc.) counts as dry asphalt, unless it is within about a metre of the paint below it.
  <!-- HeightmapTerrain.grip_at; wheel.gd SURFACE_GRIP_REACH 1.0 m -->

Per surface (the same on every level):

<details><summary>Surface list</summary>

| Surface | Grip of the all-season tyre, against dry asphalt | Added drag, share of the load |
| --- | --- | --- |
| Asphalt | 1 | 0 |
| Wet asphalt | 0.75 | 0 |
| Pad (airfield concrete) | 0.95 | 0 |
| Gravel | 0.71 | 0.01 |
| Dirt | 0.8 | 0.04 |
| Grass | 0.5 | 0.06 |
| Sand | 0.6 | 0.05 |
| Rock | 0.7 | 0.01 |
| Mud | 0.45 | 0.1 |
| Field | 0.5 | 0.06 |
| Snow | 0.34 | 0.02 |
| Ice | 0.12 | 0 |
<!-- surface.gd REF_GRIP, DRAG -->

</details>

Per vehicle:

- **Stock tyre class and size** (`tyre`, `tyre_fit`): the class the vehicle is built with, and the
  tyre size that decides which classes it may fit.

Per tyre class:

- **Grip per surface** (`surface_grip`): the class's grip on each surface against the all-season
  tyre's.
- **Rolling resistance factor** (`crr_factor`): the class's rolling resistance against the
  all-season tyre's.
- **Sizes** (`fits`): the tyre sizes the class is made in.
<!-- TyreClass; src/vehicles/tyres/*.tres -->

Per level:

- **Where each surface is**: the level's author paints the terrain with up to eight colours, and
  the level says which surface each colour is. Where two colours blend, their numbers blend in the
  same proportion. In Car Arena, the wet bend is painted wet, but looks like the rest of the road.
  <!-- HeightmapTerrain.grip_at; tools/gen_car_arena.gd -->

## Steering and Ackermann

Per vehicle:

- **Steering lock** (`max_steer_deg`): the bicycle angle at full lock, standing still (38° on the
  `sedan`).
  <!-- sedan_spec.tres max_steer_deg 38 -->
- **Steering rate** (`steer_speed`): how fast the wheels reach full lock, about a seventh of a
  second for a car, half a second for a truck, and more than a second for a tractor.
  <!-- VehicleSpec.steer_speed: CAR_BASE 7.0, TRUCK_BASE 2.0, TRACTOR_BASE 0.75 -->
- **Steering taper** (`min_steer_frac`, `steer_falloff_speed`): the share of the lock kept at
  speed, and the speed by which the lock has narrowed to it.
- **Ackermann** (`ackermann`): how far the split between the two front wheels goes towards full
  Ackermann. Every vehicle has full Ackermann, and the lock limits the bicycle angle, so the inner
  wheel turns past it (on the `sedan`, to about 49°).
  <!-- GroundDriveSpec.ackermann 1.0 on every shipped body; WheelDrive.ackermann_angle(38 deg) = 48.6 deg -->
- **Wheel positions** (`wheel_positions`): the wheelbase and the track, which set the turning
  circle.
- **Roll steer** (`roll_steer_front`, `roll_steer_rear`): how far each axle's wheels steer as the
  body leans.
- **Compliance steer** (`compliance_steer_rear`): how far the rear wheels steer under side force
  (the front-drive saloons only).

## Suspension

Per vehicle:

- **Travel** (`rest_length`): how far each wheel can drop below its hub (28 cm on the cars).
  <!-- CAR_BASE rest_length 0.28 -->
- **Springs** (`spring_rate`, `spring_rate_rear`): the cars' springs are sized from a ride
  frequency (about 1.4 Hz for a saloon, 1.3 for a big van, 1.6 for the racing cars), so they all
  stand with their springs squeezed by a little under half of their travel. The trucks' springs
  are chosen by hand for their loads.
  <!-- CAR_BASE ride_hz 1.39, VAN_BASE 1.28, race 1.6 -->
- **Dampers** (`damper_bump`, `damper_rebound`, and their `_rear` versions): about a third of
  critical damping in bump, and half in rebound, on the cars.
  <!-- zeta_bump 0.36, zeta_rebound 0.48 -->
- **Anti-roll bars** (`anti_roll_rate`, `anti_roll_rate_rear`): a saloon's front bar is about four
  times as stiff as its rear one.
  <!-- anti_roll_rate 16000 / 4000 -->
- **Anti-dive and anti-squat** (`anti_dive_slope`, `anti_squat_slope`): the share of the dive and
  the squat that the links resist (about 40 % and 50 % on the cars).
  <!-- anti_dive 0.4, anti_squat 0.5 -->
- **Swinging front axle** (`front_axle_swing_deg`): how far a tractor's front axle can swing each
  way (10°).
  <!-- TRACTOR_BASE front_axle_swing_deg 10.0 -->
- **Push ceiling** (`max_suspension_force`): the most one corner can push.

## Weight transfer and rollover

Simulation-wide:

- **Overturned**: a vehicle tipped past 70° for one and a half seconds, and almost stopped, is
  overturned, and the simulator offers a respawn. It does not put it back on its wheels by itself.
  A vehicle that falls more than 20 m below sea level is respawned.
  <!-- base_vehicle.gd OVERTURNED_DEG 70, OVERTURNED_S 1.5, OVERTURNED_MAX_SPEED; FALL_RESPAWN_Y -20 -->

Per vehicle:

- **Mass and centre of mass** (`mass`, `center_of_mass`): how much weight there is to move, and
  how high it sits.
- **Turning inertia** (`yaw_dynamic_index`): the vehicle's resistance to turning, from
  measurements of real vehicles. Its resistance to leaning and pitching comes from its shape.
  <!-- docs/handling.md Inertia -->
- **Track and wheelbase** (`wheel_positions`), **springs and anti-roll bars**: see
  [Steering and Ackermann](#steering-and-ackermann) and [Suspension](#suspension).

## Understeer and oversteer

Per vehicle:

- **The front and rear side grip** (`mu_lat`, `rear_lat_grip`), **load sensitivity** and the
  **anti-roll bars' split**: these set which end lets go first
  ([Slip and the grip curve](#slip-and-the-grip-curve), [Suspension](#suspension)).
  <!-- GroundDriveSpec.rear_lat_grip: "Understeer is the bar split and the tyre's load laws" -->
- **Roll steer and compliance steer**: see [Steering and Ackermann](#steering-and-ackermann).
- **Downforce balance** (`downforce_front`): the share of the racing cars' downforce on the front
  axle.

## Air and rolling resistance

Simulation-wide:

- **Air density** (`AIR_DENSITY`): 1.225 kg/m³, sea-level air.
  <!-- VehicleMath.AIR_DENSITY 1.225 -->

Per vehicle:

- **Drag area** (`drag_area`): drag comes from the speed through the air and this area (0.65 m²
  for the `sedan`). A trailer has a small drag area, because it is in the truck's wake.
  <!-- VehicleMath.air_force; sedan drag_area 0.65 -->
- **Side area** (`side_area`): the same for wind from the side (4.16 m² for the `sedan`). A trailer
  has its full side area.
  <!-- sedan side_area 4.16 -->
- **Where the air pushes** (`aero_centre`): the point where drag acts.
- **Downforce area** (`downforce_area`): the racing cars' wings press down with about half their
  weight at 200 km/h. For example, on the `race`: ½ × 1.225 × 55.6² × 2.24 = about 4,200 N,
  against a weight of 900 × 9.8 = about 8,800 N. The push goes through the springs, so it adds
  grip only by pressing the tyres down harder.
  <!-- VehicleMath.aero_downforce; race_spec.tres, race-future_spec.tres downforce_area 2.24; race mass 900, race-future 850 -->
- **Rolling resistance** (`rolling_resistance`): about 1 % of the load for the cars, less for the
  trucks, and about 2 % for the tractors.
  <!-- sedan_spec.tres rolling_resistance 0.012; semi_spec.tres 0.007; tractor 0.02 -->

Per tyre class and per surface:

- **Rolling resistance factor and soil drag**: see [Ground and tyre types](#ground-and-tyre-types).

## Wind and conditions

Simulation-wide:

- **Gust pattern** (`OCTAVES`, `BASE_PERIOD`): three waves of wind laid over each other, the
  slowest over about seven seconds.
  <!-- WindField OCTAVES 3, BASE_PERIOD 7 s -->

Per level:

- **Wind** (`speed`, `gust_speed`, `direction_deg`, `gust_seed`): the steady wind, the most a gust
  adds to it, the direction it blows towards, and the seed of its gusts. Two levels have wind of
  their own: Level 6 - Skyport (about 5 m/s, with gusts up to 3 more) and Open Sea (about 6 m/s,
  with gusts up to 2 more). The others are calm unless SANDBOX sets a wind.
  <!-- WindField; level_6_wind.tres speed 5, gust_speed 3; open_sea_wind.tres speed 6, gust_speed 2 -->

## The engine

Simulation-wide:

- **Road-speed governor band** (`GOVERNOR_BAND`): the governor fades the fuel out over the last
  few km/h before the limit.
  <!-- Drivetrain.GOVERNOR_BAND -->

Per vehicle:

- **Torque curve** (`torque_curve`), **idle and redline** (`idle_rpm`, `redline_rpm`).
- **Crank inertia** (`engine_inertia`): the crank is a spinning mass.
- **Engine friction and engine braking** (`engine_friction_frac`, `engine_brake_frac`): a torque
  that grows with rpm (on the `sedan`, about a fourteenth of the best torque at idle, and a
  quarter at the redline).
  <!-- sedan engine_friction_frac 0.07, engine_brake_frac 0.25 -->
- **Free-rev limit** (`free_rev_limit_rpm`): the `sedan` is limited to about 4000 rpm in neutral or
  park.
  <!-- free_rev_limit_rpm 4000 -->
- **Pedal map** (`pedal_map`): how the pedal turns into fuel (a straight line, a map measured on a
  real petrol engine, or, on the tractors, a governor for which the pedal sets an engine speed).
- **Speed limit** (`speed_limit_kmh`): the road-speed governor, where there is one (40 km/h on
  the tractor).
  <!-- tractor-kenney_spec.tres speed_limit_kmh 40 -->
- **Governor droop** (`governor_droop`): the tractor's governor droops by about 7 % from no load
  to full load.
  <!-- tractor governor_droop 0.07 -->

## Clutch and torque converter

Simulation-wide:

- **Launch**: a controller works every clutch. It launches near idle with a light pedal and
  higher with a full pedal.
  <!-- Drivetrain.launch_target_rpm -->

Per vehicle:

- **Coupling** (`coupling`): a torque converter or a friction clutch.
- **Clutch reserve** (`clutch_reserve`): a locked clutch carries one and a half to two times the
  engine's best torque.
  <!-- VehicleSpec.clutch_reserve 1.5 / 2.0 -->
- **Launch speed** (`launch_rpm_over_idle`): the semis always launch at about 900 rpm.
  <!-- semi launch_rpm_over_idle 300 -->
- **Converter stall** (`converter_stall_ratio`): the converters stall at about 2400 rpm on the
  cars and 1250 on the rigid trucks. Their creep holds most cars on slopes of about 5 to 8 %.
  <!-- Drivetrain.stall_rpm; docs/drivetrain.md Creep -->
- **Lock-up gear** (`lockup_gear`): the converter locks up from first gear on the cars, and from
  second on the trucks.
  <!-- lockup_gear 1 / 2 -->
- **Launch engagement** (`launch_engage_s`): how long a powershift's start-up clutch takes to reach
  its full strength when pulling away.

## Gearbox and shifting

Per vehicle:

- **Ratios** (`gear_ratios`, `reverse_ratio`, `final_drive`) and **efficiency** (`efficiency`,
  0.9 on every vehicle).
  <!-- VehicleSpec.efficiency 0.9 on every shipped body -->
- **Shift points** (`shift_up_rpm`, `shift_down_rpm`, `shift_up_light_rpm`,
  `shift_down_light_rpm`): with a light pedal, the `sedan` changes up at about 1800 to 2000 rpm,
  and with a full pedal at about 5900.
  <!-- CAR_BASE light pair 1800 / 1150; shift_up_rpm 5900 -->
- **Kickdown** (`kickdown_pedal`): past four fifths of the pedal on the automatics, and past almost
  all of it on the semis.
  <!-- VehicleSpec.kickdown_pedal -->
- **Start gear** (`start_gear_max`): the highest gear a pull-away may start in. The gearbox picks
  the start gear from the weight and the slope, up to this. The `semi` with no trailer starts in
  sixth on the flat, and in third with the 24-tonne box trailer.
  <!-- docs/drivetrain.md § The start gear: "On the flat the bobtail semi starts in D6 and with the 24 t box in D3" -->
- **Shift timing** (`shift_cut_s`, `shift_torque_ramp_s`, `shift_handover_s`): how long a change
  cuts the fuel and brings it back, and how long an upshift's clutch takes to hand the drive over.
- **Least time in gear** (`shift_dwell_s`): before a change asked for by the pedal, or a kickdown.
- **Skip shifts** (`skip_shifts`): an upshift can jump straight to a higher gear, as the semis' and
  the powershift tractor's gearboxes do.
  <!-- skip_shifts true on semi_spec.tres, conventional_spec.tres, tractor-kenney_spec.tres -->

## Kinds of gearbox

Per vehicle:

- **Which coupling** (`coupling`): a torque converter (the automatics) or a friction clutch (the
  sequential, automated manual and powershift gearboxes). The shift settings of
  [Gearbox and shifting](#gearbox-and-shifting) make up the rest of each kind.
- **The CVT** (`cvt_range_tops`, `cvt_accel_ms2`, `cvt_max_axle_torque`): the top ratio of each of
  its ranges, how fast it moves towards the speed the pedal asks for, and the most torque it sends
  to the axle.

## Differentials and four-wheel drive

Per vehicle:

- **Driven axles** (`driven_front`, `driven_rear`, `front_axle_engageable`): which axles drive,
  and whether the front can be switched in (the tractors).
- **Differential bias** (`diff_bias_front`, `diff_bias_rear`): 1 for an open differential.
  The rear of the `race` and the `race-future`, and the front of the `hatchback-sports`, have
  limited-slip differentials.
- **Centre differential** (`centre_diff_bias`, `centre_diff_rigid`): the `suv`, `suv-luxury` and
  `race-future` have Torsen-type centre differentials. The tractors' axles are geared together.
- **Diff lock** (`rear_diff_lockable`): the tractors' rear differential can be locked.
<!-- diff_bias_front / diff_bias_rear, centre_diff_bias in each *_spec.tres -->

## Brakes

Simulation-wide:

- **Pedal shape** (`BRAKE_HALF_PEDAL_G`): on every vehicle, half the pedal asks for about half a g.
  <!-- WheelDrive.brake_application, BRAKE_HALF_PEDAL_G 0.5 -->
- **Fade curves**: drums fade from about 180 °C, pads on discs from 400, racing pads from 650, and
  wet discs from 90 (read off their oil).
  <!-- BrakeThermal PAD, RACE, DRUM, WET -->

Per vehicle:

- **Brake torque** (`brake_torque`): each vehicle has the brakes of a real vehicle of its class,
  which are never made bigger for the simulation. Each can lock its wheels on dry asphalt.
  <!-- docs/vehicles.md Brake hardware; BrakeSizing -->
- **Front and rear split** (`brake_bias_front`): in proportion to each axle's grip in a hard stop.
  <!-- GroundDriveSpec.brake_bias_front -->
- **Brakes on the front axle** (`brake_engages_front_axle`): a tractor's foot brake engages its
  front axle, so that it brakes the front wheels through the drive shaft.
- **Handbrake** (`handbrake_torque`): each rear wheel has one brake torque, made of the foot
  brake's share and the handbrake's, with one temperature and one fade factor. At 480 °C, the
  `sedan`'s handbrake keeps 86 % of its force and still locks the rear wheels, while the
  `garbage-truck`'s keeps 50 %: it no longer locks them, and parks on about 24 % instead of 32 %.
  <!-- WheelDrive.tick: parking_torque(...) * w.brake_fade(); BrakeSizing.park_grade, run 2026-11-17 -->
- **Brake heat** (`brake_heat_capacity`, `brake_cooling_g0`, `brake_cooling_g1`,
  `brake_emissivity`, `brake_radiating_area`, `brake_fade_curve`, and their `_rear` versions):
  how much heat each brake holds, how fast the air and radiation take it away, and which fade
  curve it follows.
- **Retarder** (`retarder_equipped`, `retarder_rating_nm`): it slows the garbage truck by about a
  tenth of a g, the laden fire truck by about 0.06 g, and a semi with no trailer by about 0.15 g
  (much less with one). It is capped so that it cannot lock a wheel.
  <!-- docs/truck.md Air, retarder, axle load: 0.84 m/s² garbage truck, 0.56 firetruck, 1.47 bobtail semis, 0.37 with the box; RETARDER_SLIP_TARGET -->

<details><summary>Brake list</summary>

| Class | Vehicles | Full brake, if the tyres had unlimited grip |
| --- | --- | --- |
| Saloon discs | `sedan`, `taxi`, `hatchback-sports` | 1.3 to 1.6 g |
| Performance | `sedan-sports`, `police` | 1.6 to 1.9 g |
| SUV and light commercial | `suv`, `suv-luxury`, `van`, the pickups | 1.4 to 2.6 g |
| Racing | `race`, `race-future` | 2.5 to 2.7 g |
| Heavy van | `delivery`, `delivery-flat`, `ambulance` | 1.2 to 1.5 g |
| Truck air brakes | `garbage-truck`, `firetruck`, the semis | about 2.2 g unladen, 1.5 g on the laden `firetruck` |
| Tractor wet discs | `tractor-kenney` | about 1.4 g |
<!-- docs/vehicles.md Brake hardware table: foot brake as g at the body's mass -->

</details>

## ABS, traction and stability control

Simulation-wide:

- **Target slip** (`ABS_SLIP`, `TCS_SLIP`): ABS and traction control hold each wheel at a slip of
  0.12, the grip curve's peak.
  <!-- wheel.gd ABS_SLIP, TCS_SLIP 0.12 -->
- **Stability control's limits** (`MIN_SPEED`, `ROLL_SHARE`): it does nothing below 20 km/h or in
  reverse, and roll stability steps in at 70 % of the lift point.
  <!-- StabilityControl MIN_SPEED, ROLL_SHARE 0.7 -->

Per vehicle:

- **Which aids are fitted** (`abs_equipped`, `tcs_equipped`, `esc_equipped`): ABS and stability
  control on every car, van and truck except the two racing cars; traction control on the same
  vehicles, plus the `race`. None on the tractors.
  <!-- abs_equipped, esc_equipped, tcs_equipped in each *_spec.tres -->
- **Stability control's reference** (`esc_reference_k`, `esc_laden_kg`, `esc_laden_k`): how the
  vehicle should turn, worked out in advance from its own steady handling, laden and unladen.
- **Roll stability** (`esc_roll_lift_g`, `trailer_roll_equipped`, `trailer_roll_lift_g`): the
  sideways acceleration at which each vehicle, and each semi-trailer, starts to lift a wheel. The
  semi-trailers have ABS and their own roll control.

## Holding still

Simulation-wide:

- **Grip at rest** (`STICK_DEFLECTION`, `STICK_SPEED`): the give of a still tyre is a spring of
  about 2 cm in each patch, which fades in below a slow walking pace.
  <!-- wheel.gd STICK_DEFLECTION 0.02 m, STICK_SPEED 0.5 m/s -->
- **Park pawl speed** (`PAWL_ENGAGE_SPEED`): the park pawl drops in below about walking pace.
  <!-- WheelDrive.PAWL_ENGAGE_SPEED 1 m/s -->

Per vehicle:

- **Hill-start assist** (`hill_hold`, `hill_hold_s`): which kind, and how long it lasts (up to
  about one second on a car and three on a truck). It counts a trailer's weight, and holds the
  trailer's brakes too. The tractors have a hill hold (powershift) or an active standstill (CVT).
  <!-- hill_hold_s; WheelDrive.towed_kg -->
- **Park pawl** (`park_pawl_torque`) and **handbrake** (`handbrake_torque`): what holds the
  vehicle when parked.

## Towing

Simulation-wide:

- **Fifth wheel** (`JACKKNIFE_MAX_DEG`): lets a trailer swing up to 75°, tip 15° and lean a degree or two, and carries
  about a quarter of its weight.
  <!-- fifth_wheel.gd; Articulation.JACKKNIFE_MAX_DEG 75 -->
- **Drawbar** (`SWING_MAX_DEG`, `PITCH_LIMIT_DEG`, `ROLL_LIMIT_DEG`): allows 57°, 20° and 25°, and carries about an eighth.
  <!-- drawbar.gd SWING_MAX_DEG 57, PITCH_LIMIT_DEG 20, ROLL_LIMIT_DEG 25; docs/tractor.md -->
- **Trailer brakes** (`BRAKE_APPLY_S`, `BRAKE_RELEASE_S`): about a third of a second to apply and
  half a second to release.
  <!-- TowedBody.BRAKE_APPLY_S 0.35, BRAKE_RELEASE_S 0.5 -->
- **Raised body** (`BODY_UP_CAP_KMH`): the truck is held to 5 km/h while a tipper's body is up.
  <!-- TowHost.BODY_UP_CAP_KMH 5 -->

Per vehicle:

- **Trailer link** (`trailer_bus_equipped`): whether the truck talks to its trailer.
- **Each trailer's own settings**: a trailer is a vehicle with its own mass, tyres and brakes.

## Implements and the PTO

Simulation-wide:

- **PTO speed** (`PTO_RATED_RPM`): the PTO reaches 540 or 1000 rpm at about 2040 rpm of the
  engine.
  <!-- PTO_RATED_RPM 2043 -->

Per implement:

- **Weight** (`MASS_KG`, `MASS_CENTRE`): a carried implement's weight joins the tractor's.
  <!-- TractorVehicle._apply_implement_mass -->
- **Working depth** (`SHARE_DEPTH_M`, `TINE_DEPTH_M`): the plough and the harrow work 25 and 10 cm
  deep.
  <!-- plough.gd SHARE_DEPTH_M 0.25; harrow.gd TINE_DEPTH_M 0.1 -->
- **Draft** (`RATED_DRAFT_N`, `DRAFT_SHAPE`): draft is a real force at the hitch.
  <!-- TractorVehicle._apply_draft -->
- **PTO power** (`PTO_RATED_KW`, `PTO_SHAPE`, `CUT_KW`): the PTO puts each tool's shaft power on
  the engine's crank as a load.
  <!-- Drivetrain.accessory_torque -->

Per vehicle:

- **Hitch speed** (`hitch_travel_time`): how long the hitch takes to rise or drop.
- **PTO mode speed** (`pto_mode_rpm`): the engine speed a road truck holds while its PTO works
  parked.

Per level:

- **Soil**: Level 1's field has sandy bands where the soil is half as heavy.

## Fuel, coolant, battery and air

Simulation-wide:

- **Engine efficiency** (`FUEL_INDICATED_EFFICIENCY`): the fuel burned is the torque the fuel
  adds (the engine's net torque plus its friction), times the engine's speed, divided by an
  efficiency: 0.41 for petrol and 0.45 for diesel, the same at every speed and load. For example,
  the `sedan` idles at about a third of a litre an hour, which is just its friction at idle.
  <!-- VehicleTelemetry.fuel_rate_lph, FUEL_INDICATED_EFFICIENCY [0.41, 0.45]; docs/drivetrain.md Fuel: the sedan idles at 0.34 L/h -->
- **Tank size** (`FUEL_TANK_FULL_LOAD_S`): each tank lasts 500 seconds (a little over eight
  minutes) at full fuel at the engine's rated speed, so the gauge visibly falls. The burn that
  drains it is the real one, and an empty tank leaves the engine running.
  <!-- VehicleTelemetry FUEL_TANK_FULL_LOAD_S 500 s, tank_litres; base_vehicle.gd: an empty tank does not stop the engine -->
- **Coolant** (`COOLANT_AMBIENT`, `COOLANT_OPERATING`, `COOLANT_HOT`, `COOLANT_RATE`): 20 °C with
  the engine off. Running, its target is 90 °C at no load and 108 °C at full fuel, in proportion to
  the fuel burned, and it moves towards that target by 2 °C a second.
  <!-- VehicleTelemetry COOLANT_AMBIENT 20, COOLANT_OPERATING 90, COOLANT_HOT 108, coolant_target; BaseVehicle COOLANT_RATE 2; heat_frac = fuel_rate / rated burn -->
- **Battery** (`BATTERY_RESTING`, `BATTERY_CHARGING`, `BATTERY_LAMP_DROOP`): 12.6 V with the
  engine off and 14.2 V running, less up to 0.6 V in proportion to the lamps lit, each counted by
  its bulb's power.
  <!-- VehicleTelemetry.battery_volts; BATTERY_LAMP_DROOP 0.6; LampSet.load_share, BULB_*_W -->
- **Air** (`AIR_PRESS_PRIMARY`, `AIR_PRESS_SECONDARY`): a full press of the brake pedal takes
  0.7 bar from the first tank and 0.55 from the second, and the compressor puts back about
  0.45 bar a second into each while the engine runs. Coupling a trailer takes about 3 bar from
  the first tank and 1.5 from the second over the 8 seconds it takes to fill the trailer's.
  <!-- TruckTelemetry AIR_PRESS_PRIMARY 0.70, AIR_PRESS_SECONDARY 0.55, AIR_CHARGE_RATE 0.45, TRAILER_CHARGE_S 8, TRAILER_AIR_DRAW 0.75 of AIR_DRAW_PRIMARY 1.10 / AIR_DRAW_SECONDARY 0.85 -->

Per vehicle:

- **Fuel** (`fuel_type`): what the engine burns, which sets its efficiency, and the fuel's energy
  and density.

## Position, heading and distance

Simulation-wide:

- **Map origin** (`GPS_ORIGIN_LAT`, `GPS_ORIGIN_LON`): the world's origin is pinned to a spot in
  Paris.
  <!-- VehicleTelemetry GPS_ORIGIN_LAT 48.8566, GPS_ORIGIN_LON 2.3522 -->
- **Impact threshold** (`IMPACT_THRESHOLD`): any jolt over 25 m/s² (about 2.5 g) counts as an
  impact. Its size is held and then shrinks by 40 m/s² each second (`IMPACT_DECAY`).
  <!-- BaseVehicle IMPACT_THRESHOLD 25 m/s², IMPACT_DECAY 40 -->

## Related

- [How the simulator is built](how-its-built.md): the code behind this.
- [What the simulator keeps simple](simplifications.md): the limits of these models.
