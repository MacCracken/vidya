// Vidya — Compiler Bootstrapping in OpenQASM (Self-Referential Circuit)
//
// Bootstrapping analogy: a circuit that encodes its own structure.
// We encode the gate sequence "H, CNOT" as a quantum state, then
// apply those same gates — the circuit describes and executes itself.
// This mirrors how a compiler must compile its own source code.

OPENQASM 3.1;
include "stdgates.inc";

// ── Stage 0: The "source code" — encode gate identifiers ────────
// Encode gate types as qubit states:
//   |0⟩ = identity (no-op), |1⟩ = active gate
// Two bits: [is_hadamard, is_cnot]
qubit[2] source;
bit[2] source_c;

x source[0];       // bit 0 = 1: "H gate present"
x source[1];       // bit 1 = 1: "CNOT gate present"

// Read the source: a mid-circuit measurement the next stage branches on
source_c = measure source;
// source_c = 11 on every shot: both gates are "present"
// @expect source_c == 3

// ── Stage 1: The "compiled output" — execute the described gates ─
// Apply exactly the gates that source[] says to apply: OpenQASM 3's
// `if` tests a single measured bit and runs the gate only when it is 1
qubit[2] target;
bit[2] target_c;

// The bootstrap: apply H (because source[0] = 1)
if (source_c[0]) h target[0];
// The bootstrap: apply CNOT (because source[1] = 1)
if (source_c[1]) cx target[0], target[1];

// ── Stage 2: Verify — the output is the Bell state source described ─
target_c = measure target;
// target_c reads 00 or 11, never 01 or 10
// @expect target_c in {0, 3}

// ── Stage 3: Self-hosting — the compiled compiler compiles itself ─
// A second generation: the same gate sequence, run again on fresh qubits
qubit[2] gen2;
bit[2] gen2_c;

h gen2[0];
cx gen2[0], gen2[1];
// gen2 is in the same state as target — the compiler reproduces itself.
// (Same state, independent qubits: each shot's gen2_c and target_c are
// separate draws from {00, 11}.)

gen2_c = measure gen2;
// @expect gen2_c in {0, 3}
