// Vidya — Line Rasterization (Bresenham) in OpenQASM (qubit-diagonal analog)
//
// Classical Bresenham steps along a discrete pixel grid, lighting
// integer-coordinate cells that approximate a continuous line. The
// quantum analog is *register correlation*: a sequence of CNOTs
// from a control qubit creates a "line" of correlated qubits — when
// the control collapses, every entangled neighbor collapses to the
// same value, lighting a deterministic pattern across the register.
//
// We use a 4-qubit register as a 2x2 grid (q[y*2+x]):
//   q[0]=(0,0), q[1]=(1,0), q[2]=(0,1), q[3]=(1,1)
//
// To draw the diagonal from (0,0) to (1,1):
//   - Hadamard q[0] (the "source pixel")
//   - CNOT q[0] -> q[3] (the "endpoint pixel")
// Now q[0] and q[3] are entangled; measurement of either collapses
// both to the same value, lighting the diagonal pattern (00 or 11
// across q[0] and q[3]) just like Bresenham lights pixels (0,0) and
// (1,1) for a 2x2 diagonal.
//
// Where the analogy stops: every lit pixel still needs its own gate
// (a line of n pixels costs n-1 CNOTs from the source), so there is
// no saving over Bresenham's one step per pixel — and reading the
// image back out costs a measurement per pixel per shot.

OPENQASM 3.1;
include "stdgates.inc";

qubit[4] q;
bit[4] c;

// Source qubit in superposition
h q[0];

// "Draw line" from (0,0) to (1,1): entangle the diagonal endpoints
cx q[0], q[3];

// Measure: q[0] and q[3] agree (00 or 11); q[1] and q[2] stay |0>
c = measure q;
// So c is 0000 or 1001
// @expect c in {0, 9}
