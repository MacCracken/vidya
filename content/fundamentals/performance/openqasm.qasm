// Vidya — Performance in OpenQASM (Circuit Optimization)
//
// Circuit performance = fewer gates, less depth, fewer two-qubit gates.
// Each section demonstrates an optimization principle with the
// unoptimized and optimized circuit side by side.

OPENQASM 3.1;
include "stdgates.inc";

// ── Redundant gate elimination: X·X = I ───────────────────────────
// Unoptimized: 2 gates, does nothing
qubit[1] redund;
bit[1] redund_c;

x redund[0];
x redund[0];       // cancels the first X
// Optimizer removes both gates

redund_c = measure redund;
// Expected: always 0
// @expect redund_c == 0

// ── Gate cancellation: H·H = I ────────────────────────────────────
qubit[1] hcancel;
bit[1] hcancel_c;

h hcancel[0];
h hcancel[0];      // cancels
hcancel_c = measure hcancel;
// Expected: always 0
// @expect hcancel_c == 0

// ── Depth reduction via parallelism ───────────────────────────────
// Sequential fan-out (depth 4): a 4-qubit GHZ state built as a chain,
// each CNOT waiting on the one before it.
qubit[4] seq;
bit[4] seq_c;

h seq[0];              // depth 1
cx seq[0], seq[1];     // depth 2
cx seq[1], seq[2];     // depth 3 (depends on q1)
cx seq[2], seq[3];     // depth 4 (depends on q2)

seq_c = measure seq;
// @expect seq_c in {0, 15}

// Parallel fan-out (depth 3, the same GHZ state): once q0 and q1 both
// hold the value, each can feed one more qubit in the same layer — a
// tree instead of a chain. (Reordering CNOTs that SHARE a qubit is not
// free: cx q1,q2 and cx q2,q3 do not commute, so a rewrite must keep
// the result, not just the gate list.)
qubit[4] opt;
bit[4] opt_c;

h opt[0];              // layer 1
cx opt[0], opt[1];     // layer 2
cx opt[0], opt[2];     // layer 3
cx opt[1], opt[3];     // layer 3 (parallel — different qubits)

opt_c = measure opt;
// @expect opt_c in {0, 15}

// ── SWAP decomposition: 3 CNOTs ───────────────────────────────────
// SWAP is expensive — decomposes into 3 CX gates (stdgates.inc's
// `swap` is defined as exactly these three)
qubit[2] swp;
bit[2] swp_c;

x swp[0];              // prepare |10>

// SWAP via 3 CNOTs (standard decomposition)
cx swp[0], swp[1];
cx swp[1], swp[0];
cx swp[0], swp[1];
// Now |01> — qubits swapped

swp_c = measure swp;
// Expected: always 01 (swp[0]=0, swp[1]=1: value 2)
// @expect swp_c == 2

// ── Minimize two-qubit gates (most expensive on hardware) ──────────
// Two-qubit gates are ~10x noisier than single-qubit gates
// This Bell circuit uses exactly 1 CX (optimal):
qubit[2] bell_opt;
bit[2] bell_c;

h bell_opt[0];
cx bell_opt[0], bell_opt[1];  // only 1 two-qubit gate needed

bell_c = measure bell_opt;
// @expect bell_c in {0, 3}

// ── Rotation merging: combine adjacent rotations ──────────────────
qubit[1] rot;
bit[1] rot_c;

// Unoptimized: two separate rotations, sandwiched in H so the phase
// they add becomes visible (an rz on |0⟩ alone is only a global phase)
h rot[0];
rz(pi/4) rot[0];
rz(pi/4) rot[0];
// Optimizer merges into: rz(pi/2) rot[0]
h rot[0];

rot_c = measure rot;
// P(1) = sin²(θ/2) = ½ for the merged θ = π/2
// @expect rot_c in {0, 1}
