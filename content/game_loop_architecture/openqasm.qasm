// Vidya — Game Loop Architecture in OpenQASM (quantum-timestep analog)
//
// A classical game loop drains an accumulator in fixed-size chunks DT,
// firing one "update" per chunk. The quantum analog is a unitary U
// applied for n timesteps: each application of U evolves the state by
// the same fixed dt, exactly like one tick of a fixed-timestep loop.
// Trotterization makes this concrete — a Hamiltonian H is simulated
// by repeatedly applying e^(-iH·dt) for n steps. The number of steps
// is the quantum equivalent of "updates per frame" that the classical
// driver decides via accumulator drain.
//
// We illustrate three primitives:
//   1. Single fixed timestep — one tick of a uniform unitary
//   2. Multi-tick accumulator drain — repeated application of the same
//      unitary mirrors `while (accum >= DT) { update(); accum -= DT; }`
//   3. Render-vs-update separation — distinct registers track the
//      "update" (state evolution) and "render" (measurement) phases

OPENQASM 3.1;
include "stdgates.inc";

// ── Primitive 1: one fixed timestep ──────────────────────────────────
// A small Rz rotation acts as our per-tick unitary. Angle pi/8 is the
// quantum analog of DT_US — a fixed advance per tick.
qubit[1] t1;
bit[1] t1_c;

h t1[0];                  // |+⟩ — superposition holds phase
rz(pi/8) t1[0];           // one tick: advance phase by pi/8
h t1[0];                  // back to computational basis
t1_c[0] = measure t1[0];
// P(1) = sin²(π/16) ≈ 0.04: one small tick barely moves the readout
// @expect t1_c in {0, 1}

// ── Primitive 2: 5-tick accumulator drain (spiral cap analog) ────────
// The classical loop caps updates at MAX_ACCUM/DT_US = 5. Here we apply
// the same Rz(pi/8) rotation 5 times. Five identical rotations compose
// into Rz(5·pi/8) — the quantum equivalent of 5 fixed-step updates.
qubit[1] t5;
bit[1] t5_c;

h t5[0];
rz(pi/8) t5[0];           // tick 1
rz(pi/8) t5[0];           // tick 2
rz(pi/8) t5[0];           // tick 3
rz(pi/8) t5[0];           // tick 4
rz(pi/8) t5[0];           // tick 5 — total phase = 5pi/8
h t5[0];
t5_c[0] = measure t5[0];
// P(1) = sin²(5π/16) ≈ 0.69: five ticks moved it most of the way
// @expect t5_c in {0, 1}

// ── Primitive 3: update-vs-render separation ─────────────────────────
// The "update" register holds the evolving game state — repeated
// rotations advance it, one per frame.
// The "render" register samples (measures) the state at frame
// boundaries. Update rate (number of unitary applications) and render
// rate (number of measurements) decouple cleanly: the update register
// can absorb many rotations while the render register collapses once.
qubit[2] upd;              // 2-qubit "game state"
qubit[1] rdr;              // dedicated render qubit
bit[2] upd_c;
bit[1] rdr_c;

// 3 ticks of update (mimics 3 frames at exact dt)
h upd[0];
rz(pi/4) upd[0];          // frame 1 update
rz(pi/4) upd[0];          // frame 2 update
rz(pi/4) upd[0];          // frame 3 update

// Rotate the accumulated phase into the computational basis, THEN
// copy it: CNOT entangles render with update — render observes the
// update state. The order matters. A CNOT copies only the Z basis, and
// the ticks live in the phase: copied before this h, the render qubit
// would read 50/50 whatever the tick count, and its entanglement
// would erase the phase from upd too.
h upd[0];
cx upd[0], rdr[0];

upd_c = measure upd;
rdr_c[0] = measure rdr[0];
// P(1) = sin²(3π/8) ≈ 0.85 for both, and rdr_c always equals upd_c[0];
// upd[1] is never touched, so upd_c is 00 or 01.
// @expect upd_c in {0, 1}
// @expect rdr_c in {0, 1}

// ── Notes — classical game loop vs quantum-timestep simulation ───────
//
// Classical fixed-timestep loop:
//   - Accumulator drains in chunks of DT (e.g. 16667 us)
//   - Each drained chunk fires one update(); render() runs once per frame
//   - Spiral cap bounds updates at 5 per call to prevent runaway
//
// Quantum simulation under Trotterization:
//   - State evolves under e^(-iH·dt), one unitary per timestep
//   - The number of Trotter steps is bounded by the desired error and
//     the simulation horizon — directly analogous to MAX_ACCUM/DT
//   - Measurement (render) is a one-shot sample at frame boundaries;
//     the unitary update can run for many ticks between measurements
//
// Both regimes share the structure: a fixed per-tick operator advances
// the simulation, and a separate "render" mechanism reads it out at
// whatever cadence the display (or experimentalist) demands.
