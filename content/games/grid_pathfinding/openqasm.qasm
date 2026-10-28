// Vidya — Grid Pathfinding in OpenQASM (Quantum Walk / Grover analog)
//
// Classical BFS explores a grid one frontier at a time; classical A*
// uses a heuristic to bias which frontier extends first. The quantum
// analogs are *quantum walks* and *Grover search*:
//
//   1. A quantum walk on a graph encodes the adjacency matrix as a
//      unitary "step operator". Repeated application spreads amplitude
//      over reachable nodes — a quantum BFS frontier expansion that
//      can hit the goal in O(√N) steps on some graphs (vs O(N) classical).
//
//   2. Grover search marks the goal cell with a phase oracle and
//      amplifies its amplitude via diffusion. On an unstructured 2^n-
//      cell grid this finds the goal in O(√N) queries instead of O(N).
//
// We illustrate three primitives on a tiny 2x2 = 4-cell grid encoded
// in 2 qubits (cell index = b1 b0). Gates used: h, x, cx, cz.

OPENQASM 3.1;
include "stdgates.inc";

// ── Primitive 1: superposition over all cells (quantum walk seed) ─────
// Hadamard each position qubit ⇒ uniform amplitude over all 4 cells.
// This is the quantum analog of "BFS frontier = all cells at once."
qubit[2] pos;
bit[2] pos_c;

h pos[0];
h pos[1];
// pos is now (|00⟩ + |01⟩ + |10⟩ + |11⟩)/2 — every cell amplitude 1/2.

pos_c = measure pos;
// pos_c is uniformly random across {00, 01, 10, 11} = 4 grid cells.
// @expect pos_c in {0, 1, 2, 3}

// ── Primitive 2: phase oracle marking the goal cell |11⟩ ──────────────
// Classical BFS checks `if (curr == goal)` once per dequeue. The
// quantum analog is a phase oracle: O_goal |x⟩ = (-1)^[x=goal] |x⟩.
// For a 2-qubit register, marking |11⟩ is exactly a controlled-Z (cz):
// it flips the phase of |11⟩ and leaves |00⟩, |01⟩, |10⟩ unchanged.

qubit[2] gv;               // grid position register (init |00⟩)
bit[2] gv_c;

// Put gv in uniform superposition (all cells), then apply oracle.
h gv[0];
h gv[1];
cz gv[0], gv[1];          // mark goal = |11⟩ with a relative -1 phase

// ── Primitive 3: Grover diffusion on 2 qubits ─────────────────────────
// One Grover iteration on a 2-qubit register: oracle then diffuse.
// For N=4 with one marked item, a single iteration deterministically
// rotates onto the marked state — measurement returns the goal with
// probability 1. This is the canonical demonstration that Grover beats
// classical search even at the smallest non-trivial N.
//
// Diffusion D = H⊗H · (2|00⟩⟨00| - I) · H⊗H. Equivalent gate sequence:
//   H ⊗ H  ;  X ⊗ X  ;  CZ  ;  X ⊗ X  ;  H ⊗ H
// (The outer H's mix into the |+,+⟩ basis; the X/CZ/X stack reflects
// about the all-zeros state, which is the diffusion mirror operator.)

h gv[0];
h gv[1];
x gv[0];
x gv[1];
cz gv[0], gv[1];
x gv[0];
x gv[1];
h gv[0];
h gv[1];

gv_c = measure gv;
// gv_c = "11" with probability 1 — the goal cell, found in one query.
// @expect gv_c == 3

// ── Primitive 4: 1-step coined quantum walk (illustration) ────────────
// A discrete-time quantum walk uses a "coin" qubit to direct the next
// step. Coin in |+⟩ ⇒ equal superposition of "advance" / "stay".
// We model a 2-cell line (1-qubit position + 1-qubit coin):
//   coin H : "throw a quantum coin"
//   step   : if coin=1, flip position bit  (CNOT coin->pos)
// One step spreads amplitude across both cells — the same shape as a
// classical BFS frontier expansion, but in superposition.

qubit[1] coin;
qubit[1] cell;
bit[1] coin_c;
bit[1] cell_c;

h coin[0];                 // |+⟩ — superposed step direction
cx coin[0], cell[0];       // conditional advance — quantum-walk step

coin_c = measure coin;
cell_c = measure cell;
// Each is 0 or 1 with equal probability, and they always agree: the
// walker advanced exactly when the coin said so.
// @expect coin_c in {0, 1}
// @expect cell_c in {0, 1}

// ── Notes — the pathfinding/quantum bridge ────────────────────────────
//
// Classical BFS:    O(V + E) time, O(V) space, deterministic frontier.
// Classical A*:     O(V + E) worst case, prunes via heuristic, optimal
//                   when h is admissible.
// Quantum walk:     O(√N) hitting time on many graphs; encodes the
//                   adjacency matrix as a unitary; amplitude is the
//                   "frontier" carried in superposition.
// Grover search:    O(√N) queries to find a marked cell on an
//                   unstructured grid — quadratic speedup. With
//                   structure (Manhattan heuristic) the constant
//                   improves further but the asymptotic stays √N.
//
// In a hybrid scheme, you'd run a quantum walk to identify "promising"
// frontier cells, then return to classical A* refinement. Vidya's
// classical ports remain the ground truth — this file documents the
// quantum analog so the reference is honest about which speedup
// regime applies and which doesn't.
