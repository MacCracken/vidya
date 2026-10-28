// Vidya — Effect Systems in OpenQASM (measurement as the effect)
//
// OpenQASM 3 has no effect handlers, no suspension and no effect types: a
// `def` subroutine may measure, and its signature does not say so. Gates
// are pure: each is unitary and can be undone. Measurement is the effect,
// non-unitary and irreversible (reset, unused here, is the other such
// instruction): it collapses the state and hands the program a bit, and a
// classically controlled gate is that bit steering the rest of the run.
// Deferred measurement moves the effect to the edge: measure-then-branch
// gives the outcomes of a quantum-controlled gate with every measurement
// at the end, a pure core inside an effectful shell. Each part has its own
// qubits; the corpus relies on qiskit starting them at |0>.

OPENQASM 3.1;
include "stdgates.inc";

// --- A. The effect in the middle: measure, then branch on the bit ---
// h puts a[0] in an equal superposition. Measuring it is the effect: the
// program receives 0 or 1 (50/50 in theory), and the `if` carries on with
// that answer, copying it onto a[1]. Read with bit [0] least significant,
// ca is 0 (both bits 0) or 3 (both 1), never 1 or 2. A single bit compares
// with a bool: qiskit's importer refuses `ca[0] == 1` ("conditions must be
// 'bit == const bool' or 'bitarray == const int'").
qubit[2] a;
bit[2] ca;
h a[0];
ca[0] = measure a[0];            // mid-circuit measurement: the effect
if (ca[0] == true) x a[1];       // its result steers the program
ca[1] = measure a[1];
// @expect ca in {0, 3}

// --- B. Deferred: the same outcomes, with the effect at the edge ---
// Replace the classical control with a quantum one (cx) and move every
// measurement to the end: the unitary core runs first and the one effect
// happens last. The outcome set is the same, {0, 3}, again 50/50 in theory
// (the checker compares sets, not frequencies). The states before the
// final measurement differ: B holds the entangled (|00> + |11>)/sqrt(2), A
// a classical mixture of |00> and |11>. Measured in this basis, they give
// the same distribution.
qubit[2] b;
bit[2] cb;
h b[0];
cx b[0], b[1];                   // deferred: quantum control instead
cb = measure b;                  // and every measurement at the end
// @expect cb in {0, 3}

// --- C. Pure gates leave no trace ---
// h is its own inverse, so h then h is the identity: u returns to |0> and
// every shot reads 0. With no effect in between, the computation is
// reversible and undoes itself completely.
qubit[1] u;
bit[1] r;
h u[0];
h u[0];                          // a pure gate and its inverse
r = measure u;
// @expect r == 0

// --- D. An effect in between leaves a trace ---
// The same h ... h with a measurement between them. The measurement
// collapses w to |0> or |1>, and the second h maps either one to an equal
// superposition, so r2 reads 0 or 1: h no longer undoes h. That is the
// irreversibility. Without `m = measure w;` every r2 would read 0 again,
// and `r2 in {0, 1}` would fail, since 1 never occurs.
qubit[1] w;
bit[1] m;
bit[1] r2;
h w[0];
m = measure w;                   // the effect in between...
h w[0];
r2 = measure w;                  // ...leaves a trace: h no longer undoes h
// @expect m in {0, 1}
// @expect r2 in {0, 1}
