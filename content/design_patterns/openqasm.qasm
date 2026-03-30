// Vidya — Design Patterns in OpenQASM (Quantum Analogs)
//
// Quantum circuits exhibit design patterns analogous to classical ones:
// parameterized circuits (builder), oracle selection (strategy),
// error correction syndrome dispatch (observer), quantum state machines,
// and circuit templates (factory). Each pattern shows how quantum
// computing structures mirror classical software engineering.

OPENQASM 2.0;
include "qelib1.inc";

// ── Builder Pattern: Parameterized Circuit Construction ───────────────
// A "builder" in quantum computing constructs circuits step by step
// with configurable parameters. Here we build a parameterized rotation
// circuit: Ry(θ) followed by entanglement, with configurable angles.
// Different parameter choices yield different quantum states.

qreg build[3];
creg build_out[3];

// Step 1: Apply parameterized rotations (like setting builder fields)
ry(pi/4) build[0];       // rotation angle = π/4
ry(pi/3) build[1];       // rotation angle = π/3
ry(pi/6) build[2];       // rotation angle = π/6

// Step 2: Entangle (structural wiring — the "build" step)
cx build[0], build[1];
cx build[1], build[2];

// Step 3: Final measurement ("finalize" the built state)
measure build -> build_out;

// ── Strategy Pattern: Oracle Selection ───────────────────────────────
// Different oracles implement different "strategies" for marking
// target states. The surrounding algorithm (Grover diffusion) stays
// the same — only the oracle changes. This is strategy pattern:
// same algorithm skeleton, interchangeable core operation.

// Strategy A: oracle marks |11⟩ using CZ
qreg strat_a[2];
creg strat_a_out[2];

h strat_a[0];
h strat_a[1];

// Oracle A: CZ marks |11⟩
cz strat_a[0], strat_a[1];

// Diffusion operator (same for all strategies)
h strat_a[0];
h strat_a[1];
x strat_a[0];
x strat_a[1];
cz strat_a[0], strat_a[1];
x strat_a[0];
x strat_a[1];
h strat_a[0];
h strat_a[1];

measure strat_a -> strat_a_out;

// Strategy B: oracle marks |01⟩ using X + CZ + X
qreg strat_b[2];
creg strat_b_out[2];

h strat_b[0];
h strat_b[1];

// Oracle B: mark |01⟩ — flip qubit 0, CZ, flip back
x strat_b[0];
cz strat_b[0], strat_b[1];
x strat_b[0];

// Same diffusion operator
h strat_b[0];
h strat_b[1];
x strat_b[0];
x strat_b[1];
cz strat_b[0], strat_b[1];
x strat_b[0];
x strat_b[1];
h strat_b[0];
h strat_b[1];

measure strat_b -> strat_b_out;

// ── Observer Pattern: Error Correction Syndrome Dispatch ─────────────
// In quantum error correction, "syndrome measurement" detects errors
// without collapsing the logical state. The syndrome bits act like
// event notifications — different syndrome values trigger different
// correction operations (observers). Here: 3-qubit bit-flip code.

qreg obs_data[3];     // 3 data qubits (logical |0⟩ = |000⟩)
qreg obs_syn[2];      // 2 syndrome ancilla qubits
creg obs_s[2];        // syndrome measurement results

// Encode logical |0⟩ = |000⟩ (already initialized)
// Introduce a bit-flip error on qubit 1 for demonstration
x obs_data[1];

// Syndrome extraction: parity checks
// Syndrome bit 0: parity of qubits 0,1
cx obs_data[0], obs_syn[0];
cx obs_data[1], obs_syn[0];

// Syndrome bit 1: parity of qubits 1,2
cx obs_data[1], obs_syn[1];
cx obs_data[2], obs_syn[1];

// Measure syndrome (the "event" that triggers correction)
measure obs_syn[0] -> obs_s[0];
measure obs_syn[1] -> obs_s[1];

// Syndrome dispatch (observer callbacks):
// s=00: no error       s=01: error on qubit 2
// s=10: error on qubit 0  s=11: error on qubit 1
// In hardware, classical feedback applies X based on syndrome.
// Here we show the syndrome extraction — the measurement result
// tells which "observer" (correction gate) to dispatch.

// ── State Machine: Quantum Phase Kickback State Transitions ──────────
// A quantum state machine where applying different unitaries
// transitions between orthogonal states. This demonstrates
// deterministic state transitions using quantum gates — each gate
// is a "transition function" that maps one state to another.

qreg fsm[2];
creg fsm_out[2];

// State encoding: |00⟩=locked, |01⟩=closed, |10⟩=open
// Start in |00⟩ (locked)

// Transition: locked → closed (|00⟩ → |01⟩)
// Apply X to qubit 0
x fsm[0];

// Transition: closed → open (|01⟩ → |10⟩)
// Swap qubits: decompose to cx primitives
cx fsm[0], fsm[1];
cx fsm[1], fsm[0];
cx fsm[0], fsm[1];

// Transition: open → closed (|10⟩ → |01⟩)
// Swap back
cx fsm[0], fsm[1];
cx fsm[1], fsm[0];
cx fsm[0], fsm[1];

// Transition: closed → locked (|01⟩ → |00⟩)
x fsm[0];

// Should be back in |00⟩ (locked)
measure fsm -> fsm_out;

// ── Factory Pattern: Circuit Templates ───────────────────────────────
// A "factory" produces different circuit structures from a template.
// Here: Bell state factory — different input configurations produce
// different Bell states, all using the same H + CX template.

// Bell state |Φ+⟩ = (|00⟩ + |11⟩)/√2
qreg bell_a[2];
creg bell_a_out[2];
h bell_a[0];
cx bell_a[0], bell_a[1];
measure bell_a -> bell_a_out;

// Bell state |Ψ+⟩ = (|01⟩ + |10⟩)/√2 — flip input qubit 0
qreg bell_b[2];
creg bell_b_out[2];
x bell_b[0];          // different "parameter" to factory
h bell_b[0];
cx bell_b[0], bell_b[1];
measure bell_b -> bell_b_out;

// Bell state |Φ-⟩ = (|00⟩ - |11⟩)/√2 — apply Z after
qreg bell_c[2];
creg bell_c_out[2];
h bell_c[0];
cx bell_c[0], bell_c[1];
z bell_c[0];          // different "post-processing"
measure bell_c -> bell_c_out;

// Bell state |Ψ-⟩ = (|01⟩ - |10⟩)/√2 — flip + Z
qreg bell_d[2];
creg bell_d_out[2];
x bell_d[0];
h bell_d[0];
cx bell_d[0], bell_d[1];
z bell_d[0];
measure bell_d -> bell_d_out;
