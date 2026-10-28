// Vidya — Networking Fundamentals in OpenQASM (handshake-as-entanglement analog)
//
// Classical TCP: a three-way handshake (SYN, SYN-ACK, ACK) brings
// two sockets into the ESTABLISHED state where data can flow. The
// quantum analog is *Bell-pair generation*: two qubits are
// entangled via H + CNOT, and from then on a measurement of one
// constrains the outcome of the other — the analog of "ESTABLISHED"
// (though, unlike a socket, the pair carries no bytes; see below).
//
// 4-qubit register represents two sockets and their data channel:
//   q[0] — client socket state (after handshake: in superposition)
//   q[1] — server socket state (after handshake: entangled with q[0])
//   q[2] — client send / server recv (CNOT from client → channel)
//   q[3] — server send / client recv (CNOT from server → channel)
//
// The H + CNOT pair on q[0]/q[1] is the quantum equivalent of the
// TCP three-way handshake; subsequent CNOTs onto q[2]/q[3] model
// data transfer through the established connection. Measuring all
// four qubits collapses the channel state, completing the
// "connection lifecycle" with a shared outcome: all four read 0000
// or all read 1111, chosen at random.
//
// In real quantum networking (Quantum Internet drafts, EPR-based
// distributed computing), this is how *quantum connections* are
// established: an entangled pair is the "session state". But a gate
// on one end does NOT propagate through the entanglement — nothing
// the other end can measure changes (no-signaling). Moving data
// still takes a classical channel: teleportation spends one shared
// pair plus 2 classical bits per qubit sent.

OPENQASM 3.1;
include "stdgates.inc";

qubit[4] q;
bit[4] c;

// Three-way handshake: H + CNOT entangles client and server
h q[0];
cx q[0], q[1];

// Data transfer: client sends (entangle channel q[2] with q[0])
cx q[0], q[2];

// Server echoes back (entangle q[3] with q[1])
cx q[1], q[3];

c = measure q;
// @expect c in {0, 15}
