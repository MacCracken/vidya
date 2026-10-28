// Vidya — Design Patterns in OpenQASM (Quantum Analogs)
//
// Quantum circuits exhibit design patterns analogous to classical ones:
// parameterized circuits (builder), oracle selection (strategy),
// error correction syndrome dispatch (observer), quantum state machines,
// and circuit templates (factory). Each pattern shows how quantum
// computing structures mirror classical software engineering.

OPENQASM 3.1;
include "stdgates.inc";

// ── Builder Pattern: Parameterized Circuit Construction ───────────────
// A "builder" in quantum computing constructs circuits step by step
// with configurable parameters. Here we build a parameterized rotation
// circuit: Ry(θ) followed by entanglement, with configurable angles.
// Different parameter choices yield different quantum states.

qubit[3] build;
bit[3] build_out;

// Step 1: Apply parameterized rotations (like setting builder fields)
ry(pi/4) build[0];       // rotation angle = π/4
ry(pi/3) build[1];       // rotation angle = π/3
ry(pi/6) build[2];       // rotation angle = π/6

// Step 2: Entangle (structural wiring — the "build" step)
cx build[0], build[1];
cx build[1], build[2];

// Step 3: Final measurement ("finalize" the built state)
build_out = measure build;

// ── Strategy Pattern: Oracle Selection ───────────────────────────────
// Different oracles implement different "strategies" for marking
// target states. The surrounding algorithm (Grover diffusion) stays
// the same — only the oracle changes. This is strategy pattern:
// same algorithm skeleton, interchangeable core operation.

// Strategy A: oracle marks |11⟩ using CZ
qubit[2] strat_a;
bit[2] strat_a_out;

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

strat_a_out = measure strat_a;
// strat_a_out reads 11 on every shot: one iteration is exact for N=4
// @expect strat_a_out == 3

// Strategy B: oracle marks |01⟩ using X + CZ + X
qubit[2] strat_b;
bit[2] strat_b_out;

h strat_b[0];
h strat_b[1];

// Oracle B: mark |01⟩ (written q[0]q[1]: strat_b[0]=0, strat_b[1]=1)
// — flip qubit 0, CZ, flip back
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

strat_b_out = measure strat_b;
// strat_b_out reads strat_b[1]=1, strat_b[0]=0 (value 2) on every shot
// @expect strat_b_out == 2

// ── Observer Pattern: Error Correction Syndrome Dispatch ─────────────
// In quantum error correction, "syndrome measurement" detects errors
// without collapsing the logical state. The syndrome bits act like
// event notifications — different syndrome values trigger different
// correction operations (observers). Here: 3-qubit bit-flip code.

qubit[3] obs_data;     // 3 data qubits (logical |0⟩ = |000⟩)
qubit[2] obs_syn;      // 2 syndrome ancilla qubits
bit[2] obs_s;        // syndrome measurement results

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
obs_s[0] = measure obs_syn[0];
obs_s[1] = measure obs_syn[1];
// Both parity checks see the flipped qubit 1: obs_s = 11 on every shot
// @expect obs_s == 3

// Syndrome dispatch (observer callbacks), s written s[0]s[1]:
// s=00: no error       s=01: error on qubit 2
// s=10: error on qubit 0  s=11: error on qubit 1
// In hardware, classical feedback applies X based on syndrome.
// Here we show the syndrome extraction — the measurement result
// tells which "observer" (correction gate) to dispatch.

// ── State Machine: Quantum State Transitions ─────────────────────────
// A quantum state machine where applying different unitaries
// transitions between orthogonal states. This demonstrates
// deterministic state transitions using quantum gates — each gate
// is a "transition function" that maps one state to another.

qubit[2] fsm;
bit[2] fsm_out;

// State encoding, written fsm[1]fsm[0]: |00⟩=locked, |01⟩=closed,
// |10⟩=open
// Start in |00⟩ (locked)

// Transition: locked → closed (|00⟩ → |01⟩)
// Apply X to qubit 0
x fsm[0];

// Transition: closed → open (|01⟩ → |10⟩)
// Swap qubits: stdgates.inc has `swap`; spelled out as its 3 cx
// primitives to show the transition's cost
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
fsm_out = measure fsm;
// @expect fsm_out == 0

// ── Factory Pattern: Circuit Templates ───────────────────────────────
// A "factory" produces different circuit structures from a template.
// Here: Bell state factory — different input configurations produce
// different Bell states, all using the same H + CX template.

// Bell state |Φ+⟩ = (|00⟩ + |11⟩)/√2
qubit[2] bell_a;
bit[2] bell_a_out;
h bell_a[0];
cx bell_a[0], bell_a[1];
bell_a_out = measure bell_a;
// @expect bell_a_out in {0, 3}

// Bell state |Ψ+⟩ = (|01⟩ + |10⟩)/√2 — flip input qubit 1 (the
// target). Flipping qubit 0 (the control) instead would only change
// the sign, giving |Φ-⟩: the control's input picks the sign, the
// target's input picks Φ (equal bits) or Ψ (opposite bits).
qubit[2] bell_b;
bit[2] bell_b_out;
x bell_b[1];          // different "parameter" to factory
h bell_b[0];
cx bell_b[0], bell_b[1];
bell_b_out = measure bell_b;
// Ψ: the two bits always DIFFER — 01 or 10, never 00 or 11
// @expect bell_b_out in {1, 2}

// Bell state |Φ-⟩ = (|00⟩ - |11⟩)/√2 — apply Z after
qubit[2] bell_c;
bit[2] bell_c_out;
h bell_c[0];
cx bell_c[0], bell_c[1];
z bell_c[0];          // different "post-processing"
bell_c_out = measure bell_c;
// Same outcomes as |Φ+⟩: the sign is invisible to a Z-basis measurement
// @expect bell_c_out in {0, 3}

// Bell state |Ψ-⟩ = (|01⟩ - |10⟩)/√2 — flip the target + Z
qubit[2] bell_d;
bit[2] bell_d_out;
x bell_d[1];
h bell_d[0];
cx bell_d[0], bell_d[1];
z bell_d[0];
bell_d_out = measure bell_d;
// @expect bell_d_out in {1, 2}
