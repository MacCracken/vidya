// Vidya — Audio Synthesis in OpenQASM (rotation-as-oscillation)
//
// Classical subtractive synthesis: a phase accumulator + waveform
// function produces oscillation; an envelope state machine shapes
// amplitude over time; a voice multiplies them. Three primitives.
//
// The quantum analog is *rotation-as-oscillation*: a qubit rotated
// around the Y axis by angle θ has |1>-amplitude sin(θ/2). A qubit
// initialized in |0>, rotated through 2π over many gate steps,
// traces out exactly the sine waveform — the unit circle is the
// oscillator. Envelope amplitude is encoded in a second qubit's
// rotation angle; voice = product = controlled rotation.
//
// Three primitives illustrated:
//   1. Phase qubit: a series of ry(2π/16) rotations advances the
//      phase by 1/16 cycle each "sample", matching the 16-entry
//      sine LUT in the integer ports.
//   2. Envelope qubit: ry(small θ) for Attack ramp, ry(0) for
//      Sustain hold, ry(-small θ) for Release decay.
//   3. Voice qubit: controlled rotation gating the oscillator
//      output by the envelope amplitude.

OPENQASM 2.0;
include "qelib1.inc";

// === Sine oscillator: 4 phase steps trace a quarter cycle ============
//
// Initial state |0>. Each ry(π/8) rotation advances 1/16 cycle.
// After 4 rotations, total angle = π/2 → |1>-amplitude = sin(π/4)
// ≈ 0.707, which is the Q15 LUT value 23170/32767 ≈ 0.707. Matches
// table[2] in the integer reference exactly.

qreg phase_q[1];
creg phase_c[1];

// 4 phase advances: each ry(π/8) is one "sample" through the LUT.
ry(0.392699) phase_q[0];   // π/8
ry(0.392699) phase_q[0];   // 2π/8 = π/4
ry(0.392699) phase_q[0];   // 3π/8
ry(0.392699) phase_q[0];   // 4π/8 = π/2

measure phase_q[0] -> phase_c[0];


// === Square wave: H + Z gives ±1 superposition halves ================
//
// A square wave alternates between two basis states. Hadamard-then-
// Z prepares (|0> - |1>)/√2 — a state whose measurement collapses
// to 0 or 1 with equal probability, modelling the binary ±1 nature
// of the square waveform.

qreg square_q[1];
creg square_c[1];

h square_q[0];
z square_q[0];

measure square_q[0] -> square_c[0];


// === ADSR envelope: 4 stages as 4 successive rotations ==============
//
// Each ADSR stage corresponds to one gate that rotates the envelope
// qubit's amplitude. Attack: rotate up. Decay: rotate down a bit.
// Sustain: identity (no gate). Release: rotate down to |0>.

qreg env_q[1];
creg env_c[1];

// Attack: rotate up to peak amplitude (|1>).
ry(3.14159) env_q[0];      // π → full rotation to |1>

// Decay: rotate back down toward sustain.
ry(-0.785398) env_q[0];    // -π/4 → partial release

// Sustain: identity (no gate emitted; the qubit holds).

// Release: rotate down to |0>.
ry(-2.35619) env_q[0];     // -3π/4 → back to |0>

measure env_q[0] -> env_c[0];


// === Voice = controlled rotation =====================================
//
// Voice multiplies oscillator × envelope. In the quantum analog,
// we use the envelope qubit to control a rotation on the voice
// qubit: when env is |1> (full amplitude), the controlled rotation
// fires; when env is |0> (silent), it does not.

qreg voice_env[1];
qreg voice_osc[1];
qreg voice_out[1];
creg voice_c[1];

// Envelope = |1> (gate on, full amplitude).
x voice_env[0];

// Oscillator at peak (|1> via Hadamard then collapsing rotation).
ry(1.5708) voice_osc[0];   // π/2 → maximal amplitude

// Voice output: controlled-rotation gated by both env AND osc.
ccx voice_env[0], voice_osc[0], voice_out[0];

measure voice_out[0] -> voice_c[0];
// voice_c = "1" — voice produces output (env on AND osc at peak).


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
