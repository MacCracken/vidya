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
// register. Top-k is the same idea as amplitude amplification:
// boost the K highest amplitudes before measurement so they
// dominate the readout probability.
//
// Three primitives illustrated:
//   1. Greedy decoding: ry rotations encode logits as amplitudes;
//      measurement of the qubit with the largest amplitude
//      models argmax (highest |1>-probability wins on a single
//      shot at peaked amplitudes).
//   2. Top-k filter: amplitude amplification gates increase the
//      top-K amplitudes; the rest fade.
//   3. Autoregressive loop: 3 rounds of prepare → measure,
//      threading one classical bit forward as the next state.

OPENQASM 2.0;
include "qelib1.inc";

// === Greedy decoding via amplitude-encoded logits =====================
//
// 4-token "vocabulary": each candidate is one qubit. The qubit
// with the highest |1>-amplitude is the most likely sample (the
// argmax under the Born rule).

qreg cand[4];
creg cand_c[4];

// Encode logits as amplitudes (small angle = small amplitude):
//   cand[0]: small logit → small ry → low |1> probability
//   cand[1]: medium logit → medium ry
//   cand[2]: HIGH logit → ry near π → high |1> probability (argmax)
//   cand[3]: small logit → small ry

ry(0.2) cand[0];
ry(0.6) cand[1];
ry(2.8) cand[2];        // peaked toward |1> (argmax)
ry(0.2) cand[3];

measure cand -> cand_c;
// cand_c[2] reads "1" with high probability; others mostly "0".
// The argmax is encoded as the bit-string position with most
// |1>-probability.


// === Top-k filter as amplitude amplification ==========================
//
// The classical filter zeros out all but the K highest logits.
// In the quantum analog, we apply Z-rotations to the top-K
// candidates to amplify their |1>-amplitudes. The K=2 case here
// boosts cand_top[1] and cand_top[2] (the medium and high
// candidates), suppressing cand_top[0] and cand_top[3].

qreg cand_top[4];
creg cand_top_c[4];

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

measure cand_top -> cand_top_c;


// === Autoregressive decode loop: 3 rounds of measurement =============
//
// Each round encodes the current prefix's logits onto a fresh
// register, measures, and uses the result classically to
// determine the next round's encoding. OpenQASM 2.0 cannot
// implement classical control of subsequent gates within one
// circuit, so we model the unrolled 3-step loop with deterministic
// (highest-amplitude) outcomes per step.

qreg step1[1];
qreg step2[1];
qreg step3[1];
creg step_c[3];

// Step 1: peaked toward |1> — emits "1"
ry(2.8) step1[0];
measure step1[0] -> step_c[0];

// Step 2: also peaked toward |1>
ry(2.8) step2[0];
measure step2[0] -> step_c[1];

// Step 3: peaked toward |0> (EOS encoded as "0")
ry(0.2) step3[0];
measure step3[0] -> step_c[2];
// Decode terminates after 3 steps with classical sequence "1 1 0".


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
//   - Top-k as amplitude amplification on the top K candidates
//   - Autoregressive loop: classical bit threads forward
//
// In real quantum-assisted LLM research (2023+), variational
// quantum models explore exactly this pattern: amplitude
// encoding for the vocabulary distribution, parameterised
// rotations as the model's "logit head", and measurement as the
// sampling step. Quantum amplitude estimation can speed up the
// argmax step quadratically. The corpus example is the static
// version of what an autoregressive QNN's decode loop looks like
// before classical control logic is added.
