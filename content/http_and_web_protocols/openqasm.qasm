// Vidya — HTTP and Web Protocols in OpenQASM (request-as-superposition analog)
//
// Classical HTTP/1.1: a request is a sequential token stream
// (request line, headers, body) where each token's parse depends on
// the previous one. The quantum analog is *sequential gate
// composition*: each gate's effect is conditioned on the qubits the
// previous gates touched, exactly the way HTTP parsing is sequential
// (you can't parse headers until you've consumed the request line).
//
// 4-qubit register represents the four phases of HTTP parsing:
//   q[0] — request line consumed
//   q[1] — headers consumed (entangled with q[0] — can't parse
//          headers until request line is done)
//   q[2] — body consumed (entangled with q[1] — can't parse body
//          until headers are done)
//   q[3] — response built (entangled with q[2] — can't respond
//          until request fully parsed)
//
// The CNOT chain models the "you must parse the previous phase
// before you can start the next" constraint that drives HTTP/1.1's
// sequential design. Measuring all four collapses the parse state
// to a deterministic outcome — the request was fully consumed and
// a response can be built.
//
// In real HTTP/2 / HTTP/3, the constraint is relaxed: streams are
// multiplexed, and frames from different requests can interleave on
// the same connection. The quantum analog would be parallel
// independent qubit registers, one per stream, with no entanglement
// between them — exactly the structural shift HTTP/2 made.

OPENQASM 2.0;
include "qelib1.inc";

qreg q[4];
creg c[4];

// Request line consumed (Hadamard puts it in superposition;
// measurement will collapse to "consumed" with certainty after the
// CNOT chain propagates).
h q[0];

// Headers consumed only after request line
cx q[0], q[1];

// Body consumed only after headers
cx q[1], q[2];

// Response built only after body
cx q[2], q[3];

measure q -> c;
