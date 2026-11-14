# موسيقى خلفية هادئة تُولَّد برمجياً: وسادة أوتار دافئة وجرس خفيف ونبضتان عند ظهور الشعار.
# python3 music.py total_seconds hit1 hit2 out.wav
import sys
import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve

SR = 48000
TOTAL, HIT1, HIT2, OUT = float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
N = int(TOTAL * SR)
rng = np.random.default_rng(7)


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


# Dm(add9) · B♭maj7 · F(add9) · C(sus2) — تقدم هادئ متفائل
CHORDS = [
    [50, 57, 62, 64, 65],   # D3 A3 D4 E4 F4
    [46, 53, 58, 62, 69],   # Bb2 F3 Bb3 D4 A4
    [53, 57, 60, 65, 67],   # F3 A3 C4 F4 G4
    [48, 55, 60, 62, 67],   # C3 G3 C4 D4 G4
]
CH = 9.6  # ثوانٍ لكل وتر


def pad_note(f, n):
    t = np.arange(n) / SR
    out = np.zeros(n)
    for det in (-0.006, 0.0, 0.0055):
        ff = f * (1 + det)
        ph = rng.uniform(0, 2 * np.pi)
        for h in range(1, 14):
            if ff * h > 5000:
                break
            out += np.sin(2 * np.pi * ff * h * t + ph * h) / (h ** 1.15)
    vib = 1 + 0.0025 * np.sin(2 * np.pi * 0.21 * t + rng.uniform(0, 6))
    return out * vib / 9


def env(n, a, r):
    e = np.ones(n)
    ai, ri = int(a * SR), int(r * SR)
    e[:ai] = np.sin(np.linspace(0, np.pi / 2, ai)) ** 2
    e[-ri:] *= np.cos(np.linspace(0, np.pi / 2, ri)) ** 2
    return e


L = np.zeros(N + SR * 12)
R = np.zeros(N + SR * 12)
i, c = 0.0, 0
while i < TOTAL + 2:
    chord = CHORDS[c % 4]
    seg = int((CH + 4.0) * SR)  # تداخل 4 ثوانٍ بين الأوتار
    s0 = int(i * SR)
    for j, m in enumerate(chord):
        x = pad_note(midi(m), seg) * env(seg, 3.2, 4.0) * (0.9 if j else 0.7)
        pan = 0.5 + 0.35 * np.sin(j * 1.7)
        L[s0:s0 + seg] += x * (1 - pan)
        R[s0:s0 + seg] += x * pan
    # قاعدة منخفضة ناعمة
    sub = np.sin(2 * np.pi * midi(chord[0] - 12) * np.arange(seg) / SR) * env(seg, 3.0, 4.0) * 0.22
    L[s0:s0 + seg] += sub
    R[s0:s0 + seg] += sub
    # جرس متفرق: نغمتان أو ثلاث في كل وتر
    for k, off in enumerate((1.2, 4.4, 7.3)):
        if (c + k) % 3 == 2:
            continue
        m = chord[2 + (k + c) % 3] + 12
        nb = int(3.5 * SR)
        tb = np.arange(nb) / SR
        bell = (np.sin(2 * np.pi * midi(m) * tb) + 0.25 * np.sin(2 * np.pi * midi(m) * 2.0 * tb) + 0.08 * np.sin(2 * np.pi * midi(m) * 3.01 * tb))
        bell *= np.exp(-tb * 1.6) * (1 - np.exp(-tb * 120)) * 0.16
        b0 = s0 + int(off * SR)
        p = 0.3 + 0.4 * ((k + c) % 2)
        L[b0:b0 + nb] += bell * (1 - p)
        R[b0:b0 + nb] += bell * p
    i += CH
    c += 1

# مرشح تمرير منخفض دافئ
sos = butter(4, 2600, 'low', fs=SR, output='sos')
L, R = sosfilt(sos, L), sosfilt(sos, R)
hp = butter(2, 38, 'high', fs=SR, output='sos')
L, R = sosfilt(hp, L), sosfilt(hp, R)

# نبضة عميقة ناعمة عند ظهور الشعار والختام
for th in (HIT1, HIT2):
    nh = int(3.0 * SR)
    th_ = np.arange(nh) / SR
    f = 52 * np.exp(-th_ * 0.9) + 30
    boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-th_ * 2.2) * (1 - np.exp(-th_ * 60)) * 0.9
    h0 = int(th * SR)
    L[h0:h0 + nh] += boom
    R[h0:h0 + nh] += boom

# صدى صناعي (استجابة نبضية من ضوضاء متناقصة)
ir_n = int(3.2 * SR)
ti = np.arange(ir_n) / SR
irL = rng.standard_normal(ir_n) * np.exp(-ti * 2.1)
irR = rng.standard_normal(ir_n) * np.exp(-ti * 2.1)
lp = butter(2, 5000, 'low', fs=SR, output='sos')
irL, irR = sosfilt(lp, irL), sosfilt(lp, irR)
irL /= np.sqrt(np.sum(irL ** 2))
irR /= np.sqrt(np.sum(irR ** 2))
wetL = fftconvolve(L, irL)[:len(L)]
wetR = fftconvolve(R, irR)[:len(R)]
L = 0.62 * L + 0.55 * wetL
R = 0.62 * R + 0.55 * wetR
L, R = L[:N], R[:N]

# دخول تدريجي وخروج تدريجي
fi, fo = int(2.5 * SR), int(5.0 * SR)
g = np.ones(N)
g[:fi] = np.linspace(0, 1, fi) ** 2
g[-fo:] = np.linspace(1, 0, fo) ** 1.5
L *= g
R *= g
peak = max(np.abs(L).max(), np.abs(R).max())
L, R = L / peak * 0.7, R / peak * 0.7
st = (np.stack([L, R], 1) * 32767).astype(np.int16)
import wave
with wave.open(OUT, 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(st.tobytes())
print('ok', OUT, TOTAL)
