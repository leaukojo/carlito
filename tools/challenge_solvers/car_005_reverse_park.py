"""Reverse park: drive east, turn right to face south on the bay's line (x = -125), and stop 22 m
south of the bay. Then reverse north slowly, steering to hold that line, and stop on the bay's
centre (z = -83.7). The bay is only 0.4 m wider than the wheels on each side, so the position
comes from the GPS (centimetre precision)."""
from carlito_can import (
    connect, STEER_PURE_PURSUIT, STEER_BANGBANG, CRUISE_CONTROL_PI, CRUISE_CONTROL_BANGBANG,
    arc, clamp, D, R)

BAY_X, BAY_Z = -125.0, -83.7

# 1. Forward: a right turn onto the bay's line, then straight south.
APPROACH = arc(-133.0, -68.4, 8, 0, 90) + [(BAY_X, -50.0)]

car = connect()
car.wait_start("car_reverse_park")
car.gear = D
while car.running and car.z < -62:
    car.cruise(8, CRUISE_CONTROL_PI)  # also try CRUISE_CONTROL_BANGBANG
    car.follow(APPROACH, STEER_PURE_PURSUIT, lookahead=4)  # also try STEER_BANGBANG
    car.tick()
car.accel = 0
car.brake = 100
while car.running and car.kmh > 0.1:
    car.tick()

# 2. Reverse north into the bay.
car.gear = R
car.brake = 0
while car.running and car.z > BAY_Z + 0.2:      # stop a little early: the car needs time to stop
    car.cruise(3, CRUISE_CONTROL_PI)  # also try CRUISE_CONTROL_BANGBANG
    # Too far east? Point the nose a little east, so backing up moves the car west (and the
    # other way round). 10 degrees per metre off the line, at most 15 degrees.
    off_line = car.x - BAY_X
    want_heading = 180 - clamp(10 * off_line, -15, 15)
    # Reversing turns the car the other way: steering right makes the heading go down.
    car.steer = -4 * (want_heading - car.heading)
    car.tick()
car.accel = 0
car.brake = 100
car.steer = 0
car.handbrake = True
car.finish()
