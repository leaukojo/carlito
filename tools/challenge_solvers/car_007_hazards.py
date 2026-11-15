"""Hazard lights: there is no hazard signal, so both turn lamps are switched on and off
together, 1.5 times a second (the challenge accepts 1 to 2 Hz), while the car stands still."""
import time

from carlito_can import connect

car = connect()
car.wait_start("car_hazards")
while car.running:
    # One blink lasts 1 / 1.5 = 0.67 s: lamps on for half of it, off for the other half.
    car.turn_left = True
    car.turn_right = True
    time.sleep(0.33)
    car.turn_left = False
    car.turn_right = False
    time.sleep(0.33)
car.finish()
