// Vidya — Quantum Computing in OpenQASM
//
// Dedicated quantum algorithms: Grover's search (3-qubit),
// quantum phase estimation building blocks, VQE ansatz structure,
// Shor's period-finding oracle concept, and noise-aware circuits.
// This is the deepest quantum content in the corpus.

OPENQASM 3.1;
include "stdgates.inc";

// ── Grover's Search (3 qubits, N=8) ──────────────────────────────────
// Search for |101⟩ in 8 items. Optimal iterations = floor(π/4 × √8) = 2
// This demonstrates the full algorithm: superposition → oracle → diffusion

qubit[3] grover;
bit[3] grover_out;

// Step 1: Uniform superposition over all 8 states
h grover[0];
h grover[1];
h grover[2];

// === Iteration 1 ===
// Oracle: phase-flip |101⟩ (qubit 0=1, qubit 1=0, qubit 2=1)
// Mark |101⟩: flip qubit 1, apply CCZ (Toffoli + phase), unflip
x grover[1];
h grover[2];
ccx grover[0], grover[1], grover[2];
h grover[2];
x grover[1];

// Diffusion: 2|s⟩⟨s| - I
h grover[0]; h grover[1]; h grover[2];
x grover[0]; x grover[1]; x grover[2];
h grover[2];
ccx grover[0], grover[1], grover[2];
h grover[2];
x grover[0]; x grover[1]; x grover[2];
h grover[0]; h grover[1]; h grover[2];

// === Iteration 2 ===
x grover[1];
h grover[2];
ccx grover[0], grover[1], grover[2];
h grover[2];
x grover[1];

h grover[0]; h grover[1]; h grover[2];
x grover[0]; x grover[1]; x grover[2];
h grover[2];
ccx grover[0], grover[1], grover[2];
h grover[2];
x grover[0]; x grover[1]; x grover[2];
h grover[0]; h grover[1]; h grover[2];

// Measure: should find |101⟩ with ~94.5% probability (the rest spread
// over the other 7 values: N=8 is not a size where Grover is exact)
grover_out = measure grover;

// ── Quantum Phase Estimation (QPE) Building Block ─────────────────────
// QPE extracts eigenvalue phases from a unitary operator.
// Core of Shor's algorithm. Here: estimate phase of T gate (π/4).
// T|1⟩ = e^(iπ/4)|1⟩, so phase = 1/8 in binary = 0.001 — three bits,
// one more than the 2 counting qubits below can hold. So the estimate
// is blurred: 0.00 and 0.01 (outcomes 0 and 1) each come up 42.7% of
// the time, 10 and 11 7.3% each. A phase with ≤2 binary digits (e.g.
// 1/4) would read out exactly.

qubit[3] qpe;          // 2 counting qubits + 1 eigenstate
bit[2] qpe_out;

// Prepare eigenstate |1⟩
x qpe[2];

// Counting register in superposition
h qpe[0];
h qpe[1];

// Controlled-U^(2^k) operations
// qubit 0: controlled-T (phase π/4)
cp(pi/4) qpe[0], qpe[2];

// qubit 1: controlled-T^2 = controlled-S (phase π/2)
cp(pi/2) qpe[1], qpe[2];

// Inverse QFT on counting register (2 qubits). The bit-reversal swap
// comes FIRST: the first H must act on the qubit holding 2·φ, whose
// phase is just φ's last binary digit, so that digit lands in qpe[0]
// (the least significant bit of qpe_out). Putting the swap last
// instead reads φ = 1/4 as 50/25/25 noise. The swap is spelled out as
// 3 CNOTs; `swap qpe[0], qpe[1];` is the same gate.
cx qpe[0], qpe[1];
cx qpe[1], qpe[0];
cx qpe[0], qpe[1];
h qpe[0];
cp(-pi/2) qpe[0], qpe[1];
h qpe[1];

qpe_out[0] = measure qpe[0];
qpe_out[1] = measure qpe[1];
// @expect qpe_out in {0, 1, 2, 3}

// ── VQE Ansatz (Variational Quantum Eigensolver) ──────────────────────
// VQE finds ground state energy of molecules by optimizing a
// parameterized circuit. The ansatz (trial wavefunction) is:
// Ry rotations + entangling CNOT layers. Classical optimizer
// tunes the angles to minimize ⟨H⟩.

qubit[3] vqe;
bit[3] vqe_out;

// Layer 1: Single-qubit rotations (parameterized)
// In real VQE, these angles come from classical optimizer
ry(pi/3) vqe[0];     // θ₁ = π/3
ry(pi/4) vqe[1];     // θ₂ = π/4
ry(pi/6) vqe[2];     // θ₃ = π/6

// Entangling layer: linear CNOT chain
cx vqe[0], vqe[1];
cx vqe[1], vqe[2];

// Layer 2: More rotations
ry(pi/5) vqe[0];
ry(pi/7) vqe[1];
ry(pi/8) vqe[2];

// Second entangling layer
cx vqe[0], vqe[1];
cx vqe[1], vqe[2];

// Measure in computational basis
// Classical post-processing computes ⟨H⟩ from measurement statistics
vqe_out = measure vqe;

// ── Shor's Period Finding (Simplified Oracle) ─────────────────────────
// Shor's reduces factoring to period-finding: find r where a^r ≡ 1 (mod N)
// This oracle computes f(x) = 2^x mod 15 for factoring 15
// Period r=4: 2^0=1, 2^1=2, 2^2=4, 2^3=8, 2^4=1 (mod 15)
//
// The counting register needs 3 qubits (x = 0..7): with only 2, x
// would cover just one period and the readout would be uniform noise.

qubit[7] shor;          // 3 counting (shor[0..2]) + 4 work (shor[3..6])
bit[3] shor_out;

// Superposition on counting register; work register = |0001⟩ = 1
h shor[0];
h shor[1];
h shor[2];
x shor[3];

// Oracle: controlled multiplication by 2^(2^k) mod 15, k = counting bit.
// Simplified: on the values 1, 2, 4, 8 that occur here, ×2 mod 15 is a
// 1-bit rotate-left of the 4 work bits — three controlled-SWAPs.
// ×4 is a rotate by 2 (two controlled-SWAPs); ×16 ≡ ×1 needs no gate.
cswap shor[0], shor[5], shor[6];   // counting bit 0: ×2
cswap shor[0], shor[4], shor[5];
cswap shor[0], shor[3], shor[4];
cswap shor[1], shor[3], shor[5];   // counting bit 1: ×4
cswap shor[1], shor[4], shor[6];
                                   // counting bit 2: ×16 ≡ ×1 (mod 15)

// Inverse QFT on counting register (swap first, as in QPE above)
cx shor[0], shor[2];
cx shor[2], shor[0];
cx shor[0], shor[2];
h shor[0];
cp(-pi/2) shor[0], shor[1];
h shor[1];
cp(-pi/4) shor[0], shor[2];
cp(-pi/2) shor[1], shor[2];
h shor[2];

shor_out[0] = measure shor[0];
shor_out[1] = measure shor[1];
shor_out[2] = measure shor[2];
// Result encodes the period — classical post-processing extracts r:
// shor_out is 0, 2, 4 or 6 (= 8·s/r for s = 0..3), each 25%. Reading
// 2 or 6 gives s/r = 1/4 or 3/4, so r = 4, and gcd(2^2 ± 1, 15) = 3, 5.
// @expect shor_out in {0, 2, 4, 6}

// ── Noise-Aware Circuit: Dynamical Decoupling ─────────────────────────
// Insert identity sequences (X-X or Y-Y) to refocus dephasing noise.
// Net effect: identity, but the spin echo cancels low-frequency noise.

qubit[1] dd;
bit[1] dd_out;

// Prepare superposition (sensitive to dephasing)
h dd[0];

// Dynamical decoupling: X-delay-X refocuses Z noise
// In a real system, delays happen naturally; we just show the gate pairs
x dd[0];              // first X pulse
// (wait half the idle period — noise accumulates phase)
x dd[0];              // second X pulse (refocuses the phase error)
// Net: X·X = I, but noise between them is cancelled

// A Z·Z pair is also the identity, but it is NOT an echo for this
// noise: Z commutes with Z-type (dephasing) noise, so it refocuses
// nothing. Only pulses on a perpendicular axis (X or Y) flip the sign
// of the phase accumulated so far.
z dd[0]; z dd[0];     // Z·Z = I (no refocusing of Z noise)

// Undo the preparation so the check is deterministic: the whole
// sequence is the identity, so the superposition returns to |0⟩.
h dd[0];
dd_out[0] = measure dd[0];
// @expect dd_out == 0
