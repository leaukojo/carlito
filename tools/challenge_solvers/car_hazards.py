"""Hazard lights: there is no hazard signal, so both turn lamps are switched on and off
together, 1.5 times a second (the challenge accepts 1 to 2 Hz), while the car stands still."""
import time

from carlito_can import connect

car = connect()
car.wait_start("car_hazards")
while car.tick(0.02):
    lit = time.monotonic() % (1 / 1.5) < (0.5 / 1.5)   # on for the first half of each period
    car.turn_left = car.turn_right = lit
car.finish()
