// Vidya — Consensus and Raft in OpenQASM (vote-as-measurement)
//
// Classical Raft: each node casts at most one vote per term, and a
// candidate is elected if it secures a majority. Election safety
// requires that votes are mutually exclusive — once a node votes,
// it cannot un-vote in the same term.
//
// The quantum analog is *vote-as-measurement*: each voter qubit is
// prepared in a superposition over candidates. CNOT entangles the
// voter with a chosen candidate's tally qubit. Measurement of the
// voter qubit collapses it to one candidate — modelling the
// "one vote per term" rule. A one-qubit tally holds only the PARITY
// of its votes (three votes XOR to 1, two to 0), so the majority
// itself is computed from the voters; majority is the analog of quorum.
//
// Three primitives illustrated:
//   1. A 3-qubit voter register (one qubit per Raft node).
//   2. A 2-qubit candidate register (two competing candidates).
//   3. CNOT-based vote channelling: voter[i] in |1> casts for
//      candidate B, in |0> for candidate A.
//   4. A 1-qubit "leader" register flipped via 2-of-3 majority logic:
//      three Toffolis, one per pair of voters.

OPENQASM 3.1;
include "stdgates.inc";

// === Election state ==================================================

qubit[3] voter;               // one qubit per node
qubit[1] candidate_a_tally;   // parity of votes for candidate A
qubit[1] candidate_b_tally;   // parity of votes for candidate B
qubit[1] leader;              // |1> means a candidate has won

bit[3] voter_c;
bit[1] leader_c;

// In real Raft, the candidate would solicit; here we model the
// vote channel as the voter qubit's initial state: |0> = vote A,
// |1> = vote B. (An h on a voter would leave it undecided until
// measured.)
//
// All three voters are left in |0> (no gates) — so candidate A wins
// 3-0 on every shot.

// (No gates on voter — they remain in |000>, "all vote A".)

// Vote channelling: CNOT voter[i] -> candidate_b_tally only when
// voter is |1>. With voters all |0>, B-tally stays |0>.
cx voter[0], candidate_b_tally[0];
cx voter[1], candidate_b_tally[0];
cx voter[2], candidate_b_tally[0];

// Candidate A receives the inverted vote. We flip the inverse:
// every voter that did NOT vote B votes A. Express as: for each
// voter[i], if voter[i] == |0>, increment A.
// OpenQASM 3 can say "flip when the control is |0>" directly:
// `negctrl @ x voter[0], candidate_a_tally[0];`. We spell out what
// that modifier compiles to, NOT-then-CNOT-then-NOT.
x voter[0];
cx voter[0], candidate_a_tally[0];
x voter[0];
x voter[1];
cx voter[1], candidate_a_tally[0];
x voter[1];
x voter[2];
cx voter[2], candidate_a_tally[0];
x voter[2];

// Election rule: candidate A wins if at least 2 of 3 voters cast for A.
// 2-of-3 majority is MAJ(a,b,c) = ab XOR ac XOR bc: one Toffoli per
// pair of voters (a single Toffoli on voters 0 and 1 would miss the
// majorities 0+2 and 1+2). Voting A is |0>, so we invert each voter,
// apply the three Toffolis, invert back.
x voter[0]; x voter[1]; x voter[2];
ccx voter[0], voter[1], leader[0];
ccx voter[0], voter[2], leader[0];
ccx voter[1], voter[2], leader[0];
x voter[0]; x voter[1]; x voter[2];

// Measure
voter_c = measure voter;
leader_c = measure leader;

// voter_c = "000" (all voted A); leader_c = "1" — A wins.
// @expect voter_c == 0
// @expect leader_c == 1


// === Term monotonicity via depth =====================================
// In Raft, term advances over rounds. The quantum analog is gate
// depth: each round of the protocol adds gates to the "term
// ancilla". Where the analogy stops: one qubit holds only the
// PARITY of the round count (round 2 reads the same 0 as round 0),
// so it cannot show monotonicity — that needs a ⌈log2 rounds⌉-qubit
// counter.

qubit[1] term_anc;
bit[1] term_c;

// Three rounds of "term increment": each is an X gate flipping the
// term qubit, then a Z to mark the term boundary. The Z gates change
// only the phase (here just a global phase), which a Z-basis
// measurement never sees: term advances marked this way are NOT
// observable.
x term_anc[0]; z term_anc[0];
x term_anc[0]; z term_anc[0];
x term_anc[0]; z term_anc[0];

term_c = measure term_anc;
// term_c = "1" after 3 X gates (odd), modelling that the term has
// advanced to an odd round.
// @expect term_c == 1


// === Vote uniqueness via measurement collapse ========================
// A voter qubit measured once cannot be measured again differently.
// Once collapsed to |0> (vote A) or |1> (vote B), all future
// "queries" return the same outcome — exactly the Raft rule that
// a node votes at most once per term.

qubit[1] unique_voter;
bit[1] first_meas;
bit[1] second_meas;

// Prepare voter in superposition; measure it; measure again.
h unique_voter[0];
first_meas[0] = measure unique_voter[0];
second_meas[0] = measure unique_voter[0];
// first_meas == second_meas with probability 1 — vote uniqueness.
// Each is 0 or 1 with equal probability; they always agree.
// @expect first_meas in {0, 1}
// @expect second_meas in {0, 1}


// --- Notes — Raft vs vote-as-measurement -----------------------------
//
// Classical Raft:
//   - Node persists (currentTerm, votedFor) before responding YES
//   - Vote uniqueness via the durable voted_for field
//   - Election safety: at most one leader per term
//   - Term monotonicity: terms only increase
//
// Quantum analog (this file):
//   - Voter qubits collapsed via measurement → uniqueness for free
//   - Three Toffolis, one per voter pair → 2-of-3 majority detector
//   - X+Z gate sequence on term ancilla → term parity (not a counter)
//   - Repeated measurement of the same qubit → vote uniqueness
//
// In real fault-tolerant quantum computing, similar patterns appear
// in *Byzantine quantum consensus*: voters are entangled qubits,
// majority is detected via a quorum measurement, and the "vote" is
// fixed durably by measurement itself — unlike the unitary gates
// before it, a collapse cannot be undone.
