// Vidya — Kernel Topics in OpenQASM (Quantum Error Correction)
//
// Quantum "kernel" work: error correction codes protect qubits from
// noise (the quantum analog of ECC memory), qubit routing maps
// logical operations to physical hardware (like virtual memory),
// and measurement-based feedback is the quantum interrupt handler.

OPENQASM 3.1;
include "stdgates.inc";

// ── Bit-Flip Error Correction Code ────────────────────────────────────
// The 3-qubit repetition code protects against single bit-flip (X) errors.
// Analogous to triple modular redundancy in classical hardware.
// Encode: α|0⟩+β|1⟩ → α|000⟩+β|111⟩ via CNOT — NOT |ψψψ⟩, which the
// no-cloning theorem forbids: the CNOTs copy the basis value, not the
// state. Detect: measure syndromes. Correct: apply X.

qubit[1] data_bf;       // logical qubit
qubit[2] anc_bf;        // ancilla (redundancy)
bit[2] syn_bf;        // syndrome bits

// Encode: α|0⟩+β|1⟩ → α|000⟩+β|111⟩
// If data = |1⟩, all three become |1⟩
x data_bf[0];          // prepare |1⟩ as our data
cx data_bf[0], anc_bf[0];
cx data_bf[0], anc_bf[1];
// State is now |111⟩

// Simulate error: bit flip on qubit 1 (ancilla 0)
x anc_bf[0];
// State is now |101⟩ — one bit flipped

// Syndrome extraction: compare pairs
// syndrome[0] = data XOR anc[0], syndrome[1] = data XOR anc[1]
cx data_bf[0], anc_bf[0];
cx data_bf[0], anc_bf[1];
// Measure ancillas to get syndrome
syn_bf[0] = measure anc_bf[0];
syn_bf[1] = measure anc_bf[1];
// syndrome = 10 (syn_bf[0]=1, syn_bf[1]=0: value 1) → error on anc[0].
// Correction: apply X to anc[0]
// @expect syn_bf == 1

// ── Phase-Flip Error Correction ───────────────────────────────────────
// Protects against Z (phase flip) errors. Same structure as bit-flip
// but in the Hadamard basis. Together with bit-flip code, forms
// the Shor 9-qubit code — full single-qubit error correction.

qubit[1] data_pf;
qubit[2] anc_pf;
bit[2] syn_pf;

// Prepare and encode in Hadamard basis
h data_pf[0];
cx data_pf[0], anc_pf[0];
cx data_pf[0], anc_pf[1];

// Convert to phase basis for phase-flip detection
h data_pf[0];
h anc_pf[0];
h anc_pf[1];

// Simulate phase error on qubit 0
z data_pf[0];

// Convert back and measure syndrome
h data_pf[0];
h anc_pf[0];
h anc_pf[1];
cx data_pf[0], anc_pf[0];
cx data_pf[0], anc_pf[1];
syn_pf[0] = measure anc_pf[0];
syn_pf[1] = measure anc_pf[1];
// syndrome = 11: both checks disagree with qubit 0, so the phase error
// is on the data qubit
// @expect syn_pf == 3

// ── Qubit Routing (SWAP network) ──────────────────────────────────────
// Physical qubits have limited connectivity. To apply a gate between
// non-adjacent qubits, we SWAP qubits along the path — like the
// kernel's page migration for NUMA locality.

qubit[4] route;
bit[4] route_out;

// Prepare: qubit 0 = |1⟩, qubit 3 = |0⟩
x route[0];

// Goal: apply CNOT(0, 3) but they're not adjacent
// Route: SWAP 0↔1, then SWAP 1↔2, now original qubit 0 is at position 2
// SWAP = cx a,b; cx b,a; cx a,b — stdgates.inc's `swap` is exactly
// this; it is spelled out because those 3 CNOTs per hop are the
// routing cost the compiler pays.
cx route[0], route[1];
cx route[1], route[0];
cx route[0], route[1];    // SWAP 0,1

cx route[1], route[2];
cx route[2], route[1];
cx route[1], route[2];    // SWAP 1,2

// Now the data that was in qubit 0 is in qubit 2 — adjacent to qubit 3
cx route[2], route[3];    // CNOT(original 0, 3)

// Route back: SWAP 2,1 then SWAP 1,0
cx route[1], route[2];
cx route[2], route[1];
cx route[1], route[2];

cx route[0], route[1];
cx route[1], route[0];
cx route[0], route[1];

route_out = measure route;
// route[0] is back to 1 and the CNOT reached route[3]: 1001 = 9
// @expect route_out == 9

// ── Measurement-Based Feedback (Quantum "Interrupt") ──────────────────
// Mid-circuit measurement + classical feedback: measure a qubit,
// and conditionally apply corrections. This is the quantum analog
// of an interrupt handler — hardware event triggers corrective action.

qubit[2] fb;
bit[1] fb_meas;
bit[1] fb_out;

// Prepare entangled state
h fb[0];
cx fb[0], fb[1];

// "Interrupt": measure qubit 0
fb_meas[0] = measure fb[0];

// Conditional correction: if measured 1, flip qubit 1 to get |0⟩
// This is quantum teleportation's correction step
if (fb_meas == 1) { x fb[1]; }

fb_out[0] = measure fb[1];
// fb_meas is 0 or 1 at random; the correction makes fb_out 0 either way
// @expect fb_meas in {0, 1}
// @expect fb_out == 0

// ── Quantum Memory Management (Qubit Reset) ──────────────────────────
// Qubits are a scarce resource. After use, reset them to |0⟩ for
// reuse — like freeing memory. Reset = measure + conditional X.

qubit[2] mem;
// ⚠ `if (reg == N)` compares the ENTIRE register as an integer, not a
// single bit. With a 2-bit `mem_check`, the entangled state below only
// ever yields 00 or 11 — so `if (mem_check == 1)` (binary 01) can never
// be true and the reset silently never fires. Measured on an earlier
// version: 2059 of 4000 shots came back with both qubits still |1⟩
// while the file claimed they were reset. OpenQASM 2.0 had only the
// whole-register compare, so this file split the check into one-bit
// registers; OpenQASM 3 can also test one bit directly,
// `if (mem_check[0]) x mem[0];`. Either way, compare bits, not the
// register.
bit[1] mem_check0;
bit[1] mem_check1;
bit[2] mem_reset;

// Use qubits: create entangled state
h mem[0];
cx mem[0], mem[1];

// "Free" the qubits: measure then reset to |0⟩
mem_check0[0] = measure mem[0];
mem_check1[0] = measure mem[1];

// Reset: conditionally flip back to |0⟩
// (OpenQASM also has a native `reset` instruction, which three other
// files in this corpus use; the measure-then-conditional-X form is spelled
// out here because that is the mechanism the section is teaching.)
if (mem_check0 == 1) { x mem[0]; }
if (mem_check1 == 1) { x mem[1]; }

// Verify reset: should both be |0⟩ now
mem_reset[0] = measure mem[0];
mem_reset[1] = measure mem[1];
// mem_check0/1 agree and are 0 or 1 at random; the reset always lands
// @expect mem_check0 in {0, 1}
// @expect mem_check1 in {0, 1}
// @expect mem_reset == 0
