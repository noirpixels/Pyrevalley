"""Synthesizes Pyrevalley's sound effects, ambience and music into audio/.

Pure Python (no dependencies). Re-run to regenerate:  python3 tools/make_audio.py
Replace any file in audio/ with a recorded sound of the same name to upgrade it.

Everything is built from a few pieces: filtered noise, swept oscillators,
Karplus-Strong plucks, soft distortion and a small Schroeder reverb, layered
so each sound has a transient, a body and a tail.
"""
import math, random, struct, wave, os, sys

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
random.seed(7)
TAU = 2 * math.pi


# ------------------------------------------------------------
# Output
# ------------------------------------------------------------

def write(name, samples, peak_to=0.89):
    peak = max(1e-6, max(abs(s) for s in samples))
    scale = peak_to / peak
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples))
    print("wrote", name, round(len(samples) / RATE, 2), "s")


# ------------------------------------------------------------
# Building blocks
# ------------------------------------------------------------

def n_of(dur):
    return int(RATE * dur)


def silence(dur):
    return [0.0] * n_of(dur)


def mix(*tracks, offsets=None):
    offsets = offsets or [0.0] * len(tracks)
    length = max(len(t) + n_of(o) for t, o in zip(tracks, offsets))
    out = [0.0] * length
    for t, o in zip(tracks, offsets):
        start = n_of(o)
        for i, s in enumerate(t):
            out[start + i] += s
    return out


def gain(track, g):
    return [s * g for s in track]


def env_exp(dur, attack=0.005, decay=6.0):
    """Fast attack, exponential decay (decay = 1/seconds)."""
    n = n_of(dur)
    a = max(1, n_of(attack))
    return [min(1.0, i / a) * math.exp(-decay * i / RATE) for i in range(n)]


def env_swell(dur, peak=0.5, curve=2.0):
    """Rises to a peak at fraction `peak` of the length, then falls."""
    n = n_of(dur)
    out = []
    for i in range(n):
        t = i / n
        out.append((t / peak) ** curve if t < peak else ((1 - t) / (1 - peak)) ** curve)
    return out


def apply(track, env):
    return [s * e for s, e in zip(track, env)]


def noise(dur):
    return [random.uniform(-1, 1) for _ in range(n_of(dur))]


def lowpass(track, cutoff):
    """One-pole lowpass; cutoff may be a number or a function of t (0..1)."""
    out, y = [], 0.0
    n = len(track)
    for i, x in enumerate(track):
        c = cutoff(i / n) if callable(cutoff) else cutoff
        a = 1.0 - math.exp(-TAU * c / RATE)
        y += a * (x - y)
        out.append(y)
    return out


def highpass(track, cutoff):
    low = lowpass(track, cutoff)
    return [x - l for x, l in zip(track, low)]


def bandpass(track, centre, q=1.5):
    """State-variable bandpass; centre may be a function of t (0..1)."""
    out, low, band = [], 0.0, 0.0
    n = len(track)
    damp = 1.0 / q
    for i, x in enumerate(track):
        c = centre(i / n) if callable(centre) else centre
        f = 2.0 * math.sin(math.pi * min(c, RATE / 6) / RATE)
        low += f * band
        high = x - low - damp * band
        band += f * high
        out.append(band)
    return out


def osc(freq, dur, shape="sine", phase=0.0):
    """freq may be a number or a function of t (0..1)."""
    n = n_of(dur)
    out, p = [], phase
    for i in range(n):
        f = freq(i / n) if callable(freq) else freq
        p += f / RATE
        x = p % 1.0
        if shape == "sine":
            out.append(math.sin(TAU * x))
        elif shape == "saw":
            out.append(2.0 * x - 1.0)
        elif shape == "square":
            out.append(1.0 if x < 0.5 else -1.0)
        elif shape == "tri":
            out.append(4.0 * abs(x - 0.5) - 1.0)
    return out


def sweep(f0, f1, curve=1.0):
    return lambda t: f0 + (f1 - f0) * (t ** curve)


def drive(track, amount):
    return [math.tanh(s * amount) for s in track]


def pluck(freq, dur, bright=0.5, decay=0.996):
    """Karplus-Strong plucked string."""
    period = max(2, int(RATE / freq))
    buf = [random.uniform(-1, 1) for _ in range(period)]
    buf = lowpass(buf, 2000 + bright * 6000)
    out = []
    for i in range(n_of(dur)):
        j = i % period
        s = buf[j]
        nxt = buf[(j + 1) % period]
        buf[j] = decay * 0.5 * (s + nxt)
        out.append(s)
    # The noise burst leaves an offset; take it out
    return highpass(out, 30)


def reverb(track, wet=0.3, size=1.0, tail=1.5):
    """Small Schroeder reverb: four combs into two allpasses."""
    n = len(track) + n_of(tail)
    dry = track + [0.0] * (n - len(track))
    combs = [int(d * size) for d in (1116, 1188, 1277, 1356)]
    fb = 0.8
    acc = [0.0] * n
    for d in combs:
        d = int(d * RATE / 44100)
        buf = [0.0] * d
        idx = 0
        damp_state = 0.0
        for i in range(n):
            y = buf[idx]
            damp_state = y * 0.7 + damp_state * 0.3
            buf[idx] = dry[i] + damp_state * fb
            idx = (idx + 1) % d
            acc[i] += y * 0.25
    for d in (556, 441):
        d = int(d * RATE / 44100)
        buf = [0.0] * d
        idx = 0
        for i in range(n):
            b = buf[idx]
            y = -acc[i] + b
            buf[idx] = acc[i] + b * 0.5
            idx = (idx + 1) % d
            acc[i] = y
    return [d_ * (1 - wet) + a * wet for d_, a in zip(dry, acc)]


def fade_edges(track, fade_in=0.002, fade_out=0.02):
    n = len(track)
    fi, fo = max(1, n_of(fade_in)), max(1, n_of(fade_out))
    out = list(track)
    for i in range(min(fi, n)):
        out[i] *= i / fi
    for i in range(min(fo, n)):
        out[n - 1 - i] *= i / fo
    return out


def thump(f0, f1, dur, decay=10.0):
    return apply(osc(sweep(f0, f1, 0.5), dur), env_exp(dur, 0.002, decay))


def crack(dur=0.02, cutoff=6000):
    return apply(lowpass(noise(dur), cutoff), env_exp(dur, 0.0005, 120))


def whoosh(dur, f0, f_mid, f1, q=2.0):
    def centre(t):
        return f0 + (f_mid - f0) * (t / 0.5) if t < 0.5 else f_mid + (f1 - f_mid) * ((t - 0.5) / 0.5)
    return apply(bandpass(noise(dur), centre, q), env_swell(dur, 0.45, 1.6))


def grains(dur, count, cutoff=2500, size=0.012):
    """Crumbling: many tiny clicks scattered over the length."""
    out = silence(dur)
    for _ in range(count):
        start = random.randint(0, len(out) - n_of(size) - 1)
        g = apply(lowpass(noise(size), cutoff), env_exp(size, 0.0005, 300))
        amp = random.uniform(0.3, 1.0) * (1.0 - start / len(out)) ** 0.7
        for i, s in enumerate(g):
            out[start + i] += s * amp
    return out


def formant(f0, dur, formants, vibrato=0.0, shape="saw"):
    """A voice-like growl: a buzzy source through a few resonances."""
    src = osc(lambda t: f0(t) * (1 + vibrato * math.sin(TAU * 6 * t * dur)) if callable(f0) else f0 * (1 + vibrato * math.sin(TAU * 6 * t * dur)), dur, shape)
    return mix(*[gain(bandpass(src, f, 6.0), g) for f, g in formants])


# ------------------------------------------------------------
# Sound effects
# ------------------------------------------------------------

def make_sfx():
    # Sword swing: a fast, airy cut
    write("attack", fade_edges(mix(
        whoosh(0.2, 500, 2600, 900, 2.5),
        gain(whoosh(0.16, 1200, 5000, 2000, 4.0), 0.35),
    )))

    # Blade into ash and hide: crack, thump, a brief metallic ring
    ring = mix(*[gain(apply(osc(f, 0.25), env_exp(0.25, 0.001, 18)), g) for f, g in ((2150, 0.12), (3320, 0.08), (4710, 0.05))])
    write("hit", fade_edges(mix(
        gain(crack(0.03, 5000), 0.9),
        gain(drive(thump(160, 55, 0.16, 18), 2.0), 0.9),
        gain(apply(lowpass(noise(0.09), 1800), env_exp(0.09, 0.001, 35)), 0.5),
        ring,
    )))

    write("hit_heavy", fade_edges(reverb(mix(
        gain(crack(0.04, 4000), 1.0),
        gain(drive(thump(120, 38, 0.35, 9), 2.5), 1.0),
        gain(apply(lowpass(noise(0.25), 900), env_exp(0.25, 0.001, 14)), 0.6),
    ), 0.2, 0.8, 0.4)))

    # Killing blow: a deep boom with a long tail
    write("kill", fade_edges(reverb(mix(
        gain(drive(thump(90, 28, 0.9, 4.5), 2.0), 1.0),
        gain(crack(0.05, 3000), 0.8),
        gain(apply(lowpass(noise(0.8), 500), env_exp(0.8, 0.002, 4)), 0.5),
    ), 0.35, 1.2, 1.2)))

    write("dash", fade_edges(mix(whoosh(0.16, 900, 3600, 1500, 3.0), gain(whoosh(0.12, 300, 900, 400, 2.0), 0.5))))

    # Creature bite: a swish and two clacks of teeth
    clack = mix(crack(0.012, 7000), gain(apply(osc(1400, 0.03), env_exp(0.03, 0.0005, 80)), 0.3))
    write("enemy_attack", fade_edges(mix(gain(whoosh(0.14, 400, 1600, 600, 2.0), 0.6), clack, gain(clack, 0.7), offsets=[0, 0.09, 0.13])))

    # Windup: a low growl that rises
    growl = formant(lambda t: 70 + 30 * t, 0.42, [(400, 1.0), (900, 0.6), (2400, 0.2)], 0.04)
    growl = apply(drive(growl, 3.0), env_swell(0.42, 0.75, 1.0))
    write("enemy_windup", fade_edges(mix(growl, gain(apply(lowpass(noise(0.42), 600), env_swell(0.42, 0.8, 1.0)), 0.3))))

    # Landing from a hop: thud and a spray of dirt
    write("enemy_land", fade_edges(mix(
        gain(drive(thump(90, 40, 0.25, 12), 2.0), 1.0),
        gain(grains(0.3, 60, 3000), 0.5),
        gain(apply(lowpass(noise(0.2), 700), env_exp(0.2, 0.001, 18)), 0.5),
    )))

    # Ember spit: a wet pop and a sizzle
    sizzle = apply(highpass(noise(0.4), 3000), env_exp(0.4, 0.01, 7))
    write("spit", fade_edges(mix(
        gain(apply(bandpass(noise(0.08), sweep(800, 2200), 3.0), env_exp(0.08, 0.001, 30)), 1.0),
        gain(thump(300, 120, 0.06, 40), 0.5),
        gain(sizzle, 0.35),
    )))

    # Crumbling to ash: a sigh down, many grains, a fading sizzle
    write("enemy_death", fade_edges(reverb(mix(
        gain(apply(formant(sweep(160, 70), 0.5, [(500, 1.0), (1100, 0.5)], 0.02), env_exp(0.5, 0.01, 5)), 0.4),
        gain(grains(0.9, 220, 2600), 0.8),
        gain(apply(highpass(noise(0.9), 2500), env_exp(0.9, 0.05, 4)), 0.25),
    ), 0.25, 1.0, 0.6)))

    # Veyl hurt: a dull hit and a short breath out
    write("player_hurt", fade_edges(mix(
        gain(drive(thump(140, 60, 0.18, 15), 2.0), 0.9),
        gain(apply(formant(sweep(220, 170), 0.2, [(700, 1.0), (1200, 0.7), (2600, 0.2)]), env_exp(0.2, 0.01, 12)), 0.5),
        gain(apply(bandpass(noise(0.2), 1500, 1.0), env_exp(0.2, 0.005, 14)), 0.4),
    )))

    # The Ashbound's slam: sub thump, crack, long rumble
    write("boss_attack", fade_edges(reverb(mix(
        gain(drive(thump(70, 25, 1.0, 3.5), 2.5), 1.0),
        gain(crack(0.05, 3500), 0.9),
        gain(apply(lowpass(noise(1.3), lambda t: 500 - 350 * t), env_exp(1.3, 0.005, 2.8)), 0.8),
        gain(grains(1.0, 120, 1800), 0.4),
    ), 0.3, 1.3, 1.0)))

    # Eruption: a sucking rise, then a roar of fire
    rise = apply(bandpass(noise(0.18), sweep(200, 1200), 2.0), env_swell(0.18, 0.95, 2.0))
    roar = apply(lowpass(noise(0.9), lambda t: 1800 - 1200 * t), env_exp(0.9, 0.01, 3.5))
    flutter = [s * (0.7 + 0.3 * math.sin(TAU * 23 * i / RATE)) for i, s in enumerate(roar)]
    write("eruption", fade_edges(mix(gain(rise, 0.6), gain(flutter, 1.0), gain(thump(80, 35, 0.4, 8), 0.8), offsets=[0, 0.15, 0.15])))

    # The roar: two growling voices a fifth apart, a fire rumble under them
    v1 = formant(lambda t: 55 + 12 * math.sin(math.pi * t), 2.2, [(300, 1.0), (750, 0.8), (1900, 0.35)], 0.05)
    v2 = formant(lambda t: 82 + 15 * math.sin(math.pi * t), 2.2, [(350, 0.8), (900, 0.6), (2300, 0.25)], 0.06, "square")
    body = apply(drive(mix(v1, gain(v2, 0.7)), 4.0), env_swell(2.2, 0.3, 0.8))
    rumble = apply(lowpass(noise(2.2), 300), env_swell(2.2, 0.4, 1.0))
    write("boss_roar", fade_edges(reverb(mix(body, gain(rumble, 0.6)), 0.3, 1.4, 1.5), 0.01, 0.3))

    # The Ashbound falls: the roar dies away, it crumbles, the ground settles
    dying = formant(sweep(70, 30), 3.0, [(280, 1.0), (700, 0.6)], 0.08)
    dying = apply(drive(dying, 3.0), env_exp(3.0, 0.02, 1.2))
    write("boss_death", fade_edges(reverb(mix(
        gain(dying, 0.7),
        gain(grains(3.5, 900, 2200), 0.7),
        gain(apply(lowpass(noise(3.5), 250), env_exp(3.5, 0.05, 0.9)), 0.7),
        gain(drive(thump(60, 22, 1.5, 2.5), 2.0), 0.8),
    ), 0.35, 1.5, 2.0), 0.01, 0.5))

    # Shrine kindled: a soft ignition, then a warm bell chord
    bell = mix(*[gain(apply(osc(f, 2.0), env_exp(2.0, 0.003, d)), g) for f, g, d in
                 ((293.66, 0.5, 1.5), (587.3, 0.3, 2.2), (880.0, 0.25, 2.6), (1174.7, 0.12, 3.5), (1760.0, 0.06, 4.5))])
    write("checkpoint", fade_edges(reverb(mix(gain(whoosh(0.4, 200, 1200, 500, 1.5), 0.5), bell, offsets=[0, 0.12]), 0.35, 1.3, 1.5)))

    # Ember wall rising or dying: fire whoosh over a low rumble
    write("gate_open", fade_edges(reverb(mix(
        gain(apply(lowpass(noise(1.3), lambda t: 400 + 1400 * math.sin(math.pi * t)), env_swell(1.3, 0.35, 1.2)), 1.0),
        gain(apply(osc(sweep(55, 45), 1.3), env_swell(1.3, 0.3, 1.0)), 0.5),
    ), 0.3, 1.2, 0.8)))

    # Rowan speaks: a soft murmur
    write("npc", fade_edges(apply(formant(sweep(150, 130), 0.12, [(600, 1.0), (1100, 0.6)]), env_swell(0.12, 0.3, 1.0))))

    # Pickup: two plucked notes and a glint
    write("pickup", fade_edges(reverb(mix(
        gain(pluck(659.25, 0.5, 0.8), 0.7),
        gain(pluck(987.77, 0.6, 0.9), 0.7),
        gain(apply(osc(2637, 0.3), env_exp(0.3, 0.002, 12)), 0.15),
        offsets=[0, 0.07, 0.07]), 0.25, 1.0, 0.6)))

    write("ui_click", fade_edges(mix(crack(0.006, 5000), gain(apply(osc(420, 0.03), env_exp(0.03, 0.001, 90)), 0.4))))


# ------------------------------------------------------------
# Ambience and music (looping)
# ------------------------------------------------------------

def loop_crossfade(track, length, fade):
    """Folds the part past `length` back over the start so the loop is seamless."""
    n, f = n_of(length), n_of(fade)
    out = track[:n]
    tail = track[n:n + f]
    for i, s in enumerate(tail):
        k = i / max(1, len(tail))
        out[i] = out[i] * k + s * (1 - k)
    return out


def make_ambience():
    # Wind through pines, gusting, with far-off creaks
    dur = 24.0
    wind = lowpass(noise(dur + 2), lambda t: 350 + 250 * math.sin(TAU * t * 3) ** 2)
    gust = [0.5 + 0.5 * math.sin(TAU * i / RATE / 7.0) ** 2 for i in range(len(wind))]
    wind = [w * g for w, g in zip(wind, gust)]
    hiss = gain(lowpass(highpass(noise(dur + 2), 2500), 6000), 0.06)
    creaks = silence(dur + 2)
    for start in (3.0, 11.5, 19.0):
        c = apply(bandpass(osc(sweep(90, 70), 0.6, "saw"), 600, 8.0), env_swell(0.6, 0.3, 1.0))
        for i, s in enumerate(c):
            creaks[n_of(start) + i] += s * 0.15
    write("ambience_forest", loop_crossfade(mix(wind, hiss, creaks), dur, 2.0), 0.5)


def make_forest_music():
    # Dark, sparse: a D drone that breathes, a plucked minor motif in a big space
    bpm = 60.0
    beat = 60.0 / bpm
    bars = 16
    dur = bars * 4 * beat
    total = dur + 4.0
    drone = mix(
        gain(osc(73.42, total), 0.35),
        gain(osc(73.6, total), 0.25),
        gain(osc(110.0, total), 0.15),
        gain(lowpass(osc(146.83, total, "saw"), 400), 0.08),
    )
    breath = [0.65 + 0.35 * math.sin(TAU * i / RATE / (dur / 2)) for i in range(len(drone))]
    drone = [d * b for d, b in zip(drone, breath)]

    # D minor motif, phrase answered an octave down
    motif = [(0, 293.66), (1, 349.23), (2, 440.0), (3.5, 392.0), (6, 349.23), (7, 329.63),
             (16, 293.66), (17, 349.23), (18, 523.25), (19.5, 440.0), (22, 392.0), (23, 349.23),
             (32, 146.83), (34, 174.61), (36, 220.0), (40, 196.0),
             (48, 293.66), (49, 261.63), (50, 220.0), (52, 233.08), (56, 220.0)]
    notes = silence(total)
    for b, f in motif:
        p = gain(pluck(f, 3.5, 0.4, 0.997), 0.5)
        start = n_of(b * beat)
        for i, s in enumerate(p):
            if start + i < len(notes):
                notes[start + i] += s
    notes = reverb(notes, 0.45, 1.5, 0.0)[:len(notes)]
    write("music_forest", loop_crossfade(mix(drone, notes), dur, 4.0), 0.7)


def make_boss_music():
    # Drums and a driving low ostinato in D minor, 100 bpm, with brass stabs
    bpm = 100.0
    beat = 60.0 / bpm
    bars = 8
    dur = bars * 4 * beat
    total = dur + 2.0
    out = silence(total)

    def add(track, at, g=1.0):
        start = n_of(at)
        for i, s in enumerate(track):
            if start + i < len(out):
                out[start + i] += s * g

    taiko = drive(mix(thump(110, 45, 0.6, 7), gain(apply(lowpass(noise(0.08), 900), env_exp(0.08, 0.001, 40)), 0.5)), 1.8)
    snare = mix(gain(apply(bandpass(noise(0.2), 1800, 1.0), env_exp(0.2, 0.001, 18)), 0.6), gain(thump(220, 160, 0.1, 30), 0.4))
    # Pattern per bar (beats): big drums on 1 and the "and" of 2, snare on 2 and 4
    for bar in range(bars):
        base = bar * 4 * beat
        for b, g in ((0, 1.0), (1.5, 0.7), (2.75, 0.5), (3.0, 0.8)):
            add(taiko, base + b * beat, g)
        for b in (1, 3):
            add(snare, base + b * beat, 0.5)

    # Low ostinato in eighths: D D F D C D A, D
    pattern = [73.42, 73.42, 87.31, 73.42, 65.41, 73.42, 110.0, 73.42]
    roots = [1.0, 1.0, 1.189, 0.891]  # D, D, F, C bars cycling
    for bar in range(bars):
        shift = roots[bar % 4]
        for k, f in enumerate(pattern):
            note = lowpass(osc(f * shift, beat / 2 * 0.95, "saw"), 700)
            note = apply(note, env_exp(beat / 2 * 0.95, 0.004, 5))
            add(note, bar * 4 * beat + k * beat / 2, 0.35)

    # Brass stabs on the downbeat of every other bar
    for bar in range(0, bars, 2):
        chord = mix(*[lowpass(osc(f, beat * 1.5, "square"), 1200) for f in (146.83, 174.61, 220.0)])
        chord = apply(chord, env_exp(beat * 1.5, 0.02, 2.5))
        add(chord, bar * 4 * beat, 0.18)

    out = reverb(out, 0.22, 1.1, 0.0)[:len(out)]
    write("music_boss", loop_crossfade(drive(out, 1.2), dur, 1.0), 0.8)


# ------------------------------------------------------------
# More music
# ------------------------------------------------------------

def place(out, track, at, g=1.0):
    start = n_of(at)
    for i, s in enumerate(track):
        if start + i < len(out):
            out[start + i] += s * g


def pad(freqs, dur, cutoff=900, attack=1.5, release=1.5, detune=0.004):
    """Slow detuned-saw chord, softened by a lowpass."""
    voices = []
    for f in freqs:
        for d in (-detune, detune):
            voices.append(osc(f * (1 + d), dur, "saw", phase=random.random()))
    body = lowpass(mix(*voices), cutoff)
    n = len(body)
    a, r = n_of(attack), n_of(release)
    return [x * min(1.0, i / max(1, a)) * min(1.0, (n - i) / max(1, r)) / len(voices) for i, x in enumerate(body)]


def bowed(freq, dur, vibrato=0.006):
    """An eerie bowed tone: slow swell, gentle vibrato, a little breath."""
    tone = osc(lambda t: freq * (1 + vibrato * math.sin(TAU * 5.0 * t * dur)), dur, "tri")
    breath = gain(bandpass(noise(dur), freq * 2, 4.0), 0.3)
    return apply(mix(tone, breath), env_swell(dur, 0.5, 1.5))


def notes_track(total, events, voice):
    """events: (start seconds, freq, length seconds, gain); voice(freq, length) -> samples."""
    out = silence(total)
    for at, f, length, g in events:
        place(out, voice(f, length), at, g)
    return out


# D minor / D major note names, for readability
N = {"D2": 73.42, "F2": 87.31, "A2": 110.0, "C3": 130.81, "D3": 146.83, "E3": 164.81, "F3": 174.61,
     "G3": 196.0, "A3": 220.0, "Bb3": 233.08, "C4": 261.63, "D4": 293.66, "E4": 329.63, "F4": 349.23,
     "F#4": 369.99, "G4": 392.0, "A4": 440.0, "Bb4": 466.16, "C5": 523.25, "D5": 587.33, "E5": 659.25,
     "F5": 698.46, "F#5": 739.99, "A5": 880.0, "G2": 98.0, "Bb2": 116.54, "A1": 55.0, "D1": 36.71}


def make_menu_music():
    # Title: a slow harp arpeggio over a soft pad, Dm - Bb - F - C
    bpm = 70.0
    beat = 60.0 / bpm
    bars = 12
    dur = bars * 4 * beat
    total = dur + 5.0
    chords = [("D3", "F3", "A3", "D4"), ("Bb2", "D3", "F3", "Bb3"), ("F2", "A2", "C3", "F3"), ("C3", "E3", "G3", "C4")]
    pads = silence(total)
    harp = []
    for bar in range(bars):
        ch = chords[bar % 4]
        place(pads, pad([N[n] for n in ch[:3]], 4 * beat + 1.5, 700, 1.2, 1.2), bar * 4 * beat, 0.5)
        # Up-and-down arpeggio in eighths, an octave up
        seq = [ch[0], ch[1], ch[2], ch[3], ch[2], ch[1], ch[2], ch[3]]
        for k, n in enumerate(seq):
            harp.append((bar * 4 * beat + k * beat / 2, N[n] * 2, 2.5, 0.35 if k else 0.5))
    # A melody enters halfway
    melody = [(24, "A4"), (26, "G4"), (27, "F4"), (28, "D5"), (30, "C5"), (32, "Bb4"), (34, "A4"), (36, "F4"),
              (40, "E4"), (42, "F4"), (43, "G4"), (44, "A4")]
    harp += [(b * beat, N[n], 3.5, 0.6) for b, n in melody]
    plucks = notes_track(total, harp, lambda f, l: pluck(f, l, 0.5, 0.997))
    music = mix(pads, reverb(plucks, 0.45, 1.5, 0.0)[:len(pads)])
    write("music_menu", loop_crossfade(music, dur, 4.0), 0.7)


def make_camp_music():
    # Rowan's Fire: warm and settled, F major, a lute tune and the fire crackling
    bpm = 84.0
    beat = 60.0 / bpm
    bars = 16
    dur = bars * 4 * beat
    total = dur + 4.0
    roots = ["F2", "C3", "D3", "Bb2"]
    bass = []
    strum = []
    for bar in range(bars):
        r = roots[bar % 4]
        bass += [(bar * 4 * beat, N[r], 2.5, 0.5), (bar * 4 * beat + 2 * beat, N[r] * 1.5, 2.0, 0.3)]
        third = {"F2": "A3", "C3": "E3", "D3": "F3", "Bb2": "D4"}[r]
        fifth = {"F2": "C4", "C3": "G3", "D3": "A3", "Bb2": "F4"}[r]
        for b in (1, 3):
            strum += [(bar * 4 * beat + b * beat + k * 0.03, N[n], 1.2, 0.18) for k, n in enumerate([third, fifth])]
    tune = [(0, "A4"), (1, "C5"), (2, "A4"), (3, "G4"), (4, "F4"), (6, "G4"), (7, "A4"),
            (8, "F4"), (9, "A4"), (10, "D5"), (12, "C5"), (14, "A4"),
            (16, "Bb4"), (17, "A4"), (18, "G4"), (20, "F4"), (22, "E4"), (23, "F4"), (24, "G4"), (28, "F4")]
    lead = [(b * beat + 32 * beat * half, N[n], 2.0, 0.45) for half in (0, 1) for b, n in tune]
    voice = lambda f, l: pluck(f, l, 0.7, 0.995)
    plucked = mix(notes_track(total, bass, voice), notes_track(total, strum, voice), notes_track(total, lead, voice))
    plucked = reverb(plucked, 0.25, 0.9, 0.0)[:len(plucked)]
    # Fire: soft rumble with crackles
    fire = gain(lowpass(noise(total), 500), 0.25)
    pops = grains(total, int(total * 6), 4000, 0.008)
    write("music_camp", loop_crossfade(mix(plucked, fire, gain(pops, 0.08)), dur, 3.0), 0.75)


def make_deep_music():
    # The Deep Forest: no tune, just dread. A low pulse, a heartbeat, bowed tones that never resolve
    bpm = 56.0
    beat = 60.0 / bpm
    bars = 10
    dur = bars * 4 * beat
    total = dur + 5.0
    drone = mix(gain(osc(N["D1"] * 2, total), 0.4), gain(osc(N["D1"] * 2 * 1.007, total), 0.3),
                gain(lowpass(osc(N["A1"] * 1.414, total, "saw"), 200), 0.15))  # a tritone lurking under it
    pulse = [0.6 + 0.4 * math.sin(TAU * i / RATE / (beat * 2)) for i in range(len(drone))]
    drone = [d * p for d, p in zip(drone, pulse)]
    beats = silence(total)
    heart = mix(thump(60, 40, 0.25, 14), gain(thump(55, 38, 0.2, 16), 0.7), offsets=[0, 0.22])
    for bar in range(bars):
        place(beats, heart, bar * 4 * beat, 0.6)
        place(beats, heart, bar * 4 * beat + 2 * beat, 0.45)
    tones = notes_track(total, [(2 * beat, N["A4"], 6.0, 0.25), (9 * beat, N["Bb4"], 7.0, 0.22),
                                (17 * beat, N["E5"], 6.0, 0.18), (25 * beat, N["F4"], 8.0, 0.22),
                                (32 * beat, N["Bb4"] * 0.5, 7.0, 0.25)], bowed)
    tones = reverb(tones, 0.5, 1.6, 0.0)[:len(tones)]
    wind = gain(lowpass(noise(total), lambda t: 200 + 300 * math.sin(TAU * t * 2) ** 2), 0.15)
    write("music_deep", loop_crossfade(mix(drone, beats, tones, wind), dur, 4.0), 0.65)


def make_boss2_music():
    # The Ashbound, Burning: phase two. Faster, heavier, a growling choir
    bpm = 120.0
    beat = 60.0 / bpm
    bars = 8
    dur = bars * 4 * beat
    total = dur + 2.0
    out = silence(total)
    taiko = drive(mix(thump(110, 40, 0.5, 8), gain(apply(lowpass(noise(0.08), 900), env_exp(0.08, 0.001, 40)), 0.6)), 2.2)
    snare = mix(gain(apply(bandpass(noise(0.15), 2000, 1.0), env_exp(0.15, 0.001, 22)), 0.7), gain(thump(240, 170, 0.08, 35), 0.4))
    for bar in range(bars):
        base = bar * 4 * beat
        for b in (0, 0.75, 1.5, 2.0, 2.75, 3.5):
            place(out, taiko, base + b * beat, 0.9 if b in (0, 2.0) else 0.6)
        for b in (1, 3):
            place(out, snare, base + b * beat, 0.55)
        if bar % 2 == 1:
            for k in range(4):
                place(out, snare, base + 3 * beat + k * beat / 4, 0.3 + k * 0.1)
    roots = [1.0, 1.0, 1.189, 1.335]  # D D F G
    riff = [N["D2"], N["D2"], N["D3"], N["D2"], N["F2"], N["D2"], N["C3"], N["D2"]]
    for bar in range(bars):
        for k, f in enumerate(riff):
            f = f * roots[bar % 4]
            note = mix(lowpass(osc(f, beat / 2 * 0.9, "saw"), 800), gain(lowpass(osc(f * 2, beat / 2 * 0.9, "square"), 900), 0.4))
            place(out, apply(drive(note, 1.8), env_exp(beat / 2 * 0.9, 0.003, 6)), bar * 4 * beat + k * beat / 2, 0.32)
    # Choir: growling voices holding the chord, a bar each
    for bar in range(bars):
        r = roots[bar % 4]
        for f in (N["D3"] * r, N["A3"] * r):
            v = formant(f, 4 * beat, [(500, 1.0), (1000, 0.6), (2600, 0.2)], 0.012)
            place(out, apply(v, env_swell(4 * beat, 0.3, 0.8)), bar * 4 * beat, 0.12)
    out = reverb(out, 0.2, 1.1, 0.0)[:len(out)]
    write("music_boss2", loop_crossfade(drive(out, 1.3), dur, 1.0), 0.82)


def make_ending_music():
    # The Forest Is Quiet: the forest theme's motif, resolved into D major
    bpm = 66.0
    beat = 60.0 / bpm
    bars = 12
    dur = bars * 4 * beat
    total = dur + 5.0
    chords = [("D3", "F#4", "A3"), ("G2", "D3", "G3"), ("D3", "F#4", "A3"), ("A2", "E3", "A3")]
    pads = silence(total)
    for bar in range(bars):
        place(pads, pad([N[n] for n in chords[bar % 4]], 4 * beat + 2.0, 1100, 1.8, 1.8), bar * 4 * beat, 0.5)
    motif = [(0, "D4"), (1, "F#4"), (2, "A4"), (3.5, "G4"), (6, "F#4"), (7, "E4"),
             (16, "D4"), (17, "F#4"), (18, "D5"), (19.5, "A4"), (22, "G4"), (23, "F#4"),
             (32, "A4"), (34, "G4"), (36, "D5"), (40, "F#5"), (44, "D5")]
    lead = notes_track(total, [(b * beat, N[n], 4.0, 0.55) for b, n in motif], lambda f, l: pluck(f, l, 0.4, 0.998))
    bells = notes_track(total, [(b * 4 * beat, N["A5"], 3.0, 0.08) for b in range(0, bars, 2)],
                        lambda f, l: apply(osc(f, l), env_exp(l, 0.003, 1.5)))
    music = mix(pads, reverb(mix(lead, bells), 0.5, 1.6, 0.0)[:len(pads)])
    write("music_ending", loop_crossfade(music, dur, 4.0), 0.7)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    which = sys.argv[1:] or ["sfx", "ambience", "music"]
    if "sfx" in which:
        make_sfx()
    if "ambience" in which:
        make_ambience()
    if "music" in which:
        make_forest_music()
        make_boss_music()
        make_menu_music()
        make_camp_music()
        make_deep_music()
        make_boss2_music()
        make_ending_music()
