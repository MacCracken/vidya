// Vidya — Concurrent File Access (flock) in OpenQASM (entanglement analog)
//
// Classical concurrent file access: shared locks (LOCK_SH) let many
// readers observe the same file simultaneously; an exclusive lock
// (LOCK_EX) excludes everyone else. The quantum analog is GHZ-style
// entanglement: when N qubits are prepared in (|00...0> + |11...1>)/√2,
// measuring any one collapses ALL of them to the same value — a form
// of "shared observation" with perfect correlation.
//
// The 4-qubit register here represents 4 reader processes. After the
// GHZ prep:
//   q[0]   — Hadamard, then CNOT to q[1], q[2], q[3]
//   q[1-3] — entangled with q[0]; "shared lock" semantics
//
// Measuring all four collapses to either 0000 or 1111 — every
// "reader" sees the same value, which is exactly what shared-lock
// guarantees provide for concurrent file readers: they all observe
// a consistent snapshot of the file.
//
// In real quantum systems, GHZ states are how "shared observation"
// is implemented: the W3C Quantum Internet draft proposes GHZ-state
// distribution for distributed-consensus protocols, where each
// participant's measurement is guaranteed to agree with the others.
// The classical flock(LOCK_SH) protocol provides the same property
// at the kernel level for filesystem readers.

OPENQASM 2.0;
include "qelib1.inc";

qreg q[4];
creg c[4];

// GHZ prep — the "shared lock" analog
h q[0];
cx q[0], q[1];
cx q[0], q[2];
cx q[0], q[3];

// Measure: every reader observes the same value (0000 or 1111)
measure q -> c;
