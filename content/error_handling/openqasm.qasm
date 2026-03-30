// Vidya — Error Handling in OpenQASM (Quantum Error Correction)
//
// 3-qubit bit-flip code: encode |0> as |000>, detect single
// bit-flip errors via syndrome measurement, correct without
// destroying the quantum state. Based on Shor's 1995 QEC proof.

OPENQASM 2.0;
include "qelib1.inc";

// ── Encode logical |0> as |000> ───────────────────────────────────
qreg data[3];     // 3 physical qubits = 1 logical qubit
qreg syn[2];      // 2 syndrome qubits for error detection
creg sc[2];       // syndrome measurement results
creg out[3];      // final data measurement

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

measure syn -> sc;
// Syndrome "11" → qubit 1 flipped
// Syndrome "10" → qubit 0 flipped
// Syndrome "01" → qubit 2 flipped
// Syndrome "00" → no error

// ── Correction: flip qubit 1 back ─────────────────────────────────
x data[1];

// ── Verify: state should be |000> again ───────────────────────────
measure data -> out;
