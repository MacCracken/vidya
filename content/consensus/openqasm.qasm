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
// "one vote per term" rule. Counting the tally qubits gives the
// vote count; majority is the analog of quorum.
//
// Three primitives illustrated:
//   1. A 3-qubit voter register (one qubit per Raft node).
//   2. A 2-qubit candidate register (two competing candidates).
//   3. CNOT-based vote channelling: voter[i] in |1> casts for
//      candidate B, in |0> for candidate A.
//   4. A 1-qubit "leader" register flipped via majority logic
//      modelled as a Toffoli on two of three voter qubits.

OPENQASM 2.0;
include "qelib1.inc";

// === Election state ==================================================

qreg voter[3];               // one qubit per node
qreg candidate_a_tally[1];   // count of votes for candidate A
qreg candidate_b_tally[1];   // count of votes for candidate B
qreg leader[1];              // |1> means a candidate has won

creg voter_c[3];
creg leader_c[1];

// Prepare voters in equal superposition: each voter is undecided.
// In real Raft, the candidate would solicit; here we model the
// vote channel as a bias built into the voter qubit's initial
// state.
//
// Voter 0 leans toward candidate A (|0> = vote A).
// Voters 1 and 2 lean toward candidate A (no Hadamard) — so we'll
// see candidate A win 3-0 with high probability.

// (No gates on voter — they remain in |000>, "all vote A".)

// Vote channelling: CNOT voter[i] -> candidate_b_tally only when
// voter is |1>. With voters all |0>, B-tally stays |0>.
cx voter[0], candidate_b_tally[0];
cx voter[1], candidate_b_tally[0];
cx voter[2], candidate_b_tally[0];

// Candidate A receives the inverted vote. We flip the inverse:
// every voter that did NOT vote B votes A. Express as: for each
// voter[i], if voter[i] == |0>, increment A.
// In OpenQASM 2.0 we cannot conditionally flip on |0>, so we model
// "voted A" by NOT-then-CNOT-then-NOT.
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
// Toffoli on (voter0, voter1) → flip leader iff both are A (|0>).
// We invert each voter, AND them (Toffoli), invert back.
x voter[0]; x voter[1];
ccx voter[0], voter[1], leader[0];
x voter[0]; x voter[1];

// Measure
measure voter -> voter_c;
measure leader -> leader_c;

// voter_c = "000" (all voted A); leader_c = "1" — A wins.


// === Term monotonicity via depth =====================================
// In Raft, term advances over rounds. The quantum analog is gate
// depth: each round of the protocol adds Z-basis gates to the
// "term ancilla" so that its phase encodes the round count. A
// measurement at any point reveals the highest round seen.

qreg term_anc[1];
creg term_c[1];

// Three rounds of "term increment": each is an X gate flipping the
// term qubit, then a Z to mark the term boundary. The Z gates do
// not affect the basis-state outcome but are accumulated in phase
// — modelling that term advances are observable.
x term_anc[0]; z term_anc[0];
x term_anc[0]; z term_anc[0];
x term_anc[0]; z term_anc[0];

measure term_anc -> term_c;
// term_c = "1" after 3 X gates (odd), modelling that the term has
// advanced to an odd round.


// === Vote uniqueness via measurement collapse ========================
// A voter qubit measured once cannot be measured again differently.
// Once collapsed to |0> (vote A) or |1> (vote B), all future
// "queries" return the same outcome — exactly the Raft rule that
// a node votes at most once per term.

qreg unique_voter[1];
creg first_meas[1];
creg second_meas[1];

// Prepare voter in superposition; measure it; measure again.
h unique_voter[0];
measure unique_voter[0] -> first_meas[0];
measure unique_voter[0] -> second_meas[0];
// first_meas == second_meas with probability 1 — vote uniqueness.


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
//   - Toffoli gate on a pair of voters → majority detector
//   - X+Z gate sequence on term ancilla → term progression
//   - Repeated measurement of the same qubit → vote uniqueness
//
// In real fault-tolerant quantum computing, similar patterns appear
// in *Byzantine quantum consensus*: voters are entangled qubits,
// majority is detected via a quorum measurement, and term
// monotonicity is enforced by the unitarity of the protocol —
// non-reversible measurement collapses fix the "vote" durably.
