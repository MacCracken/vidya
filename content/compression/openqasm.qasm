// Vidya — Compression (LZ77-shaped) in OpenQASM (state-overlap analog)
//
// Classical LZ77 finds repeated substrings and encodes them as
// (offset, length) back-references — a form of *state overlap* where
// the new bytes are functions of older bytes. The quantum analog is
// *register entanglement*: when two qubits are entangled, measuring
// one collapses the other into a deterministic state, exactly the way
// a back-reference token determines its bytes from earlier output.
//
// This circuit illustrates the structure:
//
//   q[0]                — the "source byte" (first occurrence).
//   q[1], q[2], q[3]    — back-references: each entangled with q[0]
//                          via CNOT, so measuring q[0] collapses all
//                          three to the same value. This is the
//                          quantum equivalent of "decode the match
//                          token by reading the source position."
//
// The "compression ratio" analog: one Hadamard prep + three CNOTs
// produces four correlated qubit values from one bit of entropy.
// The classical equivalent: store one byte plus three (offset=1,
// length=1) match tokens. Both expand structured input into a
// compact representation that recovers the full state on decode.
//
// Quantum compilers (Qiskit's transpiler, t|ket>) actually use this
// idea to compress circuits: identical sub-circuits become a single
// stored "template" with reference instructions, much like LZ77's
// dictionary entries.

OPENQASM 2.0;
include "qelib1.inc";

qreg q[4];
creg c[4];

// "Source byte" prepared into superposition |+>
h q[0];

// Three back-references: each entangled with q[0]
cx q[0], q[1];
cx q[0], q[2];
cx q[0], q[3];

// Decode: measure all four — they will all agree (either 0000 or 1111)
measure q -> c;
