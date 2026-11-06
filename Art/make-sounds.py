"""Writes the two optional flight sounds to Resources/: a chime for when the bubble pops up,
and a propeller whirr as long as one flight (7.2 s), swelling in and fading out with it.
Synthesised here, so there is no recording to license. Run: python3 Art/make-sounds.py"""

import math
import os
import random
import struct
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
RESOURCES = os.path.join(HERE, '..', 'Resources')


def write(name, samples, rate):
    peak = max(abs(s) for s in samples) or 1
    with wave.open(os.path.join(RESOURCES, name), 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(b''.join(struct.pack('<h', int(s / peak * 0.7 * 32767)) for s in samples))


def chime(rate=22050, length=1.2):
    samples = [0.0] * int(rate * length)
    for start, pitch in ((0.0, 1046.5), (0.12, 1318.5)):  # C6, then E6
        for i in range(int(rate * start), len(samples)):
            t = i / rate - start
            attack = min(t / 0.005, 1)
            decay = math.exp(-t / 0.35)
            tone = sum(level * math.sin(2 * math.pi * pitch * harmonic * t)
                       for harmonic, level in ((1, 1.0), (2, 0.3), (3, 0.1)))
            samples[i] += attack * decay * tone
    return samples


def whirr(rate=16000, length=7.2, fly_in=2.0, hover=3.2):
    random.seed(7)
    samples = []
    phase = 0.0
    noise = 0.0
    for i in range(int(rate * length)):
        t = i / rate
        if t < fly_in:
            loudness = 0.15 + 0.85 * (1 - (1 - t / fly_in) ** 3)
            pitch = 1.03
        elif t < fly_in + hover:
            loudness = 1 + 0.05 * math.sin(2 * math.pi * 0.35 * t)
            pitch = 1.0
        else:
            u = (t - fly_in - hover) / (length - fly_in - hover)
            loudness = (1 - u) ** 2
            pitch = 1 - 0.04 * u
        fade = min(t / 0.05, (length - t) / 0.05, 1)
        phase += 2 * math.pi * 90 * pitch / rate
        buzz = sum(math.sin(phase * h) / h for h in range(1, 6))
        noise += 0.3 * (random.uniform(-1, 1) - noise)
        chop = 0.6 + 0.4 * math.sin(phase / 5)
        samples.append(fade * loudness * chop * (0.7 * buzz + 0.5 * noise))
    return samples


write('chime.wav', chime(), 22050)
write('whirr.wav', whirr(), 16000)
print('wrote chime.wav and whirr.wav')
