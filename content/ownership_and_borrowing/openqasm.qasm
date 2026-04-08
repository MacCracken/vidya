// Vidya — Ownership and Borrowing in OpenQASM (No-Cloning Theorem)
//
// Analogy: quantum no-cloning = move semantics. A qubit cannot be
// copied — it can only be moved (SWAP). Entanglement creates shared
// references, but measurement "drops" the quantum state.

OPENQASM 2.0;
include "qelib1.inc";

// ── Move semantics: SWAP transfers ownership ────────────────────
qreg owner[2];
creg owner_c[2];

h owner[0];            // owner[0] has a value
swap owner[0], owner[1]; // "move" — owner[1] now owns the state
// owner[0] is now |0⟩ (moved-from, like Rust's moved value)

measure owner -> owner_c;

// ── No copy: cloning is forbidden by physics ────────────────────
// There is no "copy gate" — this is the no-cloning theorem
// CNOT is NOT a copy: it entangles, creating a shared reference
qreg borrow[2];
creg borrow_c[2];

h borrow[0];
cx borrow[0], borrow[1]; // entangle, not copy — shared reference

measure borrow -> borrow_c;
