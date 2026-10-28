// Vidya — JSON Lines (JSONL) in OpenQASM (record-stream analog)
//
// Classical JSONL is a sequence of records separated by \n — each
// record is a self-contained, independently-parseable structure with
// no state between records. The quantum analog is a *qubit register
// where each qubit encodes one independent record*: no entanglement
// between qubits means no cross-record state, exactly the JSONL
// invariant that "each line is independent."
//
// The 4-qubit register here represents 4 JSONL records:
//   q[0]  — record {"id":1} encoded as |0> (default state).
//   q[1]  — record {"id":2} encoded as |1> (X gate flip).
//   q[2]  — record {"id":3} encoded as |+> (Hadamard, "uncertain id").
//   q[3]  — record {"escape":true} — also |+>, marks the "escape this"
//            record class.
//
// Measurement reads each record independently. The classical equivalent
// of "build a per-line index then extract by index" is exactly what a
// qubit-register measurement does: each qubit's measurement outcome is
// independent of the others, recoverable by classical-bit index.
//
// In real systems, this is the structure compilers exploit when a
// circuit splits into sub-circuits with no shared qubits (Qiskit's
// `DAGCircuit.separable_circuits()` returns them): each piece can be
// scheduled or simulated independently — exactly like JSONL records
// that can be parsed in any order.

OPENQASM 3.1;
include "stdgates.inc";

qubit[4] q;
bit[4] c;

// Record 0: |0> — no gate needed
// Record 1: |1>
x q[1];
// Record 2: |+>
h q[2];
// Record 3: |+>
h q[3];

// "Index and extract" — each measurement reads one record independently
c = measure q;
// c[0] = 0 and c[1] = 1 every shot; c[2], c[3] are each 50/50 — so c is
// one of 0010, 0110, 1010, 1110.
// @expect c in {2, 6, 10, 14}
