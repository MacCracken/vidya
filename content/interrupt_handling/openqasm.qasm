// Vidya — Interrupt Handling in OpenQASM (Measurement as Interrupt)
//
// Analogy: measurement collapses quantum state, forcing a classical
// branch — like a hardware interrupt that preempts execution and
// forces the processor into a handler routine.

OPENQASM 2.0;
include "qelib1.inc";

// ── Interrupt: measurement forces state collapse ─────────────────
qreg running[2];
creg irq[2];

h running[0];              // process running in superposition
cx running[0], running[1]; // entangled state

// "Interrupt fires" — measurement collapses to definite state
measure running -> irq;
// Post-interrupt: system is in a definite classical state
