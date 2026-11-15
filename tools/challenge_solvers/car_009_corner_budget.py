"""Perfect turns: the Easy turns road again, at 36 km/h. On a 35 m bend that is
(36 / 3.6)^2 / 35 = 2.9 m/s^2 sideways, under the 4.0 limit, and fast enough for the time limit."""
from carlito_can import (
    connect, STEER_PURE_PURSUIT, STEER_BANGBANG, CRUISE_CONTROL_PI, CRUISE_CONTROL_BANGBANG,
    arc, D)

# The road's centre line, as in car_002_easy_turns.py. The cut zones are 9.5 m inside it.
ROAD = (arc(-135.0, 90.0, 35, 0, 70)            # right
        + arc(-69.2, 66.1, 35, 250, 110)        # left
        + arc(-3.4, 90.0, 35, 290, 430)         # right
        + arc(62.3, 66.1, 35, 250, 180)         # left, ends on the finish line
        + [(80.0, 101.1)])                      # a little past it

car = connect()
car.wait_start("car_corner_budget")
car.gear = D
while car.tick():
    car.cruise(36, CRUISE_CONTROL_PI)  # also try CRUISE_CONTROL_BANGBANG
    car.follow(ROAD, STEER_PURE_PURSUIT)  # also try STEER_BANGBANG
car.finish()
