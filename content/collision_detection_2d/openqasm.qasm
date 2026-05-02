// Vidya — 2D Collision Detection in OpenQASM (state-overlap analog)
//
// Classical AABB / circle collision asks "do these two regions
// overlap?" — a Boolean predicate over discrete shapes. The quantum
// analog is the *swap test*: given two single-qubit states |a⟩, |b⟩,
// the probability of measuring 0 on an ancilla after the controlled-
// SWAP sandwich is (1 + |⟨a|b⟩|²)/2. Fully orthogonal states ("non-
// colliding") give p(0) = 1/2; identical states ("fully overlapping")
// give p(0) = 1. Distance becomes inner-product magnitude.
//
// We illustrate three primitives that mirror the classical tests:
//   1. Identical states (full overlap)            — circle A == circle A
//   2. Orthogonal states (no overlap, "disjoint") — distant circles
//   3. Partial overlap via interference            — touching circles
//
// qelib1.inc gives us no `swap` gate, so the controlled-SWAP is
// expanded as 3 CNOTs (Toffoli-style) per the standard decomposition
// `cx a,b ; cx b,a ; cx a,b` with the ancilla controlling each.

OPENQASM 2.0;
include "qelib1.inc";

// ── Primitive 1: identical states — "fully overlapping" shapes ────────
// Both states |a⟩ = |b⟩ = |0⟩. Swap-test ancilla measures 0 with p=1.
qreg a1[1];
qreg b1[1];
qreg anc1[1];
creg out1[1];

h anc1[0];
// Controlled-SWAP(anc, a1[0], b1[0]) decomposed via Toffolis:
//   CNOT(b->a)
//   Toffoli(anc, a, b)
//   CNOT(b->a)
cx b1[0], a1[0];
ccx anc1[0], a1[0], b1[0];
cx b1[0], a1[0];
h anc1[0];
measure anc1[0] -> out1[0];
// Expectation: out1 = 0 with probability 1 (states are equal)

// ── Primitive 2: orthogonal states — "disjoint" shapes ────────────────
// |a⟩ = |0⟩, |b⟩ = |1⟩.  ⟨0|1⟩ = 0, so p(0) = 1/2 — the swap test
// can no longer distinguish, marking maximal "non-overlap."
qreg a2[1];
qreg b2[1];
qreg anc2[1];
creg out2[1];

x b2[0];                     // |b⟩ = |1⟩
h anc2[0];
cx b2[0], a2[0];
ccx anc2[0], a2[0], b2[0];
cx b2[0], a2[0];
h anc2[0];
measure anc2[0] -> out2[0];
// Expectation: out2 = 0 with probability 1/2 (orthogonal)

// ── Primitive 3: partial overlap via interference ─────────────────────
// |a⟩ = |0⟩, |b⟩ = (|0⟩ + |1⟩)/√2. ⟨a|b⟩ = 1/√2, so |⟨a|b⟩|² = 1/2,
// and p(0) = 3/4 — between full overlap and full disjoint, like
// "circles touching at one point."
qreg a3[1];
qreg b3[1];
qreg anc3[1];
creg out3[1];

h b3[0];                     // |b⟩ = |+⟩
h anc3[0];
cx b3[0], a3[0];
ccx anc3[0], a3[0], b3[0];
cx b3[0], a3[0];
h anc3[0];
measure anc3[0] -> out3[0];
// Expectation: out3 = 0 with probability 3/4 (partial overlap)

// ── Notes — collision testing in the quantum regime ───────────────────
//
// Classical narrowphase:
//   - Boolean predicate (overlap or not)
//   - O(1) cost per pair after broadphase culling
//   - Squared-distance compare avoids sqrt
//
// Quantum overlap (swap test):
//   - Continuous magnitude |⟨a|b⟩|² ∈ [0, 1]
//   - 1 ancilla + n controlled-SWAPs for n-qubit states
//   - Sample-based: many shots needed to estimate p(0) to k bits
//
// The broadphase analog in quantum search is amplitude amplification
// (Grover) — concentrate amplitude on "colliding" pairs and read out.
