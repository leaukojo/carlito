"""Signal your turns: follow the road's four corners (left, right, right, left) at 25 km/h. The
lamp for the next corner is on through the 30 m straight before it and off at the corner, well
before the "lamp off" window that starts after it. It is commanded steady: RAMN's ECU D flashes it."""
from carlito_can import (
    connect, STEER_PROPORTIONAL, STEER_BANGBANG, CRUISE_CONTROL_PI, CRUISE_CONTROL_BANGBANG,
    arc, D)

# The road's centre line: straights joined by 15 m corners.
ROAD = (arc(-85.0, -50.0, 15, 180, 90)          # corner 1, left
        + arc(-55.0, -110.0, 15, 270, 360)      # corner 2, right
        + arc(5.0, -110.0, 15, 0, 90)           # corner 3, right
        + arc(35.0, -50.0, 15, 270, 180)        # corner 4, left
        + [(105.0, -35.0)])                     # the last straight, through the finish at x = 90


def inside(x_min, x_max, z_min, z_max):
    """True while the car is inside this rectangle of the map."""
    return x_min < car.x < x_max and z_min < car.z < z_max


car = connect()
car.wait_start("car_turn_signals")
car.gear = D
while car.tick():
    car.cruise(25, CRUISE_CONTROL_PI)  # also try CRUISE_CONTROL_BANGBANG
    car.follow(ROAD, STEER_PROPORTIONAL)  # also try STEER_BANGBANG
    # The 30 m straight before each corner, a little longer at its start.
    before_1 = inside(-120, -85, -47, -23)
    before_2 = inside(-82, -58, -110, -75)
    before_3 = inside(-30, 5, -137, -113)
    before_4 = inside(8, 32, -85, -50)
    car.turn_left = before_1 or before_4
    car.turn_right = before_2 or before_3
car.finish()
