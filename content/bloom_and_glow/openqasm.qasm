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
//   - cry(pi/2) q[0],q[k]  — leak half the source's intensity to each
//                            neighbor: P(neighbor on) = sin²(π/4) = ½.
//
// Measuring all 5 qubits collapses the register; with the source at
// |1> and a 50% leak per neighbor, the source is always on and each
// neighbor is independently on half the time, so all 16 neighbor
// patterns are equally likely and each neighbor's expected intensity
// is half the source's — the visual analog of a 1-pixel bloom with
// GLOW_FRAC=2 (glow = v / 2).
//
// Real quantum image processing uses controlled rotations like this
// for *quantum convolutional filters* (QCNN); the structural mapping
// is exactly the classical bloom kernel applied via amplitude
// transfer instead of byte arithmetic.

OPENQASM 3.1;
include "stdgates.inc";

qubit[5] q;
bit[5] c;

// Make the source "bright"
x q[0];

// Leak amplitude to 4 neighbors via controlled Y-rotation (cry is in
// stdgates.inc; it decomposes as ry(θ/2), cx, ry(-θ/2), cx).
cry(pi/2) q[0], q[1];
cry(pi/2) q[0], q[2];
cry(pi/2) q[0], q[3];
cry(pi/2) q[0], q[4];

c = measure q;
// c[0] (the source) is 1 on every shot; c[1..4] take all 16 patterns,
// so c is one of the 16 odd values 1, 3, ..., 31.
// @expect c in {1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31}
