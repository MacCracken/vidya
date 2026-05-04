// Vidya — Embeddings and Vector Search in OpenQASM
//                                  (inner-product-as-overlap)
//
// Classical cosine similarity over pre-normalized vectors is just
// the dot product. The dot product is a linear-algebra operation
// that has a direct quantum analog: the *inner product* of two
// quantum state vectors, |⟨ψ|φ⟩|², which is the probability that
// measurement after the SWAP test reads "0". Both classical
// cosine and quantum overlap measure the angle between two
// vectors.
//
// Three primitives illustrated:
//   1. Vector encoding: input feature vector → qubit amplitudes
//      via ry rotations.
//   2. Inner product / SWAP test: ancilla qubit + Hadamard +
//      controlled-SWAP + Hadamard + measure → overlap probability.
//      The classical analog is dot(a, b) over unit vectors.
//   3. Nearest neighbour: run the SWAP test against each corpus
//      vector; the one with highest overlap is the NN. (We model
//      the static unrolled version since OpenQASM 2.0 doesn't
//      support classical control of subsequent gates.)

OPENQASM 2.0;
include "qelib1.inc";

// === Inner product via the SWAP test ================================
//
// The SWAP test: prepare two states |ψ⟩ and |φ⟩; entangle via
// Hadamard + cswap + Hadamard on an ancilla; the ancilla measures
// "0" with probability (1 + |⟨ψ|φ⟩|²)/2. So if the states are
// identical (overlap = 1), ancilla reads "0" with probability 1.
// If orthogonal (overlap = 0), ancilla reads "0" with probability
// 1/2 (random).
//
// Classical: similarity = dot(a, b) for unit vectors.
// Quantum: similarity ≈ Pr[ancilla = 0] − 1/2, scaled by 2.

qreg ancilla[1];
qreg vec_a[1];
qreg vec_b[1];
creg overlap[1];

// Prepare |ψ⟩ and |φ⟩ — both pointing toward |1⟩ (high overlap).
ry(2.214) vec_a[0];
ry(2.214) vec_b[0];

// SWAP test: H ancilla, cswap controlled by ancilla, H ancilla, measure.
// cswap decomposed as cx + ccx + cx (qiskit qasm2 doesn't include cswap
// in its standard gate set).
h ancilla[0];
cx vec_b[0], vec_a[0];
ccx ancilla[0], vec_a[0], vec_b[0];
cx vec_b[0], vec_a[0];
h ancilla[0];
measure ancilla[0] -> overlap[0];
// overlap reads "0" with high probability — vectors are similar.


// === Orthogonal vectors: overlap → 0 ================================
//
// Prepare one toward |0> and one toward |1> — orthogonal in the
// computational basis. SWAP test ancilla reads "0" with probability
// 1/2 (no preference) — modelling cosine = 0.

qreg orth_anc[1];
qreg orth_a[1];
qreg orth_b[1];
creg orth_c[1];

// orth_a stays |0>; orth_b → |1>
x orth_b[0];

h orth_anc[0];
cx orth_b[0], orth_a[0];
ccx orth_anc[0], orth_a[0], orth_b[0];
cx orth_b[0], orth_a[0];
h orth_anc[0];
measure orth_anc[0] -> orth_c[0];


// === Nearest-neighbour: 3 SWAP tests in parallel ====================
//
// Three corpus vectors; the query is compared to each via SWAP.
// The corpus vector with highest "0"-probability on its ancilla
// is the NN. (We use 3 separate ancillas to model the parallel
// queries; classical post-processing picks the max-prob one.)

qreg query[1];
qreg corpus0[1];
qreg corpus1[1];
qreg corpus2[1];
qreg anc0[1];
qreg anc1[1];
qreg anc2[1];
creg nn_c[3];

// Query toward |1>
ry(2.214) query[0];

// Corpus 0: also toward |1> (similar to query)
ry(2.214) corpus0[0];
// Corpus 1: toward |0> (orthogonal)
// Corpus 2: also toward |1>, less aligned
ry(1.0) corpus2[0];

// SWAP test query vs each corpus vector (cswap → cx + ccx + cx)
h anc0[0];
cx corpus0[0], query[0]; ccx anc0[0], query[0], corpus0[0]; cx corpus0[0], query[0];
h anc0[0];
h anc1[0];
cx corpus1[0], query[0]; ccx anc1[0], query[0], corpus1[0]; cx corpus1[0], query[0];
h anc1[0];
h anc2[0];
cx corpus2[0], query[0]; ccx anc2[0], query[0], corpus2[0]; cx corpus2[0], query[0];
h anc2[0];

measure anc0[0] -> nn_c[0];
measure anc1[0] -> nn_c[1];
measure anc2[0] -> nn_c[2];
// Classical post-process: lowest "1" rate wins; expected NN = corpus0.


// --- Notes — embeddings vs inner-product-as-overlap ------------------
//
// Classical embedding search:
//   - Pre-normalize corpus vectors (sqrt of sum-of-squares = 1)
//   - dot(query, corpus_i) for each i
//   - argmax → NN
//
// Quantum analog (this file):
//   - Encode vectors as qubit amplitudes (ry rotations)
//   - SWAP test: ancilla overlap probability = |⟨ψ|φ⟩|²
//   - argmin over "1" rates → NN
//
// In real quantum-assisted vector search (variational quantum
// kernel methods, 2020+), the SWAP test is the basic building
// block for kernel evaluations. Production NN over millions of
// vectors uses classical ANN indexes (HNSW); the quantum
// approach is for small problem sizes where the kernel
// expressiveness is the differentiator.
