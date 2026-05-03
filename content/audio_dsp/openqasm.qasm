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
//   2. Two qubits combined via a Hadamard interference test that
//      averages their phase amplitudes — the FIR moving-average
//      analog.
//   3. Measurement of the interfered register collapses to a
//      single classical "sample" — the analog of fixed-point
//      output emission.

OPENQASM 2.0;
include "qelib1.inc";

// === Lowpass: phase-rotation as filter coefficient ===================
//
// A 1-pole lowpass IIR computes y[n] = a*x[n] + (1-a)*y[n-1].
// In the quantum analog: prepare the signal qubit in a phase
// superposition (Hadamard), apply a controlled rotation by angle
// 2π*a, and measure. The probability of |1> after measurement is
// the analog of the filtered amplitude.

qreg sig[1];
qreg state[1];
creg sig_c[1];

// Prepare signal in superposition (modelling sample = ½).
h sig[0];

// Apply a "filter coefficient" — small Y-rotation modelling a low
// cutoff. Small rotation = high attenuation of high-frequency
// (anti-phase) components.
ry(0.628) sig[0];           // 2π*0.1 ≈ 0.628 rad

// Mix with previous state via CNOT (the IIR feedback channel).
cx sig[0], state[0];

measure sig[0] -> sig_c[0];


// === FIR moving-average: Hadamard as 2-tap interference ===============
//
// The simplest FIR is a 2-tap moving average:
//   y[n] = (x[n] + x[n-1]) / 2
//
// In the quantum analog: two signal qubits are combined via
// Hadamard interference. The output amplitude is the "average"
// in the basis-state probability sense.

qreg x_n[1];
qreg x_n1[1];
qreg avg[1];
creg avg_c[1];

// Prepare both samples in superposition (modelling x[n] = x[n-1] = ½).
h x_n[0];
h x_n1[0];

// Combine: CNOT both into the averaging qubit.
cx x_n[0], avg[0];
cx x_n1[0], avg[0];

// Hadamard the result for interference.
h avg[0];

measure avg[0] -> avg_c[0];


// === Peak detection: OR via Toffoli =================================
//
// Peak detection over N samples returns max(|x[i]|). In binary
// form (sample is 0 or 1), peak = OR of all samples. Toffoli on a
// pre-set ancilla in |1> implements this:
//   peak qubit starts |0>; X (ancilla) sets it to |1> if ANY
//   sample qubit is |1>; otherwise stays |0>.
//
// We use NOT-then-Toffoli-then-NOT to detect the |0|0|0|0> case
// (all-quiet), and invert.

qreg samples[3];
qreg quiet_q[1];
qreg pk_q[1];
creg pk_c[1];

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

measure quiet_q[0] -> pk_c[0];
// pk_c = "1" — at least one sample was set, so peak detected.


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
//   - FIR moving-avg: Hadamard interference of two signal qubits
//     into a "tap" register
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
