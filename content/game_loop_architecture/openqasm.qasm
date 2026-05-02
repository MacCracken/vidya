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

OPENQASM 2.0;
include "qelib1.inc";

// ── Primitive 1: one fixed timestep ──────────────────────────────────
// A small Rz rotation acts as our per-tick unitary. Angle pi/8 is the
// quantum analog of DT_US — a fixed advance per tick.
qreg t1[1];
creg t1_c[1];

h t1[0];                  // |+⟩ — superposition holds phase
rz(pi/8) t1[0];           // one tick: advance phase by pi/8
h t1[0];                  // back to computational basis
measure t1[0] -> t1_c[0];

// ── Primitive 2: 5-tick accumulator drain (spiral cap analog) ────────
// The classical loop caps updates at MAX_ACCUM/DT_US = 5. Here we apply
// the same Rz(pi/8) rotation 5 times. Five identical rotations compose
// into Rz(5·pi/8) — the quantum equivalent of 5 fixed-step updates.
qreg t5[1];
creg t5_c[1];

h t5[0];
rz(pi/8) t5[0];           // tick 1
rz(pi/8) t5[0];           // tick 2
rz(pi/8) t5[0];           // tick 3
rz(pi/8) t5[0];           // tick 4
rz(pi/8) t5[0];           // tick 5 — total phase = 5pi/8
h t5[0];
measure t5[0] -> t5_c[0];

// ── Primitive 3: update-vs-render separation ─────────────────────────
// The "update" register holds the evolving game state — controlled
// rotations advance it by a counter encoded in the input register.
// The "render" register samples (measures) the state at frame
// boundaries. Update rate (number of unitary applications) and render
// rate (number of measurements) decouple cleanly: the update register
// can absorb many rotations while the render register collapses once.
qreg upd[2];              // 2-qubit "game state"
qreg rdr[1];              // dedicated render qubit
creg upd_c[2];
creg rdr_c[1];

// 3 ticks of update (mimics 3 frames at exact dt)
h upd[0];
rz(pi/4) upd[0];          // frame 1 update
rz(pi/4) upd[0];          // frame 2 update
rz(pi/4) upd[0];          // frame 3 update

// CNOT entangles render with update — render observes the update state
cx upd[0], rdr[0];

h upd[0];
measure upd -> upd_c;
measure rdr[0] -> rdr_c[0];

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
