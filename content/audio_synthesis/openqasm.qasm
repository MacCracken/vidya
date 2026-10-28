// Vidya — Audio Synthesis in OpenQASM (rotation-as-oscillation)
//
// Classical subtractive synthesis: a phase accumulator + waveform
// function produces oscillation; an envelope state machine shapes
// amplitude over time; a voice multiplies them. Three primitives.
//
// The quantum analog is *rotation-as-oscillation*: a qubit rotated
// around the Y axis by angle θ has |1>-amplitude sin(θ/2). A qubit
// initialized in |0>, rotated through 4π over many gate steps (θ/2
// sweeps one full turn), traces out exactly one sine cycle — the unit
// circle is the oscillator. Envelope amplitude is encoded in a second qubit's
// rotation angle; voice = product = controlled rotation.
//
// Three primitives illustrated:
//   1. Phase qubit: a series of ry(2π/16) rotations advances the
//      phase θ/2 by 1/32 cycle each "sample" — half a step of the
//      16-entry sine LUT in the integer ports, because the amplitude
//      is sin(θ/2).
//   2. Envelope qubit: ry(small θ) for Attack ramp, ry(0) for
//      Sustain hold, ry(-small θ) for Release decay.
//   3. Voice qubit: controlled rotation gating the oscillator
//      output by the envelope amplitude.

OPENQASM 3.1;
include "stdgates.inc";

// === Sine oscillator: 4 phase steps trace an eighth of a cycle =======
//
// Initial state |0>. Each ry(π/8) rotation advances the phase θ/2 by
// π/16 = 1/32 cycle (half a LUT step).
// After 4 rotations, total angle = π/2 → |1>-amplitude = sin(π/4)
// ≈ 0.707, which is the Q15 LUT value 23170/32767 ≈ 0.707. Matches
// table[2] in the integer reference exactly (2 LUT steps = 1/8 cycle).

qubit[1] phase_q;
bit[1] phase_c;

// 4 phase advances: each ry(π/8) is half a LUT step.
ry(0.392699) phase_q[0];   // π/8
ry(0.392699) phase_q[0];   // 2π/8 = π/4
ry(0.392699) phase_q[0];   // 3π/8
ry(0.392699) phase_q[0];   // 4π/8 = π/2

phase_c[0] = measure phase_q[0];
// P(1) = 0.707² = ½: the readout is 0 or 1 with equal probability.
// @expect phase_c in {0, 1}


// === Square wave: H + Z gives ±1 superposition halves ================
//
// A square wave alternates between two basis states. Hadamard-then-
// Z prepares (|0> - |1>)/√2 — a state whose measurement collapses
// to 0 or 1 with equal probability, modelling the binary ±1 nature
// of the square waveform.

qubit[1] square_q;
bit[1] square_c;

h square_q[0];
z square_q[0];

square_c[0] = measure square_q[0];
// @expect square_c in {0, 1}


// === ADSR envelope: 4 stages as 4 successive rotations ==============
//
// Each ADSR stage corresponds to one gate that rotates the envelope
// qubit's amplitude. Attack: rotate up. Decay: rotate down a bit.
// Sustain: identity (no gate). Release: rotate down to |0>.

qubit[1] env_q;
bit[1] env_c;

// Attack: rotate up to peak amplitude (|1>).
ry(3.14159) env_q[0];      // π → full rotation to |1>

// Decay: rotate back down toward sustain.
ry(-0.785398) env_q[0];    // -π/4 → partial release

// Sustain: identity (no gate emitted; the qubit holds).

// Release: rotate down to |0>.
ry(-2.35619) env_q[0];     // -3π/4 → back to |0>

env_c[0] = measure env_q[0];
// env_c = "0" on every shot: π - π/4 - 3π/4 = 0, back where it started.
// @expect env_c == 0


// === Voice = controlled rotation =====================================
//
// Voice multiplies oscillator × envelope. In the quantum analog,
// we use the envelope qubit to control a rotation on the voice
// qubit: when env is |1> (full amplitude), the controlled rotation
// fires; when env is |0> (silent), it does not.

qubit[1] voice_env;
qubit[1] voice_osc;
qubit[1] voice_out;
bit[1] voice_c;

// Envelope = |1> (gate on, full amplitude).
x voice_env[0];

// Oscillator mid-swing: ry(π/2) gives |1>-amplitude sin(π/4) ≈ 0.707,
// so P(osc = 1) = ½. (Its peak, amplitude 1, would be ry(π).)
ry(1.5708) voice_osc[0];   // π/2 → amplitude 0.707

// Voice output: a Toffoli (controlled-controlled-X) gated by env AND osc.
ccx voice_env[0], voice_osc[0], voice_out[0];

voice_c[0] = measure voice_out[0];
// voice_c is 0 or 1 with equal probability: with the envelope on, the
// voice passes the oscillator straight through, P(voice=1) = P(osc=1).
// @expect voice_c in {0, 1}


// --- Notes — synthesis vs rotation-as-oscillation -------------------
//
// Classical Q15 synth:
//   - Phase: integer counter wraps mod 2π
//   - Sine: 16-entry LUT indexed by phase >> 12
//   - Square: sign(phase - π)
//   - ADSR: 5-state machine with linear segments
//   - Voice: oscillator × envelope (Q15 multiply)
//
// Quantum analog (this file):
//   - Phase: ry(angle) rotation advances qubit amplitude
//   - Sine: rotations trace amplitude on the unit circle
//   - Square: H + Z gives binary-amplitude superposition
//   - ADSR: ry(±θ) gates per envelope stage
//   - Voice: ccx (controlled gate) ANDs env amplitude with osc
//
// In real quantum signal generation (NMR, qubit control,
// arbitrary-state preparation) the same rotation primitives
// build complex amplitude profiles. The classical synth is a
// degenerate case: rotations measured in the computational
// basis. Both regimes share the same arithmetic substrate.
