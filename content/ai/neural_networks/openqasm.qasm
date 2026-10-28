// Vidya — Neural Network Forward Pass in OpenQASM
//                                  (rotation-as-weighted-sum)
//
// Classical MLP forward pass: dense layer (weighted sum) + ReLU
// (max(0, x)) + argmax (pick the largest output). Three primitives,
// composed into a 2 → 3 → 2 classifier.
//
// The quantum analog is *amplitude-encoded inference*: input
// features encoded as qubit amplitudes, weights applied via
// controlled rotations (each weight is a rotation angle), the
// "output" qubit's |1>-amplitude after the rotation chain encodes
// the dense layer output. ReLU corresponds to a measurement-and-
// reset on negative-amplitude basis states (collapses negatives to
// |0>). Argmax falls out of measuring multiple output qubits and
// selecting the one most likely to read |1>.
//
// This pattern — amplitude encoding + parameterised rotations +
// measurement — is the basis of variational quantum classifiers
// (VQCs) and quantum neural networks (QNNs). The corpus example
// is a static 1-pass demonstration; production QNNs train the
// rotation angles via gradient descent on a quantum simulator.
//
// Three primitives illustrated:
//   1. Input encoding: ry(angle) prepares each qubit's amplitude.
//   2. Dense layer: controlled rotations apply weights to a target
//      qubit; multiple controls + cumulative rotation = sum.
//   3. ReLU + argmax: H + measurement on output qubits picks the
//      maximally-amplified one.

OPENQASM 3.1;
include "stdgates.inc";

// === Input encoding: 2 features as qubit amplitudes =================
//
// Input feature x ∈ [0, 1] encoded as ry(2 * arcsin(sqrt(x))) on a
// qubit, giving |1>-amplitude = sqrt(x). For x = 0.8, angle ≈ 2.214.

qubit[2] inputs;

// x[0] = 0.8 → |1>-amplitude = √0.8 ≈ 0.894
ry(2.214) inputs[0];

// x[1] = 0.2 → |1>-amplitude = √0.2 ≈ 0.447
ry(0.927) inputs[1];


// === Dense layer 1: weighted sum into 3 hidden qubits ===============
//
// Each hidden neuron h[j] = sum_i(W[j][i] * x[i]). In the quantum
// analog, controlled-rotation chains build cumulative amplitude on
// the hidden qubit. The angle is the weight; the control is the
// input qubit's amplitude.

qubit[3] hidden;

// h[0] = 0.5 * x[0] - 0.5 * x[1]
// Positive weight: cry (controlled-Y rotation) by +0.5*π.
// Negative weight: cry by -0.5*π.
// ⚠ The sign does not survive measurement: ry(-θ) and ry(+θ) give the
// same |1>-probability, so h[0] and h[1] below read 1 equally often
// (34% each for this input) and nothing in the state marks h[1] as
// the negative one.
cry(1.5708)  inputs[0], hidden[0];
cry(-1.5708) inputs[1], hidden[0];

// h[1] = -0.5 * x[0] + 0.5 * x[1]
cry(-1.5708) inputs[0], hidden[1];
cry(1.5708)  inputs[1], hidden[1];

// h[2] = 0.5 * x[0] + 0.5 * x[1]   (always positive — magnitude)
cry(1.5708) inputs[0], hidden[2];
cry(1.5708) inputs[1], hidden[2];


// === ReLU: measure-and-reset on negative-amplitude qubits ===========
//
// In the integer reference, ReLU clips negatives to 0. OpenQASM 3
// could branch on a measurement (`if (h1_c) reset hidden[1];`), but
// measuring a hidden qubit collapses the superposition the next
// layer needs, and (see above) the sign is not in the state to
// measure anyway. So we model the intent by an unconditional reset on
// the qubit the classical computation says is negative.
//
// For input x = [0.8, 0.2], h[1]'s weighted sum is negative (-0.3),
// so resetting it models ReLU's effect.

reset hidden[1];                    // models ReLU clipping h[1] to 0


// === Dense layer 2: 3 hidden → 2 output logits =====================
//
// logit[0] = 0.5 * h[0] + 0 * h[1] + 0 * h[2]
// logit[1] = 0 * h[0] + 0.5 * h[1] + 0 * h[2]

qubit[2] logit;

cry(1.5708) hidden[0], logit[0];             // logit[0] gets h[0] influence
cry(1.5708) hidden[1], logit[1];             // logit[1] gets h[1] influence


// === Argmax: measure both logits, classical post-process ============
//
// In production QNN, the output is sampled across many shots and
// the most-frequent class index wins. Here we just measure both
// once; the classical interpretation picks whichever read |1>.

bit[2] logit_c;
logit_c = measure logit;
// For input [0.8, 0.2]: logit[0] reads 1 on about 17% of shots
// (P(h[0]=1) · sin²(π/4) = 0.34 · 0.5) and logit[1] never does,
// since h[1] was reset. So logit_c is 00 or 01 and, over many shots,
// class 0 wins — but most single shots read 00 and pick neither,
// which is why the argmax needs many shots.
// @expect logit_c in {0, 1}


// --- Notes — MLP vs amplitude-encoded inference ---------------------
//
// Classical Q15 MLP:
//   - Dense: y[j] = sum_i(W[j][i] * x[i]) + b[j], integer multiply
//   - ReLU: max(0, x[i]) per element
//   - Argmax: scan output array, return max index
//
// Quantum analog (this file):
//   - Input encoding: ry(angle) per feature, amplitude = √feature
//   - Dense: cry (controlled-Y rotation) with angle = weight
//   - ReLU: unconditional reset on the qubit known to be negative
//   - Argmax: measure all output qubits, pick max-likelihood
//
// Variational Quantum Classifiers (VQCs, 2018+) and Quantum Neural
// Networks (QNNs, 2019+) build on exactly this pattern with
// trainable rotation angles. The classical MLP and the quantum VQC
// share the same arithmetic structure: both are weighted sums
// passed through a nonlinearity, with the weights being the
// learnable parameters.
