"""Manual gearbox: first gear, accelerator floored, and one gear up each time the engine nears its
6800 rpm redline. The finish line is 200 m down the straight."""
import time

from carlito_can import connect, STEER_PROPORTIONAL, STEER_BANGBANG

car = connect()
car.wait_start("car_manual_gearbox")
car.gear = 1
car.accel = 100
while car.tick():
    car.steer_to(200, 0, STEER_PROPORTIONAL)  # the road runs along z = 0; also try STEER_BANGBANG
    if car.rpm > 6300 and car.gear < 6:
        car.gear = car.gear + 1     # shift up
        time.sleep(0.3)             # give the rpm reading time to drop before checking again
car.finish()
