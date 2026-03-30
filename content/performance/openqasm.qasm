// Vidya — Performance in OpenQASM (Circuit Optimization)
//
// Circuit performance = fewer gates, less depth, fewer two-qubit gates.
// Each section demonstrates an optimization principle with the
// unoptimized and optimized circuit side by side.

OPENQASM 2.0;
include "qelib1.inc";

// ── Redundant gate elimination: X·X = I ───────────────────────────
// Unoptimized: 2 gates, does nothing
qreg redund[1];
creg redund_c[1];

x redund[0];
x redund[0];       // cancels the first X
// Optimizer removes both gates

measure redund -> redund_c;
// Expected: always 0

// ── Gate cancellation: H·H = I ────────────────────────────────────
qreg hcancel[1];
creg hcancel_c[1];

h hcancel[0];
h hcancel[0];      // cancels
measure hcancel -> hcancel_c;
// Expected: always 0

// ── Depth reduction via parallelism ───────────────────────────────
// Sequential (depth 4):
qreg seq[4];
creg seq_c[4];

cx seq[0], seq[1];     // depth 1
cx seq[1], seq[2];     // depth 2 (depends on q1)
cx seq[2], seq[3];     // depth 3 (depends on q2)
h seq[0];              // depth 2 (can run parallel with cx on q1,q2)

measure seq -> seq_c;

// Parallel (depth 2, same entanglement pattern):
qreg opt[4];
creg opt_c[4];

cx opt[0], opt[1];     // layer 1
cx opt[2], opt[3];     // layer 1 (parallel — different qubits)
cx opt[1], opt[2];     // layer 2

measure opt -> opt_c;

// ── SWAP decomposition: 3 CNOTs ───────────────────────────────────
// SWAP is expensive — decomposes into 3 CX gates
qreg swp[2];
creg swp_c[2];

x swp[0];              // prepare |10>

// SWAP via 3 CNOTs (standard decomposition)
cx swp[0], swp[1];
cx swp[1], swp[0];
cx swp[0], swp[1];
// Now |01> — qubits swapped

measure swp -> swp_c;
// Expected: always 01

// ── Minimize two-qubit gates (most expensive on hardware) ─────��────
// Two-qubit gates are ~10x noisier than single-qubit gates
// This Bell circuit uses exactly 1 CX (optimal):
qreg bell_opt[2];
creg bell_c[2];

h bell_opt[0];
cx bell_opt[0], bell_opt[1];  // only 1 two-qubit gate needed

measure bell_opt -> bell_c;

// ─�� Rotation merging: combine adjacent rotations ───────��──────────
qreg rot[1];
creg rot_c[1];

// Unoptimized: two separate rotations
rz(pi/4) rot[0];
rz(pi/4) rot[0];
// Optimizer merges into: rz(pi/2) rot[0]

h rot[0];          // make measurement interesting
measure rot -> rot_c;
