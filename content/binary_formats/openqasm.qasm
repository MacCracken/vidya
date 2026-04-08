// Vidya — Binary Formats in OpenQASM (Circuit Serialization)
//
// Analogy: QASM text is the "binary format" for quantum circuits.
// Register declarations are the header, gates are the instruction
// stream, measurements are the output section — structured format.

OPENQASM 2.0;
include "qelib1.inc";

// ── Header section: register declarations (like ELF headers) ────
qreg data[3];
creg out[3];

// ── Code section: gate instructions (like .text segment) ─────────
h data[0];
cx data[0], data[1];
cx data[1], data[2];

// ── Output section: measurement (like program output/exit) ───────
measure data -> out;
