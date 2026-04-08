// Vidya — Code Generation in OpenQASM (Gate Decomposition)
//
// Code generation lowers high-level operations to machine primitives.
// In quantum computing, complex gates decompose into elementary gates
// (H, CNOT, T, S, Rz) — exactly like IR lowering to machine instructions.

OPENQASM 2.0;
include "qelib1.inc";

// ── High-level op: SWAP decomposed to 3 CNOTs ───────────────────
// SWAP is a "high-level instruction" that lowers to primitive CNOTs
qreg sw[2];
creg sw_c[2];

x sw[0];           // sw = |10⟩
// SWAP decomposition: 3 CNOT gates (the "machine code")
cx sw[0], sw[1];
cx sw[1], sw[0];
cx sw[0], sw[1];
// Result: sw = |01⟩ — qubits swapped

measure sw -> sw_c;

// ── High-level op: Toffoli (CCX) decomposed to primitives ───────
// CCX is like a complex instruction that lowers to ~15 primitive gates
qreg tof[3];
creg tof_c[3];

x tof[0];          // control 1 = |1⟩
x tof[1];          // control 2 = |1⟩
// Toffoli decomposition into {H, T, Tdg, CNOT}:
h tof[2];
cx tof[1], tof[2]; tdg tof[2];
cx tof[0], tof[2]; t tof[2];
cx tof[1], tof[2]; tdg tof[2];
cx tof[0], tof[2]; t tof[1]; t tof[2]; h tof[2];
cx tof[0], tof[1]; t tof[0]; tdg tof[1];
cx tof[0], tof[1];
// Result: tof[2] flipped to |1⟩ (both controls were 1)

measure tof -> tof_c;

// ── High-level op: controlled-Z from CNOT + H ───────────────────
// CZ = (I⊗H) · CNOT · (I⊗H) — instruction selection
qreg cz_reg[2];
creg cz_c[2];

x cz_reg[0];       // control = |1⟩
x cz_reg[1];       // target = |1⟩
// CZ decomposition:
h cz_reg[1];
cx cz_reg[0], cz_reg[1];
h cz_reg[1];
// CZ applied: |11⟩ → -|11⟩ (phase flip, not bit flip)

measure cz_reg -> cz_c;

// ── Parameterized lowering: arbitrary rotation from primitives ───
// Rz(θ) decomposes to u1(θ) in the hardware basis
qreg rot[1];
creg rot_c[1];

// "High-level": rotate by π/3
// "Lowered": u1 is the hardware-native gate
u1(pi/3) rot[0];

measure rot[0] -> rot_c[0];
