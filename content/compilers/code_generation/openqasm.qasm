// Vidya — Code Generation in OpenQASM (Gate Decomposition)
//
// Code generation lowers high-level operations to machine primitives.
// In quantum computing, complex gates decompose into elementary gates
// (H, CNOT, T, S, Rz) — exactly like IR lowering to machine instructions.

OPENQASM 3.1;
include "stdgates.inc";

// ── High-level op: SWAP decomposed to 3 CNOTs ───────────────────
// SWAP is a "high-level instruction" (`swap a, b;` in stdgates.inc)
// that lowers to primitive CNOTs
qubit[2] sw;
bit[2] sw_c;

x sw[0];           // sw = |10⟩ (sw[0]=1, sw[1]=0)
// SWAP decomposition: 3 CNOT gates (the "machine code")
cx sw[0], sw[1];
cx sw[1], sw[0];
cx sw[0], sw[1];
// Result: sw = |01⟩ — qubits swapped (sw[1]=1, so sw_c reads 2)

sw_c = measure sw;
// @expect sw_c == 2

// ── High-level op: Toffoli (CCX) decomposed to primitives ───────
// CCX is like a complex instruction that lowers to ~15 primitive gates
qubit[3] tof;
bit[3] tof_c;

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

tof_c = measure tof;
// @expect tof_c == 7

// ── High-level op: controlled-Z from CNOT + H ───────────────────
// CZ = (I⊗H) · CNOT · (I⊗H) — instruction selection
qubit[2] cz_reg;
bit[2] cz_c;

x cz_reg[0];       // control = |1⟩
x cz_reg[1];       // target = |1⟩
// CZ decomposition:
h cz_reg[1];
cx cz_reg[0], cz_reg[1];
h cz_reg[1];
// CZ applied: |11⟩ → -|11⟩ (phase flip, not bit flip)

cz_c = measure cz_reg;
// A phase is invisible to measurement: cz_c still reads 11.
// @expect cz_c == 3

// ── Parameterized lowering: arbitrary rotation from primitives ───
// Rz(θ) lowers to the phase gate p(θ) (OpenQASM 2.0's u1): the two
// differ only by a global phase e^{-iθ/2}, so a compiler may emit either.
qubit[1] rot;
bit[1] rot_c;

// "High-level": rotate by π/3
// "Lowered": p(π/3), the single-parameter phase primitive
p(pi/3) rot[0];

rot_c[0] = measure rot[0];
// A Z-axis rotation of |0⟩ changes only its phase: rot_c reads 0.
// @expect rot_c == 0
