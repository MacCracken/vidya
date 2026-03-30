// Vidya — Algorithms in OpenQASM (Quantum Algorithms)
//
// Quantum algorithms exploit superposition and interference to solve
// problems faster than classical algorithms. Grover's search gives
// quadratic speedup for unstructured search. Deutsch-Jozsa determines
// function type in one query. QFT is the quantum analog of FFT.

OPENQASM 2.0;
include "qelib1.inc";

// ── Deutsch-Jozsa Algorithm ───────────────────────────────────────────
// Problem: given f(x), determine if f is constant (same output for
// all inputs) or balanced (equal 0s and 1s). Classical: need 2^(n-1)+1
// queries. Quantum: ONE query.
//
// For 2 input qubits, we implement a balanced oracle: f(x) = x0 XOR x1

qreg dj[3];          // 2 input qubits + 1 output qubit
creg dj_out[2];

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
measure dj[0] -> dj_out[0];
measure dj[1] -> dj_out[1];
// Result: NOT |00⟩ → f is balanced (correct!)

// ── Grover's Search (2 qubits, 4 items) ──────────────────────────────
// Searches for marked item in unsorted "database" of N=4 items.
// Classical: O(N) = 4 queries average. Quantum: O(√N) ≈ 1 iteration.
// We mark item |11⟩ as the target.

qreg grover[2];
creg grover_out[2];

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

// Measure: should find |11⟩ with high probability
measure grover -> grover_out;

// ── Quantum Fourier Transform (3 qubits) ─────────────────────────────
// QFT maps computational basis states to frequency domain — the
// quantum analog of the discrete Fourier transform (DFT).
// Classical FFT: O(n 2^n). QFT: O(n^2) gates on n qubits.
// QFT is the core subroutine in Shor's factoring algorithm.

qreg qft[3];
creg qft_out[3];

// Prepare input state |5⟩ = |101⟩
x qft[0];
x qft[2];

// QFT circuit: H + controlled rotations + swap
// Qubit 0
h qft[0];
// Controlled-R2 from qubit 1 to qubit 0
// R2 = phase(π/2); controlled version applies phase conditionally
cu1(pi/2) qft[1], qft[0];
// Controlled-R3 from qubit 2 to qubit 0
cu1(pi/4) qft[2], qft[0];

// Qubit 1
h qft[1];
cu1(pi/2) qft[2], qft[1];

// Qubit 2
h qft[2];

// Bit-reversal (swap qubit 0 and qubit 2)
// swap is: cx a,b; cx b,a; cx a,b
cx qft[0], qft[2];
cx qft[2], qft[0];
cx qft[0], qft[2];

measure qft -> qft_out;

// ── Bernstein-Vazirani Algorithm ──────────────────────────────────────
// Problem: find secret string s where f(x) = s·x (mod 2).
// Classical: n queries. Quantum: ONE query.
// Secret string: s = 101 (binary) = 5

qreg bv[4];          // 3 input qubits + 1 output
creg bv_out[3];

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

// Measure: should give |101⟩ = secret string s
measure bv[0] -> bv_out[0];
measure bv[1] -> bv_out[1];
measure bv[2] -> bv_out[2];

// ── Quantum Counting (Grover iteration count estimation) ──────────────
// Combines Grover's oracle with QFT-based phase estimation to
// COUNT how many solutions exist without finding them all.
// Here we show the oracle + single Grover iteration structure.

qreg count[3];
creg count_out[3];

// 2 search qubits + 1 ancilla for oracle
h count[0];
h count[1];

// Oracle: mark |10⟩
x count[1];
ccx count[0], count[1], count[2];  // Toffoli: marks |10⟩
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

measure count -> count_out;
