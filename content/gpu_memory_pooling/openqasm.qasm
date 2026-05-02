// Vidya — GPU Memory Pooling in OpenQASM (qubit-pool analog)
//
// Classical bump allocator: a single bump pointer hands out monotonic
// offsets within a pool, and reset returns it to zero. The quantum
// analog is a *qubit register where the "bump pointer" is the count
// of qubits currently in |1>*: each "alloc" flips the next |0> qubit
// to |1>, and "reset" returns the entire register to |0>.
//
// 4-qubit pool (= 4 alloc slots). The sequence of X gates marks
// allocations 0, 1, 2 (qubits q[0], q[1], q[2]). reset q[1] models
// the "reset" pattern from the bump allocator: the slot is freed
// (returns to |0>), but unlike the classical bump (which only
// resets the entire pool), individual qubits CAN be reset
// independently — a structural advantage of the quantum form.
//
// In quantum compilers, this is exactly how *qubit allocation pools*
// work: a register of "scratch" qubits gets allocated in order, used
// by a circuit, and released via reset for the next circuit. The
// classical bump-allocator-with-reset pattern maps onto this
// directly.

OPENQASM 2.0;
include "qelib1.inc";

qreg q[4];
creg c[4];

// Allocate slots 0, 1, 2
x q[0];
x q[1];
x q[2];

// Reset slot 1 (free that allocation)
reset q[1];

// Re-allocate slot 1 (bump-allocator-style; the reuse)
x q[1];

// Measure: q[0]=1, q[1]=1, q[2]=1, q[3]=0
measure q -> c;
