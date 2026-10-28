// Vidya — State Machines in OpenQASM (quantum-state evolution)
//
// A classical FSM transitions deterministically between named states.
// The quantum analog is a register whose computational-basis index
// encodes the state, with controlled gates implementing the transition
// table. Three primitives illustrated:
//
//   1. State register (3 qubits → 8 possible "states", all 8 named)
//   2. Conditional transition driven by an input register
//   3. Measurement collapses the superposed state register to one
//      definite outcome — the quantum analog of "now you've observed
//      which state the FSM is in."
//
// This is structurally how a quantum random walk on a graph works:
// the graph's adjacency matrix becomes a unitary transition operator,
// the state register holds amplitudes for every node simultaneously,
// and measurement samples one node according to the amplitude weights.

OPENQASM 3.1;
include "stdgates.inc";

// ── State register (3 qubits = 8 possible states) ─────────────────────
// PS_IDLE=000, PS_RUN=001, PS_SHOOT=010, PS_DUNK=011, PS_PASS=100,
// PS_STEAL=101, PS_BLOCK=110, PS_FALL=111
qubit[3] state_q;
bit[3] state_c;

// Initialize to IDLE = |000⟩. Every qubit starts in |0⟩ under qiskit and
// on IBM hardware; OpenQASM 3 itself leaves a freshly declared qubit's
// state undefined (2.0 guaranteed |0⟩), so portable code would
// `reset state_q;` here.

// ── Apply transition: idle (000) → run (001) ──────────────────────────
// Setting bit 0 of the state register transitions IDLE→RUN.
x state_q[0];
// state_q is now |001⟩ = RUN

// Measure: classical readout of the state index
state_c = measure state_q;
// state_c = "001" = RUN with probability 1
// @expect state_c == 1

// ── Conditional transition driven by an input qubit ───────────────────
// 1-qubit "input": |0⟩ = no input, |1⟩ = SHOOT
// When input = 1, transition state IDLE → SHOOT (010).
qubit[3] s2;        // state register (init |000⟩ = IDLE)
qubit[1] inp;        // input register
bit[3] s2_c;

// Set input = 1
x inp[0];

// Conditional transition: if inp[0] = 1, set state bit 1 (010 = SHOOT).
// Implemented as CNOT from input control to the appropriate state bit.
cx inp[0], s2[1];

s2_c = measure s2;
// s2_c = "010" = SHOOT with probability 1
// @expect s2_c == 2

// ── Superposed state — quantum random walk illustration ───────────────
// Put the state register in equal superposition of all 8 basis states.
// This represents "every classical state in parallel" — measurement
// collapses to one outcome, sampled uniformly. Real quantum walks bias
// the measurement distribution via interference; this minimal example
// just shows the encoding.
qubit[3] walk;
bit[3] walk_c;

h walk[0];
h walk[1];
h walk[2];

walk_c = measure walk;
// walk_c = uniformly random 3-bit value = one of the 8 FSM states
// @expect walk_c in {0, 1, 2, 3, 4, 5, 6, 7}

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
