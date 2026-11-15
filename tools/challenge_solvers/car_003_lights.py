"""Lights: low beams on first, then follow the causeway at 30 km/h. The causeway is a gentle S
of three 70 m bends across the lagoon: driving straight would end in the water."""
from carlito_can import connect, arc, D, IGNITION, LOW

# The causeway's centre line, from the start to past the finish line at x = 59.3.
CAUSEWAY = ([(-59.0, 143.0)]                    # the straight lead
            + arc(-59.0, 213.0, 70, 0, 25)      # right
            + arc(0.2, 86.1, 70, 205, 155)      # left
            + arc(59.3, 213.0, 70, 335, 360)    # right, ends on the finish line
            + [(100.0, 143.0)])                 # the straight after it

car = connect()
car.wait_start("car_lights")
car.lights = LOW
car.key = IGNITION
car.gear = D
while car.tick():
    car.cruise(30)
    car.follow(CAUSEWAY)
car.finish()
