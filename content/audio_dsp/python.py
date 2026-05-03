#!/usr/bin/env python3
"""Vidya — Audio DSP — Python port. Q15 fixed-point throughout."""

SCALE = 15
ONE = 32768
SMAX = 32767
SMIN = -32767


def q_mul(a, b):
    p = a * b
    return -((-p) >> SCALE) if p < 0 else (p >> SCALE)


def clip(s):
    if s > SMAX: return SMAX
    if s < SMIN: return SMIN
    return s


class Biquad:
    def __init__(self):
        self.b0 = self.b1 = self.b2 = self.a1 = self.a2 = 0
        self.x1 = self.x2 = self.y1 = self.y2 = 0

    def set_coefs(self, b0, b1, b2, a1, a2):
        self.b0, self.b1, self.b2 = b0, b1, b2
        self.a1, self.a2 = a1, a2
        self.x1 = self.x2 = self.y1 = self.y2 = 0

    def lowpass_1pole(self, a_q15):
        self.set_coefs(a_q15, 0, 0, a_q15 - ONE, 0)

    def step(self, x):
        y = (q_mul(self.b0, x) + q_mul(self.b1, self.x1) + q_mul(self.b2, self.x2)
             - q_mul(self.a1, self.y1) - q_mul(self.a2, self.y2))
        self.x2, self.x1 = self.x1, x
        self.y2, self.y1 = self.y1, y
        return y


def fir_step(taps, history, x_new):
    # Shift history right, x_new in at index 0.
    for i in range(len(history) - 1, 0, -1):
        history[i] = history[i - 1]
    history[0] = x_new
    return sum(q_mul(taps[j], history[j]) for j in range(len(taps)))


def peak(buffer):
    return max(abs(s) for s in buffer)


def mean_absolute(buffer):
    return sum(abs(s) for s in buffer) // len(buffer)


PASS, FAIL = 0, 0
def check(cond, name):
    global PASS, FAIL
    if cond: PASS += 1
    else: FAIL += 1; print(f"  FAIL: {name}")


def test_q_mul():
    check(q_mul(ONE, 100) == 100, "ONE * 100 = 100")
    check(q_mul(ONE // 2, ONE // 2) == ONE // 4, "0.5 * 0.5 = 0.25")
    r = q_mul(ONE // 2, SMAX)
    check(16383 <= r <= 16384, "0.5 * SMAX in [16383,16384]")


def test_clip():
    check(clip(50000) == SMAX, "clip(50000) = SMAX")
    check(clip(-50000) == SMIN, "clip(-50000) = SMIN")
    check(clip(1234) == 1234, "clip(1234) unchanged")


def test_biquad_lowpass_passes_dc():
    bq = Biquad()
    bq.lowpass_1pole(3277)
    for _ in range(200):
        bq.step(30000)
    check(29900 <= bq.y1 <= 30100, "DC settled near 30000")


def test_biquad_lowpass_attenuates_nyquist():
    bq = Biquad()
    bq.lowpass_1pole(3277)
    for i in range(200):
        x = 20000 if (i & 1) == 0 else -20000
        bq.step(x)
    check(abs(bq.y1) < 2000, "Nyquist heavily attenuated")


def test_fir_identity_kernel():
    taps = [ONE, 0, 0]
    history = [0, 0, 0]
    check(fir_step(taps, history, 1234) == 1234, "identity passes 1234")
    check(fir_step(taps, history, 5678) == 5678, "identity passes 5678")


def test_fir_moving_average():
    third = ONE // 3
    taps = [third, third, third]
    history = [0, 0, 0]
    fir_step(taps, history, 9000)
    fir_step(taps, history, 9000)
    y = fir_step(taps, history, 9000)
    check(8990 <= y <= 9010, "moving avg converges to 9000")


def test_peak_finds_max_abs():
    check(peak([100, -5000, 200, 3000, -1500]) == 5000, "peak = 5000")


def test_mean_absolute_constant():
    check(mean_absolute([4000] * 8) == 4000, "mean-abs constant = constant")


def test_mean_absolute_alternating():
    buf = [4000 if (i & 1) == 0 else -4000 for i in range(8)]
    check(mean_absolute(buf) == 4000, "mean-abs alternating ±4000 = 4000")


if __name__ == "__main__":
    test_q_mul()
    test_clip()
    test_biquad_lowpass_passes_dc()
    test_biquad_lowpass_attenuates_nyquist()
    test_fir_identity_kernel()
    test_fir_moving_average()
    test_peak_finds_max_abs()
    test_mean_absolute_constant()
    test_mean_absolute_alternating()
    print("=== audio_dsp ===")
    print(f"{PASS} passed, {FAIL} failed ({PASS + FAIL} total)")
    raise SystemExit(0 if FAIL == 0 else 1)
