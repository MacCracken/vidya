// Vidya — Functional Patterns in OpenQASM 3.1
//
// OpenQASM 3 has gates and subroutines (`def`), but neither is a value:
// nothing can pass, return or capture one, so there are no higher-order
// functions or closures. Every gate is a unitary, reversible and with no
// hidden state for a call to change, which makes a gate the circuit's pure
// function. What carries over: composition (a gate built from gates, where
// order matters for gates that do not commute), the inverse of a
// composition (`inv @`), computing an irreversible function such as a + b
// into a fresh register, and uncomputing scratch so nothing is left
// behind. Folds and tail calls have no analogue; the nearest thing to
// partial application is a gate that fixes another's parameter
// (`gate rx90 q { rx(pi / 2) q; }`). Nor does a persistent list carry over:
// qubits are not values two versions could share, and the no-cloning
// theorem forbids copying an unknown state.

OPENQASM 3.1;
include "stdgates.inc";

// The corpus relies on qiskit starting every qubit at |0>, as hardware
// backends do (OpenQASM 3 itself leaves a fresh qubit undefined).

// --- 1. Composition: a gate defined from gates ---
// In a gate body the first line runs first, so h_then_x is pipe(h, x),
// which is compose(x, h). h and x do not commute, and the two orders
// leave different states: from |0>, h then x gives |+> (x leaves |+>
// alone) and x then h gives |->.
gate h_then_x q { h q; x q; }
gate x_then_h q { x q; h q; }

// Read in the X basis (h, then measure): |+> reads 0 and |-> reads 1.
// ord[2] applies x and h inline, one after the other: the same result as
// the composed gate x_then_h, as composition promises.
qubit[3] ord;
bit[3] ord_x;
h_then_x ord[0];
x_then_h ord[1];
x ord[2];
h ord[2];
h ord;
ord_x = measure ord;
// bit 0 (h then x) reads 0; bits 1 and 2 (x then h, composed and inline) read 1
// @expect ord_x == 6

// The gotcha: in the computational basis the two orders look alike. |+>
// and |-> differ only by the sign of |1>, so a plain measure gives 0 or 1
// with even odds for both, and a test that reads this way cannot tell the
// order apart.
qubit[2] ordz;
bit[2] ord_z;
h_then_x ordz[0];
x_then_h ordz[1];
ord_z = measure ordz;
// @expect ord_z in {0, 1, 2, 3}

// --- 2. Reversibility: a composition and its inverse ---
// inc2 adds 1 mod 4 to the 2-bit value lo + 2*hi: flip hi when lo is 1
// (the carry), then flip lo. `inv @ inc2` runs the inverse of each gate
// in reverse order, which subtracts 1, so inc2 then its inverse leaves
// the register as it found it. `pow(2) @ inc2` composes inc2 with itself:
// adding 2, a different thing from undoing it.
gate inc2 lo, hi {
    cx lo, hi;
    x lo;
}

qubit[2] once;
qubit[2] undo;
qubit[2] twice;
bit[2] once_v;
bit[2] undo_v;
bit[2] twice_v;
x once[0];                          // each register starts at 1
x undo[0];
x twice[0];
inc2 once[0], once[1];              // 1 + 1 = 2
inc2 undo[0], undo[1];              // 1 + 1 - 1 = 1
inv @ inc2 undo[0], undo[1];
pow(2) @ inc2 twice[0], twice[1];   // 1 + 2 = 3
once_v = measure once;
undo_v = measure undo;
twice_v = measure twice;
// @expect once_v == 2
// @expect undo_v == 1
// @expect twice_v == 3

// --- 3 and 4. An irreversible function, computed and uncomputed ---
// a + b (two bits in, a 2-bit sum out) cannot be a unitary on its own:
// (1, 0) and (0, 1) both give 1, and a unitary never merges two inputs.
// So half_add keeps its inputs and writes a + b into a fresh register:
// lo ^= a xor b (two cx), hi ^= a and b (ccx). Its three gates commute
// and each is its own inverse, so here `inv @ half_add` is half_add again.
gate half_add a, b, lo, hi {
    ccx a, b, hi;
    cx a, lo;
    cx b, lo;
}

// Compute a + b into scratch for every input at once (h puts each input
// bit in an even superposition), copy the sum out with cx (cx copies basis
// values; on a superposition it entangles rather than clones, which is all
// this needs), then uncompute the scratch with the inverse. The scratch is back to |0> on every shot, the inputs are
// untouched, and res holds a + b.
qubit[2] args;
qubit[2] scratch;
qubit[2] res;
bit[2] scratch_v;
bit[4] io;
h args[0];
h args[1];
half_add args[0], args[1], scratch[0], scratch[1];
cx scratch[0], res[0];
cx scratch[1], res[1];
inv @ half_add args[0], args[1], scratch[0], scratch[1];
scratch_v = measure scratch;
io[0] = measure args[0];
io[1] = measure args[1];
io[2] = measure res[0];
io[3] = measure res[1];
// @expect scratch_v == 0
// io = a + 2b + 4(a + b): (0,0) -> 0, (1,0) -> 5, (0,1) -> 6, (1,1) -> 3 + 8 = 11
// @expect io in {0, 5, 6, 11}

// --- Why scratch must be uncomputed: a trace left behind is an effect ---
// One input in |+>; f(x) = x is computed into scratch (cx), used as a
// phase (z gives (-1)^f(x)), and in the clean register uncomputed before
// the final h. The phase then interferes into a definite answer: the
// input reads 1. The dirty register skips the uncompute, the scratch stays
// entangled with the input, and the same h gives noise: the leftover copy
// acts like a measurement, a side effect of the computation.
qubit[2] clean;
qubit[2] dirty;
bit[2] clean_v;
bit[2] dirty_v;
h clean[0];
cx clean[0], clean[1];
z clean[1];
cx clean[0], clean[1];
h clean[0];
h dirty[0];
cx dirty[0], dirty[1];
z dirty[1];
h dirty[0];
clean_v = measure clean;
dirty_v = measure dirty;
// input (bit 0) reads 1 and scratch (bit 1) is back to 0
// @expect clean_v == 1
// @expect dirty_v in {0, 1, 2, 3}
