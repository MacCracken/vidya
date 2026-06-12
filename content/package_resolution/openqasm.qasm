// Vidya — Package Resolution in OpenQASM (constraint search as Grover amplification)
//
// A dependency resolver picks the highest version of each package that
// satisfies *every* constraint imposed on it. For a shared ("diamond")
// dependency C — required by both A and B — the resolver intersects the
// two caret ranges (A's ^a AND B's ^b) and selects the highest C that
// survives. If the ranges are disjoint, no version satisfies both: the
// intersection is empty and resolution FAILS.
//
// OpenQASM cannot run a real SAT/version solver. But constraint
// satisfaction over a small candidate set is *exactly* the problem
// Grover's algorithm attacks, and the circuit's primitives map cleanly
// onto the resolver's ideas:
//
//   • CANDIDATE VERSIONS become a superposition. A 2-qubit index register
//     idx[1:0] enumerates 4 candidate versions of C: |00>,|01>,|10>,|11>.
//     Hadamards put us in an even superposition — "consider all versions
//     of C at once," the quantum echo of scanning the version list.
//
//   • A CONSTRAINT becomes a phase ORACLE. The oracle flips the phase of
//     exactly the index that satisfies the (intersected) caret range —
//     marking the "good" version the way `satisfies(v, lo, hi)` returns 1.
//
//   • The DIAMOND INTERSECTION becomes an AND inside the oracle. A and B
//     each impose a caret; their ranges are intersected, and a candidate
//     is "good" only if it lies in BOTH. We realize that AND with a
//     multi-controlled flip — only the single index in A's range *and*
//     B's range gets marked.
//
//   • HIGHEST-VERSION SELECTION becomes amplitude AMPLIFICATION. The
//     diffusion operator inflates the marked amplitude so that measuring
//     idx overwhelmingly returns the satisfying version — the resolver's
//     "pick the one version that fits."
//
//   • An UNSATISFIABLE CONFLICT (disjoint ranges, empty intersection)
//     marks NOTHING. With no phase flip, diffusion has nothing to amplify
//     and the distribution stays flat — the quantum shadow of a resolver
//     erroring out on "no version of C satisfies both A and B."
//
// We model this concrete diamond from the Cyrius reference. C ships four
// candidate versions, indexed 0..3 by idx[1:0]:
//
//      idx  version    in A's ^1 range?   in B's ^1 range?   GOOD?
//      00   C 1.0.0          yes                yes           ✗ (not highest)
//      01   C 1.5.0          yes                yes           ✓  ← winner
//      10   C 2.0.0          no  (next major)   no            ✗
//      11   C 2.5.0          no                 no            ✗
//
// Both A and B require C ^1 (=[1.0.0, 2.0.0)); intersecting two identical
// caret-^1 ranges leaves [1.0.0, 2.0.0). Among the candidates in that
// range (1.0.0 and 1.5.0) the resolver wants the HIGHEST, 1.5.0 = idx 01.
// So the oracle marks idx == 01 and diffusion amplifies it.
//
// qelib1.inc gates only — h, x, z, cx, ccx; no `swap`, no custom gates.

OPENQASM 2.0;
include "qelib1.inc";

// ── Registers ─────────────────────────────────────────────────────────
//   idx[1:0] : 2-qubit index selecting one of 4 candidate C versions.
//              idx == 01 (binary) is the satisfying winner, C 1.5.0.
//   anc      : one ancilla, prepared in the |-> state, so a controlled-X
//              onto it imprints a PHASE flip on the marked index (the
//              standard phase-kickback oracle trick).
//   out[1:0] : classical bits — the resolved version index after collapse.
qreg idx[2];
qreg anc[1];
creg out[2];

// ── Superposition: "consider every candidate version of C at once" ────
// Hadamard the index register: idx is now an equal mix of |00>,|01>,|10>,
// |11> — all four candidate versions held simultaneously, the quantum
// analog of iterating the available-versions list before deciding.
h idx[0];
h idx[1];

// ── Ancilla in |->: turns the oracle's bit-flip into a PHASE flip ─────
// x then h prepares anc = |-> = (|0> - |1>)/√2. A CNOT/CCX targeting a
// |-> ancilla kicks back a -1 phase onto the control pattern instead of
// flipping a data qubit — so the "satisfying version" gets marked by sign.
x anc[0];
h anc[0];

// ── Phase oracle: mark the index that satisfies BOTH carets ───────────
// The intersected constraint (A's ^1 AND B's ^1) is satisfied uniquely,
// among the candidates the resolver would *pick*, by idx == 01 (C 1.5.0):
// the highest version inside [1.0.0, 2.0.0). We mark |01>, i.e. idx[1]=0
// and idx[0]=1.
//
// To AND over "idx[1] is 0" and "idx[0] is 1" with a ccx, we momentarily
// invert idx[1] (X) so the all-controls-high CCX fires precisely on the
// |idx[1]=0, idx[0]=1> pattern, kicking the phase onto the |-> ancilla.
// This single multi-controlled gate IS the diamond AND: only the version
// in BOTH requirers' ranges is marked.
//
// (A disjoint/unsatisfiable diamond would target a pattern matched by NO
// candidate — the CCX would never fire, nothing is marked, and the
// diffusion below amplifies nothing: the empty-intersection failure.)
x   idx[1];                 // pre-invert: select the idx[1]==0 sub-branch
ccx idx[0], idx[1], anc[0]; // AND(idx[0]==1, idx[1]==0) ⇒ phase-mark |01>
x   idx[1];                 // restore idx[1]

// ── Diffusion (inversion about the mean): amplify the marked version ──
// The standard Grover diffuser H–X–(controlled-Z)–X–H on the index
// register. It reflects amplitudes about their average, growing the
// phase-marked |01> while shrinking the rest — "select the highest
// satisfying version." With one marked item out of four, this single
// iteration drives the winner's probability to certainty.
h idx[0];
h idx[1];
x idx[0];
x idx[1];
// controlled-Z on idx via H-CX-H sandwich (qelib1.inc has no `cz`):
h   idx[1];
cx  idx[0], idx[1];
h   idx[1];
x idx[0];
x idx[1];
h idx[0];
h idx[1];

// ── Measure: read the resolved version index ──────────────────────────
// out should collapse to 01 (binary) = candidate index 1 = C 1.5.0, the
// highest version satisfying both A's ^1 and B's ^1 — the resolved pick
// of the diamond dependency. (Had the carets been disjoint, no index was
// marked and out would be a uniform-random 2-bit value: resolution
// failure, the quantum echo of an empty range intersection.)
measure idx -> out;

// ── Notes — the resolver / quantum bridge ─────────────────────────────
//
// Classical resolution:    encode semver as an integer (maj*1e6+min*1e3+
//                          patch) so compare == int compare; a caret ^X.Y.Z
//                          is the half-open range [X.Y.Z, (X+1).0.0);
//                          a diamond intersects requirers' ranges (lo=max,
//                          hi=min) and picks the highest surviving version;
//                          an empty range (lo>=hi) is an unsatisfiable
//                          conflict. Backtracking retries an earlier choice
//                          when the highest pick corners a later dependency.
//
// Grover analog:
//   • Candidate versions   = index register in superposition (scan all).
//   • A constraint         = a phase oracle marking the satisfying index.
//   • Diamond intersection = an AND inside the oracle (in A's range AND
//                            B's range) realized by a multi-controlled gate.
//   • Highest-version pick  = diffusion amplifying the single marked index.
//   • Empty intersection    = oracle marks nothing ⇒ no amplification ⇒
//                            flat distribution: the resolver's conflict.
//
// Where the analogy stops: Grover finds *a* marked item, not the *ordered*
// maximum — we pre-bake "highest satisfying" into which index the oracle
// marks, rather than deriving it from version ordering. The circuit also
// can't backtrack across a chain of coupled choices or detect dependency
// cycles (a quantum circuit is itself an acyclic DAG, so it cannot encode
// the A↔B cycle the Cyrius reference rejects). The classical ports remain
// ground truth; this file documents which resolution ideas the circuit
// captures (candidate search, range AND, satisfying-pick amplification,
// unsatisfiable = no amplification) and which it cannot (true max-ordering,
// backtracking, cycle detection).
