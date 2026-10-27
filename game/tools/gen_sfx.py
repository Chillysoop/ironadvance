#!/usr/bin/env python3
"""Synthesizes the chiptune sound effects into assets/sfx/*.wav (16-bit mono 22050 Hz).

Run from the project root:  python3 tools/gen_sfx.py
"""
import math, os, random, struct, wave

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'sfx')
rnd = random.Random(5)

def tone(f, d, kind='square', vol=0.3, slide=0.0, at=0.0):
    n = int(SR * d)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / n
        fr = f * ((max(30, f + slide) / f) ** t) if slide else f
        ph += fr / SR
        x = ph % 1.0
        if kind == 'square': v = 1.0 if x < 0.5 else -1.0
        elif kind == 'triangle': v = 4 * abs(x - 0.5) - 1
        elif kind == 'sawtooth': v = 2 * x - 1
        else: v = math.sin(ph * 2 * math.pi)
        env = (1 - t) ** 2
        out.append(v * vol * env)
    return (at, out)

def noise(d, vol=0.5, lp=1200, at=0.0, decay=2.0):
    n = int(SR * d)
    out = []
    a = min(1.0, 2 * math.pi * lp / SR)
    y = 0.0
    for i in range(n):
        y += a * ((rnd.random() * 2 - 1) - y)
        out.append(y * vol * 3 * (1 - i / n) ** decay)
    return (at, out)

def mix(parts, tail=0.02):
    length = max(int(at * SR) + len(s) for at, s in parts) + int(tail * SR)
    buf = [0.0] * length
    for at, s in parts:
        o = int(at * SR)
        for i, v in enumerate(s):
            buf[o + i] += v
    peak = max(1e-6, max(abs(v) for v in buf))
    if peak > 0.95:
        buf = [v * 0.95 / peak for v in buf]
    return buf

def save(name, buf):
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v)) * 32767)) for v in buf))

def arp(notes, step, d, kind='square', vol=0.25):
    return [tone(f, d, kind, vol, 0, i * step) for i, f in enumerate(notes)]

SFX = {
    'shot':   lambda: mix([noise(0.09, 0.6, 3200), tone(240, 0.06, 'square', 0.25, -160)]),
    'mg':     lambda: mix([noise(0.06, 0.6, 2400), tone(180, 0.05, 'square', 0.2, -100)]),
    'snipe':  lambda: mix([noise(0.18, 0.7, 4200, decay=3), tone(520, 0.12, 'square', 0.25, -440), tone(90, 0.2, 'sine', 0.4, -40)]),
    'boom':   lambda: mix([noise(0.8, 0.9, 520, decay=1.6), tone(90, 0.5, 'sine', 0.6, -60), noise(0.25, 0.5, 2400, decay=3)]),
    'bigboom': lambda: mix([noise(1.3, 1.0, 380, decay=1.3), tone(70, 0.8, 'sine', 0.7, -40), noise(0.3, 0.6, 3000, decay=3)]),
    'thud':   lambda: mix([noise(0.4, 0.8, 260), tone(60, 0.3, 'sine', 0.6, -20)]),
    'bonk':   lambda: mix([tone(140, 0.12, 'square', 0.35, -60)]),
    'ping':   lambda: mix([tone(1800, 0.08, 'triangle', 0.3, -600), tone(2400, 0.05, 'triangle', 0.15, -900, 0.01)]),
    'click':  lambda: mix([tone(660, 0.04, 'square', 0.2)]),
    'select': lambda: mix([tone(880, 0.07, 'square', 0.2, 240)]),
    'hurt':   lambda: mix([tone(190, 0.18, 'sawtooth', 0.4, -110)]),
    'coin':   lambda: mix([tone(988, 0.08, 'square', 0.25), tone(1319, 0.22, 'square', 0.25, 0, 0.08)]),
    'start':  lambda: mix(arp([523, 659, 784, 1046], 0.08, 0.13)),
    'power':  lambda: mix(arp([392, 523, 659, 784, 1046, 1318], 0.05, 0.1, 'sawtooth', 0.2)),
    'levelup': lambda: mix(arp([523, 659, 784, 1046, 784, 1046, 1318, 1568], 0.06, 0.12, 'square', 0.2)),
    'alarm':  lambda: mix([tone(440, 0.16, 'square', 0.3, 240), tone(440, 0.16, 'square', 0.3, 240, 0.19)]),
    'toss':   lambda: mix([tone(320, 0.12, 'triangle', 0.4, 320)]),
    'splash': lambda: mix([noise(0.5, 0.6, 900)]),
    'bad':    lambda: mix([tone(150, 0.4, 'square', 0.35, -70)]),
    'slash':  lambda: mix([noise(0.1, 0.6, 6000)]),
    'tick':   lambda: mix([tone(1200, 0.025, 'square', 0.15)]),
    'scream': lambda: mix([tone(620, 0.35, 'sawtooth', 0.25, -380), tone(640, 0.3, 'square', 0.1, -400, 0.02)]),
    'buy':    lambda: mix(arp([784, 988, 1175], 0.05, 0.09)),
    'deny':   lambda: mix([tone(220, 0.1, 'square', 0.25), tone(180, 0.14, 'square', 0.25, 0, 0.1)]),
    'step':   lambda: mix([noise(0.03, 0.2, 800)]),
    'land':   lambda: mix([noise(0.08, 0.35, 500)]),
    'rocket': lambda: mix([noise(0.35, 0.5, 1600, decay=1), tone(200, 0.3, 'sawtooth', 0.12, 300)]),
}

if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for k, f in SFX.items():
        save(k, f())
    print('sfx generated:', len(SFX))
