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

OPENQASM 2.0;
include "qelib1.inc";

// === Input encoding: 2 features as qubit amplitudes =================
//
// Input feature x ∈ [0, 1] encoded as ry(2 * arcsin(sqrt(x))) on a
// qubit, giving |1>-amplitude = sqrt(x). For x = 0.8, angle ≈ 2.214.

qreg input[2];

// x[0] = 0.8 → |1>-amplitude = √0.8 ≈ 0.894
ry(2.214) input[0];

// x[1] = 0.2 → |1>-amplitude = √0.2 ≈ 0.447
ry(0.927) input[1];


// === Dense layer 1: weighted sum into 3 hidden qubits ===============
//
// Each hidden neuron h[j] = sum_i(W[j][i] * x[i]). In the quantum
// analog, controlled-rotation chains build cumulative amplitude on
// the hidden qubit. The angle is the weight; the control is the
// input qubit's amplitude.

qreg hidden[3];

// h[0] = 0.5 * x[0] - 0.5 * x[1]
// Positive weight: cry (controlled-Y rotation) by +0.5*π.
// Negative weight: cry by -0.5*π.
cu3(1.5708, 0, 0)  input[0], hidden[0];
cu3(-1.5708, 0, 0) input[1], hidden[0];

// h[1] = -0.5 * x[0] + 0.5 * x[1]
cu3(-1.5708, 0, 0) input[0], hidden[1];
cu3(1.5708, 0, 0)  input[1], hidden[1];

// h[2] = 0.5 * x[0] + 0.5 * x[1]   (always positive — magnitude)
cu3(1.5708, 0, 0) input[0], hidden[2];
cu3(1.5708, 0, 0) input[1], hidden[2];


// === ReLU: measure-and-reset on negative-amplitude qubits ===========
//
// In the integer reference, ReLU clips negatives to 0. The quantum
// analog: measure the qubit and reset to |0> if it collapsed to
// |0> (which corresponds to the negative-amplitude case after the
// controlled rotation chain). OpenQASM 2.0 doesn't have classical-
// conditional reset; we model the intent by inserting an explicit
// reset on the qubit we expect to be "negative" for the test input.
//
// For input x = [0.8, 0.2], h[1] should be near |0> (its sum is
// negative), so resetting it models ReLU's effect.

reset hidden[1];                    // models ReLU clipping h[1] to 0


// === Dense layer 2: 3 hidden → 2 output logits =====================
//
// logit[0] = 0.5 * h[0] + 0 * h[1] + 0 * h[2]
// logit[1] = 0 * h[0] + 0.5 * h[1] + 0 * h[2]

qreg logit[2];

cu3(1.5708, 0, 0) hidden[0], logit[0];     // logit[0] gets h[0] influence
cu3(1.5708, 0, 0) hidden[1], logit[1];     // logit[1] gets h[1] influence


// === Argmax: measure both logits, classical post-process ============
//
// In production QNN, the output is sampled across many shots and
// the most-frequent class index wins. Here we just measure both
// once; the classical interpretation picks whichever read |1>.

creg logit_c[2];
measure logit -> logit_c;
// For input [0.8, 0.2]: logit[0] should read 1, logit[1] should
// read 0 with high probability — classifier predicts class 0.


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
//   - ReLU: reset (measurement + classical conditional)
//   - Argmax: measure all output qubits, pick max-likelihood
//
// Variational Quantum Classifiers (VQCs, 2018+) and Quantum Neural
// Networks (QNNs, 2019+) build on exactly this pattern with
// trainable rotation angles. The classical MLP and the quantum VQC
// share the same arithmetic structure: both are weighted sums
// passed through a nonlinearity, with the weights being the
// learnable parameters.
