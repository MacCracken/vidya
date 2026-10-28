// Vidya — Embeddings and Vector Search in OpenQASM
//                                  (inner-product-as-overlap)
//
// Classical cosine similarity over pre-normalized vectors is just
// the dot product. The dot product is a linear-algebra operation
// that has a direct quantum analog: the *inner product* of two
// quantum state vectors, |⟨ψ|φ⟩|², which the SWAP test estimates:
// its ancilla reads "0" with probability (1 + |⟨ψ|φ⟩|²)/2. Both
// classical cosine and quantum overlap measure the angle between
// two vectors (the overlap is cos², so it loses the sign).
//
// Three primitives illustrated:
//   1. Vector encoding: input feature vector → qubit amplitudes
//      via ry rotations.
//   2. Inner product / SWAP test: ancilla qubit + Hadamard +
//      controlled-SWAP + Hadamard + measure → overlap probability.
//      The classical analog is dot(a, b) over unit vectors.
//   3. Nearest neighbour: run the SWAP test against each corpus
//      vector; the one with highest overlap is the NN. (We model
//      the static unrolled version: each overlap is a probability,
//      estimated from many shots, so picking the max is classical
//      post-processing over the counts, not a per-shot `if`.)

OPENQASM 3.1;
include "stdgates.inc";

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

qubit[1] ancilla;
qubit[1] vec_a;
qubit[1] vec_b;
bit[1] overlap;

// Prepare |ψ⟩ and |φ⟩ — the same ry angle, so identical (overlap = 1).
ry(2.214) vec_a[0];
ry(2.214) vec_b[0];

// SWAP test: H ancilla, cswap controlled by ancilla, H ancilla, measure.
// stdgates.inc has `cswap`; it is spelled out as cx + ccx + cx to show
// the standard decomposition (only the middle gate needs the ancilla).
h ancilla[0];
cx vec_b[0], vec_a[0];
ccx ancilla[0], vec_a[0], vec_b[0];
cx vec_b[0], vec_a[0];
h ancilla[0];
overlap[0] = measure ancilla[0];
// overlap reads "0" with probability 1 — the vectors are identical.
// @expect overlap == 0


// === Orthogonal vectors: overlap → 0 ================================
//
// Prepare one toward |0> and one toward |1> — orthogonal in the
// computational basis. SWAP test ancilla reads "0" with probability
// 1/2 (no preference) — modelling cosine = 0.

qubit[1] orth_anc;
qubit[1] orth_a;
qubit[1] orth_b;
bit[1] orth_c;

// orth_a stays |0>; orth_b → |1>
x orth_b[0];

h orth_anc[0];
cx orth_b[0], orth_a[0];
ccx orth_anc[0], orth_a[0], orth_b[0];
cx orth_b[0], orth_a[0];
h orth_anc[0];
orth_c[0] = measure orth_anc[0];
// @expect orth_c in {0, 1}


// === Nearest-neighbour: 3 SWAP tests in parallel ====================
//
// Three corpus vectors; the query is compared to each via SWAP.
// The corpus vector with highest "0"-probability on its ancilla
// is the NN. (We use 3 separate ancillas to model the parallel
// queries; classical post-processing picks the max-prob one.)
//
// Each test needs its OWN copy of the query, prepared from scratch:
// a SWAP test leaves its query entangled with that test's ancilla,
// so reusing one query qubit for all three would skew every later
// test (here the corpus-2 rate would read 0.139 instead of 0.163),
// and the no-cloning theorem forbids copying the query instead.

qubit[1] query;
qubit[1] query1;
qubit[1] query2;
qubit[1] corpus0;
qubit[1] corpus1;
qubit[1] corpus2;
qubit[1] anc0;
qubit[1] anc1;
qubit[1] anc2;
bit[3] nn_c;

// Query toward |1> (amplitudes 0.447, 0.894), one copy per test
ry(2.214) query[0];
ry(2.214) query1[0];
ry(2.214) query2[0];

// Corpus 0: the same vector as the query (overlap 1)
ry(2.214) corpus0[0];
// Corpus 1: stays |0> — far from the query, overlap cos²(1.107) = 0.2
// Corpus 2: ry(1.0), between |0> and the query, overlap 0.67
ry(1.0) corpus2[0];

// SWAP test query vs each corpus vector (cswap → cx + ccx + cx)
h anc0[0];
cx corpus0[0], query[0]; ccx anc0[0], query[0], corpus0[0]; cx corpus0[0], query[0];
h anc0[0];
h anc1[0];
cx corpus1[0], query1[0]; ccx anc1[0], query1[0], corpus1[0]; cx corpus1[0], query1[0];
h anc1[0];
h anc2[0];
cx corpus2[0], query2[0]; ccx anc2[0], query2[0], corpus2[0]; cx corpus2[0], query2[0];
h anc2[0];

nn_c[0] = measure anc0[0];
nn_c[1] = measure anc1[0];
nn_c[2] = measure anc2[0];
// Classical post-process: lowest "1" rate wins; expected NN = corpus0.
// "1" rates: corpus0 0 (never), corpus1 0.40, corpus2 0.16 — so nn_c[0]
// is always 0 and nn_c is one of 000, 010, 100, 110.
// @expect nn_c in {0, 2, 4, 6}


// --- Notes — embeddings vs inner-product-as-overlap ------------------
//
// Classical embedding search:
//   - Pre-normalize corpus vectors (sqrt of sum-of-squares = 1)
//   - dot(query, corpus_i) for each i
//   - argmax → NN
//
// Quantum analog (this file):
//   - Encode vectors as qubit amplitudes (ry rotations)
//   - SWAP test: ancilla P(0) = (1 + |⟨ψ|φ⟩|²)/2
//   - argmin over "1" rates → NN
//
// In real quantum-assisted vector search (variational quantum
// kernel methods, 2020+), the SWAP test is the basic building
// block for kernel evaluations. Production NN over millions of
// vectors uses classical ANN indexes (HNSW); the quantum
// approach is for small problem sizes where the kernel
// expressiveness is the differentiator.
