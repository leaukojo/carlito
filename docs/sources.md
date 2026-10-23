# Sources

The sourced figures behind the vehicle specs and the references they cite. Reference data, read
on demand: the tours and derivations are `docs/vehicles.md` (its header lists the rest).

## Sourced figures

Each figure is graded:
- **sourced**: a primary document, read;
- **secondary**: a search summary or forum quoting a primary, not opened;
- **estimate**: reasoned from the sourced ones.

The bracketed numbers, here and in the vehicle docs, are § Reference list.

*Crank inertia* (`engine_inertia`), measured at the crank. It includes the flywheel or flexplate
and, on a converter body, the impeller side:

| Class | Bodies | J (kg·m²) | Basis |
| --- | --- | --- | --- |
| Car petrol 1.2-2.0 L, converter | `CAR_BASE` | 0.20 | sourced anchor: a 2013 Malibu's 2.5 L I4 with its converter's impeller side measures 0.20 by spin-down (engine 0.161, converter 0.0585) [33], a larger engine than the class, so 0.20 sits at its top. A whole engine measures 0.149 at 1.0 L and 0.125 at 1.2 L, the crankshaft 0.014-0.015 of it [1]; a car converter's impeller is 0.092 [2]. Generic car engines at 0.35 [3] and a 2.5 L I4 at 0.373 [4, secondary] disagree with the measurement |
| Sports, converter | `sedan-sports`, `hatchback-sports` | 0.18 | estimate: a lighter rotating assembly, the same impeller |
| Race, sequential and clutch | `race`, `race-future` | 0.06 | estimate: a crankshaft alone is 0.014-0.027 [1], plus a light flywheel and a small multi-plate clutch |
| Van diesel 3.2 L, converter | `VAN_BASE` | 0.40 | estimate, band 0.35-0.45: twice a 2.5 L petrol I4's measured 0.20 with its impeller side (spin-down; engine 0.161, converter 0.0585) [33], for a five-cylinder diesel's heavier crank and flywheel. No 3-4 L diesel figure found |
| Medium diesel 6-9 L, Allison-class | `TRUCK_BASE` | 1.5 | sourced anchor: Volvo Penta TD640VE (5.48 L), total mass moment of inertia 1.50 [5]. A 7 L genset lists 2.60 [6, secondary] |
| Heavy diesel 11-13 L, AMT | both semis | 3.0 | estimate, between 1.50 at 5.5 L [5] and 4.20 for the 16.1 L TAD1641GE [7] |
| Tractor diesel 4.5-7 L, powershift | `TRACTOR_BASE` | 1.5 | sourced anchor: the same 5.5 L, 1.50 [5] |

*The gear-1 mass factor while locked* (computed; r = 0.36 m, the tractor's driven 0.66 m rear; G1
is first gear times the final drive, D3 on the tractor). It is `J G1²` over the body's `m r²`:

| Body | G1 | J G1² (kg·m²) | Driven wheels' own I | Body m r² | Added |
| --- | --- | --- | --- | --- | --- |
| `sedan` | 17.55 | 62 | 2.4 | 149 | +41 % |
| `race` | 13.44 | 11 | 2.4 | 117 | +9 % |
| `delivery` | 15.56 | 97 | 6.0 | 544 | +18 % |
| `garbage-truck` | 14.00 | 294 | 6.0 | 1037 | +28 % |
| `semi` + 24 t | 19.01 | 1084 | 6.0 | 4147 | +26 % |
| `tractor-kenney` | 39.32 | 2319 | 180 | 3049 | +76 % |

In top gear it is small (+1.7 % on the `sedan`). A slipping coupling decouples the crank. A real
vehicle has the same term, so a
body behind its reference is fixed from its own data (curve, gearing), never by shaving inertia.

*The converter:*
- **Stall torque ratio:** about 2.0 on cars, ~2.5 on 1990s four-speeds [8], with a typical model
  default of 2.23 [9]. Allison 3000 trucks: 1.98-2.20 [10, secondary]. It ships at 1.0
  (`docs/drivetrain.md` § Converter).
- **Coupling point:** at a speed ratio of ~0.9. The ratio is 1.07 at 0.87, 1.02 at 0.92 and 1.00
  at 0.94 [9].
- **Capacity:** K = speed / √torque. It is nearly flat to a speed ratio of 0.8 (12.3 to 14.6),
  then climbs: 16.3 at 0.87, 22.1 at 0.94, 50 at 0.97 [9]. The truck shape is assumed the same.
- **Overrun:** it runs on its own K curve [11]. No figure was found, so `OVERRUN_CAPACITY` 0.5 is
  an estimate.
- **Lock-up:**
  - 6+ speeds open the converter only for the launch [8]; 1st-range lock-up is an Allison option
    [14, secondary].
  - It releases as the throttle closes and on braking, so a locked engine cannot stall [12]. The
    ZF 8HP decouples at a standstill in D [13].
- **Stall speed:** typically 1800-2800 rpm [15]. An unverified AT545 owner report puts a truck at
  1300-1400 rpm [16], near the derived 1250 on the Kenney trucks.

*The friction clutch:*
- **Capacity:** about 1.5x the engine's peak on cars and 2x on trucks [17]; OE ratings carry a
  20 % margin [18]. A wet powershift pack takes the truck's 2.0 (estimate).
- **AMT launch:** a heavy truck's AMT holds the crank about 300 rpm over idle [19].
- **Powershift modulation:** a fill, then a pressure ramp [20]. No duration was found, so
  `launch_engage_s` 0.8 is an estimate.
- **Torque through a clutch-to-clutch shift:** a road box's TCU holds the engine's torque reduced
  through the inertia phase [44], or briefly cuts it there through the engine management, so the
  output does not rise on the crank's inertia [97]. A Deere powershift's controller requests an
  engine torque over the bus through the shift, held at a level such as 20 % over the present
  torque and cancelled after the swap [98]; no tractor source reducing it was found. The tractor's
  reduction is the road boxes' law (a COMPROMISE at `TRACTOR_BASE`).

*Idle and holds:*
- **Loaded idle:** the ECU adds air when a drive range is selected, so idle stays put. Without that
  signal it falls under 800 rpm and recovers [21]. Owners report 50-100 rpm dips [22, secondary].
- **Hill-start assist:** it holds about 1 s on a car (Honda) [23] and 3 s on a truck (Volvo VN)
  [24]. It releases once the driver asks to drive and the engine torque passes what holds the grade
  [23, 24, 25].
- **Tractor:** Valtra's HillHold holds a powershift tractor until the drive pedal is pressed [26].

*Engine friction:* `docs/drivetrain.md` § Motoring and friction. The diesels' is Volvo Penta friction power, [5] and [7]; the petrol's is EPA's measured Malibu motoring curve [91].

*The heavy vans' drivetrain* (`VAN_BASE`: `delivery`, `delivery-flat`, `ambulance`): a Ford
Transit 3.2 L five-cylinder diesel behind the 6R80 six-speed automatic, the class of a 4.7 t
Transit 350 HD. The ambulance is a van-based box ambulance on the same drivetrain.

| Figure | Value | Grade |
| --- | --- | --- |
| Engine, gearbox | 3.2 L five-cylinder diesel, every Transit engine behind the 6R80 [27] | sourced |
| Peak torque | 470 N·m [27]; held over 1750-2500 rpm [29], at least 90 % over 1500-2750 [30] | sourced; the band secondary |
| Rated power | 147 kW at 3000 rpm [29], which is 468 N·m: the plateau holds to rated speed | secondary; the N·m computed |
| Ford's "90 % from 1,700 to 3,500 rpm" [27] | not used: 423 N·m at 3500 rpm is 155 kW, past the rating | sourced |
| Idle, the curve's zero | 750 rpm at half the peak (`TRUCK_BASE`'s idle share), straight to 423 N·m at 1500; a governor droop from rated speed to nothing at 4000 rpm | estimate |
| Ratios | 4.171 / 2.340 / 1.521 / 1.143 / 0.867 / 0.691, reverse 3.403 [28] | secondary |
| Axle | 3.73 limited-slip, on a 4.7 t dual-rear-wheel Transit 350 HD with this engine [31]; 3.31 / 3.73 / 4.10 on other diesel Transits [32] | secondary |
| Overall | first 15.56:1; top 52.7 km/h per 1000 rpm at r 0.36 m, so the top speed is drag's, not the droop's | computed |
| Friction, clutch, lock-up | 0.10 of peak at idle (`TRUCK_BASE`'s, no van figure found); the car OE clutch margin 1.5 [17]; lock-up from D1, as on any 6+ speed [8] | estimate; estimate; sourced class rule |
| Stall speed | the derived 1562 rpm (`Drivetrain.stall_rpm`): `(idle / stall)²` 0.23, against 0.28 on `TRUCK_BASE`. No van figure found | computed |

`shift_up_rpm` 3300 sits past rated speed, where each step's next gear meets this gear's wheel
torque on the droop (D1 > D2 ~3440 rpm, D5 > D6 ~3200), and lands the 1.78 D1 > D2 step at 1850
rpm, in the band. `shift_down_rpm` 1400 sits under the band's 1500 edge.

*The Kenney trucks' drivetrain* (`TRUCK_BASE`), medium-duty for their 7.5-8 t: a Class 8 L9 (1695 N·m)
creeps harder on them (computed) than a 30 % pedal asks.

| Figure | Value | Grade |
| --- | --- | --- |
| Engine | Cummins B6.7 (2021) 325 hp, 750 lb-ft (1017 N·m) at 1800 rpm, governed 2600 ([brochure](https://mart.cummins.com/imagelibrary/data/assetfiles/0064235.pdf)): 890 N·m rated. Idle 700 at half the peak, 0.81 of it at 1200, rated speed to nothing at 2900 | sourced; computed; estimate |
| Ratios | Allison 3000 / 3200 close: 3.49 / 1.86 / 1.41 / 1.00 / 0.75 / 0.65, R 5.03 ([Allison](https://pprod.allisontransmission.com/en-gb/transmissions/models/3000-series)) | sourced |
| Axle, tyre | 5.57 on a Mack MD7 rear loader, 6.7 L and 3000 RDS ([listing](https://www.brucknertruck.com/inventory/2026-mack-md7-base-68364/)); 315/80R22.5 at 0.500 m loaded ([Michelin](https://business.michelin.ca/en/tires/michelin-x-multi-z-315)); `firetruck` takes the same | secondary, search summaries; estimate |
| At the drawn 0.36 m | `final_drive` 5.57 × 0.36 / 0.500 = 4.010, the same `G / r`: first 38.9 per metre, top 52.1 km/h per 1000 rpm. Creep at rest `T(stall) (idle / stall)² G η / r`, stall 1250 rpm: the creep of `docs/drivetrain.md` § Creep | computed |

| The tractor's wheels, `I = m (κ r)²` at the drawn radius (tyre and rim; ballast does not turn) | Value | Grade |
| --- | --- | --- |
| Tyres, MultiBib 650/65R38 / 540/65R28; rims 20 × 38 / 16 × 28 | 207 / 83 kg ([rear](https://onlineshop.bohnenkamp.de/en/tyre-michelin-multibib-650-65-r-38-13327680), [front](https://onlineshop.bohnenkamp-benelux.com/en/tyre-michelin-multibib-540-65-r-28-13327620): light, other makes 106-135 kg); 160 kg ([Deere AL205108](https://shop.deere.com/us/product/AL205108%3A-Rim%2C-20-X-38/p/AL205108)) / ~60 kg (off [Deere's 16 × 30](https://shop.deere.com/us/product/0250282713%3A-Rim%2C-16-X-30/p/0250282713), 64 kg) | secondary / sourced, one retailer; secondary / estimate |
| κ, then I rear / front | 0.75 (half the tyre at its tread, half over the sidewall annulus, the rim at 0.89 of its bead seat; no measured figure found); 367 kg × (0.75 × 0.66)² = 90, 143 kg × (0.75 × 0.44)² = 16 kg·m² | computed, estimate model |
| Rear tyre rate (`spring_rate_rear`), 650/65R38 157D at its rated 4127 kg, 1.6 bar | 72.8 in across, 32.6 in static loaded radius: 9.65 cm down, a secant 420 kN/m [62] | secondary, one retailer's data sheet; computed |
| Steering rate (`steer_speed`): a hydrostatic unit turns the wheels as fast as the hand winds | a Fendt 516 Vario takes 5 1/3 turns lock to lock [60]; a quick human hand ~720 deg/s, NHTSA's fishhook rate [61]; their ratio over the 960 deg centre to lock | sourced; secondary |
| Brakes inboard of the final reduction | [Case IH Puma](https://www.ultimatespecs.com/tractor-specs/caseih/caseih-puma-155-2008): "differential" wet discs; on the differential shaft, upstream of the planetary reduction ([Dana US 4,646,880](https://patents.google.com/patent/US4646880)) | secondary, no workshop manual |

| Implement draft (`ImplementBase.draft_rating` / `draft_shape`); speeds in km/h, forces in kN | Value | Grade |
| --- | --- | --- |
| Mouldboard plough, ASABE D497.7's row (plough.gd `DRAFT_SHAPE`) | A 652, B 0, C 5.1, in N per m width per cm depth; soil texture factor fine 1.0, medium 0.70, coarse 0.45 [45] | secondary |
| Its field speed range | 5.0-10.0, typical 7.0, the reference speed (`TractorTelemetry.DRAFT_S_REF_KMH`); held above the top [46] | sourced; the table read does not name D497 |
| Plough working depth | 25 cm, drawn, for the 4 × 14" (1.42 m) cut: furrow width over depth ~1.4, inside a design slide's 1.1-1.5 [47]; a 4-furrow plough measured in work ran 1.4 m at 28 cm [51] | estimate |
| Plough rating (plough.gd `RATED_DRAFT_N`, also `draft_max_force`) | medium soil × the row at 7 × 1.42 m × 25 cm, 22.41; g(0) 0.72 | computed |
| Power harrow | 3 m, 6-15 cm, speeds 3-12, rotors at 285 / 411 rpm off a 1000 rpm PTO; draught 4-13 over the trials [48]; 5.7 at 3 rising to 10.0 at 9 [49] | the trials sourced (abstract); both draught figures secondary, unverified against the paper's tables |
| Harrow rating (harrow.gd `DRAFT_SHAPE`, `RATED_DRAFT_N`) | the line through that pair, per m of width, held above 9; over the drawn 3.0 m, the trials' own width, 8.57; g(0) 0.41 | computed, estimate |

| Implement mass and ground support (`ImplementBase.mass_kg` / `ground_share`), Category 2 | Value | Grade |
| --- | --- | --- |
| Linkage (`headstock.tscn`) | lower pins 0.86 m apart at the ball centres (34 in [58]; 32 in between the link ends [59]); mast 0.533 m, inside the class's 15-24 in [59] | secondary |
| Plough, 4 × 14" conventional | 900 kg: Kverneland AD Variomat 85 at 4 furrows, 80-100 hp [50] | sourced |
| Its ground share | 0.35: the depth wheel carried about a third of a 2180 kg 4-furrow plough's weight, top link free, in work [51] | sourced, read off a graph |
| Power harrow, 3.0 m with packer | 1550 kg: Kverneland M 3.0 at 1550 (its summary table says 927) [52]; Amazone KE 3002 at 1530 with its roller, 1040 without [53]; Kuhn HR 3030 at 1679, Cat 2/3 [54] | sourced; secondary |
| Its ground share | 0.8: the roller sets the depth and carries the machine | estimate |
| Rotary cutter, 7 ft | 620 kg: Land Pride RCR2684 at 1370 lb with a single tail wheel, Cat II/III, 60-130 hp [55]; Woods BB84.40 at 1041-1132 lb [56] | sourced; secondary |
| Its ground share | the mass centre's lever over the tail wheel's (1.21 / 2.8 m behind the pins, off `mower.tscn`), the top link floating | computed; the float an estimate |
| Spreader, ~800 L single disc | 150 kg empty, Demir DMR SF 800 [57]; carried full of AN prill at 950 kg/m³ | sourced |
| Front-axle ballasting minimum (the `hitch` pass's guideline) | ≥ 20 % of total weight on the front axle to keep the tractor steerable: John Deere operator's manual, "Select Ballast Carefully" | sourced, no link recorded |

*PTO power* (`ImplementBase.pto_power_kw`, `RefuseBody.PUMP_KW`; on the crank through
`VehicleTelemetry.pto_crank_torque`). D497 rates neither drawn machine: its rotary-power table has
no power harrow and no single-spindle cutter.

| Figure; torques in N·m at the shaft, speeds in km/h, powers in kW | Value | Grade |
| --- | --- | --- |
| Power harrow PTO torque, 3 m, 1000 rpm shaft | means 215 / 271 / 391 at 3 / 6 / 9 over the trials' 6-15 cm; 116 at 6 cm and 3, 480 at 15 cm and 9 [48] | secondary: the results read only in search excerpts of the paper |
| Its speed and depth law | quadratic in speed, linear in depth; a power harrow's mean 168.9 per m width at the PTO, 8-12 cm at 2.2-4.8 [100] | abstract read |
| Harrow model (harrow.gd `PTO_SHAPE`, `PTO_RATED_KW`) | D497's form through the three means, A 223, B -13.33, C 3.556, held above 9; 303.9 at 7, 31.8 at 1000 rpm; g(0) 0.73; linear in depth through zero (129 at 6 cm and 3 against the 116 measured) | computed; the depth law an estimate |
| Rotary mower (mower.gd `CUT_KW`) | D497's disk mower, b 5.0 per m width ±30 %, a 0: 10.7 on the 2.14 m sweep. Rotz and Muhtar select 5 per m for a rotary mower ±30 % [102]; Arizona's reproduction of the table reads the same [103]. The D497.4 OCR copy's b column runs a row off its names (its ranges do not) [101] | secondary |
| Spreader disc (spreader.gd `DISC_KW`) | 2: the throw ~0.3 (0.33 kg/s leaving at ~30 m/s), the rest drag and the angle box; a single-disc spreader's maker asks for a tractor of 11 [104] | estimate |
| Refuse body pump (`RefuseBody.PUMP_KW`, `PUMP_RATED_ENGINE_RPM`) | a 40 yd³ front loader's: ~50 gpm at 1300 engine rpm, 2500 psi relief, arms lifting an 8000 lb container in a 13-18 second cycle [105]; raising at half the relief over a 0.85 pump, 32 | the spec sourced; the pressure share and pump efficiency estimates |
| PTO driveline (`VehicleTelemetry.PTO_EFFICIENCY`) | PTO power ~0.90 of net flywheel power [101] | secondary (an OCR copy); taken for the truck's gear PTO too, an estimate there |
| The ECM's PTO mode, its interlocks (`TruckTelemetry.pto_mode_engaged`, `PTO_MODE_MAX_SPEED_MS`; the neutral one `Drivetrain.pto_set_rpm`) | a Cummins ECM's PTO parameters: maximum vehicle speed 2 mph, parking brake interlock, transmission neutral interlock enabled [113]; with the neutral interlock off, an rpm ramp-up in drive can overcome the park brake [114] | secondary: the bulletin and the recall read in search excerpts |
| Its set speed (`VehicleSpec.pto_mode_rpm` 1300 on `garbage-truck`) | a Cummins remote PTO sets one of five preset speeds, typical for refuse [115]; J1939 PTO1 carries the set speed (SPN 187) and the governor's state (SPN 976), whose states include an accelerator override [116]. The preset is the body builder's calibration: the pump's rated speed | secondary; the value computed from the pump's rating |
| Its governing (droop 0, `PedalMap.MIN_DROOP`) | no truck PTO droop figure found; an electronic set-speed control holds its speed (isochronous, droop 0 % [117]); an aftermarket PT-pump PTO governor quotes ~10 % at most | estimate |
| The arm's rate against the pump's speed (`RefuseBody.pump_flow`) | a fixed-displacement pump's flow is its speed's share of the rated, so `ARM_TRAVEL_SEC` holds at 1300 rpm; capped at 1 past it, the body's flow control | computed; the cap an estimate |

*Surfaces* (`Surface`, `src/levels/base/surface.gd`). Grip is the all-season tyre's peak over its
dry-asphalt peak (Wong's 0.8-0.9, read as 0.85 [63]); drag is rolling resistance added over a car
tyre's 0.013 on asphalt [68]. A class scales grip per surface; drag is tyre-blind.

| Surface | Grip | Drag | Basis | Grade |
| --- | --- | --- | --- | --- |
| WET | 0.55 | 0 | the bottom of Wong's wet asphalt, 0.5-0.7 [63]; between Car 15's 0.6 (a clear slip spike, still controllable) and 0.5 (spins the car out), so it has no par | secondary |
| PAD | 0.95 | 0 | dry concrete grips as asphalt [63], less the skyport's paint | estimate |
| GRAVEL | 0.71 | 0.01 | Wong's gravel 0.60 [63]; rolled gravel 0.02 [68] | secondary |
| DIRT | 0.80 | 0.04 | Wong's dry earth road 0.68 [63]; unpaved road 0.05 [68] | secondary |
| GRASS | 0.50 | 0.06 | a street tyre ~0.35 on dry grass against ~0.72 on asphalt [64]; clover verges brake at ~60 % of rye-grass [65]; drag Wong's car on medium-hard soil, 0.08 [63] | estimate |
| SAND | 0.60 | 0.05 | firm (damp, packed) beach sand: 0.04-0.08, loose 0.2-0.4 [69]; grip none found | drag secondary, grip estimate |
| ROCK | 0.70 | 0.01 | none found; drag as setts, 0.015 [68] | estimate |
| MUD | 0.45 | 0.10 | grip under Wong's wet earth road (0.55, so 0.65) [63], for deep soft mud; drag below | grip estimate, drag computed |
| FIELD | 0.50 | 0.06 | grip a road tread in tilled soil, none found; drag below | grip estimate, drag computed |
| SNOW | 0.45 | 0.02 | hard-packed: snow braking puts the winter references at 22.3-22.7 m (mu ~0.44) and the all-season tyres at 22.6-24.4 [66], a quarter behind with summer tyres at twice the winter's distance in a blog's comparison [67]; Wong's 0.20 [63] is that summer tyre; drag none found | secondary, [67] indicative (no method stated); drag estimate |
| ICE | 0.12 | 0 | Wong's 0.10 [63]; black ice at most 0.10 in Bosch [68] | secondary |

MUD and FIELD drag: Zoz and Grisso's radial motion resistance `1.2/Bn + 0.5 s/sqrt(Bn) + 0.03` [45]
at the curve's 0.12 peak slip, on a 205/55R16 at a 1.15 t car's corner load (deflection 0.15 of
its section, an estimate), cone index 450 (wet soft) and 900 kPa (tilled) [45]: 0.109 and 0.073 in
all, inside Bosch's field band 0.10-0.35 [68] and at its foot. `Bn = (CI b d / W)(1 + 5 δ/h) /
(1 + 3 b/d)` is D497's form, not read in a primary. COMPROMISE: tyre-blind, so a big tyre pays the
car's figure (the tractor's own law gives 0.087 and 0.061 in all, over its 0.02); a per-tyre figure
is a fitment law (the mobility number), a later `GroundDriveSpec` field.

*Tyre classes* (`src/vehicles/tyres/`, each derivation in its `.tres` comment):

| Figure | Basis | Grade |
| --- | --- | --- |
| Summer `dry` 1.10 | the best all-season 6.5 m behind the summer reference's 37.0 m dry, SUV size [70]; car sizes run closer | secondary; 1.10 an estimate |
| Summer and Winter on snow | as SNOW above [66, 67] | secondary |
| Winter and Summer on ice | ice braking: winter 17.7, all-season 26.2, summer 35.5 m [71] | secondary |
| Studded on ice | new studs about twice friction tyres on severe ice, worn studs as studless [72]; 1.6x a modern studless taken | secondary; the figure an estimate |
| Mud on wet asphalt | wet-tar braking on a Hilux: mud-terrains 38.7 m, ~9 m past highway-terrains [73] | secondary |
| Soil factors of every class (Mud, R-1W lug, slick ...) | no published lug-against-road-tread figure found; D497 carries no tread term | estimate |
| `crr_factor` | EU label C1 classes: A ≤ 6.5, B 6.6-7.7, C 7.8-9.0, D 9.1-10.5, E ≥ 10.6 N/kN [74]; summer B, all-season C, winter C's top, mud E's floor | sourced bands; each class's band an estimate |

*Aero balance* (`downforce_front`, `race` and `race-future`; `docs/handling.md` § Aero balance):

| Figure | Basis | Grade |
| --- | --- | --- |
| The centre of pressure sits just behind the CG | a race car is set up with the aero resultant behind its CG, so a mid-engined car wants more downforce at the rear; an F1 car carries ~45 % of its downforce at the front axle line [75]. The centre of pressure closely matches the CG, wants a slight rear bias in low and mid-speed turns, and can sit neutral to slightly forward at high speed [76] | secondary: engineering articles, read; Katz and Milliken not opened |
| `downforce_front` 0.40 against a 0.42 weight split | two points of rear bias, inside "closely matches" and on the stable side [75, 76] | estimate |

*Crosswind* (`side_area`, the side force's `aero_centre`; `VehicleMath.air_force`, `gen_kenney_vehicles.gd`
`CY_SIDE` / `SIDE_CP_FRAC`, each hand-built spec's header):

| Figure | Basis | Grade |
| --- | --- | --- |
| Side force linear in yaw, set mostly by height | it rises about linearly over a wide yaw range, its gradient alike within a class and size, height dominating as slender-wing theory gives with the car's ground image [77]. With the image, that theory's slope is `q π h²` per radian (computed) | secondary |
| `CY_SIDE` 1.2 broadside on the side area | a road vehicle's side-force coefficient on its projected side area rises to 1.17 (fitted) to 1.34 (CFD) and holds from ~75 to ~165 degrees of yaw; on the frontal area the same reads 6.5, which is why high-sided figures look large [78] | sourced (CFD) |
| One `side_area` for broadside and the small-yaw slope | the `sin(yaw)` form makes them one figure. On a sedan-sized 4.4 × 1.38 m box, 1.2 × 0.82 × L × H is 5.97 m² against `π h²` 5.98; the Kenney bodies, shorter, sit at 0.4-1.3 × `π h²` (`gen_kenney_vehicles` prints both) | computed |
| A trailer's side area is its full side | cab and trailer take side forces of about the same size at 0-16 degrees of yaw despite the trailer's length; the side force's line of action sits just below each body's mid-height [79] | sourced |
| The side force acts ahead of the COM | most road vehicles have their centre of pressure in the front half, typically ahead of the neutral steer point, so a crosswind yaws them downwind [80]. `SIDE_CP_FRAC` 0.25 of the wheelbase ahead of the axles' midpoint | sourced; the fraction an estimate |
| Tanker barrel 0.7 | a circular cylinder's drag coefficient climbs back to ~0.7 near Re 3.5e6 past the drag crisis and holds [81]; the barrel at a 13 m/s crosswind sits at Re 1.5e6, below that plateau, so 0.7 is the upper end | secondary; the figure an estimate |

*Roll steer* (`GroundDriveSpec.roll_steer_front` / `_rear`, `gen_kenney_vehicles.gd`): degrees of
wheel steer per degree of the axle's suspension roll, + = toward understeer on either axle (the
front out of the turn, the rear into it). Gillespie's ε (+ = toward the side the body rolls to)
converts as `ε_f = front`, `ε_r = −rear`; MRA's axle coefficient signs the rear the same as here
and the front opposite.

| Figure | Basis | Grade |
| --- | --- | --- |
| Roll is the axle's against the chassis, not the body's world roll | the axle roll steer coefficients are defined on axle roll relative to the chassis; a positive rear coefficient is understeer [82] | sourced |
| Twist-beam rear 0.036 | an OEM baseline twist beam (ADAMS, correlated with the physical K&C rig) steers both rear wheels 0.14 deg into the turn at 3.9 deg of body roll [83] | sourced |
| Strut / double-wishbone front 0.10 | "typical near design height", varying a lot between well-handling cars; one reply calls 0.1 a little high [85]. Inside the compilation's front band, +0.2 (understeer) to −0.1 [84] | secondary |
| Multi-link rear 0.05 | mid of the compilation's rear band, +0.13 (understeer) to −0.06 [84]; no per-type figure found | secondary band; the figure an estimate |
| Leaf-sprung solid rear 0.10 | a rigid axle on semi-elliptic springs, front eyes below the rear ones, moves each wheel forward in jounce and rearward in rebound, so roll steers the rear wheels the way the fronts are turned: "the conventional roll understeer condition" [87]. It gives no size; 0.10 is the upper half of the compilation's rear band [84] | the sign sourced; the figure an estimate |
| The rear band's + end is understeer | the twist beam [83] and the leaf axle [87] both steer the rear into the turn as the body rolls, a positive rear coefficient in MRA's convention [82]. The compilation names no turn or roll direction [84] | sourced on both axles; the compilation's own convention unread |
| Open-wheelers, tractor 0 | no figure found; race kinematics are laid out for minimal toe change | estimate |
| Kenney trucks and the semis' drive axle: rear 0.10, front 0 | a truck's leaf axle shares [87]'s mechanism, its sign set by its spring eyes' heights; no size found. 0.10 is the leaf figure above, kept because it lands `garbage-truck` inside the tractor criterion [120] at the truck family's two slowest steps (`docs/vehicle_measurements.md` § Step steer); the rear-heavy `firetruck` and the laden semis stay under it, as load on the rear axles cuts K [121] (the semis' figures: `src/vehicles/truck/semi_spec.tres` header). The likely primaries, UMTRI's heavy-truck component factbook and *Descriptive parameters ... Vol. 4: steering and suspension systems* (UM-HSRI-81-19-4), are on Deep Blue, which refuses automated fetching | the sign sourced; the figure an estimate fitted to a criterion |
| Primaries not opened | Gillespie, *Fundamentals of Vehicle Dynamics*, ch. 6 (no copy reachable); SAE 1999-01-1323 (Erdogan, Guenther, Heydinger: its abstract reads roll steer against body roll on a side-pull rig, no figure); NHTSA's SPMD / VRTC reports (nhtsa.gov refuses automated fetching) | — |

*Compliance steer* (`GroundDriveSpec.compliance_steer_rear`; `docs/handling.md` § Balance), + = toward
understeer as above:

| Figure | Basis | Grade |
| --- | --- | --- |
| The unit: deg per kN at each contact patch | "degrees of toe change per Kilo-Newton of force at the contact patch" [126], which names no loading; the twist-beam figure below loads both wheels alike [83]. A test of one wheel against its own force is another figure | sourced (the definition); the loading per source |
| Twist-beam rear −0.061 to −0.066 deg/kN (the axle) | K&C "Lat Parallel – Toe Stiffness": one lateral force on both rear wheels, plotted per wheel. On the OEM baseline curve (ADAMS, correlated with the physical K&C rig) each wheel steers against the force, so a turn's force steers the rear out of it. A wheel's size depends on the force's side: ~−0.053 deg/kN inboard (the outer wheel), −0.068 softening to −0.080 outboard, with a stiff kink near zero force. The two wheels' mean, the axle's steer at a force F on each, has a secant of −0.061 to −0.066 over the force a saloon's rear patch carries from half a g to its limit: the field's figure off half the axle's total [83, Fig. 37; App. 1 p. 66] | sourced; read off the figure (digitised) |
| The axle's steer reads the axle's total | "Lat Opposed – Toe Stiffness" is linear and mirrored: inward forces toe both wheels out, ~0.076 deg/kN each, a mean steer of 0. With the parallel test, `steer_L = a F_L + b F_R` gives a ≈ −0.070, b ≈ +0.006 deg/kN, so the axle's mean steer is `(a + b)(F_L + F_R) / 2` however the force splits. The toe term `(a − b)(F_L − F_R) / 2` is equal and opposite on the two wheels and yaws nothing [83, App. 1 p. 69]. Superposition is exact only while each wheel has one rate, and the parallel test's split by side says it does not, so an axle whose outer wheel carries most of the force leans toward the inboard −0.053: the band's low end | sourced; read off the figures, superposition assumed |
| Leaf-sprung rigid rear: toward oversteer | with a bushed front eye and a rear shackle, the cornering force at each spring's centre deflects its rear end laterally more than its front, "so creating lateral force oversteer". A designed axle can give lateral force understeer instead, which acts without roll understeer's lag [87] | sourced; no size |
| A designed leaf hanger: toward understeer | a front eye in preloaded rubber cups [124], or on a cantilever bracket angled ~20 deg off the rail [125], moves outward under the cornering force. In their left turn the left wheel sits "a little behind its normal straight-away location" as the axle pivots about its midpoint, which steers both rear wheels into the turn. Both call it an advantageous "lateral force compliance steer"; neither names a sign (the direction read off the geometry) or a size | sourced as designs; the sign read off the geometry |
| Multi-link rear: toe-in under side force is a design | an assist-arm bushing softer than the lower arm's toes the outer rear in under a turn's lateral force: "Toe-in induces an understeer in a vehicle, helping to obtain a turn stability". It is the invention's own aim, not a class trait; the same axle also toes in under braking [123]. No size | sourced (one design); no size |
| Fronts, multi-link rears, trucks: no size | none found (searched 2026-10-23: K&C tables, NHTSA SPMD, Reimpell), nor among the user's sources (2026-10-23); the illustrative budget's compliance steer is 0.5 deg/g (side force 0.4) [86] | secondary |
| The illustrative budget's rear | Fy compliance steer front 0.3 / rear −0.1 deg/g. Its K is front − rear, so the rear's −0.1 adds understeer, while its text calls a negative entry "over-steering ... for that axle"; an imaginary example, applicable only while its parameters stay constant (low g) [86] | secondary; the rear's sign ambiguous |

*Linear understeer* (the step pass's K at its slowest speed, `docs/vehicle_measurements.md` § Step steer):

| Figure | Basis | Grade |
| --- | --- | --- |
| K band 0.7-8.2 deg/g, mean 4.4 (FWD 4.2, RWD 4.7) | US vehicles at a lateral acceleration of 0.15 of g [84] | secondary |
| Heavy trucks 0.5-2.0 deg/g at 0.15 of g | a recommended range for tractors: 0.5 its sensitivity boundary, 2.0 its steerability boundary, and the turn to oversteer no lower than 0.2 of g; read on the front axle's steer (steering compliance excluded) in a ramp of 0.03 deg/s at the axle, at highway speed [120] | sourced; a criterion, not a population |
| Load on a truck's rear axles cuts its K | a two-axle power unit loses ~1 deg/g per 0.06 off the front axle's share of its load, a three-axle one per 0.025; a radial steer axle on bias drive tyres cuts more than any axle-load case. Those ramp-steer simulations read 3-5 deg/g over the steady turns of tested trucks (radial tyres at 0.25 of g: −0.5 to +2.7) [121, pp. 56-59, Fig. 22] | sourced (simulation) |
| 15-passenger vans 2.7-4.3 deg/g | a 2003 Ford E-350 (means 2.72-3.49) and a 2004 GMC Savana 3500 (3.26-4.32), 2 to 15 occupants, by slowly increasing steer (SAE J266 constant speed); the table prints the unit as deg/deg [122, Table 5.1] | sourced |
| Cars, SUVs, pickups: no class band | none found in a primary. A forum poll puts recent cars at 2-3 deg/g (the sportier ~2), light trucks at 3 and more, a laden light truck near 1 [85] | secondary |
| Roll steer's share | 1.0 of an illustrative 4.1 deg/g budget (front 0.6, rear −0.4 in the per-axle K convention, K = front − rear); roll camber 1.2, compliance steer 0.5 (side-force 0.4, aligning-torque 0.1) and aligning torque 0.4 more [86] | secondary |

*Pedal map* (`PedalMap`, `VehicleSpec.pedal_map`; `docs/drivetrain.md` § The pedal map):

| Figure | Basis | Grade |
| --- | --- | --- |
| `PETROL_REQUEST` | brake torque against pedal % and rpm on a dynamometer, a 2016 Honda L15B7 (1.5 L turbo), 1000-5000 rpm [88, Fig. 2]; the contours read at 600 dpi as a share of the figure's own peak, to about ±0.013 of it | primary measurement, read off a figure (secondary) |
| The jump inside the first 1 % of pedal | "torque output transitions from unfueled minimum to a positive value between zero and one percent accelerator pedal", on many production calibrations [88] | sourced |
| The request flat in rpm, clipped by full load | the figure's contours run near-level in N·m from 1500 to 4500 rpm and meet full load at 1000-1500 rpm from 30 % pedal [88]; read as the torque-structured request the engine realises up to full load | the reading an interpretation of a sourced figure |
| The rpm axis over rated speed | the L15B7 makes 174 hp at 6000 rpm [90]; each body's own rated speed is where its curve's power peaks | sourced |
| Road diesels LINEAR | on a truck's min-max governor "the driver operates the control rod in the fuel injection pump directly by means of the accelerator pedal, and thus sets the required torque"; the governor acts at idle and maximum speed only [89]. No electronic road-diesel map (J1939 SPN 91 to SPN 512) was found | sourced (mechanical governor); the electronic one assumed alike |

*Governor* (`PedalMap.Kind.ALL_SPEED`, `VehicleSpec.governor_droop`,
`TractorTelemetry.PTO_RATED_RPM`; `docs/drivetrain.md` § The pedal map):

| Figure | Basis | Grade |
| --- | --- | --- |
| The all-speed governor | a variable-speed governor holds every engine speed the lever sets between idle and maximum, fuelling along its regulation curve [89] | sourced |
| `governor_droop` 0.07 | John Deere 6170R-6210R, operator's manual, Engine: slow idle 850, fast idle 2250, rated 2100 rpm, working range 1500-2100 [106]: fast idle 7.1 % over rated | secondary: read in a search excerpt; the manual's page refused the connection |
| The top setting's 18 % (the curve's 2200-2600 tail, kept) | the sourced 7 % puts the high idle near 2350, and the top speed at D16's road speed there | COMPROMISE (`TRACTOR_BASE`) |
| `PTO_RATED_RPM` 2043 | the 6175R turns 540 and 1000 at 1950 engine rpm [107], 0.929 of its 2100 rated speed [106]; on the curve's 2200 rated (its governor's break) | secondary |
| An electronic engine's selectable droop; ISO 3046-4's governing classes | none found. ISO 3046-4 is paywalled, not read; patents describe a positive droop preset in software [108] and an isochronous mode held at a set engine speed [109], with no figure | not found |
| A part demand upshifts two droops under its setting (`ShiftPolicy.GOVERNED_UPSHIFT_DROOP`): the line's full-fuel end, less a droop for the drive tyres' slip | no governed shift schedule found. Measured: on the map's own point the tractor at demand 0.5 (setting 1700, point 1762) never leaves its start gear; at half a droop (the line's middle) the tipper climbing 8 % at demand 0.6 holds D4 on 43 % fuel, its road speed's rpm 1744 under the 1816 point while ~5 % slip holds the crank at 1839 | estimate |
| A governed box keeps the map's downshift points (`ShiftPolicy.down_rpm`): a setting under the landing floor holds its gear, one under the coast line crawls in D1 | an engine-speed-shifting powershift's behaviour (AutoPowr / Dynashift class); no shift schedule found | estimate |

*Fuel* (`VehicleTelemetry.fuel_rate_lph`; `docs/drivetrain.md` § Fuel). The model's reading is computed off each spec:

| Figure | Basis | Model reads | Grade |
| --- | --- | --- | --- |
| PETROL: 41.05 MJ/kg, 0.757 kg/L; η_i 0.41 | the Malibu map's E10 test fuel; its minimum BSFC 239 g/kWh [91] | `sedan` 241 g/kWh at 2000 rpm | sourced |
| Petrol idle | the Malibu at 650 rpm at no load: 0.076 g/s, 0.36 L/h [91]; a 2.0 L compact, no accessory load, 0.61 L/h [92] | `sedan` 0.34 L/h at 900 rpm, on the Malibu's friction law (`docs/drivetrain.md` § Motoring and friction) | sourced; secondary |
| DIESEL: 42.7 MJ/kg, 0.84 kg/L; η_i 0.45 | Volvo Penta's rating fuel; at full load over their friction power, η_i 0.450 (TD640VE, 213 g/kWh at 1800 rpm) and 0.456 (TAD1641GE, 197-200 at 1500) [5, 7] | `garbage-truck` 211, `semi` 201 g/kWh | sourced |
| Diesel idle | a Class 8 tractor-semitrailer idles at 2.4 L/h [92], with the accessories and raised idle this model omits | `semi` 1.62 L/h at 600 rpm | secondary |
| Tractor | OECD test 2136, John Deere 6175R: 130.4 kW at its PTO on 36.3 L/h, ~234 g/kWh there [93]; no tractor idle figure found | `tractor-kenney` 222 g/kWh at the crank at rated, 211 at best | secondary |

*Gearing* (the semis' and the tractor's `gear_ratios`; `docs/drivetrain.md` § The shift policy):

| Figure | Basis | Grade |
| --- | --- | --- |
| Semis' twelve, the I-Shift ATO2612 | overdrive, no crawler: 11.73 / 9.21 / 7.09 / 5.57 / 4.35 / 3.41 / 2.70 / 2.12 / 1.63 / 1.28 / 1.00 / 0.79, steps 1.26-1.30 [94] | sourced |
| Fitted onto the shipped span | the steps' logarithms scaled by 0.8313 so 6.5 to 0.69 keeps D1 and the overdrive: 6.5 / 5.316 / 4.277 / 3.5 / 2.849 / 2.327 / 1.917 / 1.568 / 1.26 / 1.031 / 0.839 / 0.69, steps 1.21-1.24 | computed |
| Tractor's sixteen, a full powershift | the John Deere 8R e16: Power Shift, 16 forward / 4 reverse, at rated speed 1.88 to 39.13 (km/h; OECD 2/2 682, the 8235R) [95]; its chart at 2100 rpm reads, in km/h, 1.9 / 2.4 / 3.2 / 4.5 / 5.0 / 5.8 / 6.8 / 7.7 / 9.0 / 10.3 / 12.1 / 13.8 / 16.3 / 21.7 / 29.0 / 42.2, field steps ~1.15 [96] | sourced; the chart secondary |
| Even 1.103 steps over 7.0 to 1.6 | the shipped span is only the e16's gears 8-16, so sixteen ratios there step at the brief's 1.10 edge; its 22:1 span would deepen D1 past the stall hold (a COMPROMISE, `gen_kenney_vehicles.gd`) | computed |
| The start gear's slip time, `START_SLIP_S` | an automatic start-gear selection: the highest start gear, up to a programmed maximum (3rd or 5th in its example), whose estimated clutch slip time on tractive effort, rolling resistance, grade and gross weight stays under a reference, "say 1.5 seconds" (a quarter of a second to five acceptable) [99]; the I-Shift picks its own and lets the driver take a lower one [37] | sourced; the half-ramp dead time an estimate |

*CVT* (`tractor-cvt`; `docs/tractor.md` § The CVT tractor):

| Figure | Basis | Grade |
| --- | --- | --- |
| Four ranges changing synchronously; in km/h at 2300 rpm, 0-6.4 / 6.4-13 / 13-26 / 26-51 | the ZF Eccom, an input-coupled hydrostatic power split shifted at synchronous speeds without a power interruption; John Deere fits it as AutoPowr on its 6000 line since 2001 [110] | sourced (a review of Pohlenz & Gruhle 2002) |
| Ratio tops 0.1128 / 0.229 / 0.4581 / 0.8986 (gearbox output over input) | those speeds through `final_drive` 10.083 and the 0.66 m rear at 2300 rpm (`gen_kenney_vehicles.gd` `_cvt`): the road-speed limit at ~1800 rpm, the overdrive Renius asks of a CVT [110] | computed |
| Hydrostatic share +40 % at a range's bottom, -35 % at its top (`CVT_SHARE_BOTTOM` / `_TOP`) | the Eccom's hydrostatic power portion across each range, through zero at the lock-up [110] | sourced |
| Variator 85 % (`CVT_VARIATOR_EFF`) | the analysis figure for 45-degree bent-axis units (gear pairs 97 %) [110] | sourced |
| The efficiency linear in the share, `efficiency` at each lock-up | constant path efficiencies, as Renius's own analysis assumes; range I's near-zero-speed circulating power left out (a COMPROMISE at `Drivetrain.cvt_efficiency`) [110] | estimate |
| Active standstill; reverse's top (`CVT_REVERSE_KMH`) | a CVT's market demands: active zero speed control under all practical loads, reverse from zero to about 25 (km/h) [110] | sourced (a requirement) |
| The relief at `mass g r` (`cvt_max_axle_torque`) | peak gross traction on concrete is about the ballasted tractor's weight, and a hydrostatic CVT's pressure is limited to it [110] | sourced; the rule's application an estimate |
| The rate as the ground-speed reference's acceleration (`cvt_accel_ms2`), one rate both ways | a CVT tractor's acceleration demand bands: low up to 0.25, medium 0.5-0.7, high 1-2 m/s², vehicle accelerations; the ratio as output over input speed [111]; acceleration and deceleration ratio rates limited separately, no values published [119] | sourced (a patent's bands); the figure picked in the high band; symmetric an estimate |
| Engine-speed management in pedal mode (`Drivetrain.cvt_managed_setting`): the setting falls in proportion to the load, full load at rated, light load at 57 % of rated (`CVT_LIGHT_LOAD_SHARE`, 1140 rpm here); the hand throttle or an engaged PTO stands it down; its load the road-load estimate plus the rig's mass at the commanded acceleration (`cvt_commanded_accel`) over the limit speed's full power, floored to reach the command at the top ratio, falling at the ratio's rate (`cvt_setting_step`) | an IVT tractor's automatic mode reduces engine speed "proportional to the load reduction" to hold the vehicle speed; light load at 57-81 % of rated in the maximum mode (its example 1140 rpm on a 2000 rpm engine; 62-86 % intermediate); rated speed with the PTO on; manual mode holds the operator's speed; no load signal, rate or delay named [118] | sourced; the maximum mode's bottom picked; the load's inputs computed |
| The brake pedal brings it to standstill (`Drivetrain.cvt_speed_command`) | AutoPowr's AutoClutch lets the driver stop the tractor on the brake pedals [112] | secondary |
| Limit-load control (`cvt_ratio_step`): the crank held at the governor line's full-fuel end, the ground speed giving, over `CVT_LOAD_TAU_S`; the range byte's `CVT_RANGE_HYSTERESIS`; the pressure cut-off | no control law found | estimate |

## Reference list

1. Ubysz, "Problems of rotational mass in passenger vehicles", Transport Problems 5(1), 2010, Table 1: http://transportproblems.polsl.pl/pl/archiwum/2010/zeszyt1/2010t5z1_04.pdf
2. Honda CR-V converter impeller inertia, arXiv 2305.15216: https://arxiv.org/pdf/2305.15216
3. SimulationX automotive powertrain tutorial: https://doc.simulationx.com/4.3/1033/Content/Tutorials/AutomotivePowertrain.htm
4. "Impact of Engine Inertia on P2 Mild HEV Fuel Consumption", WEVJ 15(5) 220, 2024: https://doi.org/10.3390/wevj15050220
5. Volvo Penta TD640VE technical data (inertia 1.50 kg·m²; friction power 17-26 kW at 1800-2400 rpm; specific fuel consumption by load; 42.7 MJ/kg, 0.84 kg/L): https://sra-moteur.com/uploads/catalogue/produits/documentations/td640ve-td640ve.pdf
6. Volvo Penta TAD734GE data sheet: https://www.scribd.com/document/457581321/TAD734GE
7. Volvo Penta TAD1641GE technical data (inertia 4.20 kg·m²; friction power 36 / 53 kW at 1500 / 1800 rpm; specific fuel consumption by load): https://www.wincogen.com/wp-content/uploads/PD/Engines/VOLVO_TAD1641GE.pdf
8. Middelmann, "The Torque Converter as a System", Schaeffler (LuK) symposium: https://www.schaeffler.com/remotemedien/media/_shared_media/08_media_library/01_publications/schaeffler_2/symposia_1/downloads_11/6_Torque_Converter.pdf
9. MathWorks Powertrain Blockset, Torque Converter block: https://www.mathworks.com/help/autoblks/ref/torqueconverter.html
10. Allison 3000 stall torque ratios, quoted on a forum: https://www.skoolie.net/goto/post?id=7439134
11. ADVISOR automatic transmission model validation (NREL): https://adv-vehicle-sim.sourceforge.net/NewAutoTX.html
12. Lock-up release: US 4,618,041 (https://patents.google.com/patent/US4618041A/en) and US 7,238,142 (https://patents.google.com/patent/US7238142B2/en)
13. Audi technology portal, tiptronic (ZF 8HP): https://www.audi-technology-portal.de/en/drivetrain/transmission-technologies/tiptronic_en
14. Fleet Equipment, "Allison continues to optimize for 2011": https://www.fleetequipmentmag.com/?p=82312
15. Stall speed glossary: https://www.youcanic.com/glossary/stall-speed/
16. An AT545 owner report, seen only in a search summary (unverified).
17. Maki and Iwasaki, "On the transmitted torque of automotive friction clutches", Trans. JSME 18(70), 1952: https://ndlsearch.ndl.go.jp/books/R000000004-I10033763
18. Phoenix Friction, clutch torque capacity ratings: https://www.phoenixfriction.com/t-Clutch-Kit-Torque-Capacity-Ratings.aspx
19. Eaton, US 9,783,181 B2: https://patents.google.com/patent/US9783181B2/en
20. Caterpillar, US 5,467,854: https://patents.google.com/patent/US5467854A/en
21. Saab WIS, Motronic 2.8.1 idling compensation: https://saabwisonline.com/900/1994/2-engine/motronic-2-8-1/technical-description/idling-compensation
22. Ranger Station forum, D/P rpm drop: https://www.therangerstation.com/forums/threads/d-p-rpm-drop.164763
23. Honda Hill Start Assist: https://global.honda/en/tech/Hill_Start_Assist/
24. Volvo VN hill start assist: https://static.nhtsa.gov/odi/tsbs/2019/MC-10169013-9999.pdf
25. Robert Bosch, EP 2 203 334 B1: https://patents.google.com/patent/EP2203334B1/en
26. Valtra, "What exactly is the Powershift Revolution": https://valtra.co.uk/blog/technology/what-exactly-is-the-powershift-revolution.html
27. Ford Motor Company, press release, 2012-12-10, "Advanced, Fuel-Efficient 3.2-Liter Power Stroke Turbo Diesel Makes North American Debut in All-New 2014 Ford Transit", reproduced at https://www.firehouse.com/apparatus/press-release/10839682/ford-motor-media-advanced-fuel-efficient-32-liter-power-stroke-turbo-diesel-makes-north-american-debut-in-all-new-2014-ford-transit
28. Wikipedia, "Ford 6R transmission": https://en.wikipedia.org/wiki/Ford_6R_transmission
29. Wikipedia, "Ford Duratorq engine" (3.2 L Puma): https://en.wikipedia.org/wiki/Ford_Duratorq_engine
30. DieselHub, "3.2 Power Stroke": https://www.dieselhub.com/halfton/3.2-powerstroke.html
31. Dealer listing, 2019 Transit 350 HD DRW cutaway (3.73 limited-slip, 10,360 lb GVWR): https://www.comvoy.com/work-truck/kenosha-wi/used-2019-ford-transit-350-hd-service-utility-van-18061317
32. Parts and dealer listings for 3.31 / 3.73 / 4.10 diesel Transit axles, seen only in search summaries: https://allusedparts.com/ford/transit_350/2017/rear_axle_assembly/
33. Newman, Kargul, Barba (US EPA), "Benchmarking and Modeling of a Conventional Mid-Size Car Using ALPHA", SAE 2015-01-1140: https://19january2021snapshot.epa.gov/sites/static/files/2016-10/documents/2015-01-1140.pdf
34. Newman, Kargul, Barba (US EPA), "Development and Testing of an Automatic Transmission Shift Schedule Algorithm for Vehicle Simulation", SAE 2015-01-1142 (the Malibu's measured shift map, Fig. 11; ALPHA's suggested hold times and downshift ceiling): https://19january2021snapshot.epa.gov/sites/static/files/2016-10/documents/2015-01-1142.pdf
35. Wikipedia, "GM 6T40 transmission" (secondary): https://en.wikipedia.org/wiki/GM_6T40_transmission
36. Volvo Trucks, fact sheet "I-Shift drive modes", 2024: https://stpi.it.volvo.com/STPIFiles/Volvo/FactSheet/DRM-E,DRM-BE_Eng_06_331992824.pdf
37. Volvo Trucks North America, "Operator's manual, I-Shift transmission", PV776-20906026, 2007: https://hhrvresource.com/sites/default/files/dfiles/VolvoOperatorsManualI_Shift_PV77620906026.pdf
38. Volvo Trucks North America, D13 engine brochure (cruise 1250-1500 rpm, never above 1550): https://www.volvotrucks.us/media/vtna/files/shared/powertrain/revised4147-101-volvo-d13-engine-brochure-low-res.pdf
39. Massey Ferguson, "Innovation", AutoDrive (Power 2100 rpm, Eco 1500 rpm): https://www.masseyferguson.com/en_za/farming-technology/innovation.html
40. Farmers Weekly, "MF's new developments improve efficiency", 2001-02-16 (Dynashift AutoDrive): https://www.fwi.co.uk/news/mfs-new-developments-improve-efficiency
41. Jaguar Land Rover, US 11,724,688 B2 (torque and inertia phases ~0.15-0.5 s each): https://patents.google.com/patent/US11724688B2/en
42. Ford Global Technologies, US 10,343,690 B2 (inertia-phase output torque set by the oncoming clutch): https://patents.google.com/patent/US10343690B2/en
43. Zhang et al., "Study on Shifting Performance of Tractor Multi-Clutch under Different Engagement Rules", Agriculture 14(2) 254, 2024 (a simulation; abstract read): https://ideas.repec.org/a/gam/jagris/v14y2024i2p254-d1333372.html
44. GM Global Technology Operations, US 9,327,733 B2 (engine torque held reduced through the inertia phase): https://patents.google.com/patent/US9327733B2/en
45. Hefele and Oksanen, "EcoTIM: Fuel-saving multi-brand tillage with ISO 11783 TIM", arXiv 2604.17991, 2026 (its draft model and Table 2, quoting ASAE D497.7): https://arxiv.org/html/2604.17991
46. University of Arizona, "Table 3 – Field efficiency, field speed, and repair and maintenance cost parameters" (an archived copy read): https://web.archive.org/web/20240420133028/https://ag.arizona.edu/crop/equipment/agmgttable3.pdf
47. "Mouldboard plough" design slides (furrow width over depth 1.1-1.5): https://www.slideshare.net/slideshow/mb-ploughpptx/254915097
48. Balsari et al., "Performance analysis of a tractor - power harrow system under different working conditions", Biosystems Engineering 202, 28-41, 2021, doi:10.1016/j.biosystemseng.2020.11.009 (abstract read via OpenAlex; its highlights and its PTO torque means seen only in search results; the full text and the repository copy sit behind a bot check): https://www.sciencedirect.com/science/article/pii/S1537511020303147
49. Academia.edu's generated summary of [48], seen only in search results: https://www.academia.edu/83175306/Performance_analysis_of_a_tractor_power_harrow_system_under_different_working_conditions
50. Kverneland, "Kverneland AD", technical specifications (AD Variomat 85: 730 / 900 / 1090 kg at 3 / 4 / 5 furrows): https://ien.kverneland.com/ploughs/conventional-ploughs/kverneland-ad
51. Oberhaus, Biller, Keuper and Stachnik, "Load Transfer from the Fully-mounted Plough to the Tractor", Landtechnik 60(6) 330-331, 2005 (Fig. 2 at 0 MPa; read in full): https://www.agricultural-engineering.eu/landtechnik/article/download/2005-60-6-330-331/2005-60-6-330-331-en-pdf/2059
52. Kverneland, "M series" power harrows, technical data (with levelling bar, tooth packer roller and PTO shaft): https://uk.kverneland.com/tillage-tools/power-harrows/m-series
53. AllMachines, "Amazone KE 3002-150" (2293 lb without roller, 3373 lb with KW 580): https://www.allmachines.com/harrows/amazone-ke-3002-150
54. Kuhn North America, HR 1030 series (HR 3030: 3702 lb with MaxiPacker): https://kuhn-usa.com/node/14441
55. Land Pride, RCR2684 rotary cutter manual, form 312-785S, 2012-03-05: https://www.manualsdir.com/manuals/168383/land-pride-rotary-cutter-rcr2684.html
56. Woods BB84.40 dealer listings (1041 and 1132 lb), seen only in search results: https://www.parishtractor.com/product/bb84-40
57. Demir Machinery, single-disc fertilizer spreader (DMR SF 800: 800 L, 150 kg): https://www.demirmachinery.com/fertilizer-spreader-single-disc/
58. Wikipedia, "Three-point hitch" (category table: lower hitch spacing 28 / 34 / 40 in): https://en.wikipedia.org/wiki/Three-point_hitch
59. Koenig Equipment, "What are the Differences in 3-point Hitch Categories?" (lift arm spacing 26 / 32 / 38 in; Category 2 mast 15-24 in): https://blog.koenigequipment.com/what-are-differences-3-point-hitch-categories
60. top agrar, "Testprotokoll Fendt 516 Vario" ("Das Lenkrad ist mit 5 1/3 Umdrehungen lang übersetzt"; under 4 with VarioActive): https://www.topagrar.com/technik/aus-dem-heft/testprotokoll-fendt-516-vario-9670043.html
61. NHTSA rollover-resistance manoeuvres (fishhook at 720 deg/s handwheel rate; J-turn 1000 deg/s), seen only in search results: https://www.nhtsa.gov/sites/nhtsa.gov/files/forkenbrock_0.pdf
62. NTS Tire Supply, "650/65R38 Firestone Performer 65 R-1W 157D" (diameter 72.8, static load radius 32.6, 4127 kg, 23 psi): https://store.ntstiresupply.com/shop/003015-650-65r38-firestone-performer-65-r-1w-157d-100-34994
63. Wong, *Theory of Ground Vehicles*, 2nd ed., 1993, p. 26 (peak and sliding adhesion) and p. 17 (rolling resistance by tyre and surface), quoted by HPWizard (the book not opened): https://hpwizard.com/tire-friction-coefficient.html
64. An iRacing forum post (street tyres ~0.35 on dry grass, ~0.72 on asphalt), seen only in search results: https://www.iracing.com/?p=19604
65. Cenek, Jamieson and McLarin, "Frictional characteristics of roadside grass types", 2005 (abstract): https://trid.trb.org/View/783691
66. Tyre Reviews, "2025 AutoBild All Season Tyre Test" and "2024 AutoBild All Season Tyre Test" (snow braking), seen in search results: https://www.tyrereviews.com/Tyre-Tests/2025-AutoBild-All-Season-Tyre-Test.htm
67. TyreMap, "All-Season vs Winter Tyres" (snow braking: winter 31 m, all-season 38, summer 62; no method stated), seen in search results: https://tyremap.com/blog/all-season-vs-winter-tyres-comparison/
68. Robert Bosch GmbH, *Automotive Handbook*, 4th ed., 1996, p. 330 (rolling resistance by surface) and p. 335 (tyre friction by speed and water), quoted by HPWizard: https://hpwizard.com/tire-friction-coefficient.html
69. Engineering ToolBox, "Rolling Resistance" (car tyre on solid sand 0.04-0.08, on loose sand 0.2-0.4): https://engineeringtoolbox.com/rolling-friction-resistance-d_1303.html
70. Tyre Reviews, "2020 ADAC SUV All Season Tyre Test" (235/55 R17; summer reference 37.0 m dry, the best all-season 6.5 m more), seen in search results: https://www.tyrereviews.com/Article/2020-ADAC-SUV-All-Season-Tyre-Test.htm
71. Autonavigator, "What are the best tyres for this winter? We have tested 19 sets" (ice braking), seen in search results: https://www.autonavigator.hu/tippek_tanacsadok/what-are-the-best-tyres-for-this-winter-we-have-tested-19-sets
72. VTI, "Field test of studded and non-studded winter tires: subjective rating by taxi drivers", 1990 (abstract, seen in search results): https://trid.trb.org/view/361699
73. Leisure Wheels, highway-, all- and mud-terrain tyres on a Hilux (wet braking), seen in search results: https://www.leisurewheels.co.za/?p=1149944
74. Regulation (EU) 2020/740, Annex I Part A (rolling resistance classes): https://legislation.gov.uk/eur/2020/740/annex/I/part/1?view=plain
75. J. Paton, Total Simulation, "Secrets of Formula 1 Part 2 - Importance of Aerodynamics", 2016-06-14: https://www.totalsimulation.co.uk/secrets-formula-1-part-2-importance-aerodynamics/
76. Formula 1 Dictionary, "Aerodynamic balance or Centre of Pressure (CofP)": https://www.formula1-dictionary.net/aerodynamic_balance.html
77. J. Howell, S. Panigrahi, "Aerodynamic Side Forces on Passenger Cars at Yaw", SAE 2016-01-1620 (abstract): https://saemobilus.sae.org/content/2016-01-1620/
78. V. Malviya et al., University of Huddersfield, "Effect of cross wind on aerodynamic coefficients of ground vehicles": https://eprints.hud.ac.uk/6856/1/4_V_Malviya.pdf
79. M. Hammache, M. Michaelian, F. Browand, "Aerodynamic Forces on Truck Models, Including Two Trucks in Tandem", California PATH UCB-ITS-PRR-2001-27, 2001: https://escholarship.org/uc/item/6jr154q9
80. A. Brandt, "Driving stability of passenger vehicles under crosswinds", licentiate thesis, Chalmers, 2021: https://research.chalmers.se/publication/521674/file/521674_Fulltext.pdf
81. A. Roshko, "Experiments on the flow past a circular cylinder at very high Reynolds number", J. Fluid Mech. 10, 1961 (abstract): https://authors.library.caltech.edu/records/m8vtc-33e74
82. Milliken Research Associates, *MRA Moment Method User's Manual* v4.10, § 4.5.5 Axle Roll Steer, 2000: https://millikenresearch.com/MMM410man.pdf
83. Auto/Steel Partnership, *Lightweight Twist Beam Development — Final Report*, Fig. 35 (K&C: roll — roll steer), Fig. 37 and Appendix 1 pp. 66, 69 (K&C: lat parallel / lat opposed — toe stiffness): https://www.a-sp.org/wp-content/uploads/2020/08/Lightweight-Twist-Beam-Final-Report.pdf
84. "Summary of typical vehicle parameter measurements — compliance parameters", unattributed compilation (search summary; the page refuses fetching): https://www.researchgate.net/publication/329552571
85. Eng-Tips, "Understeer gradient of modern passenger cars" (forum): https://www.eng-tips.com/threads/understeer-gradient-of-modern-passenger-cars.190555/
86. Wikipedia, "Bundorf analysis" (after Bundorf & Leffert, SAE 760713; the example is illustrative): https://en.wikipedia.org/wiki/Bundorf_analysis
87. US 4,919,449, "Vehicle rear suspension" (General Motors; G. S. Toms; 1990; the description read): https://patents.google.com/patent/US4919449
88. Dekraker, Barba, Moskalik, Butters (US EPA), "Constructing Engine Maps for Full Vehicle Simulation Modeling", SAE 2018-01-1412 (Fig. 2: pedal against torque, a 2016 Honda L15B7): https://www.epa.gov/sites/default/files/2018-10/documents/sae-paper-2018-01-1412.pdf
89. Robert Bosch GmbH, *Fuel Injection Equipment for Diesel Engines: Governors for In-Line Pumps*, Technical Instruction, 1975 (English 1977; the min-max governor, read in full): https://injectionpumps.co.uk/wp-content/uploads/2020/04/Bosch-Governors-for-Inline-Injection-Pumps.pdf
90. American Honda, press release, "Honda 1.5-liter turbo engine" (174 hp at 6000 rpm): https://hondanews.com/en-US/releases/release-40b876fa88ce36bf41449f6e441f9b95-honda-15-liter-turbo-engine
91. US EPA NCAT, "Process for Generating Engine Fuel Consumption Map (Chevy Malibu 2.5L I4 engine using Tier 3 fuel)", 2016-11-28 (BSFC map, idle at 650 rpm, the closed-throttle motoring curve, the test fuel): https://19january2021snapshot.epa.gov/sites/static/files/2016-11/documents/procs-gen-eng-fuel-cons-map-2013-chevy-malibu.pdf
92. US DOE, "Fact #861: Idle Fuel Consumption for Selected Gasoline and Diesel Vehicles", 2015, after an Argonne worksheet (no accessory load; seen only in search summaries): https://www.energy.gov/eere/vehicles/fact-861-february-23-2015-idle-fuel-consumption-selected-gasoline-and-diesel-vehicles
93. TractorData, "John Deere 6175R Tests" (OECD Tractor Test 2136, 2015): https://www.tractordata.com/farm-tractors/007/9/3/7930-john-deere-6175r-tests.html
94. Volvo Trucks North America, *Body Builder Instructions VNL, Section 4: I-Shift Transmission*, USA175332888, 5.2024, p. 5 (gear ratios, AT2612 and ATO2612): https://www.volvotrucks.us/media/vtna/files/shared/body-builder/manuals/2025/section-4.pdf
95. OECD, tractor test approval 2/2 682, John Deere 8235R, Power Shift (the 40-km/h box), 2012-02-27 (Nebraska Tractor Test Laboratory): https://webfs.oecd.org/TADWEB/agriculture/data/tractor/2012/Fr2682.pdf
96. TractorData, "John Deere 8235R Transmission" (16-speed Automatic PowerShift speed chart at 2100 rpm, Group 47 rears): https://www.tractordata.com/farm-tractors/006/7/1/6712-john-deere-8235r-transmission.html
97. Getrag Ford Transmissions, US 7,086,989 B2 (drive torque briefly reduced through the speed-adaptation phase by an engine-management intervention; road vehicles): https://patents.google.com/patent/US7086989B2/en
98. Deere & Company, US 2004/0014563 A1, "Transmission shift control with engine torque control" (a powershift's controller requests a torque level from the engine controller through the shift; read via its summary): https://patents.google.com/patent/US20040014563
99. Eaton Corporation, US 6,953,410 B2, "Automatic selection of start gear", 2005-10-11 (the start gear from estimated clutch slip time; read via its description): https://patents.google.com/patent/US6953410B2/en
100. Sihag, Upadhyay, Choudhary and Patel, "Specific Torque Requirement of Different Tractor PTO Operated Active Tillage Machinery", Journal of Agricultural Engineering (India) 63(2), 259-269, 2026, doi:10.52151/jae2026632.2002 (abstract read; the PTO speed not stated there): https://pub.isae.in/index.php/jae/article/view/3348
101. ASAE D497.4, "Agricultural Machinery Management Data", 2003: Table 2, rotary power requirement parameters, and the PTO-to-flywheel figure (an OCR copy read): https://pdfcoffee.com/ansi-asabe-d497-4-2003-4-pdf-free.html
102. Rotz and Muhtar, "Rotary Power Requirements for Harvesting and Handling Equipment", Applied Engineering in Agriculture 8(6), 751-757, 1992 (seen only in search results): https://pure.psu.edu/en/publications/rotary-power-requirements-for-harvesting-and-handling-equipment/
103. University of Arizona, "Table 2 – Rotary power requirement parameters" (cutterbar 1.2, disk 5.0, flail 10.0 kW/m; seen only in search results): https://ag.arizona.edu/crop/equipment/agmgttable2.pdf
104. Pronar, "Spreader FD1-M03 & FD1-M05" (single disc, 11 kW power requirement; seen in search results): https://pronar.pl/en/produkt/spreader-fd1-m03-fd1-m05/
105. City of Caliente, "Request for equipment purchase through solicitation: rebuilt refuse collection truck", 2022 (40 yd³ front loader, items 18-19; read in full): https://cityofcaliente.com/wp-content/uploads/2022/12/Request-for-Equipment-Purchase-Through-Soliciation-Rebuilt-Refuse-Collection-Truck.pdf
106. John Deere, operator's manual OMETN78900, "Engine (on Tractors 6170R to 6210R)" (seen in a search excerpt; the page refused the connection): http://manuals.deere.com/omview/OMETN78900_19/OULXBER,0001903_19_20120306.html
107. TractorData, "John Deere 6175R" (rear PTO: 540@1950, 1000@1950 engine rpm): https://www.tractordata.com/farm-tractors/007/9/3/7930-john-deere-6175r.html
108. US 8,175,790, "Engine droop governor and method" (seen in search results): https://patents.justia.com/patent/8175790
109. US 8,991,143, "Work vehicle with a mower unit" (seen in search results): https://patents.google.com/patent/US8991143
110. K. Th. Renius and R. Resch, "Continuously Variable Tractor Transmissions", ASAE Distinguished Lecture Series No. 29, February 2005 (read in full): https://elibrary.asabe.org/data/pdf/6/cvtt2005/lectureseries29rev.pdf
111. US 11,994,210, "Method and system for controlling the acceleration of a vehicle" (JC Bamford Excavators; read): https://patents.google.com/patent/US11994210B2/en
112. Pleinchamp, "John Deere : la variation continue et l'autoguidage pour les tracteurs 6M", 2020 (seen in a search summary): https://www.pleinchamp.com/actualite/john-deere-la-variation-continue-et-l-autoguidage-pour-les-tracteurs-6m
113. Navistar service bulletin to NHTSA, MC-10189738, 2021 (PTO parameters in Cummins INSITE; seen in a search summary): https://static.nhtsa.gov/odi/tsbs/2021/MC-10189738-0001.pdf
114. NHTSA recall report 22V-172 (the PTO neutral interlock not enabled in the Cummins ECM; seen in a search summary): https://static.nhtsa.gov/odi/rcl/2022/RCLRPT-22V172-2139.PDF
115. Cummins, "Truck equipment manufacturers and body builders" (PTO engine-speed control interfaces; seen in a search summary): https://selfscreening.cummins.com/engines/truck/truck-equipment-manufacturers-and-body-builders
116. SPN 976, PTO governor state, J1939 (DIMO's field reference; secondary to SAE J1939DA): https://docs.dimo.org/dimo-explorer/field-descriptions-in-detail/j1939-heavy-truck/assorted-signals/ptogovernorstatej1939-spn-976
117. Toromont Power Systems, "Engine Speed Governors" (droop and isochronous; seen in a search summary): https://www.toromontpowersystems.com/pdf/ConsultantsCorner/Engine%20Speed%20Governors.pdf
118. US 6,553,302, "Work vehicle with operator selected load control and fuel economy control" (Deere & Company; CA 2352906; description and claims read): https://patents.google.com/patent/US6553302B2/en
119. US 8,494,731 (US 2013/0126257), "Method of controlling gear ratio rate of change in continuously variable transmission" (Caterpillar; partly read): https://patents.google.com/patent/US20130126257A1/en
120. J. H. Woodrooffe, M. El-Gindy (NRC Canada), "Application of handling and roll stability performance measures for determining a suitable tractor wheelbase", *Heavy vehicles and roads: technology, safety and policy*, Thomas Telford, London, 1992 (the three-point understeer measure): https://hvttforum.org/wp-content/uploads/2019/11/Application-of-handling-and-roll-stability-performance-measures-for-determining-a-suitable-tractor-wheelbase-Woodrooffe-.pdf
121. R. D. Ervin, R. L. Nisonger, C. C. MacAdam, P. S. Fancher, *Influence of Size and Weight Variables on the Stability and Control Properties of Heavy Trucks*, Vol. I, UMTRI-83-10/1 (FHWA/RD-83/029), 1983 (scanned; pp. 37-38, 56-59 read): https://www.comt.ca/english/programs/trucking/Stability/UMTRI%20Influence%20of%20Size%20and%20Weight%20Variables%20on%20Stability%20and%20Control%20Properties%20of%20Heavy%20Trucks%201983.pdf
122. G. J. Forkenbrock, W. R. Garrott (NHTSA VRTC), *Testing the Dynamic Rollover Resistance of Two 15-Passenger Vans With Multiple Load Configurations*, DOT HS 809 704, 2004: https://rosap.ntl.bts.gov/view/dot/16484/dot_16484_DS1.pdf
123. US 7,243,934, "Multi-link rear suspension system" (Hyundai Motor; U.-K. Lee et al.; 2007; the description read): https://patents.google.com/patent/US7243934B2/en
124. US 4,061,364, "Leaf spring suspension system" (General Motors; R. R. Parks; 1977; the description read): https://patents.google.com/patent/US4061364A/en
125. US 4,004,826, "Leaf spring suspension system" (General Motors; J. W. Subhedar; 1977; the description and claims 1-5 read): https://patents.google.com/patent/US4004826A/en
126. RACE Software, "Compliance steer" (suspension designer library; a KPI overview, no figures): https://race.software/academy/suspension-designer-library/compliance-steer/
