// Vidya — LLM Inference (Decoding) in OpenQASM
//                                  (measurement-as-greedy-decode)
//
// Classical autoregressive decoding: a model produces logits over
// the next-token vocabulary; argmax picks the highest; the picked
// token is fed back as the new prefix; loop until EOS or
// max_length. The decode loop is irreducibly sequential — each
// token depends on all previous ones.
//
// The quantum analog is *measurement-as-greedy-decode*: each
// candidate next-token is encoded as a qubit's amplitude
// (proportional to its logit). Measurement collapses the register
// to a basis state — the analog of argmax for a maximally-peaked
// amplitude distribution. The autoregressive loop becomes:
// prepare → measure → use classical result to prepare next
// register. Top-k is the same goal as amplitude amplification:
// boost the K highest amplitudes before measurement so they
// dominate the readout probability.
//
// Three primitives illustrated:
//   1. Greedy decoding: ry rotations encode logits as amplitudes;
//      measurement of the qubit with the largest amplitude
//      models argmax (highest |1>-probability wins on a single
//      shot at peaked amplitudes).
//   2. Top-k filter: extra rotations increase the top-K
//      amplitudes; the rest fade.
//   3. Autoregressive loop: 3 rounds of prepare → measure,
//      threading one classical bit forward as the next state.

OPENQASM 3.1;
include "stdgates.inc";

// === Greedy decoding via amplitude-encoded logits =====================
//
// 4-token "vocabulary": each candidate is one qubit. The qubit
// with the highest |1>-amplitude is the most likely sample (the
// argmax under the Born rule).

qubit[4] cand;
bit[4] cand_c;

// Encode logits as amplitudes (small angle = small amplitude):
//   cand[0]: small logit → small ry → low |1> probability
//   cand[1]: medium logit → medium ry
//   cand[2]: HIGH logit → ry near π → high |1> probability (argmax)
//   cand[3]: small logit → small ry

ry(0.2) cand[0];
ry(0.6) cand[1];
ry(2.8) cand[2];        // peaked toward |1> (argmax)
ry(0.2) cand[3];

cand_c = measure cand;
// cand_c[2] reads "1" with high probability; others mostly "0".
// The argmax is encoded as the bit-string position with most
// |1>-probability.


// === Top-k filter as amplitude amplification ==========================
//
// The classical filter zeros out all but the K highest logits.
// In the quantum analog, we apply extra Y-rotations (ry) to the
// top-K candidates to raise their |1>-amplitudes; a Z-rotation
// would change only the phase, never the |1>-probability. The K=2
// case here boosts cand_top[1] and cand_top[2] (the medium and high
// candidates), suppressing cand_top[0] and cand_top[3]. (This is a
// hand-placed boost: real amplitude amplification is the Grover
// iteration, which needs an oracle that marks the top K.)

qubit[4] cand_top;
bit[4] cand_top_c;

ry(0.2) cand_top[0];
ry(0.6) cand_top[1];
ry(2.8) cand_top[2];
ry(0.2) cand_top[3];

// Amplify the top-2 (cand_top[1] and cand_top[2]):
ry(0.5) cand_top[1];                // boost
ry(0.5) cand_top[2];                // boost

// Suppress the others — apply -ry to bring amplitude back toward |0>:
ry(-0.2) cand_top[0];
ry(-0.2) cand_top[3];

cand_top_c = measure cand_top;
// ry(0.2) then ry(-0.2) is the identity, so cand_top[0] and
// cand_top[3] read 0 on every shot; cand_top[2] reads 1 about 99% of
// the time, cand_top[1] about 27%.


// === Autoregressive decode loop: 3 rounds of measurement =============
//
// Each round encodes the current prefix's logits onto a fresh
// register, measures, and uses the result classically to
// determine the next round's encoding. OpenQASM 3 does that with
// `if` on a measured bit: step 2's logits depend on the token step 1
// emitted. Each step is peaked, not deterministic, so the sequence
// is a likely outcome, not a certain one.

qubit[1] step1;
qubit[1] step2;
qubit[1] step3;
bit[3] step_c;

// Step 1: peaked toward |1> — emits "1"
ry(2.8) step1[0];
step_c[0] = measure step1[0];

// Step 2: the token just emitted picks this round's logits — after
// a "1", peaked toward |1> again; after a "0", peaked toward EOS
if (step_c[0]) ry(2.8) step2[0]; else ry(0.2) step2[0];
step_c[1] = measure step2[0];

// Step 3: peaked toward |0> (EOS encoded as "0")
ry(0.2) step3[0];
step_c[2] = measure step3[0];
// Decode terminates after 3 steps, most often (≈93% of shots, each
// step being ≈97-99% peaked) with the classical sequence "1 1 0"
// (step_c[0], step_c[1], step_c[2]).


// --- Notes — inference vs measurement-as-decode ----------------------
//
// Classical greedy decoding:
//   - Compute logits over vocab
//   - Argmax → next token
//   - Append + repeat until EOS
//
// Quantum analog (this file):
//   - Encode logits as ry rotations on candidate qubits
//   - Measurement collapses to argmax with probability
//     proportional to |amplitude|²
//   - Top-k as an extra rotation on the top K candidates
//   - Autoregressive loop: classical bit threads forward via `if`
//
// In real quantum-assisted LLM research (2023+), variational
// quantum models explore exactly this pattern: amplitude
// encoding for the vocabulary distribution, parameterised
// rotations as the model's "logit head", and measurement as the
// sampling step. Quantum minimum finding (Dürr–Høyer 1996, built
// on Grover search) can find the argmax of N logits in O(√N)
// queries instead of O(N). The corpus example is a small version
// of an autoregressive QNN's decode loop, with one round of
// classical feed-forward.
