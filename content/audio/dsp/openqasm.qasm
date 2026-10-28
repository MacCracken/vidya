// Vidya — Audio DSP in OpenQASM (interference-as-filtering)
//
// Classical audio DSP: a filter cascades multiplications and
// additions on a sample stream — biquad's 5-multiply IIR, FIR's
// N-tap convolution, level metering's max/sum operations. Three
// arithmetic primitives over a fixed-point integer signal.
//
// The quantum analog is *interference-as-filtering*: a qubit's
// amplitude encodes a "signal value", controlled rotations apply
// "filter coefficients", and measurement extracts the result.
// Lowpass behaviour falls out of constructive interference for
// in-phase components and destructive interference for high-frequency
// (anti-phase) components — exactly the signal-processing intuition
// behind a 1-pole lowpass filter.
//
// Three primitives illustrated:
//   1. A "signal" qubit prepared in a phase superposition modelling
//      a sample value; controlled-Y rotation applies a filter
//      coefficient.
//   2. Two sample qubits CNOT-combined into a tap qubit — the 2-tap
//      FIR structure. (What it computes is their parity, a
//      difference rather than an average; see that section.)
//   3. Measurement of the interfered register collapses to a
//      single classical "sample" — the analog of fixed-point
//      output emission.

OPENQASM 3.1;
include "stdgates.inc";

// === Lowpass: phase-rotation as filter coefficient ===================
//
// A 1-pole lowpass IIR computes y[n] = a*x[n] + (1-a)*y[n-1].
// In the quantum analog: prepare the signal qubit in a phase
// superposition (Hadamard), apply a controlled rotation by angle
// 2π*a, and measure. The probability of |1> after measurement is
// the analog of the filtered amplitude.

qubit[1] sig;
qubit[1] state;
bit[1] sig_c;

// Prepare signal in superposition (modelling sample = ½).
h sig[0];

// Apply a "filter coefficient" — small Y-rotation modelling a low
// cutoff. Small rotation = high attenuation of high-frequency
// (anti-phase) components.
ry(0.628) sig[0];           // 2π*0.1 ≈ 0.628 rad

// Mix with previous state via CNOT (the IIR feedback channel). The
// CNOT writes into `state` only; it never changes its control's
// measurement statistics, so sig_c depends on the rotations alone.
cx sig[0], state[0];

sig_c[0] = measure sig[0];
// P(1) = sin²((π/2 + 0.628)/2) ≈ 0.79: mostly 1, sometimes 0.
// @expect sig_c in {0, 1}


// === FIR moving-average: Hadamard as 2-tap interference ===============
//
// The simplest FIR is a 2-tap moving average:
//   y[n] = (x[n] + x[n-1]) / 2
//
// In the quantum analog: CNOT both samples into a tap qubit. Note what
// that computes: avg = x[n] XOR x[n-1], which for bits is
// |x[n] - x[n-1]| — the 2-tap DIFFERENCE (a high-pass), not the
// average. A true average needs an adder; parity is the cheapest
// 2-input reduction CNOTs give.

qubit[1] x_n;
qubit[1] x_n1;
qubit[1] avg;
bit[1] avg_c;

// Prepare both samples in superposition (modelling x[n] = x[n-1] = ½).
h x_n[0];
h x_n1[0];

// Combine: CNOT both into the averaging qubit.
cx x_n[0], avg[0];
cx x_n1[0], avg[0];

// The Hadamard cannot interfere anything here: avg is entangled with
// both samples, so on its own it is an even mixture of |0> and |1>,
// and avg_c is 0 or 1 with equal probability with or without this gate.
h avg[0];

avg_c[0] = measure avg[0];
// @expect avg_c in {0, 1}


// === Peak detection: OR via Toffoli =================================
//
// Peak detection over N samples returns max(|x[i]|). In binary
// form (sample is 0 or 1), peak = OR of all samples. There is no
// OR gate, so use De Morgan: peak = NOT (all samples are 0).
//
// We use NOT-then-Toffoli-then-NOT to detect the |000> case
// (all-quiet), and invert.

qubit[3] samples;
qubit[1] quiet_q;
qubit[1] pk_q;
bit[1] pk_c;

// Set sample 0 = 1, others = 0 (peak should be 1).
x samples[0];

// quiet_q = (sample[0]==0) AND (sample[1]==0) AND (sample[2]==0)
// Use X to invert each sample, AND via Toffoli, then re-invert.
x samples[0]; x samples[1]; x samples[2];
ccx samples[0], samples[1], pk_q[0];     // intermediate AND
ccx pk_q[0], samples[2], quiet_q[0];     // full AND → quiet
x samples[0]; x samples[1]; x samples[2];

// peak = NOT quiet
x quiet_q[0];                             // peak signal lives here

pk_c[0] = measure quiet_q[0];
// pk_c = "1" — at least one sample was set, so peak detected.
// @expect pk_c == 1


// --- Notes — DSP vs interference-as-filtering ------------------------
//
// Classical Q15 DSP:
//   - Biquad: 5 multiplies + 4 adds per sample
//   - FIR: N multiplies + N-1 adds per sample
//   - Peak: max(abs(s) for s in window)
//   - Mean-absolute: sum(abs(s)) / N
//
// Quantum analog (this file):
//   - Lowpass: ry(small angle) on signal qubit + CNOT feedback to
//     state qubit; small angle = strong low-frequency pass
//   - FIR 2-tap: CNOT parity of two signal qubits into a "tap"
//     register (a difference, not an average)
//   - Peak: NOT-Toffoli-NOT chain detects the all-zero case;
//     inverting gives "any non-zero" = OR = peak-present
//
// In real quantum signal processing (Quantum Singular-Value
// Transformation, QSVT, since 2019) these primitives generalise
// to *block-encoded* matrix functions: any polynomial filter shape
// can be implemented as a sequence of controlled rotations on a
// signal-amplitude qubit. The classical biquad is a degree-2
// polynomial; QSVT computes arbitrary polynomial transforms with
// circuits of depth O(degree). The two regimes meet at the same
// arithmetic structure: filtering is amplitude transformation.
