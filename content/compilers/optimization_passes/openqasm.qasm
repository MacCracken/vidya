// Vidya — Optimization Passes in OpenQASM (Circuit Optimization)
//
// Quantum circuit optimization mirrors compiler optimization passes:
// gate cancellation (like dead code elimination), gate commutation
// (like instruction reordering), and depth reduction (like critical
// path shortening). Each section shows before/after.

OPENQASM 3.1;
include "stdgates.inc";

// ── Pass 1: Gate cancellation (H·H = I, X·X = I) ────────────────
// Before optimization: redundant gates
qubit[2] cancel;
bit[2] cancel_c;

// Unoptimized: H H X X = identity (4 gates)
// H·H cancels, X·X cancels
// Optimized: 0 gates (entire sequence is identity)
// Showing the unoptimized version to demonstrate the pattern:
h cancel[0]; h cancel[0];      // H·H = I (cancels)
x cancel[1]; x cancel[1];      // X·X = I (cancels)

cancel_c = measure cancel;
// @expect cancel_c == 0

// ── Pass 2: Rotation merging ─────────────────────────────────────
// Before: Rz(π/4) · Rz(π/4) = two gates
// After:  Rz(π/2) = one gate (merged)
qubit[1] merge;
bit[1] merge_c;

// Unoptimized: two separate rotations
rz(pi/4) merge[0];
rz(pi/4) merge[0];
// Optimized equivalent: rz(pi/2) merge[0];  — one gate

merge_c[0] = measure merge[0];
// A Z-rotation of |0⟩ is only a phase: merge_c reads 0 either way
// @expect merge_c == 0

// ── Pass 3: Gate commutation for depth reduction ─────────────────
// When gates commute, reorder them to reduce circuit depth
qubit[4] comm;
bit[4] comm_c;

// Text order is NOT schedule order. Written as
//   H q[0]; CX q[0],q[1]; H q[2]; CX q[2],q[3]
// the circuit is already depth 2: depth follows the dependency DAG,
// and gates on disjoint qubits run in parallel however they are listed.
//   layer 1: H q[0], H q[2]           — parallel
//   layer 2: CX q[0],q[1], CX q[2],q[3] — parallel
// Commutation pays off when gates SHARE a qubit: an rz on a CNOT's
// control commutes through the CNOT, so it can slide to the other side
// and merge with an rz there (Pass 2), removing a layer.
h comm[0];
h comm[2];          // listed early; the schedule is the same either way
cx comm[0], comm[1];
cx comm[2], comm[3]; // now parallel with the other CNOT

comm_c = measure comm;
// Two independent Bell pairs: each pair reads 00 or 11
// @expect comm_c in {0, 3, 12, 15}

// ── Pass 4: Constant folding — known-state propagation ───────────
// If we know a qubit is |0⟩, we can simplify controlled gates
qubit[2] fold;
bit[2] fold_c;

// q[0] = |0⟩ (known), so CX(q[0], q[1]) is identity
// Before: cx fold[0], fold[1]; — gate does nothing
// After:  (removed entirely)
// Showing what the optimizer would eliminate:
cx fold[0], fold[1];   // control is |0⟩, so target unchanged

fold_c = measure fold;
// @expect fold_c == 0

// ── Pass 5: Template matching — replace subcircuit with equivalent ─
// Three CNOTs = SWAP (stdgates.inc's `swap`), but if we only need the
// effect on one qubit, we can replace SWAP with fewer gates
qubit[2] tmpl;
bit[2] tmpl_c;

x tmpl[0];
// Full SWAP (3 CNOTs):
cx tmpl[0], tmpl[1];
cx tmpl[1], tmpl[0];
cx tmpl[0], tmpl[1];
// Optimizer recognizes SWAP template, may replace with
// direct qubit remapping (0 gates) if topology allows

tmpl_c = measure tmpl;
// The 1 moved from tmpl[0] to tmpl[1]: tmpl_c = 10 (value 2)
// @expect tmpl_c == 2
