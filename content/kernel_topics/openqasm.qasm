// Vidya — Kernel Topics in OpenQASM (Quantum Error Correction)
//
// Quantum "kernel" work: error correction codes protect qubits from
// noise (the quantum analog of ECC memory), qubit routing maps
// logical operations to physical hardware (like virtual memory),
// and measurement-based feedback is the quantum interrupt handler.

OPENQASM 2.0;
include "qelib1.inc";

// ── Bit-Flip Error Correction Code ────────────────────────────────────
// The 3-qubit repetition code protects against single bit-flip (X) errors.
// Analogous to triple modular redundancy in classical hardware.
// Encode: |ψ⟩ → |ψψψ⟩ via CNOT. Detect: measure syndromes. Correct: apply X.

qreg data_bf[1];       // logical qubit
qreg anc_bf[2];        // ancilla (redundancy)
creg syn_bf[2];        // syndrome bits

// Encode: |ψ⟩ → |ψψψ⟩
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
measure anc_bf[0] -> syn_bf[0];
measure anc_bf[1] -> syn_bf[1];
// syndrome = 10 → error on anc[0]. Correction: apply X to anc[0]

// ── Phase-Flip Error Correction ───────────────────────────────────────
// Protects against Z (phase flip) errors. Same structure as bit-flip
// but in the Hadamard basis. Together with bit-flip code, forms
// the Shor 9-qubit code — full single-qubit error correction.

qreg data_pf[1];
qreg anc_pf[2];
creg syn_pf[2];

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
measure anc_pf[0] -> syn_pf[0];
measure anc_pf[1] -> syn_pf[1];

// ── Qubit Routing (SWAP network) ──────────────────────────────────────
// Physical qubits have limited connectivity. To apply a gate between
// non-adjacent qubits, we SWAP qubits along the path — like the
// kernel's page migration for NUMA locality.

qreg route[4];
creg route_out[4];

// Prepare: qubit 0 = |1⟩, qubit 3 = |0⟩
x route[0];

// Goal: apply CNOT(0, 3) but they're not adjacent
// Route: SWAP 0↔1, then SWAP 1↔2, now original qubit 0 is at position 2
// SWAP = cx a,b; cx b,a; cx a,b
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

measure route -> route_out;

// ── Measurement-Based Feedback (Quantum "Interrupt") ──────────────────
// Mid-circuit measurement + classical feedback: measure a qubit,
// and conditionally apply corrections. This is the quantum analog
// of an interrupt handler — hardware event triggers corrective action.

qreg fb[2];
creg fb_meas[1];
creg fb_out[1];

// Prepare entangled state
h fb[0];
cx fb[0], fb[1];

// "Interrupt": measure qubit 0
measure fb[0] -> fb_meas[0];

// Conditional correction: if measured 1, flip qubit 1 to get |0⟩
// This is quantum teleportation's correction step
if(fb_meas==1) x fb[1];

measure fb[1] -> fb_out[0];

// ── Quantum Memory Management (Qubit Reset) ──────────────────────────
// Qubits are a scarce resource. After use, reset them to |0⟩ for
// reuse — like freeing memory. Reset = measure + conditional X.

qreg mem[2];
creg mem_check[2];
creg mem_reset[2];

// Use qubits: create entangled state
h mem[0];
cx mem[0], mem[1];

// "Free" the qubits: measure then reset to |0⟩
measure mem[0] -> mem_check[0];
measure mem[1] -> mem_check[1];

// Reset: conditionally flip back to |0⟩
if(mem_check==1) x mem[0];
if(mem_check==1) x mem[1];

// Verify reset: should both be |0⟩ now
measure mem[0] -> mem_reset[0];
measure mem[1] -> mem_reset[1];
