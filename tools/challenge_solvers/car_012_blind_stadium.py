"""GPS self-driving: the invisible stadium is two 40 m straights joined by two 15 m half circles.
The car starts in the middle of one straight, heading 30 degrees, and drives one lap anticlockwise
at 20 km/h, steering from the GPS position."""
from carlito_can import (
    connect, STEER_PROPORTIONAL, STEER_BANGBANG, CRUISE_CONTROL_PI, CRUISE_CONTROL_BANGBANG,
    arc, D, IGNITION)

# The track's centre line. The half circles' centres are 20 m either side of the stadium's centre
# (60, -60), along the straights; the first point of the first half circle is the hint's first GPS
# point (48.8572272, 2.3533331), i.e. x = 83.0, z = -69.8.
TRACK = (arc(70.0, -77.3, 15, 120, -60)         # first half circle, left
         + arc(50.0, -42.7, 15, 300, 120)       # second half circle, left
         + [(73.0, -52.5),                      # back at the start...
            (78.0, -61.2)])                     # ...and a little further, to finish the lap

car = connect()
car.wait_start("car_blind_stadium")
car.key = IGNITION
car.gear = D
while car.tick():
    car.cruise(20, CRUISE_CONTROL_PI)  # also try CRUISE_CONTROL_BANGBANG
    car.follow(TRACK, STEER_PROPORTIONAL)  # also try STEER_BANGBANG
car.finish()
