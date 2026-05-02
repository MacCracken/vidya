// Vidya — Projectile Physics in OpenQASM (quantum-state-evolution analog)
//
// Classical projectile physics integrates a velocity-and-position state
// forward in time with a fixed-point operator (semi-implicit Euler is
// just a 2x2 update matrix per axis). The quantum analog encodes the
// state in a register's amplitudes and applies the same update as a
// unitary — what the VQE / quantum-walk / Trotterized-Hamiltonian
// literature calls "evolving |ψ(t)⟩ → |ψ(t+dt)⟩."
//
// We illustrate three primitives:
//   1. State register encoding position bits (the "ball" qubit cluster)
//   2. A unitary "step" — controlled rotations that act like the
//      semi-implicit-Euler update matrix
//   3. Measurement that collapses the trajectory to a sampled outcome,
//      analogous to reading the ball's position out of the simulation
//
// qelib1.inc does not define `swap`; the SWAP in the inverse-QFT-style
// readout below is expanded as 3 CNOTs.

OPENQASM 2.0;
include "qelib1.inc";

// ── Primitive 1: position-and-velocity register ──────────────────────
// 3 qubits encode an 8-level "height" — ground floor at |000⟩, apex
// at |111⟩. A 4th qubit holds the sign of vy (0 = down, 1 = up).
qreg pos[3];
qreg vy_sign[1];
creg pos_c[3];
creg vy_c[1];

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
rz(pi/8) vy_sign[0];         // gravity nudge: pi/8 ≈ "0.0625 of a flip"
h vy_sign[0];                // back to computational basis

// ── Primitive 3: bounce as a controlled X on the sign qubit ──────────
// When the ball reaches the floor (pos == |000⟩), the bounce flips vy.
// Express this as: if all pos bits are 0, flip vy_sign. CCX with the
// controls inverted — surround target controls with X to gate on |0⟩.
x pos[0]; x pos[1]; x pos[2];
ccx pos[0], pos[1], vy_sign[0];   // partial: 2-of-3
// (A 3-control Toffoli isn't in qelib1; we approximate "all zeros"
// with two controls + an extra ancilla in real circuits. The pattern
// is what matters: the FSM transition "if at floor, reflect vy" is a
// multi-controlled gate, structurally identical to the classical
// `if (y > FLOOR_Y) vy = -vy` branch.)
x pos[0]; x pos[1]; x pos[2];

// ── Inverse-QFT-style readout: measure trajectory bits ───────────────
// In a real quantum simulation, the position register would carry the
// trajectory amplitudes; an inverse QFT on it would reveal the
// dominant frequency components — the "where will the ball land?"
// readout. For this minimal example we just measure directly.
//
// Demonstrate a 3-CNOT SWAP (qelib1 has no `swap` gate) on the way:
// reorder pos[0] and pos[2] before measurement. SWAP = cx a,b ; cx
// b,a ; cx a,b is the standard decomposition.
cx pos[0], pos[2];
cx pos[2], pos[0];
cx pos[0], pos[2];

measure pos -> pos_c;
measure vy_sign -> vy_c;

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
//   samples the trajectory distribution. This is exactly how
//   variational-quantum-Eulers in quantum-fluid-dynamics research
//   simulate ballistic trajectories on NISQ hardware.
//
// The takeaway: classical fixed-point physics and quantum-amplitude
// physics share the same skeleton — a small unitary (or arithmetic)
// operator applied repeatedly, with measurement (or readout) at the
// end. Only the storage medium differs.
