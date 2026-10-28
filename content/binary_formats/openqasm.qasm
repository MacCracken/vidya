// Vidya — Binary Formats in OpenQASM (Circuit Serialization)
//
// Analogy: QASM text is the "binary format" for quantum circuits.
// Register declarations are the header, gates are the instruction
// stream, measurements are the output section — structured format.

OPENQASM 3.1;
include "stdgates.inc";

// ── Header section: register declarations (like ELF headers) ────
qubit[3] data;
bit[3] out;

// ── Code section: gate instructions (like .text segment) ─────────
h data[0];
cx data[0], data[1];
cx data[1], data[2];

// ── Output section: measurement (like program output/exit) ───────
out = measure data;
// out reads 000 or 111 with equal probability, never a mix: the three
// qubits are in a GHZ state.
// @expect out in {0, 7}
