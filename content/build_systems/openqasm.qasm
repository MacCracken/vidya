// Vidya — Build Systems in OpenQASM (Dependency DAG as a CNOT cascade)
//
// A build system is a directed acyclic graph (DAG) of targets. To build
// a target you must first build its dependencies; a topological sort of
// the DAG gives a legal build order. Incremental tools (make, ninja,
// bazel) add dirty-tracking: edit a source and the *change ripples
// downstream* — every target that transitively depends on it rebuilds,
// while untouched siblings are skipped.
//
// OpenQASM cannot run a real build engine. But the *shape* of a build
// DAG maps cleanly onto a quantum circuit, and the circuit's hard
// constraints actually mirror the build system's rules:
//
//   • A dependency edge  upstream -> downstream  becomes a CNOT
//     cx upstream, downstream : the dependent qubit is "rebuilt"
//     (its bit flips) controlled by its dependency. Entanglement
//     encodes "downstream depends on upstream."
//
//   • Topological order becomes GATE order. A CNOT's control must carry
//     its final value before it fires, so every dependency's gates must
//     precede its dependents' gates — exactly Kahn's-algorithm ordering.
//
//   • "Dirty propagation" becomes amplitude propagation: put an X on a
//     source qubit (an edit) and the CNOT cascade carries that flip to
//     every downstream target — a change rippling through the graph.
//
//   • A "clean / no-op build" is the cascade with no source edit: every
//     control starts |0>, so no CNOT fires and nothing flips — nothing
//     rebuilds.
//
// We model the classic tiny C graph from the Cyrius reference:
//
//      util.o ──┐
//               ├──► app        (app depends on util.o AND main.o)
//      main.o ──┘
//
// qelib1.inc gates only — no `swap`, no custom gates.

OPENQASM 2.0;
include "qelib1.inc";

// ── Qubit assignment: one qubit per build target ──────────────────────
//   tgt[0] = util.o   (a source/leaf target — no dependencies)
//   tgt[1] = main.o   (a source/leaf target — no dependencies)
//   tgt[2] = app      (depends on util.o + main.o — the DAG sink)
//
// A qubit reads |0> = "clean / up to date", |1> = "dirty / rebuilt".
qreg tgt[3];
creg out[3];

// ── Scenario A: cold build vs. clean build ────────────────────────────
// All qubits start |0> (a fresh checkout: nothing built yet, but also
// nothing edited). To demonstrate "clean build = no propagation" we
// leave the sources untouched and run only the dependency cascade.
//
// The dependency edges, applied in TOPOLOGICAL order (leaves first,
// sink last) so each control holds its value before its CNOT fires:
//
//   util.o ──► app   :  cx tgt[0], tgt[2]
//   main.o ──► app   :  cx tgt[1], tgt[2]
//
// With both controls |0>, neither CNOT flips tgt[2]: app stays clean.
// This is `ninja` reporting "no work to do."
cx tgt[0], tgt[2];        // edge util.o -> app   (control clean ⇒ no flip)
cx tgt[1], tgt[2];        // edge main.o -> app   (control clean ⇒ no flip)

// ── Scenario B: edit a source, watch the change ripple downstream ─────
// Now simulate `touch main.c`: flip the main.o source qubit dirty with
// an X (the "edit"). Replaying the SAME dependency cascade carries that
// dirtiness into app — the dependent rebuilds — while util.o, untouched,
// stays clean. This is the core incremental-build behavior: edit one
// leaf, only it and its transitive dependents rebuild.
//
// Edge order still respects topological sort: we re-flip via the
// main.o -> app edge after the source edit is in place.
x   tgt[1];               // EDIT: mark main.o dirty (a source changed)
cx  tgt[1], tgt[2];       // main.o -> app : dirty control flips app dirty
// tgt[0] (util.o) was never edited, so the util.o -> app edge above did
// not contribute a flip — the sibling is correctly skipped.

// ── Measure: read the final build state of every target ───────────────
// out[2] (app) now reads dirty (1): it rebuilt because main.o changed.
// out[1] (main.o) reads dirty (1): the edited source.
// out[0] (util.o) reads clean (0): untouched, not rebuilt.
measure tgt -> out;

// ── Notes — the build-system / quantum bridge ─────────────────────────
//
// Classical topological sort:  O(V + E), Kahn's ready-scan or DFS.
//                              Detects cycles (a DAG that isn't acyclic
//                              has no valid order).
// Incremental rebuild:         hash/mtime per target; rebuild iff an
//                              input signature changed; dirtiness is
//                              transitive over the dependency edges.
//
// CNOT cascade analog:
//   • Edge = cx upstream, downstream — entangles dependent on dependency.
//   • Topological order = gate order — a control must be final before
//     its CNOT fires, the same constraint Kahn's algorithm enforces.
//   • Dirty propagation = a flip on a source riding the cascade to every
//     downstream target; an unedited leaf contributes no flip (skipped).
//
// Where the analogy stops: a quantum circuit is itself a DAG and MUST be
// acyclic, so it cannot even *represent* the cyclic-dependency error the
// Cyrius reference detects (0 <-> 1). And CNOT propagation is linear
// (XOR), whereas real dirty-tracking compares content signatures. The
// classical ports remain the ground truth — this file documents the
// structural analogy so the reference is honest about which build ideas
// the circuit captures (edges, ordering, ripple) and which it cannot
// (cycle detection, content hashing).
