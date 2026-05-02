// Vidya — Page Management in OpenQASM (qubit-as-page analog)
//
// Classical page management: allocate fixed-size 4KB pages from a file,
// recycle freed pages via a stack-shaped free list. The quantum analog
// is *qubit lifecycle in a quantum register*: each qubit starts in |0>
// (the "freshly-allocated, zeroed page"), gets prepared into a data
// state by some operation (the "page write"), is measured (the "page
// read"), and can be reset back to |0> (the "page free") so it can be
// reused for a different computation.
//
// The 4-qubit register here represents 4 page slots. We:
//   q[0]  — page 1: prepared into |1> (the "value 42" analog), then
//           measured to verify the prep landed correctly.
//   q[1]  — page 2: allocated, then "freed" via reset, then re-prepared
//           into a new state (showing reuse from the free list).
//   q[2]  — page 3: extension path — allocated into |+> (Hadamard) to
//           show that successive allocs return distinct slots.
//   q[3]  — page 4: idle — illustrates that unallocated slots stay |0>.
//
// In real quantum compilers, qubit allocation is exactly this pattern:
// the compiler tracks a free-list of "scratch" qubits and recycles them
// after a measurement collapse and reset (see Qiskit's QubitManager and
// Cirq's QidPool). The classical page-allocator/free-list pattern maps
// directly onto the quantum compiler's register pressure problem.

OPENQASM 2.0;
include "qelib1.inc";

qreg q[4];
creg c[4];

// "Allocate page 1 + write 42" — flip to |1>
x q[0];

// "Allocate page 2" — leave at |0> for now
// (In the classical analog: page 2 is allocated, then freed.)

// "Allocate page 3" — Hadamard to |+>, distinct from page 1
h q[2];

// Measure all four (the "page reads")
measure q -> c;
