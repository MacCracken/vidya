// Vidya — Syscalls and ABI in OpenQASM (Gate Calling Convention)
//
// Analogy: custom gate definitions are the quantum ABI. Parameters
// are passed by value (angles), qubits are passed by reference.
// The gate signature defines the calling convention.

OPENQASM 3.1;
include "stdgates.inc";

// ── Custom gate = syscall with defined ABI ───────────────────────
// Gate signature: name(params) qubits — the calling convention
gate bell a, b {
    h a;
    cx a, b;
}

qubit[2] args;
bit[2] ret;

// "Syscall": invoke gate with qubit arguments (passed by reference)
bell args[0], args[1];

// "Return value": measurement reads the result
ret = measure args;
// The Bell pair "returns" 00 or 11, each half the time
// @expect ret in {0, 3}
