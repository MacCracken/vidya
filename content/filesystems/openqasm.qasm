// Vidya — Filesystems in OpenQASM (Quantum State Storage)
//
// Analogy: registers are storage locations, measurement reads data,
// and gate operations write data — like filesystem read/write.
// Multiple registers partition the qubit space like directories.

OPENQASM 2.0;
include "qelib1.inc";

// ── Partitioned storage (directories) ────────────────────────────
qreg file_a[2];    // "file A" — 2 qubits of storage
qreg file_b[2];    // "file B" — separate allocation
creg read_a[2];
creg read_b[2];

// "Write" data to file A
x file_a[0];
x file_a[1];       // file_a stores |11⟩

// "Write" data to file B
h file_b[0];
cx file_b[0], file_b[1]; // file_b stores entangled state

// "Read" — measurement extracts classical data
measure file_a -> read_a;
measure file_b -> read_b;
