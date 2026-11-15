"""Hazard lights: there is no hazard signal, so both turn lamps are commanded on together while
the car stands still. RAMN's ECU D flashes them at 1 Hz (the challenge accepts 0.8 to 2 Hz)."""
from carlito_can import connect

car = connect()
car.wait_start("car_hazards")
car.turn_left = True
car.turn_right = True
car.finish()
