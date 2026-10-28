// Vidya — Filesystems in OpenQASM (Quantum State Storage)
//
// Analogy: registers are storage locations, measurement reads data,
// and gate operations write data — like filesystem read/write.
// Multiple registers partition the qubit space like directories.

OPENQASM 3.1;
include "stdgates.inc";

// ── Partitioned storage (directories) ────────────────────────────
qubit[2] file_a;    // "file A" — 2 qubits of storage
qubit[2] file_b;    // "file B" — separate allocation
bit[2] read_a;
bit[2] read_b;

// "Write" data to file A
x file_a[0];
x file_a[1];       // file_a stores |11⟩

// "Write" data to file B
h file_b[0];
cx file_b[0], file_b[1]; // file_b stores entangled state

// "Read" — measurement extracts classical data
read_a = measure file_a;
read_b = measure file_b;
// read_a = 11 on every shot; read_b is 00 or 11 (the entangled pair
// always agrees), each half the time
// @expect read_a == 3
// @expect read_b in {0, 3}
