// Vidya — Projectile Physics in OpenQASM (quantum-state-evolution analog)
//
// Classical projectile physics integrates a velocity-and-position state
// forward in time with a fixed-point operator (semi-implicit Euler is
// just a 2x2 update matrix per axis). The quantum analog encodes the
// state in a register's amplitudes and applies the same update as a
// unitary — what the quantum-walk / Trotterized-Hamiltonian
// literature calls "evolving |ψ(t)⟩ → |ψ(t+dt)⟩."
//
// We illustrate three primitives:
//   1. State register encoding position bits (the "ball" qubit cluster)
//   2. A unitary "step" — controlled rotations that act like the
//      semi-implicit-Euler update matrix
//   3. Measurement that collapses the trajectory to a sampled outcome,
//      analogous to reading the ball's position out of the simulation
//
// stdgates.inc has `swap`; the SWAP in the inverse-QFT-style readout
// below is spelled out as its 3 CNOTs to show what it costs.

OPENQASM 3.1;
include "stdgates.inc";

// ── Primitive 1: position-and-velocity register ──────────────────────
// 3 qubits encode an 8-level "height" — ground floor at |000⟩, apex
// at |111⟩. A 4th qubit holds the sign of vy (0 = down, 1 = up).
qubit[3] pos;
qubit[1] vy_sign;
bit[3] pos_c;
bit[1] vy_c;

// Initialize: ball at mid-height (|100⟩ = 4) moving upward (sign = 1).
// In classical fixed-point: y = mid, vy = +up. Here we just flip qubits.
x pos[2];                    // height = 4 (binary 100)
x vy_sign[0];                // upward

// ── Primitive 2: gravity step as a controlled rotation ───────────────
// The gravity update vy += GRAVITY is, in the phase-encoding view, a
// small Rz rotation on the velocity qubit's relative phase. Over many
// frames this rotates from "up" (|+⟩-like) through zero into "down".
// We model one step: a small Rz on vy_sign that nudges its phase.
h vy_sign[0];                // |+⟩ basis — phase encodes velocity
rz(pi/8) vy_sign[0];         // gravity nudge: pi/8 = 1/8 of a flip (π)
h vy_sign[0];                // back to computational basis

// ── Primitive 3: bounce as a controlled X on the sign qubit ──────────
// When the ball reaches the floor (pos == |000⟩), the bounce flips vy.
// Express this as: if all pos bits are 0, flip vy_sign. A 3-control X
// with the controls inverted — surround the controls with X to gate on
// |0⟩. OpenQASM 3's `ctrl(3) @` modifier builds the 3-control gate
// directly (`negctrl(3) @ x` would fold the X sandwich in too). The
// FSM transition "if at floor, reflect vy" is a multi-controlled gate,
// structurally identical to the classical `if (y > FLOOR_Y) vy = -vy`
// branch. (Checking only 2 of the 3 bits is NOT a cheap stand-in: it
// fires at height 4 = |100⟩ too, reversing the ball mid-flight.)
x pos[0]; x pos[1]; x pos[2];
ctrl(3) @ x pos[0], pos[1], pos[2], vy_sign[0];
x pos[0]; x pos[1]; x pos[2];

// ── Inverse-QFT-style readout: measure trajectory bits ───────────────
// In a real quantum simulation, the position register would carry the
// trajectory amplitudes; an inverse QFT on it would reveal the
// dominant frequency components — the "where will the ball land?"
// readout. For this minimal example we just measure directly.
//
// Demonstrate a 3-CNOT SWAP on the way: reorder pos[0] and pos[2]
// before measurement. SWAP = cx a,b ; cx b,a ; cx a,b is the standard
// decomposition (and exactly how stdgates.inc defines `swap`).
cx pos[0], pos[2];
cx pos[2], pos[0];
cx pos[0], pos[2];

pos_c = measure pos;
vy_c = measure vy_sign;
// pos_c = 001: height 4 (|100⟩) with bits 0 and 2 swapped. The ball is
// not at the floor, so no bounce: vy_c reads 1 (still up) except for
// the sin²(π/16) ≈ 4% that the gravity nudge tipped toward down.
// @expect pos_c == 1
// @expect vy_c in {0, 1}

// ── Notes — projectile physics meets quantum-state evolution ─────────
//
// Classical Euler step:
//   vy ← vy + GRAVITY      (additive: phase shift in |+⟩ basis)
//   y  ← y  + vy           (additive: controlled rotation on pos)
//   if y > floor: y ← floor; vy ← -vy * restitution
//                          (FSM transition: multi-controlled flip)
//
// Quantum analog:
//   Each step is a unitary U_step that evolves the entire amplitude
//   vector. Over T steps the trajectory is U_step^T |ψ_0⟩. Measuring
//   collapses to one classical outcome; running the circuit many times
//   samples the trajectory distribution. Quantum simulation follows the
//   same evolve-then-sample shape: Hamiltonian simulation (Lloyd,
//   "Universal Quantum Simulators", Science 273, 1996) and variational
//   time evolution (Li and Benjamin, Phys. Rev. X 7, 021050, 2017).
//
// The takeaway: classical fixed-point physics and quantum-amplitude
// physics share the same skeleton — a small unitary (or arithmetic)
// operator applied repeatedly, with measurement (or readout) at the
// end. Only the storage medium differs.
