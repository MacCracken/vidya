// Vidya — IPC in OpenQASM (entanglement-as-shared-state analog)
//
// Classical IPC: shared memory lets two processes mutate the same
// state; pipes carry one-directional byte streams; named channels
// carry typed messages between endpoints. The quantum analog is
// *entanglement*: two qubits that share a Bell-pair correlation
// behave like a shared-memory cell — measuring either collapses
// both to the same value, exactly the way two processes reading
// shared memory observe the same byte.
//
// 4-qubit register represents the three IPC primitives:
//   q[0] — process A's view of shared memory
//   q[1] — process B's view of shared memory (entangled with q[0])
//   q[2] — pipe writer
//   q[3] — pipe reader (entangled with q[2] via CNOT — what writer
//          writes, reader reads)
//
// The H + CNOT pair on q[0]/q[1] creates the shared-memory entanglement;
// the CNOT q[2]→q[3] models the pipe's writer-to-reader transfer.
// Measuring all four collapses the system: q[0] and q[1] agree,
// q[3] reflects what q[2] held.
//
// In real quantum-distributed-systems research, entanglement
// distribution provides shared RANDOMNESS without a classical channel
// between the processes — the two endpoints just measure their local
// qubit and get correlated outcomes. It is not a channel: neither
// endpoint can choose the value the other sees (the no-communication
// theorem), so actually writing a message still needs classical
// communication. Shared randomness is what distributed consensus
// (common coins) and quantum key distribution use.

OPENQASM 3.1;
include "stdgates.inc";

qubit[4] q;
bit[4] c;

// Shared memory: A and B entangled
h q[0];
cx q[0], q[1];

// Pipe: writer's state propagates to reader
x q[2];
cx q[2], q[3];

c = measure q;
// q[0] and q[1] agree (00 or 11); q[2] and q[3] both read 1 — so c is
// 1100 or 1111.
// @expect c in {12, 15}
