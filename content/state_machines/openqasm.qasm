// Vidya — State Machines in OpenQASM (quantum-state evolution)
//
// A classical FSM transitions deterministically between named states.
// The quantum analog is a register whose computational-basis index
// encodes the state, with controlled gates implementing the transition
// table. Three primitives illustrated:
//
//   1. State register (4 qubits → 16 possible "states", we use 5)
//   2. Conditional transition driven by an input register
//   3. Measurement collapses the superposed state register to one
//      definite outcome — the quantum analog of "now you've observed
//      which state the FSM is in."
//
// This is structurally how a quantum random walk on a graph works:
// the graph's adjacency matrix becomes a unitary transition operator,
// the state register holds amplitudes for every node simultaneously,
// and measurement samples one node according to the amplitude weights.

OPENQASM 2.0;
include "qelib1.inc";

// ── State register (3 qubits = 8 possible states) ─────────────────────
// PS_IDLE=000, PS_RUN=001, PS_SHOOT=010, PS_DUNK=011, PS_PASS=100,
// PS_STEAL=101, PS_BLOCK=110, PS_FALL=111
qreg state_q[3];
creg state_c[3];

// Initialize to IDLE = |000⟩ (already the default after qreg decl)

// ── Apply transition: idle (000) → run (001) ──────────────────────────
// Setting bit 0 of the state register transitions IDLE→RUN.
x state_q[0];
// state_q is now |001⟩ = RUN

// Measure: classical readout of the state index
measure state_q -> state_c;
// state_c = "001" = RUN with probability 1

// ── Conditional transition driven by an input qubit ───────────────────
// 1-qubit "input": |0⟩ = no input, |1⟩ = SHOOT
// When input = 1, transition state IDLE → SHOOT (010).
qreg s2[3];        // state register (init |000⟩ = IDLE)
qreg in[1];        // input register
creg s2_c[3];

// Set input = 1
x in[0];

// Conditional transition: if in[0] = 1, set state bit 1 (010 = SHOOT).
// Implemented as CNOT from input control to the appropriate state bit.
cx in[0], s2[1];

measure s2 -> s2_c;
// s2_c = "010" = SHOOT with probability 1

// ── Superposed state — quantum random walk illustration ───────────────
// Put the state register in equal superposition of all 8 basis states.
// This represents "every classical state in parallel" — measurement
// collapses to one outcome, sampled uniformly. Real quantum walks bias
// the measurement distribution via interference; this minimal example
// just shows the encoding.
qreg walk[3];
creg walk_c[3];

h walk[0];
h walk[1];
h walk[2];

measure walk -> walk_c;
// walk_c = uniformly random 3-bit value = one of the 8 FSM states

// ── Notes — classical FSM vs quantum-state evolution ──────────────────
//
// Classical FSM:
//   - One state at a time
//   - Deterministic transitions on input
//   - Observable cost is O(1) per transition
//
// Quantum state evolution:
//   - Superposition of states tracked simultaneously (2^n amplitudes)
//   - Unitary "transition operator" applies to all amplitudes at once
//   - Measurement collapses to one outcome, sampled by amplitude²
//
// The two regimes meet in algorithms like quantum Markov chains and
// Grover's search — both encode the FSM transition table as a unitary,
// then exploit the parallelism to sample interesting states faster
// than classical traversal would.
