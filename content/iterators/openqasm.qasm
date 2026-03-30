// Vidya — Iterators in OpenQASM (Circuit Composition)
//
// Quantum "iteration" is gate repetition and circuit layering.
// Applying H to all qubits is "map". Building a GHZ state by
// chaining CNOT is "fold". Circuit depth is iteration count.

OPENQASM 2.0;
include "qelib1.inc";

// ── Map: apply H to every qubit (parallel) ────────────────────────
qreg map_q[4];
creg map_c[4];

h map_q[0];
h map_q[1];
h map_q[2];
h map_q[3];
// Creates equal superposition of all 16 basis states

measure map_q -> map_c;

// ── Fold: chain CNOT to build GHZ state ───────────────────────────
// GHZ = (|00000> + |11111>)/√2
qreg ghz[5];
creg ghz_c[5];

h ghz[0];              // seed with superposition
cx ghz[0], ghz[1];    // propagate entanglement
cx ghz[1], ghz[2];
cx ghz[2], ghz[3];
cx ghz[3], ghz[4];
// Result: only |00000> and |11111> have nonzero amplitude

measure ghz -> ghz_c;

// ── Repeated application: H twice = identity ──────────────────────
qreg rep[1];
creg rep_c[1];

h rep[0];              // |0> → |+>
h rep[0];              // |+> → |0>  (H·H = I)

measure rep -> rep_c;
// Always measures 0

// ── Layer-by-layer: alternating single and two-qubit gates ────────
qreg layer[3];
creg layer_c[3];

// Layer 1: single-qubit
h layer[0];
h layer[1];
h layer[2];

// Layer 2: entangling
cx layer[0], layer[1];
cx layer[1], layer[2];

// Layer 3: rotations
rz(pi/4) layer[0];
rz(pi/2) layer[1];
rz(pi) layer[2];

measure layer -> layer_c;
