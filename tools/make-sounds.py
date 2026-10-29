#!/usr/bin/env python3
"""Synthesize the alarm sounds shipped in bsadik.timers/sounds/.

Each file is one loop of the alarm; the service plays it over and over until
the alarm is stopped. Pure standard library, so it runs anywhere:

    python3 tools/make-sounds.py
"""

import math
import os
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "bsadik.timers", "sounds")


def silence(seconds):
    return [0.0] * int(RATE * seconds)


def tone(freq, seconds, partials, decay, attack=0.004):
    """A struck tone: a few harmonics under an exponential decay."""
    n = int(RATE * seconds)
    out = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / attack) * math.exp(-t * decay)
        s = 0.0
        for mult, amp, pdecay in partials:
            s += amp * math.sin(2 * math.pi * freq * mult * t) * math.exp(-t * pdecay)
        out.append(s * env)
    return out


def beep(freq, seconds):
    """A clean digital beep with short fades so it doesn't click."""
    n = int(RATE * seconds)
    fade = int(RATE * 0.006)
    out = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, i / fade, (n - i) / fade)
        s = math.sin(2 * math.pi * freq * t) + 0.25 * math.sin(2 * math.pi * freq * 2 * t)
        out.append(s * env)
    return out


def mix(track, sound, at):
    start = int(RATE * at)
    end = start + len(sound)
    if end > len(track):
        track.extend([0.0] * (end - len(track)))
    for i, s in enumerate(sound):
        track[start + i] += s
    return track


def write(name, samples, peak=0.85):
    top = max(abs(s) for s in samples) or 1.0
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s / top * peak * 32767)) for s in samples))
    print("wrote", os.path.relpath(path))


def marimba():
    # A rising, bouncy marimba figure, played twice, then a breath.
    note = lambda f: tone(f, 0.55, [(1, 1.0, 0), (4, 0.35, 18), (10, 0.08, 40)], decay=7)
    notes = [(0.00, 659.25), (0.14, 880.00), (0.28, 987.77), (0.42, 1318.51),
             (0.70, 659.25), (0.84, 880.00), (0.98, 987.77), (1.12, 1318.51)]
    track = []
    for at, f in notes:
        mix(track, note(f), at)
    return track + silence(1.65 - len(track) / RATE)


def classic():
    # The bedside-clock pattern: four quick beeps, then a pause.
    track = []
    for k in range(4):
        mix(track, beep(2093.0, 0.075), k * 0.13)
    return track + silence(1.0 - len(track) / RATE)


def chime():
    # Soft bell arpeggio, for when the alarm should be gentle.
    bell = lambda f: tone(f, 1.6, [(1, 1.0, 0), (2.76, 0.4, 3), (5.4, 0.15, 6)], decay=2.2)
    track = []
    for at, f in [(0.0, 523.25), (0.22, 659.25), (0.44, 783.99), (0.66, 1046.5)]:
        mix(track, bell(f), at)
    return track + silence(2.6 - len(track) / RATE)


def tick():
    # Short click used when a timer is started.
    return tone(1567.98, 0.12, [(1, 1.0, 0), (3, 0.3, 30)], decay=35)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    write("marimba", marimba())
    write("classic", classic(), peak=0.6)
    write("chime", chime())
    write("start", tick(), peak=0.5)
