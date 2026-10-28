// Vidya — Explicit GPU Synchronization in OpenQASM (entanglement-as-fence analog)
//
// Classical timeline semaphores are monotonic counters: signal(N)
// advances the timeline; wait(target) returns when the counter
// reaches target. The quantum analog is *Bell-pair / GHZ-state
// synchronization*: a producer qubit gets entangled with a consumer
// qubit, and the consumer's measurement is constrained by the
// producer's state — exactly the semantics of "wait until producer
// signals."
//
// This circuit models a 4-stage pipeline:
//   q[0] — producer (compute queue)
//   q[1] — first dependent (graphics queue waiting on compute)
//   q[2] — second dependent (transfer queue waiting on compute)
//   q[3] — final consumer (waits on BOTH q[1] and q[2] — wait_all)
//
// CNOT chains entangle the dependents; a Toffoli sets q[3] to the AND
// of q[1] and q[2], so it reads "signaled" only when both are — the
// wait_all. (XORing q[3] with both, two CNOTs, would leave it 0 on
// every shot: two equal signals cancel.) Measurement of all four
// reveals the synchronization fan-out — the quantum equivalent of a
// render-graph topological sort over signal/wait relationships.
//
// The closest real pattern is teleportation in distributed quantum
// computing: a consumer can use its half of a shared entangled pair
// only after the producer's measurement result reaches it over a
// classical channel — that classical message is the "signal".

OPENQASM 3.1;
include "stdgates.inc";

qubit[4] q;
bit[4] c;

// Producer: signaled (1) or not (0) with equal probability (Hadamard)
h q[0];

// Two dependents wait on the producer
cx q[0], q[1];
cx q[0], q[2];

// Final consumer waits on BOTH dependents (wait_all = AND)
ccx q[1], q[2], q[3];

// Measure: all four collapse together; q[3] reflects the joint state
c = measure q;
// c is 0000 (nothing signaled) or 1111 (all signaled), never a mix
// @expect c in {0, 15}
