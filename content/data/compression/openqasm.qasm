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
// OpenQASM's own `gate` definitions are the closest circuit analog: a
// sub-circuit stored once and invoked by name, like an LZ77 dictionary
// entry. (Transpilers do not factor circuits this way: Qiskit's output
// is flat basis gates, and its TemplateOptimization pass rewrites any
// sub-circuit that matches a template identity into a cheaper one.)

OPENQASM 3.1;
include "stdgates.inc";

qubit[4] q;
bit[4] c;

// "Source byte" prepared into superposition |+>
h q[0];

// Three back-references: each entangled with q[0]
cx q[0], q[1];
cx q[0], q[2];
cx q[0], q[3];

// Decode: measure all four — they will all agree (either 0000 or 1111)
c = measure q;
// @expect c in {0, 15}
