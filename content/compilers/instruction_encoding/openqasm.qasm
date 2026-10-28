// Vidya — Instruction Encoding in OpenQASM (Gate Encoding)
//
// Classical instructions encode opcodes and operands in bit patterns.
// Quantum gates encode as unitary matrices with specific parameters.
// Each gate family (rx, ry, rz, U) is parameterized — the angle IS
// the "immediate operand" of the quantum instruction.

OPENQASM 3.1;
include "stdgates.inc";

// ── Fixed-encoding gates: no parameters (like opcode-only insns) ─
qubit[4] fixed;
bit[4] fixed_c;

x fixed[0];        // Pauli-X: [[0,1],[1,0]] — bit flip
y fixed[1];        // Pauli-Y: [[0,-i],[i,0]] — bit+phase flip
z fixed[2];        // Pauli-Z: [[1,0],[0,-1]] — phase flip
h fixed[3];        // Hadamard: [[1,1],[1,-1]]/√2 — superposition

fixed_c = measure fixed;
// X and Y both flip |0⟩ to |1⟩ (Y adds a phase); Z changes only a phase;
// H gives 50/50 — so fixed_c is 0011 or 1011.
// @expect fixed_c in {3, 11}

// ── 1-parameter gates: angle as immediate operand ────────────────
qubit[3] rot1;
bit[3] rot1_c;

rx(pi/2) rot1[0];  // Rx(π/2): rotation around X-axis by 90°
ry(pi/3) rot1[1];  // Ry(π/3): rotation around Y-axis by 60°
rz(pi/4) rot1[2];  // Rz(π/4): rotation around Z-axis by 45° (T gate)

rot1_c = measure rot1;
// rot1[0] is 1 half the time, rot1[1] a quarter (sin²(π/6)), rot1[2]
// never (a Z-rotation of |0⟩ is only a phase).
// @expect rot1_c in {0, 1, 2, 3}

// ── Phase gates: discrete angle encodings ────────────────────────
// Like fixed-point immediate fields with specific bit patterns
qubit[4] phase_q;
bit[4] phase_c;

s phase_q[0];        // S gate: Rz(π/2) — 90° phase
t phase_q[1];        // T gate: Rz(π/4) — 45° phase
sdg phase_q[2];      // S†: Rz(-π/2) — inverse S
tdg phase_q[3];      // T†: Rz(-π/4) — inverse T

phase_c = measure phase_q;
// Phase gates on |0⟩ leave it |0⟩: phase_c = 0000 on every shot.
// @expect phase_c == 0

// ── 3-parameter gate: full instruction word ──────────────────────
// U(θ,φ,λ) — OpenQASM 2.0's u3 — is the most general single-qubit gate
// Like a full instruction with opcode + 3 operand fields:
//   U(θ,φ,λ) = Rz(φ)·Ry(θ)·Rz(λ) up to a global phase, so
//   θ = rotation angle, λ = pre-rotation phase (applied first),
//   φ = post-rotation phase (applied last)
qubit[3] full;
bit[3] full_c;

U(pi, 0, pi) full[0];          // = X gate (specific encoding)
U(pi, pi/2, pi/2) full[1];     // = Y gate (different params, same format)
U(pi/2, 0, pi) full[2];        // = H gate (Hadamard encoding)

full_c = measure full;
// full_c is 011 or 111: X and Y read 1, H is 50/50
// @expect full_c in {3, 7}

// ── 2-qubit gate encoding: opcode + 2 register operands ─────────
qubit[4] two_q;
bit[4] two_q_c;

// CNOT: control + target (2-operand instruction)
cx two_q[0], two_q[1];
// SWAP: 3 CNOTs (complex instruction = microcode sequence).
// stdgates.inc defines `swap` as exactly these three CNOTs; they are
// spelled out here to show the microcode.
cx two_q[2], two_q[3];
cx two_q[3], two_q[2];
cx two_q[2], two_q[3];

two_q_c = measure two_q;
// Every input was |0⟩, so neither CNOT nor SWAP has anything to move:
// two_q_c = 0000.
// @expect two_q_c == 0
