"""Report levels, clipping, 2-6 kHz harshness, stereo image and masking for a WAV captured from the game.

Usage: python3 tools/audio_report.py WAV [--soundtest]

Reads 32-bit float or 16-bit PCM WAV, mono or stereo. With --soundtest the file is a `BOT SOUNDTEST`
capture (sound k starts at 1 + k * 1.5 s for k = 0..19, then the music ramps from calm at 30 s to full
intensity at 70 s); each sound is then also measured against the drone bed and the full-intensity
music in its loudest octave band, which shows what masks it.
"""
import array
import cmath
import math
import operator
import struct
import sys

WINDOW = 2048
BANDS = [(0, 150, "<150"), (150, 500, "150-500"), (500, 2000, "0.5-2k"), (2000, 6000, "2-6k"), (6000, 1e9, ">6k")]
OCTAVES = [31.25 * 2 ** i for i in range(10)]
SOUNDS = ["shotgun", "minigun", "rocket", "explosion", "plasma", "hit tick", "crawler", "screamer", "tentacle", "brute",
          "hurt", "spit", "step/splat", "boss", "heartbeat", "bell", "kick", "snare/dash", "hat", "bass"]


def read_wav(path):
    try:
        data = open(path, "rb").read()
    except OSError as error:
        sys.exit(f"{path}: {error.strerror}")
    if len(data) < 12 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        sys.exit(f"{path}: not a RIFF/WAVE file")
    pos, fmt, body = 12, None, None
    while pos + 8 <= len(data):
        kind, size = data[pos:pos + 4], struct.unpack("<I", data[pos + 4:pos + 8])[0]
        chunk = data[pos + 8:pos + 8 + size]
        if kind == b"fmt " and len(chunk) >= 16:
            fmt = struct.unpack("<HHIIHH", chunk[:16])
        elif kind == b"data":
            body = chunk
        pos += 8 + size + (size & 1)
    if fmt is None or body is None:
        sys.exit(f"{path}: missing fmt or data chunk")
    tag, channels, rate, _, _, bits = fmt
    if tag == 3 and bits == 32:
        samples = array.array("f")
        samples.frombytes(body[:len(body) // 4 * 4])
    elif tag == 1 and bits == 16:
        ints = array.array("h")
        ints.frombytes(body[:len(body) // 2 * 2])
        samples = array.array("f", (v / 32768.0 for v in ints))
    else:
        sys.exit(f"{path}: unsupported sample format (tag {tag}, {bits} bit)")
    if channels not in (1, 2) or rate <= 0:
        sys.exit(f"{path}: unsupported layout ({channels} channels at {rate} Hz)")
    frames = len(samples) // channels
    if frames < WINDOW:
        sys.exit(f"{path}: too short ({frames} frames)")
    return rate, samples[0:frames * channels:channels], samples[channels - 1:frames * channels:channels]


TWIDDLES = {}


def fft(values):
    n = len(values)
    a = list(values)
    j = 0
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j |= bit
        if i < j:
            a[i], a[j] = a[j], a[i]
    size = 2
    while size <= n:
        half = size // 2
        if size not in TWIDDLES:
            TWIDDLES[size] = [cmath.exp(-2j * math.pi * k / size) for k in range(half)]
        twiddle = TWIDDLES[size]
        for start in range(0, n, size):
            for k in range(half):
                u, v = a[start + k], a[start + k + half] * twiddle[k]
                a[start + k], a[start + k + half] = u + v, u - v
        size *= 2
    return a


HANN = [0.5 - 0.5 * math.cos(2 * math.pi * i / WINDOW) for i in range(WINDOW)]


def spectrum(left, right, start):
    """Mono power spectrum of one Hann window, from a single complex FFT of left + i*right."""
    z = fft([complex(left[start + i], right[start + i]) * HANN[i] for i in range(WINDOW)])
    power = []
    for k in range(WINDOW // 2):
        zk, zm = z[k], z[-k % WINDOW].conjugate()
        power.append(abs((zk + zm) * 0.5 + (zk - zm) * -0.5j) ** 2 * 0.25)
    return power


def shares(power, rate):
    total = sum(power) + 1e-30
    hz = rate / WINDOW
    bands = [sum(p for k, p in enumerate(power) if lo <= k * hz < hi) / total for lo, hi, _ in BANDS]
    return bands, sum(k * hz * p for k, p in enumerate(power)) / total


def octaves(power, rate):
    hz = rate / WINDOW
    return [sum(p for k, p in enumerate(power) if c / math.sqrt(2) <= k * hz < c * math.sqrt(2)) for c in OCTAVES]


def db(x):
    return 10 * math.log10(x + 1e-20)


def rms_db(seg):
    return db(sum(map(operator.mul, seg, seg)) / max(len(seg), 1))


def spectra(left, right, rate, begin, end, step):
    return [(s, spectrum(left, right, s)) for s in range(begin, min(end, len(left) - WINDOW), step)]


def overview(left, right, rate):
    frames = len(left)
    every = [v for v in left] + [v for v in right]
    peak = max(map(abs, every))
    clipped = sum(1 for v in every if abs(v) >= 1.0)
    hot = sum(1 for v in every if abs(v) > 0.7) / len(every)
    print(f"{frames / rate:.1f} s at {rate} Hz. Peak {peak:.3f} ({db(peak * peak):.1f} dBFS), {clipped} samples at or above 1.0, "
          f"{hot * 100:.2f}% above 0.7 (tanh compression).")
    print(f"RMS: left {rms_db(left):.1f} dBFS, right {rms_db(right):.1f} dBFS.")
    block = rate // 20
    diffs = sorted(abs(rms_db(left[s:s + block]) - rms_db(right[s:s + block])) for s in range(0, frames - block, block)
                   if rms_db(left[s:s + block]) > -60)
    lr = sum(map(operator.mul, left, right))
    correlation = lr / math.sqrt(sum(map(operator.mul, left, left)) * sum(map(operator.mul, right, right)) + 1e-30)
    mid = sum((a + b) ** 2 for a, b in zip(left, right))
    side = sum((a - b) ** 2 for a, b in zip(left, right))
    if diffs:
        print(f"Stereo: side/mid {db(side / (mid + 1e-30)):.1f} dB, L/R correlation {correlation:.2f}, |L-R| per 50 ms "
              f"median {diffs[len(diffs) // 2]:.1f} dB, 99th percentile {diffs[int(len(diffs) * 0.99)]:.1f} dB, max {diffs[-1]:.1f} dB.")
    seconds = []
    for s in range(0, frames - rate + 1, rate):
        seg_l, seg_r = left[s:s + rate], right[s:s + rate]
        windows = spectra(left, right, rate, s, s + rate, rate // 8)
        power = [sum(w[1][k] for w in windows) for k in range(WINDOW // 2)] if windows else [0.0] * (WINDOW // 2)
        bands, centroid = shares(power, rate)
        m = sum((a + b) ** 2 for a, b in zip(seg_l, seg_r))
        side_s = sum((a - b) ** 2 for a, b in zip(seg_l, seg_r))
        hot_s = sum(1 for v in seg_l if abs(v) > 0.7) + sum(1 for v in seg_r if abs(v) > 0.7)
        seconds.append((s // rate, rms_db(seg_l), rms_db(seg_r), max(max(map(abs, seg_l)), max(map(abs, seg_r))),
                        hot_s / (2 * rate), bands, centroid, db(side_s / (m + 1e-30)), power))
    levels = sorted((a + b) / 2 for _, a, b, *_ in seconds)
    if levels:
        p10, p50, p95 = levels[len(levels) // 10], levels[len(levels) // 2], levels[min(len(levels) - 1, len(levels) * 95 // 100)]
        print(f"Dynamics: per-second RMS p10 {p10:.1f}, median {p50:.1f}, p95 {p95:.1f} dBFS (range {p95 - p10:.1f} dB).")
        total = [sum(sec[8][k] for sec in seconds) for k in range(WINDOW // 2)]
        bands, centroid = shares(total, rate)
        worst = max(seconds, key=lambda sec: sec[5][3])
        print("Spectrum: " + ", ".join(f"{name} {share * 100:.1f}%" for (_, _, name), share in zip(BANDS, bands)) +
              f"; centroid {centroid:.0f} Hz. Harshest second: {worst[0]} s with {worst[5][3] * 100:.1f}% in 2-6 kHz.")
        print("\nPer second:  t  rmsL  rmsR  peak  >0.7%  " + "  ".join(f"{name:>7}" for _, _, name in BANDS) + "  centroid  side/mid")
        for t, a, b, peak_s, hot_s, bands, centroid, sm, _ in seconds:
            print(f"           {t:3d} {a:5.1f} {b:5.1f}  {peak_s:.2f}  {hot_s * 100:5.2f}  " +
                  "  ".join(f"{share * 100:6.1f}%" for share in bands) + f"  {centroid:6.0f} Hz  {sm:6.1f} dB")
    return seconds


def soundtest(left, right, rate):
    bed_windows = spectra(left, right, rate, 0, 30 * rate, rate // 8)
    music_windows = spectra(left, right, rate, 65 * rate, 70 * rate, rate // 8)
    if not bed_windows or not music_windows:
        print("\nToo short for a SOUNDTEST capture (needs 70 s).")
        return
    bed = [min(octaves(p, rate)[o] for _, p in bed_windows) for o in range(len(OCTAVES))]
    music_octaves = [octaves(p, rate) for _, p in music_windows]
    music = [sum(m[o] for m in music_octaves) / len(music_octaves) for o in range(len(OCTAVES))]
    print("\nSounds (gain 1, centred). Margin = the sound's loudest octave band at its peak against the same band of the"
          " drone bed (always present) and of the full-intensity music (65-70 s).")
    print(" k  sound         peak  loud50ms  centroid    <150   2-6k  loudest band  over bed  over music")
    for k, name in enumerate(SOUNDS):
        s0 = int((1 + k * 1.5) * rate) + 200
        seg = left[s0:s0 + int(1.2 * rate)]
        if len(seg) < WINDOW:
            break
        block = rate // 20
        loud = max(rms_db(seg[i:i + block]) for i in range(0, len(seg) - block, block // 2))
        windows = spectra(left, right, rate, s0, s0 + int(0.4 * rate), WINDOW // 2)
        power = [sum(w[1][i] for w in windows) for i in range(WINDOW // 2)]
        bands, centroid = shares(power, rate)
        peak_octaves = [max(octaves(p, rate)[o] for _, p in windows) for o in range(len(OCTAVES))]
        best = max(range(len(OCTAVES)), key=lambda o: peak_octaves[o])
        print(f"{k:2d}  {name:12s} {max(map(abs, seg)):.2f}  {loud:6.1f} dB  {centroid:6.0f} Hz  {bands[0] * 100:5.1f}%  "
              f"{bands[3] * 100:5.1f}%  {OCTAVES[best]:7.0f} Hz  {db(peak_octaves[best]) - db(bed[best]):6.1f} dB  "
              f"{db(peak_octaves[best]) - db(music[best]):6.1f} dB")
    calm = spectra(left, right, rate, 30 * rate, 35 * rate, rate // 8)
    print("\nMusic RMS per second from 30 s (intensity ramps 0 -> 1 until 70 s): " +
          " ".join(f"{rms_db(left[s:s + rate]):.0f}" for s in range(30 * rate, len(left) - rate + 1, rate)))
    if calm:
        calm_power = [sum(w[1][i] for w in calm) for i in range(WINDOW // 2)]
        full_power = [sum(w[1][i] for w in music_windows) for i in range(WINDOW // 2)]
        for label, power in (("calm music 30-35 s", calm_power), ("full music 65-70 s", full_power)):
            bands, centroid = shares(power, rate)
            print(f"{label}: " + ", ".join(f"{n} {s * 100:.1f}%" for (_, _, n), s in zip(BANDS, bands)) + f"; centroid {centroid:.0f} Hz")


def main():
    args = [a for a in sys.argv[1:] if a != "--soundtest"]
    if len(args) != 1:
        sys.exit(__doc__.strip().split("\n\n")[1])
    rate, left, right = read_wav(args[0])
    overview(left, right, rate)
    if "--soundtest" in sys.argv:
        soundtest(left, right, rate)


main()
