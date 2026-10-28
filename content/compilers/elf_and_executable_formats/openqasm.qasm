// Vidya — ELF and Executable Formats in OpenQASM (Circuit Structure)
//
// Analogy: a QASM file has structured sections like an ELF binary.
// Version header = ELF magic, include = linking against a library
// (resolved when the file is parsed, so static rather than dynamic),
// qubit/bit declarations = segment table, gates = executable code.

OPENQASM 3.1;                   // magic number / format version
include "stdgates.inc";           // linker: pull in the gate library

// ── Segment table: register declarations ─────────────────────────
qubit[2] text;      // .text — executable qubit space
qubit[2] bss;       // .bss — uninitialized (all |0⟩)
bit[4] result;

// ── .text: executable instructions ───────────────────────────────
h text[0];
cx text[0], text[1];

// ── .bss remains at zero (uninitialized segment) ─────────────────
// bss[0] and bss[1] are |0⟩ — never written

// ── Program exit: emit results ───────────────────────────────────
result[0] = measure text[0];
result[1] = measure text[1];
result[2] = measure bss[0];
result[3] = measure bss[1];
// result reads 0000 or 0011: the .text Bell pair agrees with itself,
// and the .bss bits are always 0.
// @expect result in {0, 3}
