// Vidya — Dependent Types in OpenQASM 3.1
//
// A dependent type depends on a VALUE: Vec n a is a vector whose length n
// is part of its type, Fin n an index proven < n, and a Σ pair (n, v) ties
// v's length to n. Agda, Idris, Lean, Rocq and F* check these even for
// values computed at run time; none of vidya's 11 languages can.
//
// OpenQASM sits with Zig, Rust, C and Cyrius: a register's size is a
// compile-time expression, the compiler compares lengths wherever whole
// registers meet (a broadcast gate, a measurement) and checks every
// constant index. The gate's importer takes no classical integers or
// subroutines, so Fin, Percent and Σ reduce to fixed sizes.

OPENQASM 3.1;
include "stdgates.inc";

// --- 1. Length-indexed vector ---
// The spec allows a named size (`const uint N = 3; qubit[N] q;`), but
// qiskit's importer, which the gate uses, refuses every const declaration
// ("node of type ConstantDeclaration is not supported"). So sizes here are
// literal expressions, computed by the compiler: qubit[2 + 3] is Vec(2 + 3).
qubit[2] a;
qubit[3] b;
qubit[2 + 3] r;
bit[2] ca;
bit[3] cb;
bit[2 + 3] cr;
bit[2 + 3] cj;

// a holds [1, 0] and b holds [0, 0, 1] (bit [0] is the least significant).
x a[0];
x b[2];

// append as a copy into r: each slice is checked against the register it
// receives (ranges are inclusive, so r[0:1] is 2 qubits and r[2:4] is 3).
// The wrong length is refused when the circuit loads, for a slice
//   cx a, r[0:2];   ->   mismatched lengths in gate broadcast
// or for whole registers
//   cx a, b;        ->   mismatched lengths in gate broadcast
// (cx copies a basis state only; a qubit in superposition cannot be cloned.)
cx a, r[0:1];
cx b, r[2:4];
cr = measure r;
// r reads a then b: bits 0 and 4, 1 + 16.
// @expect cr == 17

// append as an alias: `a ++ b` is a register of length 2 + 3 naming the
// same qubits. Measuring it into the wrong length is refused:
//   bit[4] c4; c4 = measure j;   ->   register size error
let j = a ++ b;
cj = measure j;
// @expect cj == 17

// The copies left a and b as they were.
ca = measure a;
cb = measure b;
// @expect ca == 1
// @expect cb == 4

// head of an empty register does not compile: a constant index is checked
// against the declared size, and a qubit[0] has no index 0:
//   qubit[0] e; x e[0];   ->   IndexError: index out of range
// A register's size is fixed when the circuit is compiled, so there is no
// run-time length, and the run-time head of the other ports has no
// counterpart here.

// --- 2. Fin n: an index proven in range ---
// Every constant index is checked against its register's size, so an
// index that loads is in range: `x f[3];` on this qubit[3] is refused
// (IndexError: index out of range). The range is not 0..2, though: as in
// Python, a negative index counts from the end, so f[-1] is f[2] and the
// first refused negative is f[-4]. There are no index variables to refine
// (this importer cannot index a register with a loop variable).
qubit[3] f;
bit[3] cf;
x f[1];
x f[-1];
cf = measure f;
// f[1] and f[-1] = f[2]: 2 + 4.
// @expect cf == 6

// --- 3. Refinement at the boundary, and 4. Σ type ---
// No analogue. A Percent needs a classical integer that a constructor
// validates, and this importer refuses integer declarations ("declarations
// of type 'int' are not supported"), classical assignment ("node of type
// ClassicalAssignment is not supported") and subroutines ("node of type
// SubroutineDefinition is not supported"). A Σ pair (n, data of length n)
// is what every register already is, with n fixed at compile time.

// --- 5. The escape hatch ---
// The size checks run only where whole registers meet. Each per-qubit
// index is checked against its own register, never against the other, so
// a 2-qubit control and a 3-qubit target pass when spelled out:
//   cx u, w;   ->   mismatched lengths in gate broadcast
// but this compiles, and nothing notices that w has a third qubit:
qubit[2] u;
qubit[3] w;
bit[3] cw;
bit[2] cw2;
x u[0];
x u[1];
x w[2];
cx u[0], w[0];
cx u[1], w[1];
cw = measure w;
// @expect cw == 7

// Measuring the 3-qubit w into 2 bits is refused as a whole
// (`cw2 = measure w;` -> register size error) and accepted bit by bit,
// which drops w[2]'s 1 without a word:
cw2[0] = measure w[0];
cw2[1] = measure w[1];
// @expect cw2 == 3

// What keeps sizes honest is writing whole-register operations, where the
// compiler compares lengths; a per-qubit spelling is checked by review only.
