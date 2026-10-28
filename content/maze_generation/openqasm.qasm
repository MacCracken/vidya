// Vidya — Maze Generation in OpenQASM (quantum walk on a graph)
//
// Recursive backtracker is one classical way to find a spanning tree
// of a grid graph; on a quantum computer, the natural cousin is a
// continuous- or discrete-time quantum walk, in which a state vector
// holds amplitudes for every node simultaneously and the unitary
// evolution operator encodes the graph's adjacency. The classical
// "carve a wall" step has no direct quantum analog — instead, the
// quantum walk stays in superposition over the *whole* graph, and the
// measurement distribution is shaped by interference.
//
// Three primitives illustrated:
//
//   1. A 2-qubit "position register" indexes the 4 cells of a 2x2 sub-
//      grid (00, 01, 10, 11 = NW, NE, SW, SE). A Hadamard on each
//      qubit puts the walker in a uniform superposition over all four
//      cells — the analog of "the walker is everywhere at once".
//
//   2. A 1-qubit "coin" register chooses a direction. Flipping the
//      coin (Hadamard) and then conditionally translating the walker
//      via CNOT-controlled position-flips is the discrete-time quantum
//      walk's elementary step.
//
//   3. A measurement collapses the position register to one cell — the
//      quantum analog of "report which cell of the spanning tree the
//      walker is in right now". Repeated runs sample cells with
//      probabilities determined by the interference pattern.
//
// The maze-adjacent uses of quantum walks are faster-than-classical
// *connectivity* and *spanning-tree* sampling, where the known gains
// are polynomial: Aharonov, Ambainis, Kempe and Vazirani showed a
// quantum walk on the n-cycle mixes almost quadratically faster than the
// classical walk (O(n log n) steps against Θ(n²)), and that on general
// graphs a quantum walk can be at most polynomially faster ("Quantum
// Walks On Graphs", STOC 2001, arXiv:quant-ph/0012090). The structural
// mapping to recursive backtracker is inexact (backtracker carves
// walls; the quantum walk doesn't carve, it navigates), but both share
// the same goal: visit every node of the grid.

OPENQASM 3.1;
include "stdgates.inc";

// --- Position register: 2 qubits = 4 cells (a 2x2 sub-grid) ----------
// pos[0] is column-bit, pos[1] is row-bit:
//   00 = (0,0)  01 = (1,0)
//   10 = (0,1)  11 = (1,1)
qubit[2] pos;
bit[2] pos_c;

// Uniform superposition over all 4 cells — the walker is "everywhere"
// before the first measurement, just as recursive backtracker has not
// committed to any path before its first random choice.
h pos[0];
h pos[1];

// Measure: classical readout collapses the walker to one cell. Across
// many runs, each cell is sampled with probability 1/4 — the quantum
// equivalent of a uniformly random starting cell choice.
pos_c = measure pos;
// @expect pos_c in {0, 1, 2, 3}


// --- Coin + conditional step: discrete-time quantum walk -------------
// A 1-qubit "coin" decides the step direction; a CNOT from coin to
// position implements "if coin = 1, flip the column bit" — that is,
// move east or west on the 2x2 grid.
qubit[2] pos2;
qubit[1] coin;
bit[2] pos2_c;

// Initialize walker at (0,0) = |00>; coin starts in superposition.
h coin[0];

// Coin-controlled translation: flip column bit conditional on coin.
cx coin[0], pos2[0];

// The walker is now in superposition of (0,0) and (1,0). Measurement
// samples one of them — the analog of "after one DFS step, which cell
// does the backtracker visit next?".
pos2_c = measure pos2;
// pos2_c is 00 or 01 (the row bit never moves), each half the time
// @expect pos2_c in {0, 1}


// --- Wall-bit register: 4 qubits encode the 4 walls of one cell ------
// Bit ordering matches the classical encoding: q[0]=N, q[1]=S, q[2]=E,
// q[3]=W.  All four walls present <=> |1111> (= 15, WALLS_ALL). The
// classical backtracker clears bits to carve passages; here we just
// initialize them all to |1> so a measurement of the register reports
// 1111 every time — the quantum analog of "freshly initialized cell".
qubit[4] walls;
bit[4] walls_c;

x walls[0];   // N wall present
x walls[1];   // S wall present
x walls[2];   // E wall present
x walls[3];   // W wall present

walls_c = measure walls;
// walls_c will read as "1111" with probability 1, mirroring
// WALLS_ALL = 15 from the classical port's init state.
// @expect walls_c == 15


// --- Notes — classical backtracker vs quantum walk -------------------
//
// Classical recursive backtracker:
//   - O(N) per call, deterministic given seed
//   - Produces a *spanning tree* — exactly N-1 edges removed
//   - Memory: O(N) for the visited set + DFS stack
//
// Quantum walk on the grid graph:
//   - O(log N) qubits encode a position over N cells
//   - Walker amplitude evolves under the graph Laplacian
//   - Mixing/hitting time can be quadratically faster than classical
//
// Where the two regimes meet: Magniez-Nayak-Roland-Santha (2007,
// "Search via Quantum Walk", arXiv:quant-ph/0608026)
// search builds a quantum walk from a classical random walk and finds
// a marked vertex in about the square root of that walk's hitting
// time. Its scaffolding is the classical walk's transition matrix —
// not a backtracker's spanning tree.
