// Vidya — Iterators in OpenQASM (Circuit Composition)
//
// Quantum "iteration" is gate repetition and circuit layering.
// Applying H to all qubits is "map". Building a GHZ state by
// chaining CNOT is "fold". Circuit depth is iteration count.
//
// OpenQASM 3 also has real loops: `for uint i in [0:3] { h map_q[i]; }`
// (ranges are inclusive). qiskit's importer (qiskit-qasm3-import 0.6.0)
// cannot yet index a register by the loop variable, so map and fold are
// unrolled by hand below; the repeated-application section, whose body
// does not use the index, is a real `for` loop.

OPENQASM 3.1;
include "stdgates.inc";

// ── Map: apply H to every qubit (parallel) ────────────────────────
qubit[4] map_q;
bit[4] map_c;

h map_q[0];
h map_q[1];
h map_q[2];
h map_q[3];
// Creates equal superposition of all 16 basis states

map_c = measure map_q;
// Measurement picks one of the 16, uniformly
// @expect map_c in {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}

// ── Fold: chain CNOT to build GHZ state ───────────────────────────
// GHZ = (|00000> + |11111>)/√2
qubit[5] ghz;
bit[5] ghz_c;

h ghz[0];              // seed with superposition
cx ghz[0], ghz[1];    // propagate entanglement
cx ghz[1], ghz[2];
cx ghz[2], ghz[3];
cx ghz[3], ghz[4];
// Result: only |00000> and |11111> have nonzero amplitude

ghz_c = measure ghz;
// @expect ghz_c in {0, 31}

// ── Repeated application: H twice = identity ──────────────────────
qubit[1] rep;
bit[1] rep_c;

// Two iterations ([0:1] includes both ends): |0> → |+> → |0>  (H·H = I)
for uint i in [0:1] {
    h rep[0];
}

rep_c = measure rep;
// Always measures 0
// @expect rep_c == 0

// ── Layer-by-layer: alternating single and two-qubit gates ────────
qubit[3] layer;
bit[3] layer_c;

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

layer_c = measure layer;
// Layer 1 made all 8 basis states equally likely, CNOTs only permute
// them, and Z-rotations change only phases — so layer_c is uniform.
// @expect layer_c in {0, 1, 2, 3, 4, 5, 6, 7}
