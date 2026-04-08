// Vidya — Syscalls and ABI in OpenQASM (Gate Calling Convention)
//
// Analogy: custom gate definitions are the quantum ABI. Parameters
// are passed by value (angles), qubits are passed by reference.
// The gate signature defines the calling convention.

OPENQASM 2.0;
include "qelib1.inc";

// ── Custom gate = syscall with defined ABI ───────────────────────
// Gate signature: name(params) qubits — the calling convention
gate bell a, b {
    h a;
    cx a, b;
}

qreg args[2];
creg ret[2];

// "Syscall": invoke gate with qubit arguments (passed by reference)
bell args[0], args[1];

// "Return value": measurement reads the result
measure args -> ret;
