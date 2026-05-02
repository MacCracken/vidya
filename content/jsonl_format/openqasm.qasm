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
// In real systems, this is the structure of *circuit slicing* in
// quantum compilers (Qiskit's Layouter, Cirq's CircuitOperation): a
// circuit is treated as a sequence of "records" (sub-circuits with no
// shared qubits) that can be scheduled independently — exactly like
// JSONL records that can be parsed in any order.

OPENQASM 2.0;
include "qelib1.inc";

qreg q[4];
creg c[4];

// Record 0: |0> — no gate needed
// Record 1: |1>
x q[1];
// Record 2: |+>
h q[2];
// Record 3: |+>
h q[3];

// "Index and extract" — each measurement reads one record independently
measure q -> c;
