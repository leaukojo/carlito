"""Easy turns: follow the winding road at 25 km/h. The road is four 35 m bends that touch,
right, left, right, left, around four centre points; the finish line is at the end of the last."""
from carlito_can import (
    connect, STEER_PURE_PURSUIT, STEER_BANGBANG, CRUISE_CONTROL_PI, CRUISE_CONTROL_BANGBANG,
    arc, D)

# The road's centre line: arc(centre x, centre z, radius, from bearing, to bearing).
ROAD = (arc(-135.0, 90.0, 35, 0, 70)            # right
        + arc(-69.2, 66.1, 35, 250, 110)        # left
        + arc(-3.4, 90.0, 35, 290, 430)         # right
        + arc(62.3, 66.1, 35, 250, 180)         # left, ends on the finish line
        + [(80.0, 101.1)])                      # a little past it

car = connect()
car.wait_start("car_easy_turns")
car.gear = D
while car.tick():
    car.cruise(25, CRUISE_CONTROL_PI)  # also try CRUISE_CONTROL_BANGBANG
    car.follow(ROAD, STEER_PURE_PURSUIT)  # also try STEER_BANGBANG
car.finish()
