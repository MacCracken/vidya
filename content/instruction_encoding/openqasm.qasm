// Vidya — Instruction Encoding in OpenQASM (Gate Encoding)
//
// Classical instructions encode opcodes and operands in bit patterns.
// Quantum gates encode as unitary matrices with specific parameters.
// Each gate family (rx, ry, rz, u3) is parameterized — the angle IS
// the "immediate operand" of the quantum instruction.

OPENQASM 2.0;
include "qelib1.inc";

// ── Fixed-encoding gates: no parameters (like opcode-only insns) ─
qreg fixed[4];
creg fixed_c[4];

x fixed[0];        // Pauli-X: [[0,1],[1,0]] — bit flip
y fixed[1];        // Pauli-Y: [[0,-i],[i,0]] — bit+phase flip
z fixed[2];        // Pauli-Z: [[1,0],[0,-1]] — phase flip
h fixed[3];        // Hadamard: [[1,1],[1,-1]]/√2 — superposition

measure fixed -> fixed_c;

// ── 1-parameter gates: angle as immediate operand ────────────────
qreg rot1[3];
creg rot1_c[3];

rx(pi/2) rot1[0];  // Rx(π/2): rotation around X-axis by 90°
ry(pi/3) rot1[1];  // Ry(π/3): rotation around Y-axis by 60°
rz(pi/4) rot1[2];  // Rz(π/4): rotation around Z-axis by 45° (T gate)

measure rot1 -> rot1_c;

// ── Phase gates: discrete angle encodings ────────────────────────
// Like fixed-point immediate fields with specific bit patterns
qreg phase[4];
creg phase_c[4];

s phase[0];        // S gate: Rz(π/2) — 90° phase
t phase[1];        // T gate: Rz(π/4) — 45° phase
sdg phase[2];      // S†: Rz(-π/2) — inverse S
tdg phase[3];      // T†: Rz(-π/4) — inverse T

measure phase -> phase_c;

// ── 3-parameter gate: full instruction word ──────────────────────
// u3(θ,φ,λ) is the most general single-qubit gate
// Like a full instruction with opcode + 3 operand fields:
//   θ = rotation angle, φ = pre-rotation phase, λ = post-rotation phase
qreg full[3];
creg full_c[3];

u3(pi, 0, pi) full[0];          // = X gate (specific encoding)
u3(pi, pi/2, pi/2) full[1];     // = Y gate (different params, same format)
u3(pi/2, 0, pi) full[2];        // = H gate (Hadamard encoding)

measure full -> full_c;

// ── 2-qubit gate encoding: opcode + 2 register operands ─────────
qreg two_q[4];
creg two_q_c[4];

// CNOT: control + target (2-operand instruction)
cx two_q[0], two_q[1];
// SWAP: 3 CNOTs (complex instruction = microcode sequence)
swap two_q[2], two_q[3];

measure two_q -> two_q_c;
