
import math

def sonntag_vapor_pressure(temp_c):
    T = temp_c + 273.15
    # Over ice for T < 0
    # Sonntag (1990)
    if temp_c < 0.01:
        ln_es = -6024.5282 / T + 29.32707 + 1.0613868e-2 * T - 1.3198825e-5 * T**2 - 0.49382577 * math.log(T)
    else:
        # Over water
        ln_es = -6096.9385 / T + 21.2409642 - 2.711193e-2 * T + 1.673952e-5 * T**2 + 2.433502 * math.log(T)
    return math.exp(ln_es)

def calculate_ppm(temp_c, pressure_pa=101325): # Standard atm pressure
    es = sonntag_vapor_pressure(temp_c)
    return (es / (pressure_pa - es)) * 1e6

points = [
    (-1, 5515),
    (-2, 5125),
    (-10, 2786),
    (-20, 1222),
    (-30, 497),
    (-38.70, -1), # User query: check exact value
    (-39, 205),
    (-40, 185),
    (-50, 62),
    (-60, 18),
    (-70, 5),
    (-80, -1) # User query: check limit
]

with open('verification_result.txt', 'w') as f:
    f.write(f'{"Temp(C)":<10} | {"Calc PPM":<15} | {"Target":<10} | {"Diff":<10}\n')
    f.write('-'*55 + '\n')
    for t, target in points:
        ppm = calculate_ppm(t)
        diff = ppm - target
        f.write(f'{t:<10} | {ppm:<15.2f} | {target:<10} | {diff:<10.2f}\n')
