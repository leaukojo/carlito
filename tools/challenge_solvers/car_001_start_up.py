"""Start up: gear in D, a gentle 40 % on the accelerator, aimed at the finish line. The key is
yours: turn the RAMN's key to Ignition (the demo's Control panel key starts there)."""
from carlito_can import connect, STEER_PROPORTIONAL, STEER_BANGBANG, D

car = connect()
car.wait_start("car_start_up")
car.gear = D
car.accel = 40          # not 100: flooring it from a standstill spins the wheels
while car.tick():
    # the finish line crosses the road at x = 50, 200 m ahead
    car.steer_to(50, 0, STEER_PROPORTIONAL)  # also try STEER_BANGBANG
car.finish()
