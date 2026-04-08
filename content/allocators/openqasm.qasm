// Vidya — Allocators in OpenQASM (Quantum Register Allocation)
//
// Quantum register allocation parallels classical memory allocation:
// qreg declares qubit storage (like malloc), creg declares classical
// storage for measurement results. Register sizes are fixed at
// declaration — quantum memory cannot be dynamically resized.

OPENQASM 2.0;
include "qelib1.inc";

// ── Fixed-size allocation: declare registers of various sizes ────
// Like a bump allocator: each qreg is a contiguous block
qreg single[1];    // 1 qubit — minimal allocation
qreg pair[2];      // 2 qubits — for entangled pairs
qreg byte_reg[8];  // 8 qubits — one quantum "byte"
qreg wide[16];     // 16 qubits — larger working space

creg single_c[1];
creg pair_c[2];
creg byte_c[8];
creg wide_c[16];

// ── Using the smallest allocation needed ─────────────────────────
// Good practice: allocate only what you need (like sized allocators)
// Single qubit: one Hadamard, measure
h single[0];
measure single[0] -> single_c[0];

// ── Pair allocation for entanglement ─────────────────────────────
// Two-qubit allocation is the minimum for Bell states
h pair[0];
cx pair[0], pair[1];
measure pair -> pair_c;

// ── Bulk allocation: initialize an 8-qubit register ──────────────
// Like allocating a buffer — all qubits start as |0⟩
h byte_reg[0];
h byte_reg[1];
h byte_reg[2];
h byte_reg[3];
h byte_reg[4];
h byte_reg[5];
h byte_reg[6];
h byte_reg[7];
measure byte_reg -> byte_c;

// ── Subregister addressing ───────────────────────────────────────
// Individual qubits within a register are accessed by index,
// like pointer arithmetic into an allocated block
x wide[0];         // set qubit 0
x wide[4];         // set qubit 4 (offset access)
x wide[15];        // set last qubit (bounds: 0..size-1)
cx wide[0], wide[1];  // operate on adjacent qubits
measure wide -> wide_c;
