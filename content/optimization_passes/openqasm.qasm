// Vidya — Optimization Passes in OpenQASM (Circuit Optimization)
//
// Quantum circuit optimization mirrors compiler optimization passes:
// gate cancellation (like dead code elimination), gate commutation
// (like instruction reordering), and depth reduction (like critical
// path shortening). Each section shows before/after.

OPENQASM 2.0;
include "qelib1.inc";

// ── Pass 1: Gate cancellation (H·H = I, X·X = I) ────────────────
// Before optimization: redundant gates
qreg cancel[2];
creg cancel_c[2];

// Unoptimized: H H X X = identity (4 gates)
// H·H cancels, X·X cancels
// Optimized: 0 gates (entire sequence is identity)
// Showing the unoptimized version to demonstrate the pattern:
h cancel[0]; h cancel[0];      // H·H = I (cancels)
x cancel[1]; x cancel[1];      // X·X = I (cancels)

measure cancel -> cancel_c;

// ── Pass 2: Rotation merging ─────────────────────────────────────
// Before: Rz(π/4) · Rz(π/4) = two gates
// After:  Rz(π/2) = one gate (merged)
qreg merge[1];
creg merge_c[1];

// Unoptimized: two separate rotations
rz(pi/4) merge[0];
rz(pi/4) merge[0];
// Optimized equivalent: rz(pi/2) merge[0];  — one gate

measure merge[0] -> merge_c[0];

// ── Pass 3: Gate commutation for depth reduction ─────────────────
// When gates commute, reorder them to reduce circuit depth
qreg comm[4];
creg comm_c[4];

// Before reordering (depth 4):
//   layer 1: H q[0]
//   layer 2: CX q[0],q[1]
//   layer 3: H q[2]         ← wasted: could be in layer 1
//   layer 4: CX q[2],q[3]
// After reordering (depth 2):
//   layer 1: H q[0], H q[2]           — parallel
//   layer 2: CX q[0],q[1], CX q[2],q[3] — parallel
h comm[0];
h comm[2];          // moved up — commutes with gates on q[0],q[1]
cx comm[0], comm[1];
cx comm[2], comm[3]; // now parallel with the other CNOT

measure comm -> comm_c;

// ── Pass 4: Constant folding — known-state propagation ───────────
// If we know a qubit is |0⟩, we can simplify controlled gates
qreg fold[2];
creg fold_c[2];

// q[0] = |0⟩ (known), so CX(q[0], q[1]) is identity
// Before: cx fold[0], fold[1]; — gate does nothing
// After:  (removed entirely)
// Showing what the optimizer would eliminate:
cx fold[0], fold[1];   // control is |0⟩, so target unchanged

measure fold -> fold_c;

// ── Pass 5: Template matching — replace subcircuit with equivalent ─
// Three CNOTs = SWAP, but if we only need the effect on one qubit,
// we can replace SWAP with fewer gates
qreg tmpl[2];
creg tmpl_c[2];

x tmpl[0];
// Full SWAP (3 CNOTs):
cx tmpl[0], tmpl[1];
cx tmpl[1], tmpl[0];
cx tmpl[0], tmpl[1];
// Optimizer recognizes SWAP template, may replace with
// direct qubit remapping (0 gates) if topology allows

measure tmpl -> tmpl_c;
