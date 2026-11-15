"""Stop in the box (blind): the same solve as car_010_box_stop.py, but the distance comes from the
odometer instead of the GPS: the gate is 170 m from the start. The fog does not matter on CAN."""
from carlito_can import (
    connect, STEER_PROPORTIONAL, STEER_BANGBANG, CRUISE_CONTROL_PI, CRUISE_CONTROL_BANGBANG, D)

car = connect()
car.wait_start("car_box_blind")
start_odo = car.odo                     # odometer reading at the start, in metres
car.gear = D
while car.running and car.odo - start_odo < 171:   # until just past the gate
    car.cruise(55, CRUISE_CONTROL_PI)  # also try CRUISE_CONTROL_BANGBANG
    car.steer_to(200, 0, STEER_PROPORTIONAL)  # the road runs along z = 0; also try STEER_BANGBANG
    car.tick()
car.accel = 0
car.brake = 100
while car.running and car.kmh > 0.5:
    car.tick()
car.handbrake = True                    # stopped: now stay still
car.finish()
