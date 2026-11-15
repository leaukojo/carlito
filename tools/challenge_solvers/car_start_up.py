"""Start up: key on, gear in D, a gentle 40 % on the accelerator, aimed at the finish line."""
from carlito_can import connect, D, IGNITION

car = connect()
car.wait_start("car_start_up")
car.key = IGNITION
car.gear = D
car.accel = 40          # not 100: flooring it from a standstill spins the wheels
while car.tick():
    car.steer_to(50, 0)  # the finish line crosses the road at x = 50, 200 m ahead
car.finish()
