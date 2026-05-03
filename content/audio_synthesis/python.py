#!/usr/bin/env python3
"""Vidya — Audio Synthesis — Python port. Q15 fixed-point.

Mirrors naad's API surface (Adsr, EnvelopeState, gate_on/off,
Voice). naad uses f32 + PolyBLEP; this port uses Q15 + naive
waveforms for cross-port portability.
"""

SCALE = 15
ONE = 32768
PHASE_MASK = 65535
PHASE_HALF = 32768


def q_mul(a, b):
    p = a * b
    return -((-p) >> SCALE) if p < 0 else (p >> SCALE)


def phase_advance(current, inc):
    return (current + inc) & PHASE_MASK


# 16-entry sine LUT in Q15.
SINE_TABLE = [
    0, 12540, 23170, 30274, 32767, 30274, 23170, 12540,
    0, -12540, -23170, -30274, -32767, -30274, -23170, -12540,
]


def osc_sine(phase):
    return SINE_TABLE[phase >> 12]


def osc_saw(phase):
    return phase - PHASE_HALF


def osc_square(phase):
    return 32767 if phase < PHASE_HALF else -32767


# === ADSR envelope ===

ENV_IDLE, ENV_ATTACK, ENV_DECAY, ENV_SUSTAIN, ENV_RELEASE = 0, 1, 2, 3, 4


class Adsr:
    def __init__(self):
        self.state = ENV_IDLE
        self.level = 0
        self.stage_samples = 0
        self.release_start = 0
        self.attack_samples = 0
        self.decay_samples = 0
        self.sustain_level = 0
        self.release_samples = 0

    def set_params(self, attack, decay, sustain, release):
        self.attack_samples = attack
        self.decay_samples = decay
        self.sustain_level = sustain
        self.release_samples = release

    def reset(self):
        self.state = ENV_IDLE
        self.level = 0
        self.stage_samples = 0
        self.release_start = 0

    def gate_on(self):
        self.state = ENV_ATTACK
        self.stage_samples = 0

    def gate_off(self):
        if self.state == ENV_IDLE:
            return False
        self.release_start = self.level
        self.state = ENV_RELEASE
        self.stage_samples = 0
        return True

    def step(self):
        if self.state == ENV_IDLE:
            self.level = 0
            return 0

        if self.state == ENV_ATTACK:
            inc = ONE // self.attack_samples
            self.level += inc
            self.stage_samples += 1
            if self.stage_samples >= self.attack_samples:
                self.level = ONE
                self.state = ENV_DECAY
                self.stage_samples = 0
            return self.level

        if self.state == ENV_DECAY:
            diff = ONE - self.sustain_level
            dec = diff // self.decay_samples
            self.level -= dec
            self.stage_samples += 1
            if self.stage_samples >= self.decay_samples:
                self.level = self.sustain_level
                self.state = ENV_SUSTAIN
                self.stage_samples = 0
            return self.level

        if self.state == ENV_SUSTAIN:
            self.level = self.sustain_level
            return self.level

        if self.state == ENV_RELEASE:
            dec = self.release_start // self.release_samples
            self.level -= dec
            self.stage_samples += 1
            if self.stage_samples >= self.release_samples:
                self.level = 0
                self.state = ENV_IDLE
                self.stage_samples = 0
            return self.level

        return 0


# === Voice ===

WAVE_SINE, WAVE_SAW, WAVE_SQUARE = 0, 1, 2


class Voice:
    def __init__(self, waveform, phase_inc, env):
        self.waveform = waveform
        self.phase = 0
        self.phase_inc = phase_inc
        self.env = env

    def oscillator(self, phase):
        if self.waveform == WAVE_SINE: return osc_sine(phase)
        if self.waveform == WAVE_SAW: return osc_saw(phase)
        if self.waveform == WAVE_SQUARE: return osc_square(phase)
        return 0

    def step(self):
        osc = self.oscillator(self.phase)
        self.phase = phase_advance(self.phase, self.phase_inc)
        env = self.env.step()
        return q_mul(osc, env)


PASS, FAIL = 0, 0
def check(cond, name):
    global PASS, FAIL
    if cond: PASS += 1
    else: FAIL += 1; print(f"  FAIL: {name}")


def test_phase_wrap():
    check(phase_advance(60000, 10000) == 4464, "phase wraps past PHASE_MAX")
    check(phase_advance(0, 1000) == 1000, "phase advances within range")


def test_sine_lut():
    check(osc_sine(0) == 0, "sin(0) = 0")
    check(osc_sine(16384) == 32767, "sin(π/2) = ONE")
    check(osc_sine(32768) == 0, "sin(π) = 0")
    check(osc_sine(49152) == -32767, "sin(3π/2) = -ONE")


def test_saw():
    check(osc_saw(0) == -PHASE_HALF, "saw(0) = -ONE")
    check(osc_saw(PHASE_HALF) == 0, "saw(π) = 0")
    check(osc_saw(65535) == 32767, "saw(near max) = ONE-1")


def test_square():
    check(osc_square(0) == 32767, "square first half = +ONE")
    check(osc_square(PHASE_HALF) == -32767, "square second half = -ONE")
    check(osc_square(32767) == 32767, "square just before half = +ONE")
    check(osc_square(65535) == -32767, "square at end = -ONE")


def test_env_attack():
    e = Adsr()
    e.set_params(4, 4, 16384, 4)
    e.gate_on()
    for _ in range(4): e.step()
    check(e.state == ENV_DECAY, "attack → decay")
    check(e.level == ONE, "level reaches ONE")


def test_env_decay_to_sustain():
    e = Adsr()
    e.set_params(4, 4, 16384, 4)
    e.gate_on()
    for _ in range(8): e.step()
    check(e.state == ENV_SUSTAIN, "decay → sustain")
    check(e.level == 16384, "level = sustain")


def test_env_sustain_holds():
    e = Adsr()
    e.set_params(4, 4, 16384, 4)
    e.gate_on()
    for _ in range(8): e.step()
    for _ in range(100): e.step()
    check(e.state == ENV_SUSTAIN, "sustain holds")
    check(e.level == 16384, "level held")


def test_env_release_to_idle():
    e = Adsr()
    e.set_params(4, 4, 16384, 4)
    e.gate_on()
    for _ in range(8): e.step()
    e.gate_off()
    check(e.release_start == 16384, "release_start captured")
    for _ in range(4): e.step()
    check(e.state == ENV_IDLE, "release → idle")
    check(e.level == 0, "level = 0")


def test_env_gate_off_during_attack_no_click():
    e = Adsr()
    e.set_params(8, 4, 16384, 4)
    e.gate_on()
    e.step(); e.step()
    e.gate_off()
    check(e.release_start == 8192, "release captures partial-attack level")


def test_voice_silent_when_idle():
    e = Adsr()
    e.set_params(4, 4, 16384, 4)
    v = Voice(WAVE_SINE, 8192, e)
    check(v.step() == 0, "voice silent when env idle")


def test_voice_audible_when_gated_on():
    e = Adsr()
    e.set_params(4, 4, 16384, 4)
    v = Voice(WAVE_SINE, 8192, e)
    e.gate_on()
    any_nonzero = any(v.step() != 0 for _ in range(16))
    check(any_nonzero, "voice produces non-zero when gated")


if __name__ == "__main__":
    test_phase_wrap()
    test_sine_lut()
    test_saw()
    test_square()
    test_env_attack()
    test_env_decay_to_sustain()
    test_env_sustain_holds()
    test_env_release_to_idle()
    test_env_gate_off_during_attack_no_click()
    test_voice_silent_when_idle()
    test_voice_audible_when_gated_on()
    print("=== audio_synthesis ===")
    print(f"{PASS} passed, {FAIL} failed ({PASS + FAIL} total)")
    raise SystemExit(0 if FAIL == 0 else 1)
