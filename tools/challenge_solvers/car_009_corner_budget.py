"""Perfect turns: the Easy turns road again, at 38 km/h. On a 35 m bend that is
(38 / 3.6)^2 / 35 = 3.2 m/s^2 sideways, under the 4.0 limit, and fast enough for the time limit."""
from carlito_can import connect, arc, D, IGNITION

# The road's centre line, as in car_002_easy_turns.py. The cut zones are 9.5 m inside it.
ROAD = (arc(-135.0, 90.0, 35, 0, 70)            # right
        + arc(-69.2, 66.1, 35, 250, 110)        # left
        + arc(-3.4, 90.0, 35, 290, 430)         # right
        + arc(62.3, 66.1, 35, 250, 180)         # left, ends on the finish line
        + [(80.0, 101.1)])                      # a little past it

car = connect()
car.wait_start("car_corner_budget")
car.key = IGNITION
car.gear = D
while car.tick():
    car.cruise(38)
    car.follow(ROAD)
car.finish()
