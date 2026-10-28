// Vidya — Allocators in OpenQASM (Quantum Register Allocation)
//
// Quantum register allocation parallels classical memory allocation:
// `qubit[n]` declares qubit storage (like malloc), `bit[n]` declares
// classical storage for measurement results. Register sizes are fixed at
// declaration — quantum memory cannot be dynamically resized.

OPENQASM 3.1;
include "stdgates.inc";

// ── Fixed-size allocation: declare registers of various sizes ────
// Like a bump allocator: each `qubit[n]` declaration is a contiguous block
qubit[1] single;    // 1 qubit — minimal allocation
qubit[2] pair;      // 2 qubits — for entangled pairs
qubit[8] byte_reg;  // 8 qubits — one quantum "byte"
qubit[16] wide;     // 16 qubits — larger working space

bit[1] single_c;
bit[2] pair_c;
bit[8] byte_c;
bit[16] wide_c;

// ── Using the smallest allocation needed ─────────────────────────
// Good practice: allocate only what you need (like sized allocators)
// Single qubit: one Hadamard, measure
h single[0];
single_c[0] = measure single[0];
// single_c is 0 or 1 with equal probability
// @expect single_c in {0, 1}

// ── Pair allocation for entanglement ─────────────────────────────
// Two-qubit allocation is the minimum for Bell states
h pair[0];
cx pair[0], pair[1];
pair_c = measure pair;
// pair_c reads 00 or 11, never 01 or 10 — the Bell pair's correlation
// @expect pair_c in {0, 3}

// ── Bulk allocation: initialize an 8-qubit register ──────────────
// Like allocating a buffer — all qubits start as |0⟩ under qiskit and
// on IBM hardware (like calloc). OpenQASM 3 itself leaves a declared
// qubit's state undefined (like malloc), so portable code resets first.
h byte_reg[0];
h byte_reg[1];
h byte_reg[2];
h byte_reg[3];
h byte_reg[4];
h byte_reg[5];
h byte_reg[6];
h byte_reg[7];
byte_c = measure byte_reg;

// ── Subregister addressing ───────────────────────────────────────
// Individual qubits within a register are accessed by index,
// like pointer arithmetic into an allocated block
x wide[0];         // set qubit 0
x wide[4];         // set qubit 4 (offset access)
x wide[15];        // set last qubit (bounds: 0..size-1)
cx wide[0], wide[1];  // operate on adjacent qubits
wide_c = measure wide;
// wide_c has bits 0, 1, 4 and 15 set (the cx copied wide[0] into wide[1]):
// 2^0 + 2^1 + 2^4 + 2^15 = 32787 on every shot
// @expect wide_c == 32787
