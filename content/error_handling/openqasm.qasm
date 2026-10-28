// Vidya — Error Handling in OpenQASM (Quantum Error Correction)
//
// 3-qubit bit-flip code: encode |0> as |000>, detect single
// bit-flip errors via syndrome measurement, correct without
// destroying the quantum state. Based on Shor's 1995 QEC proof.

OPENQASM 3.1;
include "stdgates.inc";

// ── Encode logical |0> as |000> ───────────────────────────────────
qubit[3] data;     // 3 physical qubits = 1 logical qubit
qubit[2] syn;      // 2 syndrome qubits for error detection
bit[2] sc;       // syndrome measurement results
bit[3] out;      // final data measurement

// Encoding: |0> → |000>
cx data[0], data[1];   // copy qubit 0 to qubit 1
cx data[0], data[2];   // copy qubit 0 to qubit 2
// State: |000>

// ── Introduce a bit-flip error on qubit 1 ─────────────────────────
x data[1];             // error! |000> → |010>

// ── Syndrome measurement (detects which qubit flipped) ────────────
// Syndrome 0: parity of qubits 0 and 1
cx data[0], syn[0];
cx data[1], syn[0];
// Syndrome 1: parity of qubits 1 and 2
cx data[1], syn[1];
cx data[2], syn[1];

sc = measure syn;
// Syndrome as an integer (sc[0] is bit 0, the way `if (sc == n)` reads):
// sc == 3 (sc[0]=1, sc[1]=1) → qubit 1 flipped
// sc == 1 (sc[0]=1, sc[1]=0) → qubit 0 flipped
// sc == 2 (sc[0]=0, sc[1]=1) → qubit 2 flipped
// sc == 0                    → no error
// @expect sc == 3

// ── Correction: dispatch on the syndrome ──────────────────────────
// OpenQASM 3 branches on the measured syndrome, so the correction is
// chosen by what was detected, not hard-coded to the injected error.
if (sc == 1) x data[0];
if (sc == 3) x data[1];
if (sc == 2) x data[2];

// ── Verify: state should be |000> again ───────────────────────────
out = measure data;
// @expect out == 0
