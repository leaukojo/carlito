"""Speed trap: a cruise control holds 60 km/h (the trap wants 58 to 62) all the way, while the
car steers at a point far down the straight."""
from carlito_can import connect, CRUISE_CONTROL_PI, CRUISE_CONTROL_BANGBANG, D, IGNITION

car = connect()
car.wait_start("car_speed_trap")
car.key = IGNITION
car.gear = D
while car.tick():
    car.cruise(60, CRUISE_CONTROL_PI)  # also try CRUISE_CONTROL_BANGBANG
    car.steer_to(200, 0)  # the trap runs along z = 0, from x = -40 to x = 120
car.finish()
