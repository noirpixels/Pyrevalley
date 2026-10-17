"""Synthesizes Embervale's sound effects, ambience and music into audio/.

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
