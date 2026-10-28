// Vidya — Bindless Resources in OpenQASM (qubit-as-handle analog)
//
// Classical bindless: a global table of resource descriptors indexed
// by integer handle, replacing per-draw bindings. The quantum analog
// is a *qubit register where each qubit is one handle slot*: the
// register state encodes the entire descriptor table at once, and
// integer handles map to qubit indices.
//
// 4-qubit register = 4-slot descriptor table. Operations:
//   - X gate on q[i]    — "alloc handle i" (mark slot occupied)
//   - measure q[i]      — "lookup handle i" (read slot state)
//   - reset q[i]        — "free handle i" (mark slot empty)
//
// In real quantum compute, this maps to *quantum register
// allocation*: the compiler tracks a free-pool of physical qubits and
// recycles them via reset, exactly like the classical bindless free-
// list pattern. The structural advantage of the quantum form:
// because all "handles" live in one register, batched
// resource updates can be expressed as multi-qubit gates (e.g., all
// uniform buffers updated via a multi-controlled gate) rather than
// per-handle ioctl calls.

OPENQASM 3.1;
include "stdgates.inc";

qubit[4] q;
bit[4] c;

// Allocate handles 0, 1, 2 (mark them occupied)
x q[0];
x q[1];
x q[2];

// Free handle 1 (reset to |0>)
reset q[1];

// Re-allocate (X again — the freed slot gets reused)
x q[1];

// Measure: handles 0, 1, 2 read 1; handle 3 reads 0 (c = 0111 = 7)
c = measure q;
// @expect c == 7
