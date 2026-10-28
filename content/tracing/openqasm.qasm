// Vidya — Tracing in OpenQASM (Measurement as Observation)
//
// Analogy: mid-circuit measurement is like inserting a tracepoint.
// It observes the state (collapsing it), capturing a classical
// snapshot — like logging a variable's value during execution.

OPENQASM 3.1;
include "stdgates.inc";

// ── Tracepoint: measure mid-circuit to observe state ─────────────
qubit[2] q;
bit[1] trace0;    // first tracepoint capture
bit[1] trace1;    // second tracepoint capture
bit[2] final;

h q[0];
cx q[0], q[1];

// Tracepoint 1: observe qubit 0 (collapses superposition)
trace0[0] = measure q[0];

// Computation continues after trace
h q[1];

// Tracepoint 2: observe qubit 1
trace1[0] = measure q[1];

// Final measurement
final = measure q;
// A measured qubit stays in the state it collapsed to, so final[0]
// always equals trace0 and final[1] always equals trace1. Each trace
// is 0 or 1 at random, so final takes all four values.
// @expect trace0 in {0, 1}
// @expect trace1 in {0, 1}
// @expect final in {0, 1, 2, 3}
