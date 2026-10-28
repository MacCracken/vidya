// Vidya — Algorithms in OpenQASM (Quantum Algorithms)
//
// Quantum algorithms exploit superposition and interference to solve
// problems faster than classical algorithms. Grover's search gives
// quadratic speedup for unstructured search. Deutsch-Jozsa determines
// function type in one query. QFT is the quantum analog of FFT.

OPENQASM 3.1;
include "stdgates.inc";

// ── Deutsch-Jozsa Algorithm ───────────────────────────────────────────
// Problem: given f(x), determine if f is constant (same output for
// all inputs) or balanced (equal 0s and 1s). Classical: need 2^(n-1)+1
// queries. Quantum: ONE query.
//
// For 2 input qubits, we implement a balanced oracle: f(x) = x0 XOR x1

qubit[3] dj;          // 2 input qubits + 1 output qubit
bit[2] dj_out;

// Prepare: inputs in |+⟩, output in |−⟩
x dj[2];             // output qubit to |1⟩
h dj[0];             // input 0 to |+⟩
h dj[1];             // input 1 to |+⟩
h dj[2];             // output to |−⟩

// Oracle: f(x) = x0 XOR x1 (balanced function)
// Implemented as: CNOT from each input to output
cx dj[0], dj[2];
cx dj[1], dj[2];

// Interference: apply H to inputs
h dj[0];
h dj[1];

// Measure inputs: |00⟩ = constant, anything else = balanced
dj_out[0] = measure dj[0];
dj_out[1] = measure dj[1];
// Result: |11⟩ (the oracle's mask x0 XOR x1) on every shot — not |00⟩,
// so f is balanced (correct!)
// @expect dj_out == 3

// ── Grover's Search (2 qubits, 4 items) ──────────────────────────────
// Searches for marked item in unsorted "database" of N=4 items.
// Classical: O(N) — up to 3 queries for N=4 (the 4th is inferred).
// Quantum: O(√N) — exactly 1 iteration for N=4.
// We mark item |11⟩ as the target.

qubit[2] grover;
bit[2] grover_out;

// Step 1: Uniform superposition
h grover[0];
h grover[1];

// Step 2: Oracle — mark |11⟩ by flipping its phase
// CZ gate: phase flip when both qubits are |1⟩
cz grover[0], grover[1];

// Step 3: Diffusion operator (amplitude amplification)
// H on all qubits
h grover[0];
h grover[1];
// Conditional phase flip on |00⟩
x grover[0];
x grover[1];
cz grover[0], grover[1];
x grover[0];
x grover[1];
// H on all qubits
h grover[0];
h grover[1];

// Measure: finds |11⟩ with probability 1 — N=4 with one marked item is
// the size where a single Grover iteration lands exactly on the target.
grover_out = measure grover;
// @expect grover_out == 3

// ── Quantum Fourier Transform (3 qubits) ─────────────────────────────
// QFT maps computational basis states to frequency domain — the
// quantum analog of the discrete Fourier transform (DFT).
// Classical FFT: O(n 2^n). QFT: O(n^2) gates on n qubits.
// QFT is the core subroutine in Shor's factoring algorithm.

qubit[3] qft;
bit[3] qft_out;

// Prepare input state |5⟩ = |101⟩
x qft[0];
x qft[2];

// QFT circuit: H + controlled rotations + swap
// Qubit 0
h qft[0];
// Controlled-R2 from qubit 1 to qubit 0
// R2 = phase(π/2); controlled version applies phase conditionally
cp(pi/2) qft[1], qft[0];
// Controlled-R3 from qubit 2 to qubit 0
cp(pi/4) qft[2], qft[0];

// Qubit 1
h qft[1];
cp(pi/2) qft[2], qft[1];

// Qubit 2
h qft[2];

// Bit-reversal (swap qubit 0 and qubit 2). stdgates.inc has `swap`;
// it is spelled out here as its 3-CNOT expansion (cx a,b; cx b,a;
// cx a,b) to show what the bit-reversal costs on CNOT-only hardware.
cx qft[0], qft[2];
cx qft[2], qft[0];
cx qft[0], qft[2];

qft_out = measure qft;
// The QFT of a basis state has equal magnitude on every output, so all
// 8 values are equally likely: the input |5⟩ now lives in the relative
// phases, which a computational-basis measurement cannot see.
// @expect qft_out in {0, 1, 2, 3, 4, 5, 6, 7}

// ── Bernstein-Vazirani Algorithm ──────────────────────────────────────
// Problem: find secret string s where f(x) = s·x (mod 2).
// Classical: n queries. Quantum: ONE query.
// Secret string: s = 101 (binary) = 5

qubit[4] bv;          // 3 input qubits + 1 output
bit[3] bv_out;

// Prepare output qubit in |−⟩
x bv[3];
h bv[0];
h bv[1];
h bv[2];
h bv[3];

// Oracle for s = 101: CNOT from input bits where s_i = 1
cx bv[0], bv[3];     // s[0] = 1
                       // s[1] = 0 (no gate)
cx bv[2], bv[3];     // s[2] = 1

// Apply H to inputs
h bv[0];
h bv[1];
h bv[2];

// Measure: gives |101⟩ = secret string s on every shot
// @expect bv_out == 5
bv_out[0] = measure bv[0];
bv_out[1] = measure bv[1];
bv_out[2] = measure bv[2];

// ── Quantum Counting (Grover iteration count estimation) ──────────────
// Combines Grover's oracle with QFT-based phase estimation to
// COUNT how many solutions exist without finding them all.
// Here we show the oracle + single Grover iteration structure (the
// phase-estimation register that does the counting is not shown).

qubit[3] count;
bit[3] count_out;

// 2 search qubits + 1 ancilla for oracle. The ancilla goes to |−⟩ (as
// in Deutsch-Jozsa above) so the Toffoli kicks back a -1 phase. Left in
// |0⟩, it would only copy f(x) into the ancilla — a bit-flip, not a
// phase mark — and the diffusion step could not amplify the target.
x count[2];
h count[2];
h count[0];
h count[1];

// Oracle: mark count[0]=1, count[1]=0 (value 1)
x count[1];
ccx count[0], count[1], count[2];  // Toffoli: phase-marks value 1
x count[1];

// Diffusion on search qubits
h count[0];
h count[1];
x count[0];
x count[1];
cz count[0], count[1];
x count[0];
x count[1];
h count[0];
h count[1];

// Return the ancilla from |−⟩ to |0⟩ before reading the register.
h count[2];
x count[2];

count_out = measure count;
// count_out = 1 on every shot: the marked item, found in one iteration.
// @expect count_out == 1
