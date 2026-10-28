// Vidya — Ownership and Borrowing in OpenQASM (No-Cloning Theorem)
//
// Analogy: quantum no-cloning = move semantics. A qubit cannot be
// copied — it can only be moved (SWAP). Entanglement creates shared
// references, but measurement "drops" the quantum state.

OPENQASM 3.1;
include "stdgates.inc";

// ── Move semantics: SWAP transfers ownership ────────────────────
qubit[2] owner;
bit[2] owner_c;

h owner[0];            // owner[0] has a value
// swap = "move" — owner[1] now owns the state. stdgates.inc has
// `swap owner[0], owner[1];`; it is expanded as its 3 CNOTs
// (a, b → b, a) to show that a move costs three 2-qubit gates.
cx owner[0], owner[1];
cx owner[1], owner[0];
cx owner[0], owner[1];
// owner[0] is now |0⟩ (moved-from, like Rust's moved value)

owner_c = measure owner;
// owner[0] reads 0 every shot; owner[1] carries the |+⟩ (50/50)
// @expect owner_c in {0, 2}

// ── No copy: cloning is forbidden by physics ────────────────────
// There is no "copy gate" — this is the no-cloning theorem
// CNOT is NOT a copy: it entangles, creating a shared reference
qubit[2] borrow;
bit[2] borrow_c;

h borrow[0];
cx borrow[0], borrow[1]; // entangle, not copy — shared reference

borrow_c = measure borrow;
// A copy would give two independent coin flips (all four outcomes);
// the entangled pair only ever reads 00 or 11
// @expect borrow_c in {0, 3}
