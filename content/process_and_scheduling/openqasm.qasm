// Vidya — Process and Scheduling in OpenQASM (Quantum Parallelism)
//
// Analogy: independent qubit operations execute in parallel layers,
// like an OS scheduler assigning independent processes to cores.
// Circuit depth = makespan of the schedule.

OPENQASM 3.1;
include "stdgates.inc";

// ── Two independent "processes" scheduled in parallel ────────────
qubit[4] proc;
bit[4] proc_c;

// Layer 1: two independent tasks run simultaneously
h proc[0];         // process A
h proc[2];         // process B (independent, runs in parallel)

// Layer 2: each process continues independently
cx proc[0], proc[1]; // process A step 2
cx proc[2], proc[3]; // process B step 2 (parallel)

// Total depth = 2, despite 4 gates (parallel scheduling)
proc_c = measure proc;
// Each process ends as its own Bell pair: 00 or 11 per pair
// @expect proc_c in {0, 3, 12, 15}
