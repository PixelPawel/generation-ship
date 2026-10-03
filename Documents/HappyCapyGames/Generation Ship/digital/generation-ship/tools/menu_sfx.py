"""Synthesised sound effects for the parked-cockpit main menu (placeholders until
real sound design): idle hum loop, power-up, console blips, relay click, hull
creak, screen static, spark.

    python tools/menu_sfx.py   -> assets/effects/menu/*.wav
"""
import os
import numpy as np
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "effects", "menu")
rng = np.random.default_rng(7)


def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


def env(n, attack=0.01, release=0.1):
    e = np.ones(n)
    a = max(1, int(SR * attack))
    r = max(1, int(SR * release))
    e[:a] = np.linspace(0, 1, a)
    e[-r:] *= np.linspace(1, 0, r)
    return e


def lowpass(x, cutoff):
    # one-pole low-pass
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def bandpass_noise(n, centre, q=6.0):
    noise = rng.standard_normal(n)
    # resonant 2-pole band-pass (biquad)
    w0 = 2 * np.pi * centre / SR
    alpha = np.sin(w0) / (2 * q)
    b0, b2 = alpha, -alpha
    a0, a1, a2 = 1 + alpha, -2 * np.cos(w0), 1 - alpha
    y = np.zeros(n)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(n):
        x0 = noise[i]
        y0 = (b0 * x0 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        y[i] = y0
        x2, x1 = x1, x0
        y2, y1 = y1, y0
    return y


def save(name, x, peak=0.8):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    print(name, round(len(x) / SR, 2), "s")


# idle hum: 8 s, every partial a whole number of cycles so it loops seamlessly
L = 8.0
t = t_axis(L)
hum = (np.sin(2 * np.pi * 55 * t) * 0.6 + np.sin(2 * np.pi * 110 * t) * 0.25
       + np.sin(2 * np.pi * 165 * t) * 0.1 + np.sin(2 * np.pi * 220.25 * t) * 0.05)
hum *= 0.8 + 0.2 * np.sin(2 * np.pi * 0.25 * t)            # slow breathing, 2 cycles per loop
air = lowpass(rng.standard_normal(len(t)), 300) * 0.4
air -= np.linspace(air[0], air[-1], len(air))               # ends meet for the loop
save("ship_hum_loop.wav", hum + air, peak=0.5)

# power-up: relay clicks, rising whine, thump, bright chime
t = t_axis(2.4)
f = 70 + (420 - 70) * (t / 2.4) ** 1.6
whine = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.5 + np.sin(2 * np.pi * np.cumsum(f * 2.01) / SR) * 0.18
whine *= np.clip(t / 2.0, 0, 1) * env(len(t), 0.05, 0.25)
x = whine.copy()
for c in (0.05, 0.16, 0.27):                                # relays catching
    i = int(c * SR)
    click = rng.standard_normal(300) * np.exp(-np.arange(300) / 40)
    x[i:i + 300] += click * 0.9
i = int(2.0 * SR)                                           # the thump as everything comes on
tt = np.arange(len(x) - i) / SR
x[i:] += np.sin(2 * np.pi * (60 - 20 * tt) * tt) * np.exp(-tt * 6) * 1.2
x[i:] += (np.sin(2 * np.pi * 1318.5 * tt) + 0.6 * np.sin(2 * np.pi * 1975.5 * tt)) * np.exp(-tt * 3) * 0.25
save("ship_power_up.wav", x)

# console blips: little tone patterns
for k, notes in enumerate([(1760, 2349), (1318, 1760, 1318), (2093, 1568, 2637)]):
    parts = []
    for fq in notes:
        tt = t_axis(0.06)
        tone = np.sign(np.sin(2 * np.pi * fq * tt)) * 0.25 + np.sin(2 * np.pi * fq * tt) * 0.75
        parts.append(tone * env(len(tt), 0.003, 0.02))
        parts.append(np.zeros(int(SR * 0.035)))
    save("console_blip_%d.wav" % (k + 1), lowpass(np.concatenate(parts), 6000), peak=0.45)

# relay click
n = int(SR * 0.12)
x = np.zeros(n)
for c, amp in ((0.0, 1.0), (0.045, 0.6)):
    i = int(c * SR)
    m = min(500, n - i)
    x[i:i + m] += rng.standard_normal(m) * np.exp(-np.arange(m) / 60) * amp
save("relay_click.wav", lowpass(x, 5000), peak=0.6)

# hull creak: resonant noise sliding in pitch
t = t_axis(1.4)
x = np.zeros(len(t))
for centre in (180, 260):
    seg = bandpass_noise(len(t), centre, q=18.0)
    x += seg * (np.sin(np.pi * t / 1.4) ** 2) * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * t))
save("hull_creak.wav", x, peak=0.5)

# screen static
t = t_axis(0.45)
x = rng.standard_normal(len(t)) * (0.5 + 0.5 * (rng.random(len(t)) > 0.97))
x *= env(len(t), 0.005, 0.15) * (0.6 + 0.4 * np.sin(2 * np.pi * 60 * t))
save("screen_static.wav", lowpass(x, 7000), peak=0.35)

# spark: crackles
t = t_axis(0.5)
x = np.zeros(len(t))
for _ in range(14):
    i = int(rng.random() * (len(t) - 800))
    x[i:i + 800] += rng.standard_normal(800) * np.exp(-np.arange(800) / 90) * rng.random()
x += bandpass_noise(len(t), 3200, q=3.0) * np.exp(-t * 8) * 0.4
save("spark.wav", x, peak=0.6)
