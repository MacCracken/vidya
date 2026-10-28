// Vidya — Concurrency in OpenQASM (Quantum Parallelism)
//
// Quantum parallelism is intrinsic: gates on different qubits
// execute simultaneously. Superposition processes all basis states
// at once. Entanglement creates correlations without communication.

OPENQASM 3.1;
include "stdgates.inc";

// ── Natural parallelism: independent gates run simultaneously ─────
qubit[4] par;
bit[4] par_c;

// These 4 gates execute in ONE time step (depth = 1)
h par[0];
x par[1];
z par[2];
h par[3];

par_c = measure par;
// par[1] reads 1 and par[2] reads 0 (z on |0⟩ is invisible); par[0] and
// par[3] are 50/50 — so par_c is one of 0010, 0011, 1010, 1011.
// @expect par_c in {2, 3, 10, 11}

// ── Superposition: implicit parallel computation ──────────────────
// n qubits in superposition represent 2^n states simultaneously
qubit[3] sup;
bit[3] sup_c;

h sup[0];
h sup[1];
h sup[2];
// State is now all 8 bit strings simultaneously: 000 through 111

sup_c = measure sup;
// Measurement returns ONE of them, uniformly: you cannot read all 8.
// @expect sup_c in {0, 1, 2, 3, 4, 5, 6, 7}

// ── Entanglement: correlated without communication ────────────────
// EPR pair: measuring one qubit instantly determines the other
qubit[2] epr;
bit[2] epr_c;

h epr[0];
cx epr[0], epr[1];
// |Φ+> = (|00> + |11>)/√2
// Always correlated: both 0 or both 1, never 01 or 10

epr_c = measure epr;
// @expect epr_c in {0, 3}

// ── GHZ state: n-qubit entanglement ───────────────────────────────
// All-or-nothing correlation across 5 qubits
qubit[5] ghz;
bit[5] ghz_c;

h ghz[0];
cx ghz[0], ghz[1];
cx ghz[1], ghz[2];
cx ghz[2], ghz[3];
cx ghz[3], ghz[4];
// Only |00000> and |11111> — maximal entanglement

ghz_c = measure ghz;
// @expect ghz_c in {0, 31}

// ── Depth = parallel execution time ───────────────────────────────
// Circuit depth is the critical path (longest chain of dependent gates)
qubit[4] depth_demo;
bit[4] depth_c;

// Layer 1 (depth 1): all parallel
h depth_demo[0];
h depth_demo[1];
h depth_demo[2];
h depth_demo[3];

// Layer 2 (depth 2): two parallel CNOTs
cx depth_demo[0], depth_demo[1];
cx depth_demo[2], depth_demo[3];

// Layer 3 (depth 3): one CNOT
cx depth_demo[1], depth_demo[2];
// Total depth = 3 despite 7 gates

depth_c = measure depth_demo;
// Layer 1 made all 16 basis states equally likely and CNOTs only permute
// basis states, so depth_c is uniform over 0..15.
// @expect depth_c in {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}
