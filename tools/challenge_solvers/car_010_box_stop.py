"""Stop in the box: hold 55 km/h to the gate at x = 20, then brake as hard as possible. From
55 km/h the car stops about 17 m later, near the middle of the box (x = 28 to 46). The x
position comes from the GPS."""
from carlito_can import (
    connect, STEER_PROPORTIONAL, STEER_BANGBANG, CRUISE_CONTROL_PI, CRUISE_CONTROL_BANGBANG, D)

car = connect()
car.wait_start("car_box_stop")
car.gear = D
while car.running and car.x < 20.5:     # until just past the gate
    car.cruise(55, CRUISE_CONTROL_PI)  # also try CRUISE_CONTROL_BANGBANG
    # aim 20 m ahead on the line z = 0
    car.steer_to(car.x + 20, 0, STEER_PROPORTIONAL)  # also try STEER_BANGBANG
    car.tick()
car.accel = 0
car.brake = 100
while car.running and car.kmh > 0.5:
    car.steer_to(car.x + 20, 0, STEER_PROPORTIONAL)
    car.tick()
car.handbrake = True                    # stopped: now stay still
car.finish()
