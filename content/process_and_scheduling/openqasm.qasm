// Vidya — Process and Scheduling in OpenQASM (Quantum Parallelism)
//
// Analogy: independent qubit operations execute in parallel layers,
// like an OS scheduler assigning independent processes to cores.
// Circuit depth = makespan of the schedule.

OPENQASM 2.0;
include "qelib1.inc";

// ── Two independent "processes" scheduled in parallel ────────────
qreg proc[4];
creg proc_c[4];

// Layer 1: two independent tasks run simultaneously
h proc[0];         // process A
h proc[2];         // process B (independent, runs in parallel)

// Layer 2: each process continues independently
cx proc[0], proc[1]; // process A step 2
cx proc[2], proc[3]; // process B step 2 (parallel)

// Total depth = 2, despite 4 gates (parallel scheduling)
measure proc -> proc_c;
