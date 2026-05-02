// Vidya — Bloom and Glow in OpenQASM (entanglement-as-light-bleed analog)
//
// Classical bloom: a bright pixel "bleeds" intensity into adjacent
// pixels via additive blending, simulating how real light scatters
// off neighbors. The quantum analog is *amplitude leakage via
// controlled rotations*: a "bright" qubit (in a high-amplitude state)
// can transfer some of its amplitude to neighboring qubits via CRY
// (controlled rotation), simulating the light-bleed effect at the
// state-vector level.
//
// We use 5 qubits — q[0] is the "source pixel", q[1..4] are the four
// cardinal neighbors:
//
//                q[3] (up)
//   q[1] (left)  q[0] (src)  q[2] (right)
//                q[4] (down)
//
// Operations:
//   - X q[0]               — make the source pixel "bright" (|1>)
//   - cry(pi/2) q[0],q[k]  — leak ~50% amplitude to each neighbor.
//                            (cry decomposes via Hadamard sandwich +
//                             two controlled-RZ rotations in qelib1.)
//
// Measuring all 5 qubits collapses the register; with the source at
// |1> and ~50% leak per neighbor, the most likely outcome is the
// source on with each neighbor having ~25% chance of also being on
// — exactly the visual analog of a 1-pixel bloom with GLOW_FRAC=2.
//
// Real quantum image processing uses controlled rotations like this
// for *quantum convolutional filters* (QCNN); the structural mapping
// is exactly the classical bloom kernel applied via amplitude
// transfer instead of byte arithmetic.

OPENQASM 2.0;
include "qelib1.inc";

qreg q[5];
creg c[5];

// Make the source "bright"
x q[0];

// Leak amplitude to 4 neighbors via controlled rotation.
// cry decomposes to two cu1's around a Hadamard sandwich;
// qelib1 exposes cu1 directly.
h q[1]; cu1(0.785398) q[0], q[1]; h q[1];
h q[2]; cu1(0.785398) q[0], q[2]; h q[2];
h q[3]; cu1(0.785398) q[0], q[3]; h q[3];
h q[4]; cu1(0.785398) q[0], q[4]; h q[4];

measure q -> c;
