// Vidya — Write-Ahead Logging in OpenQASM (phase-encoded checkpoint)
//
// Classical WAL: append a record to a sequential log BEFORE mutating
// the data store; on crash, replay the log to recover the durable
// state. The quantum analog is *quantum-state recovery*: a register
// encodes the data, a separate register acts as a "log" by entangling
// with the data on each transition, and a measurement of the log
// register collapses to the most recent committed state. Three
// primitives illustrated:
//
//   1. A 4-qubit "data store" register encodes 4 boolean keys.
//   2. A 4-qubit "log" register entangles via CNOT with each data
//      transition — the analog of "append a SET op record before
//      flipping the data bit". Entanglement is the irreversible "log
//      record" in this picture.
//   3. Measurement of the log register reports the recovered key
//      states — the quantum analog of replay.
//
// In real quantum-error-correction codes (Shor, Steane, surface) the
// analog is much deeper: ancilla qubits are entangled with the data
// register before each gate so that a measurement of the ancillas
// reveals the syndrome of any error that occurred — *exactly* the WAL
// pattern, with the ancilla register playing the role of the durable
// log. The structural mapping: classical WAL records "what changed";
// QEC ancillas record "what went wrong" — both are checkpoint streams
// that enable post-hoc state recovery.

OPENQASM 2.0;
include "qelib1.inc";

// --- Data store register: 4 keys × 1 bit each -----------------------
// data[i] = |1> means "key i has a value", |0> means absent.
qreg data[4];
creg data_c[4];

// --- Log register: 4 record slots, one per data transition ----------
// log[i] is entangled with data[i] on each SET operation. After
// commit, measurement of log_c yields the recovered keys.
qreg log[4];
creg log_c[4];

// --- SET key 0: classical analog is store_set(0, 100). The "log
// before data" rule means we entangle log[0] with the eventual data
// state BEFORE mutating data[0]. We achieve this by:
//   1. Flip log[0] to |1> (the log record).
//   2. CNOT log[0] -> data[0] (mutate data conditional on log).
// Because log[0] is in |1>, the CNOT deterministically flips data[0]
// — the same end state as a classical SET, but via the log.
x log[0];
cx log[0], data[0];

// --- SET key 1: same pattern.
x log[1];
cx log[1], data[1];

// --- SET key 2: same pattern.
x log[2];
cx log[2], data[2];

// --- Commit: in the classical model, fsync makes log[0..2] durable.
// In the quantum model, we measure the log register — collapsing it
// to a definite computational-basis state, which is the durable
// checkpoint. data_c is read out separately to verify both registers
// agree (the log-data consistency invariant).
measure log -> log_c;
measure data -> data_c;

// log_c will read "0111" (bits 0, 1, 2 set) with probability 1.
// data_c will read "0111" — the same — confirming WAL's invariant:
// every committed log record corresponds to a data mutation.


// --- Crash + replay illustration ------------------------------------
// A second run demonstrates recovery: the data register is
// re-initialized to |0000>, but the log register still holds the
// committed records. Replaying the log against fresh data restores
// state.
qreg data2[4];
qreg log2[4];
creg data2_c[4];

// Re-establish the committed log (in a real system this would be
// loaded from disk; here we re-prepare it).
x log2[0];
x log2[1];
x log2[2];

// Replay: each set log bit drives a CNOT into the corresponding data
// bit. data2 was |0000>, becomes |0111> — the recovered state.
cx log2[0], data2[0];
cx log2[1], data2[1];
cx log2[2], data2[2];

measure data2 -> data2_c;
// data2_c = "0111" — replay successfully reconstructed the data
// store from the log register.


// --- Notes — classical WAL vs quantum-state recovery ----------------
//
// Classical WAL:
//   - Sequential append-only log file
//   - log_committed marks the durable prefix
//   - Replay applies each record to a fresh data store
//   - Recovery is O(log_size) per restart
//
// Quantum analog (this file):
//   - Log register entangled with data via CNOT-per-transition
//   - Measurement collapses the log to a durable basis state
//   - Re-applying the same gate sequence on a fresh data register
//     reconstructs the post-commit state
//   - This is structurally identical to syndrome extraction in
//     stabilizer-code QEC: ancillas (log) are measured, classical
//     decoder (replay) determines the correction
//
// Where the two regimes meet: fault-tolerant quantum computers will
// log every gate's syndrome to a classical WAL, then replay-correct
// during decoding. The two abstractions become one system.
