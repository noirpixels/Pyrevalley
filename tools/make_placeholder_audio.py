"""Generates the prototype's placeholder sound effects and music into audio/.

Pure Python (no dependencies). Re-run to regenerate:  python3 tools/make_placeholder_audio.py
Replace any file in audio/ with a real sound of the same name to upgrade it.
"""
import math, random, struct, wave, os

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
random.seed(7)


def write(name, samples):
    peak = max(1e-6, max(abs(s) for s in samples))
    scale = 0.8 / peak if peak > 0.8 else 1.0
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767)) for s in samples))


def env(i, n, attack=0.01, curve=2.0):
    t = i / n
    a = min(1.0, t / attack) if attack > 0 else 1.0
    return a * (1.0 - t) ** curve


def tone(freq_fn, dur, wave_fn=math.sin, attack=0.01, curve=2.0, vol=1.0):
    n = int(RATE * dur)
    out, phase = [], 0.0
    for i in range(n):
        phase += 2 * math.pi * freq_fn(i / n) / RATE
        out.append(wave_fn(phase) * env(i, n, attack, curve) * vol)
    return out


def noise(dur, attack=0.01, curve=2.0, vol=1.0, smooth=0.0):
    n = int(RATE * dur)
    out, last = [], 0.0
    for i in range(n):
        last = last * smooth + random.uniform(-1, 1) * (1 - smooth)
        out.append(last * env(i, n, attack, curve) * vol)
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] for t in tracks if i < len(t)) for i in range(n)]


def square(p):
    return 1.0 if math.sin(p) >= 0 else -1.0


def sweep(f0, f1):
    return lambda t: f0 + (f1 - f0) * t


os.makedirs(OUT, exist_ok=True)

write("attack", mix(noise(0.16, 0.2, 1.5, 0.7, smooth=0.6), tone(sweep(900, 300), 0.16, vol=0.15)))
write("enemy_attack", mix(noise(0.2, 0.3, 1.5, 0.6, smooth=0.8), tone(sweep(220, 110), 0.2, vol=0.3)))
write("hit", mix(tone(sweep(180, 60), 0.12, vol=0.9), noise(0.05, 0.0, 3.0, 0.5)))
write("enemy_death", mix(tone(sweep(400, 70), 0.45, square, vol=0.25), noise(0.4, 0.01, 2.0, 0.4, smooth=0.7)))
write("player_hurt", mix(tone(sweep(260, 140), 0.22, square, vol=0.35), noise(0.08, 0.0, 2.0, 0.3)))
write("pickup", tone(lambda t: 660 if t < 0.4 else 990, 0.28, curve=1.5, vol=0.5))
write("npc", tone(lambda t: 520 + 30 * math.sin(t * 40), 0.08, vol=0.35))
write("ui_click", tone(lambda t: 1400, 0.035, curve=3.0, vol=0.4))
write("checkpoint", mix(*[tone(lambda t, f=f: f, 0.9, attack=0.05, curve=1.5, vol=0.25) for f in (220, 277, 330, 440)]))
write("gate_open", mix(noise(1.1, 0.5, 1.0, 0.5, smooth=0.9), tone(sweep(110, 440), 1.1, attack=0.4, curve=1.0, vol=0.3)))
write("boss_attack", mix(tone(sweep(90, 30), 0.7, vol=1.0), noise(0.6, 0.0, 2.5, 0.6, smooth=0.85)))
write("boss_death", mix(tone(sweep(160, 25), 2.2, attack=0.02, curve=1.2, vol=0.8),
                        noise(2.2, 0.05, 1.5, 0.6, smooth=0.92)))

# Dark forest drone: low minor chord with slow beating, sparse bell notes.
dur = 24.0
n = int(RATE * dur)
music = []
bells = [(2.0, 440.0), (7.5, 523.25), (12.0, 392.0), (17.5, 349.23), (21.0, 329.63)]
for i in range(n):
    t = i / RATE
    s = 0.0
    for f, v in ((55.0, 0.35), (55.4, 0.3), (82.41, 0.18), (65.41, 0.16), (110.0, 0.08)):
        s += math.sin(2 * math.pi * f * t) * v
    s *= 0.6 + 0.4 * math.sin(2 * math.pi * t / dur)  # slow swell, loops cleanly
    for start, f in bells:
        if t >= start:
            dt = t - start
            s += math.sin(2 * math.pi * f * dt) * math.exp(-dt * 1.2) * 0.12
    music.append(s)
# Short crossfade so the loop point doesn't click
fade = int(RATE * 0.5)
for i in range(fade):
    k = i / fade
    music[i] *= k
    music[n - 1 - i] *= k
write("music_forest", music)
print("wrote", sorted(os.listdir(OUT)))
