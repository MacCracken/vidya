// Vidya — Fixed-Point Arithmetic in OpenQASM (Quantum Phase Encoding)
//
// Classical fixed-point packs a fractional value into the low bits of
// an integer register. The quantum analog is *phase encoding*: a
// single-qubit rotation Rz(2π · x / 2^n) writes an n-bit fixed-point
// value into the relative phase of a |+⟩ state, and the inverse
// quantum Fourier transform reads it back into computational-basis
// bits. This is the workhorse of quantum phase estimation, Shor's
// factoring, and any algorithm that needs to convert continuous
// rotation angles into discrete measurement outcomes.
//
// We illustrate three primitives:
//   1. Phase kickback as fixed-point write
//   2. Controlled rotations with binary-weighted angles (the same
//      shape as binary fixed-point)
//   3. Inverse-QFT readout that recovers a 3-bit fixed-point estimate

OPENQASM 2.0;
include "qelib1.inc";

// ── Primitive 1: phase kickback as a 1-bit fixed-point write ──────────
// |+⟩ ── Rz(θ) ── = (|0⟩ + e^(iθ)|1⟩)/√2
// θ = π corresponds to the fixed-point value 0.5 (half a full circle).
// Measurement in the X basis (H then Z-basis read) recovers the bit.

qreg pk[1];
creg pk_c[1];

h pk[0];                     // |+⟩
rz(pi) pk[0];                // write 0.5 — phase = π
h pk[0];                     // X-basis measurement
measure pk[0] -> pk_c[0];    // expect 1 with probability 1

// ── Primitive 2: binary-weighted controlled rotations ─────────────────
// For an n-bit fixed-point value x = b_{n-1}…b_1 b_0 / 2^n, the phase
// e^(2πi · x) decomposes into a product of controlled rotations:
//   Rz(π · b_{n-1})  Rz(π/2 · b_{n-2})  Rz(π/4 · b_{n-3}) …
// Each control bit contributes its place-value weight to the phase —
// identical in shape to fixed-point: high bit = π = 0.5, next = π/2 =
// 0.25, etc. Three control bits write a 3-bit fractional value.

qreg fp[4];                  // 3 control bits (fp[0..2]) + 1 target (fp[3])
creg fp_c[4];

// Prepare control register in the basis state |x⟩ where x = 0.625 = 0.101
// (b2=1, b1=0, b0=1). This is the value we will encode into the phase.
x fp[0];                     // b0 = 1
x fp[2];                     // b2 = 1

// Target qubit in |+⟩
h fp[3];

// Apply binary-weighted controlled rotations. The smaller-weight rotation
// goes first because in OpenQASM 2.0 we use cu1 (controlled phase) with
// fixed angle arguments — pi/4 for b0, pi/2 for b1, pi for b2.
cu1(pi/4) fp[0], fp[3];      // b0 contributes 1/8 of full circle
cu1(pi/2) fp[1], fp[3];      // b1 contributes 1/4 of full circle (b1=0, no-op)
cu1(pi)   fp[2], fp[3];      // b2 contributes 1/2 of full circle

// fp[3] now carries phase 2π · 0.625 = 5π/4 in its |1⟩ component.

// ── Primitive 3: inverse QFT to read the phase as fixed-point bits ────
// 3-qubit inverse QFT on a separate readout register — applied here as
// a self-contained example. A real phase-estimation circuit would run
// the controlled rotations onto a |+⟩ register and then inverse-QFT it
// to recover the 3 fractional bits in the computational basis.

qreg rd[3];
creg rd_c[3];

// Seed the readout register in superposition + a known phase
h rd[0]; h rd[1]; h rd[2];
rz(pi/2) rd[0];               // fractional offset to make readout interesting

// Inverse QFT (3 qubits, manual decomposition for OpenQASM 2.0)
swap rd[0], rd[2];
h rd[0];
cu1(-pi/2) rd[0], rd[1];
h rd[1];
cu1(-pi/4) rd[0], rd[2];
cu1(-pi/2) rd[1], rd[2];
h rd[2];

measure rd -> rd_c;

// ── Notes — the fixed-point/quantum bridge ────────────────────────────
//
// In classical 16.16 fixed-point, the value x is the integer floor(x · 2^16).
// In phase encoding, the value x ∈ [0, 1) is the angle θ = 2π · x.
// Both pack a fractional value into n bits and recover it via shift /
// inverse-QFT. The arithmetic on those bits — addition is rotation
// composition, multiplication is repeated controlled rotations — has
// the same place-value structure as classical fixed-point arithmetic.
//
// Quantum phase estimation reads an unknown phase φ to n bits of
// precision in O(n) controlled rotations + an n-qubit inverse QFT.
// That's the quantum analog of "convert this float to a fixed-point
// integer."
