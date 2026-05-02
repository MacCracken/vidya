// Vidya — Serialization in OpenQASM (variable-length-encoding analog)
//
// Classical varint (LEB128) encodes a value in 1-10 bytes — small
// magnitudes use fewer bytes, the high bit signals continuation.
// The quantum analog is *amplitude encoding*: a value's magnitude
// determines how many qubits are needed to represent it without
// truncation, and ancilla qubits act as the continuation bits.
//
// 4-qubit register represents a 4-byte varint encoding:
//   q[0] — first encoded byte (low 7 bits of value, plus continuation)
//   q[1] — second byte if value >= 128 (entangled with q[0])
//   q[2] — third byte if value >= 16384 (entangled with q[1])
//   q[3] — fourth byte if value >= 2^21 (entangled with q[2])
//
// The CNOT chain models the continuation-bit dependency: each byte
// only "matters" if the previous byte's high bit was set. Measurement
// collapses the chain to the bytes-actually-used count.
//
// In real quantum information theory, this is the structural pattern
// of *adaptive measurements*: each qubit's measurement decision
// depends on the previous result. Adaptive quantum protocols use the
// same dependency chain that LEB128 uses to pack arbitrary-sized
// integers into variable byte counts.

OPENQASM 2.0;
include "qelib1.inc";

qreg q[4];
creg c[4];

// Value with continuation through all 4 bytes
h q[0];

// Each subsequent byte depends on the previous (continuation chain)
cx q[0], q[1];
cx q[1], q[2];
cx q[2], q[3];

measure q -> c;
