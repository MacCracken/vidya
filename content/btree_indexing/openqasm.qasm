// Vidya — B+ Tree Indexing in OpenQASM (quantum-search analog)
//
// A classical B+ tree lookup descends O(log_N) levels: at each internal
// node, compare the search key against routing keys to pick one of N
// children. The quantum analog is *Grover search* — find a marked key in
// an unstructured 2^n-key space in O(√N) queries instead of O(N), and
// *quantum walks on trees*, which can hit a marked leaf in O(√depth) on
// some balanced trees.
//
// We illustrate three primitives on a tiny 2-qubit "tree" (4 leaves):
//   1. Address register in superposition — descend all branches at once.
//   2. Phase oracle marking the "search hit" leaf (= one Grover query).
//   3. One Grover iteration that deterministically rotates onto the
//      marked leaf for the canonical N=4 single-marked-item case.
// qelib1.inc only — no `swap`.

OPENQASM 2.0;
include "qelib1.inc";

// ── Primitive 1: superposition over all leaves (tree address register)─
// 2 qubits = 4 leaf addresses (matching a depth-2 binary tree).
// Hadamard each address bit ⇒ uniform amplitude over all leaves =
// quantum analog of "visit every leaf in parallel."
qreg addr[2];
creg addr_c[2];

h addr[0];
h addr[1];
// addr is now (|00⟩ + |01⟩ + |10⟩ + |11⟩)/2 — every leaf address has
// amplitude 1/2 — the entire tree's leaf set in one register.

measure addr -> addr_c;
// addr_c = uniformly random 2-bit value = one of the 4 leaf indexes.

// ── Primitive 2: phase oracle marking the search hit ──────────────────
// Classical bt_search(root, key) returns the value at the leaf whose key
// matches; in quantum form, we mark that leaf with a phase flip.
// O_hit |x⟩ = (-1)^[x = target] |x⟩. For a 2-qubit register marking
// |11⟩, this is exactly a controlled-Z (cz).

qreg key[2];
creg key_c[2];

h key[0];
h key[1];
cz key[0], key[1];   // mark target leaf = |11⟩ with relative -1 phase

// ── Primitive 3: one Grover iteration on N=4 ──────────────────────────
// One iteration of (oracle ; diffuse) on a 2-qubit register with one
// marked item lands the amplitude on the marked state with probability
// 1 — the canonical N=4 demonstration that Grover's quadratic speedup
// is exact at the smallest non-trivial size.
//
// Diffusion D = H⊗H · (2|00⟩⟨00| - I) · H⊗H. Equivalent gate sequence:
//   H ⊗ H  ;  X ⊗ X  ;  CZ  ;  X ⊗ X  ;  H ⊗ H
//
// (The outer H's mix into the |+,+⟩ basis; the X/CZ/X stack reflects
// about the all-ones state, which is the diffusion mirror operator.)

h key[0];
h key[1];
x key[0];
x key[1];
cz key[0], key[1];
x key[0];
x key[1];
h key[0];
h key[1];

measure key -> key_c;
// key_c = "11" with probability 1 — the search hit, found in one query.

// ── Primitive 4: descent qubit (depth-1 traversal step) ───────────────
// A B+ tree descent at one level reads the routing key, then routes
// left or right. Quantum analog: a "coin" qubit in |+⟩ + a controlled
// step that updates the address register. We model a 1-level descent
// (root → one of two leaves) in 1 address bit + 1 coin qubit.

qreg coin[1];
qreg leaf[1];
creg coin_c[1];
creg leaf_c[1];

h coin[0];                 // |+⟩ — superposed routing decision
cx coin[0], leaf[0];       // conditional step — quantum descent

measure coin -> coin_c;
measure leaf -> leaf_c;

// ── Notes — B+ tree lookup vs quantum search ──────────────────────────
//
// Classical B+ tree:    O(log_N rows) page reads per lookup, O(N) keys
//                       scanned per page; deterministic descent guided
//                       by routing keys.
// Grover search:        O(√N) queries to find a marked key on an
//                       unstructured 2^n-key space; tree structure
//                       generally not required.
// Quantum walks on trees: O(√depth) hitting time on balanced trees
//                       under specific encoding choices; encodes the
//                       parent/child adjacency as a unitary step.
//
// Practical note: real database indexes already exploit log-depth tree
// structure to beat unstructured search classically, so quantum
// indexing is mostly of theoretical interest. Vidya's classical ports
// remain the ground truth — this file documents the quantum analog so
// the reference is honest about which speedup regime applies.
