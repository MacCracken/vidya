// Vidya — ELF and Executable Formats in OpenQASM (Circuit Structure)
//
// Analogy: a QASM file has structured sections like an ELF binary.
// Version header = ELF magic, includes = dynamic linking,
// qreg/creg = segment table, gates = executable code.

OPENQASM 2.0;                   // magic number / format version
include "qelib1.inc";           // dynamic linker: load shared lib

// ── Segment table: register declarations ─────────────────────────
qreg text[2];      // .text — executable qubit space
qreg bss[2];       // .bss — uninitialized (all |0⟩)
creg result[4];

// ── .text: executable instructions ───────────────────────────────
h text[0];
cx text[0], text[1];

// ── .bss remains at zero (uninitialized segment) ─────────────────
// bss[0] and bss[1] are |0⟩ — never written

// ── Program exit: emit results ───────────────────────────────────
measure text[0] -> result[0];
measure text[1] -> result[1];
measure bss[0] -> result[2];
measure bss[1] -> result[3];
