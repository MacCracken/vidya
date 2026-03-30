// Vidya — Concurrency in OpenQASM (Quantum Parallelism)
//
// Quantum parallelism is intrinsic: gates on different qubits
// execute simultaneously. Superposition processes all basis states
// at once. Entanglement creates correlations without communication.

OPENQASM 2.0;
include "qelib1.inc";

// ── Natural parallelism: independent gates run simultaneously ─────
qreg par[4];
creg par_c[4];

// These 4 gates execute in ONE time step (depth = 1)
h par[0];
x par[1];
z par[2];
h par[3];

measure par -> par_c;

// ── Superposition: implicit parallel computation ──────��───────────
// n qubits in superposition represent 2^n states simultaneously
qreg sup[3];
creg sup_c[3];

h sup[0];
h sup[1];
h sup[2];
// State is now all 8 bit strings simultaneously: 000 through 111

measure sup -> sup_c;

// ── Entanglement: correlated without communication ────────────────
// EPR pair: measuring one qubit instantly determines the other
qreg epr[2];
creg epr_c[2];

h epr[0];
cx epr[0], epr[1];
// |Φ+> = (|00> + |11>)/√2
// Always correlated: both 0 or both 1, never 01 or 10

measure epr -> epr_c;

// ── GHZ state: n-qubit entanglement ───────────────────────────────
// All-or-nothing correlation across 5 qubits
qreg ghz[5];
creg ghz_c[5];

h ghz[0];
cx ghz[0], ghz[1];
cx ghz[1], ghz[2];
cx ghz[2], ghz[3];
cx ghz[3], ghz[4];
// Only |00000> and |11111> — maximal entanglement

measure ghz -> ghz_c;

// ── Depth = parallel execution time ───────────────────────────────
// Circuit depth is the critical path (longest chain of dependent gates)
qreg depth_demo[4];
creg depth_c[4];

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

measure depth_demo -> depth_c;
