// Vidya — Game AI Decision Making in OpenQASM (rotation-based choice)
//
// A classical AI scores N options and picks the highest. The quantum
// analog is rotation-based probabilistic choice: each option is encoded
// in a basis state and an Ry rotation biases the measurement
// distribution toward the higher-scoring option. Three primitives
// illustrated:
//
//   1. Probabilistic action selection via Ry(θ) where θ encodes the
//      score-driven probability — measurement collapses to one action.
//   2. Conditional decision driven by an "input state" qubit, mirroring
//      the if-stat-then-action branch of the classical version.
//   3. Quantum random walk over the 5 actions (SHOOT, DUNK, PASS,
//      DRIVE, STEAL) — Hadamards over a 3-qubit register sample one
//      of its 8 codes uniformly (5 are actions), the same way an
//      unbiased AI would explore.
//
// Research proposals use this pattern in QAOA-style policy
// evaluation: the cost Hamiltonian encodes the scoring function, and
// the trained circuit concentrates measurement probability on the
// high-scoring actions (QAOA optimizes; it does not sample ∝ score).

OPENQASM 3.1;
include "stdgates.inc";

// ── Action register (3 qubits = 8 possible states; we use 5) ──────────
// ACT_SHOOT=000, ACT_DUNK=001, ACT_PASS=010, ACT_DRIVE=011, ACT_STEAL=100
qubit[3] act_q;
bit[3] act_c;

// ── Probabilistic shoot bias ──────────────────────────────────────────
// A "shooting stat" of 8/10 corresponds to roughly 80% confidence in
// SHOOT. Ry(2*acos(sqrt(0.8))) ≈ Ry(0.927) on the lowest action bit
// produces |0⟩ with prob 0.8 — so measurement collapses to ACT_SHOOT
// (000) with probability 80%, ACT_DUNK (001) with probability 20%.
ry(0.927) act_q[0];
act_c = measure act_q;
// @expect act_c in {0, 1}

// ── Conditional decision driven by an "input" qubit ───────────────────
// 1-qubit "scenario": |0⟩ = open shot (prefer SHOOT/000),
//                      |1⟩ = close range (prefer DUNK/001).
// When scenario = 1, flip act bit 0 to transition SHOOT (000) → DUNK (001).
qubit[3] act2;
qubit[1] scenario;
bit[3] act2_c;

// Set scenario = 1 (close range)
x scenario[0];

// Conditional transition: if scenario[0] = 1, set act2[0] (000 → 001).
cx scenario[0], act2[0];

act2_c = measure act2;
// act2_c = "001" = ACT_DUNK with probability 1
// @expect act2_c == 1

// ── Quantum random-walk action sampling ───────────────────────────────
// Put the action register into uniform superposition — this is the
// "explore all options simultaneously" quantum analog of the classical
// add_noise() stage. Measurement samples one action uniformly among
// the 8 basis states (5 of which are valid actions; the other 3 are
// unused codes — a realistic AI would post-filter or use Grover-style
// amplitude amplification on the valid subset).
qubit[3] walk;
bit[3] walk_c;

h walk[0];
h walk[1];
h walk[2];

walk_c = measure walk;
// walk_c = uniformly random 3-bit value
// @expect walk_c in {0, 1, 2, 3, 4, 5, 6, 7}

// ── Notes — classical AI scoring vs quantum rotation-based choice ─────
//
// Classical AI:
//   - Score each option (shoot=75, dunk=120, pass=24, drive=30)
//   - Pick the argmax — deterministic given the inputs and PRNG seed
//   - O(N) per evaluation, sub-microsecond per entity
//
// Quantum rotation-based choice:
//   - Encode each option's score as a rotation angle θ_i = 2*acos(√p_i)
//   - Apply Ry(θ_i) to the corresponding qubit — amplitude ∝ √score
//   - Measurement samples action with probability ∝ score
//   - O(log N) qubits for N options, but requires O(N) gates to encode
//
// Where the two regimes meet: variational-quantum policies (VQE,
// QAOA) parameterize the rotation angles and learn them from gameplay
// data — the classical AI's hand-tuned weights become trainable
// quantum parameters.
