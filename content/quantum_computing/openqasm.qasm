// Vidya — Quantum Computing in OpenQASM
//
// Dedicated quantum algorithms: Grover's search (3-qubit),
// quantum phase estimation building blocks, VQE ansatz structure,
// Shor's period-finding oracle concept, and noise-aware circuits.
// This is the deepest quantum content in the corpus.

OPENQASM 2.0;
include "qelib1.inc";

// ── Grover's Search (3 qubits, N=8) ──────────────────────────────────
// Search for |101⟩ in 8 items. Optimal iterations = floor(π/4 × √8) = 2
// This demonstrates the full algorithm: superposition → oracle → diffusion

qreg grover[3];
creg grover_out[3];

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

// Measure: should find |101⟩ with ~94.5% probability
measure grover -> grover_out;

// ── Quantum Phase Estimation (QPE) Building Block ─────────────────────
// QPE extracts eigenvalue phases from a unitary operator.
// Core of Shor's algorithm. Here: estimate phase of T gate (π/4).
// T|1⟩ = e^(iπ/4)|1⟩, so phase = 1/8 in binary = 0.001

qreg qpe[3];          // 2 counting qubits + 1 eigenstate
creg qpe_out[2];

// Prepare eigenstate |1⟩
x qpe[2];

// Counting register in superposition
h qpe[0];
h qpe[1];

// Controlled-U^(2^k) operations
// qubit 0: controlled-T (phase π/4)
cu1(pi/4) qpe[0], qpe[2];

// qubit 1: controlled-T^2 = controlled-S (phase π/2)
cu1(pi/2) qpe[1], qpe[2];

// Inverse QFT on counting register (2 qubits)
h qpe[0];
cu1(-pi/2) qpe[1], qpe[0];
h qpe[1];
// Swap counting qubits for bit reversal
cx qpe[0], qpe[1];
cx qpe[1], qpe[0];
cx qpe[0], qpe[1];

measure qpe[0] -> qpe_out[0];
measure qpe[1] -> qpe_out[1];

// ── VQE Ansatz (Variational Quantum Eigensolver) ──────────────────────
// VQE finds ground state energy of molecules by optimizing a
// parameterized circuit. The ansatz (trial wavefunction) is:
// Ry rotations + entangling CNOT layers. Classical optimizer
// tunes the angles to minimize ⟨H⟩.

qreg vqe[3];
creg vqe_out[3];

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
measure vqe -> vqe_out;

// ── Shor's Period Finding (Simplified Oracle) ─────────────────────────
// Shor's reduces factoring to period-finding: find r where a^r ≡ 1 (mod N)
// This oracle computes f(x) = 2^x mod 15 for factoring 15
// Period r=4: 2^0=1, 2^1=2, 2^2=4, 2^3=8, 2^4=1 (mod 15)

qreg shor[4];          // 2 counting + 2 work qubits
creg shor_out[2];

// Superposition on counting register
h shor[0];
h shor[1];

// Oracle: controlled multiplication by 2 mod 15
// Simplified: controlled-SWAP implements multiplication by 2 in binary
// when input = |01⟩, output = |10⟩ (1→2)
cx shor[0], shor[2];   // controlled operation based on counting qubit 0
cx shor[1], shor[3];   // controlled operation based on counting qubit 1

// Inverse QFT on counting register
h shor[0];
cu1(-pi/2) shor[1], shor[0];
h shor[1];

measure shor[0] -> shor_out[0];
measure shor[1] -> shor_out[1];
// Result encodes the period — classical post-processing extracts r

// ── Noise-Aware Circuit: Dynamical Decoupling ─────────────────────────
// Insert identity sequences (X-X or Y-Y) to refocus dephasing noise.
// Net effect: identity, but the spin echo cancels low-frequency noise.

qreg dd[1];
creg dd_out[1];

// Prepare superposition (sensitive to dephasing)
h dd[0];

// Dynamical decoupling: X-delay-X refocuses Z noise
// In a real system, delays happen naturally; we just show the gate pairs
x dd[0];              // first X pulse
// (wait half the idle period — noise accumulates phase)
x dd[0];              // second X pulse (refocuses the phase error)
// Net: X·X = I, but noise between them is cancelled

// Additional echo: same principle with different axis
z dd[0]; z dd[0];     // Z·Z = I echo

measure dd[0] -> dd_out[0];
