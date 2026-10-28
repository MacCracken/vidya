// Vidya — Direct DRM GPU Compute in OpenQASM (qubit-as-BO analog)
//
// Classical: open render node, GEM_CREATE returns BO handles, VA-map
// binds them to virtual addresses, submit dispatches, syncobj_wait
// waits for completion. The quantum analog is a *qubit register
// where each qubit is one BO slot*: the device "opens" by preparing
// the register in a known state, "alloc" flips a slot to |1>, and
// "submit + wait" is captured by sequential gates that consume the
// allocated slot.
//
// 4-qubit register = 4 BO slots:
//   q[0]  — the "device fd" (always |0> after init; analog of the
//            "always returns 42" placeholder fd).
//   q[1]  — BO handle 1 (alloc → flip to |1>)
//   q[2]  — BO handle 2 (alloc → flip to |1>)
//   q[3]  — submission outcome (computed from q[1] and q[2] — the
//            sync chain that completes once both BOs are dispatched)
//
// The Toffoli (ccx) from q[1] and q[2] into q[3] models the
// syncobj_wait semantic: q[3] reaches the "completed" state only after
// both upstream BOs have been allocated — an AND. (Two CNOTs into q[3]
// would compute the XOR instead: both BOs present would read 0, "not
// complete" — exactly backwards.) Measuring all four reads back the
// device's terminal state.
//
// In real DRM compute work, this maps onto AMDGPU's per-context
// fence chains: each submission allocates a syncobj seq, and a
// downstream wait blocks until all upstream seqs reach their
// targets — exactly the structure here.

OPENQASM 3.1;
include "stdgates.inc";

qubit[4] q;
bit[4] c;

// q[0] stays at |0> (the "fd" sentinel; nothing to allocate)

// Allocate two BOs
x q[1];
x q[2];

// Submission "completes" only when both BOs are present
ccx q[1], q[2], q[3];

c = measure q;
// c = 1110: fd q[0] = 0, both BOs = 1, submission q[3] = 1 (completed)
// @expect c == 14
