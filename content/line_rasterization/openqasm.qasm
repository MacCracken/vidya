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
// In real quantum computing, this is exactly how *coherent state
// preparation* works for graphics applications: a quantum image
// renderer entangles control qubits with target pixel qubits to
// "draw" patterns into the register without touching each pixel
// individually — a structural advantage over classical Bresenham,
// which must visit every pixel along the line.

OPENQASM 2.0;
include "qelib1.inc";

qreg q[4];
creg c[4];

// Source qubit in superposition
h q[0];

// "Draw line" from (0,0) to (1,1): entangle the diagonal endpoints
cx q[0], q[3];

// Measure: q[0] and q[3] agree (00 or 11); q[1] and q[2] stay |0>
measure q -> c;
