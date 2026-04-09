// Vidya — Tracing in OpenQASM (Measurement as Observation)
//
// Analogy: mid-circuit measurement is like inserting a tracepoint.
// It observes the state (collapsing it), capturing a classical
// snapshot — like logging a variable's value during execution.

OPENQASM 2.0;
include "qelib1.inc";

// ── Tracepoint: measure mid-circuit to observe state ─────────────
qreg q[2];
creg trace0[1];    // first tracepoint capture
creg trace1[1];    // second tracepoint capture
creg final[2];

h q[0];
cx q[0], q[1];

// Tracepoint 1: observe qubit 0 (collapses superposition)
measure q[0] -> trace0[0];

// Computation continues after trace
h q[1];

// Tracepoint 2: observe qubit 1
measure q[1] -> trace1[0];

// Final measurement
measure q -> final;
