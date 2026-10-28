// Vidya — Interrupt Handling in OpenQASM (Measurement as Interrupt)
//
// Analogy: measurement collapses quantum state, forcing a classical
// branch — like a hardware interrupt that preempts execution and
// forces the processor into a handler routine.

OPENQASM 3.1;
include "stdgates.inc";

// ── Interrupt: measurement forces state collapse ─────────────────
qubit[2] running;
bit[2] irq;

h running[0];              // process running in superposition
cx running[0], running[1]; // entangled state

// "Interrupt fires" — measurement collapses to definite state
irq = measure running;
// Post-interrupt: system is in a definite classical state, 00 or 11
// @expect irq in {0, 3}
