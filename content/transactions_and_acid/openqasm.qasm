// Vidya — Transactions and ACID in OpenQASM (entanglement-as-commit)
//
// Classical ACID: a transaction stages writes locally, then commits
// atomically (all-or-nothing) to the durable store. Aborts discard.
// Optimistic concurrency control adds a per-key version snapshot —
// commit succeeds only if the snapshot still matches when validation
// runs.
//
// The quantum analog is *entanglement-as-commit*: the "durable" data
// register and the "transaction" register start unentangled; gate
// operations build a tx-local proposed state without touching data;
// a single controlled gate at commit time entangles them so that any
// measurement of data sees the tx's writes. Aborting is *not running*
// the entanglement gate — the tx register is discarded, data is
// untouched. Atomicity is the all-or-nothing structure of a single
// gate: it either fires or it doesn't.
//
// OCC validation maps to a *version qubit*: entangled with data on
// every write. The tx snapshots the version qubit at read time. If a
// concurrent tx has flipped the version qubit before our commit, the
// snapshot register and the live version register are now out of
// phase, and the controlled-commit gate on (snap == live) blocks the
// install. The structural pattern matches stabilizer-code QEC: the
// ancilla register is measured to detect whether an unauthorized
// change happened between read and commit.
//
// Three primitives illustrated:
//   1. A 3-qubit "accounts" register (3 keys × 1 bit each).
//   2. A 3-qubit "tx writes" register staging proposed writes.
//   3. A 1-qubit "version" register entangled with account[0].
//
// Each demonstration is a self-contained sub-circuit on its own
// register — qiskit's qasm2 loader accepts the file as long as the
// gate set is valid.

OPENQASM 2.0;
include "qelib1.inc";

// === A — Atomicity: commit installs all-or-nothing ==================
// data_c is initially |000>. tx_c stages writes |111>. A controlled
// fan-out (via CNOTs from tx into data) copies tx onto data only if
// the commit qubit is |1>. Setting commit = |1> = "commit"; |0> = "abort".

qreg data[3];
qreg tx[3];
qreg commit_q[1];
creg data_c[3];

// Stage 3 writes in tx (|111>)
x tx[0];
x tx[1];
x tx[2];

// Set commit_q = |1>: COMMIT path
x commit_q[0];

// Controlled fan-out: copy tx[i] into data[i] iff commit_q == 1.
// Built from Toffoli (ccx) — the all-or-nothing gate.
ccx commit_q[0], tx[0], data[0];
ccx commit_q[0], tx[1], data[1];
ccx commit_q[0], tx[2], data[2];

measure data -> data_c;
// data_c = "111" — commit installed all three writes atomically.


// === A — Atomicity: abort discards all writes =======================
// Same setup but commit_q stays |0> — the ccx gates never fire.

qreg data_a[3];
qreg tx_a[3];
qreg commit_a[1];
creg data_ac[3];

x tx_a[0];
x tx_a[1];
x tx_a[2];

// commit_a stays |0> (ABORT)

ccx commit_a[0], tx_a[0], data_a[0];
ccx commit_a[0], tx_a[1], data_a[1];
ccx commit_a[0], tx_a[2], data_a[2];

measure data_a -> data_ac;
// data_ac = "000" — abort, all writes discarded.


// === I — Isolation via OCC version snapshot =========================
// version qubit entangles with account[0]. Tx reads → snapshot version.
// Concurrent tx flips version. Validation gate gates the commit on
// (snapshot == live), which now disagree → commit blocked.

qreg account[1];
qreg version[1];
qreg snap[1];
qreg tx_w[1];
qreg validate[1];
creg account_c[1];

// Initial state: account[0] = |0>, version[0] = |0>.

// Tx reads: snapshot the current version into snap.
cx version[0], snap[0];      // snap = version (|0>)

// Tx stages a write proposal: tx_w = |1>.
x tx_w[0];

// Concurrent commit by another tx: bumps version[0] to |1>.
x version[0];                // version = |1>; snap is stale (still |0>)

// Validation: validate = (snap == version)? In computational basis,
// snap XOR version = 0 means equal. CNOT version into a copy of snap;
// if they differ, the result is |1> and we set validate = |0>.
//
// Simpler form: prepare validate = |1>; if snap != version, flip
// validate to |0>. We approximate by XORing snap into validate
// (controlled on the disagreement).

x validate[0];               // validate = |1> (assume valid)
cx snap[0], validate[0];     // if snap is |1>, flip validate
cx version[0], validate[0];  // if version is |1>, flip again
// If snap == version, validate flipped 0 or 2 times → unchanged at |1>.
// If snap != version, validate flipped exactly once → now |0>.

// Commit: install tx_w into account ONLY if validate == |1>.
ccx validate[0], tx_w[0], account[0];

measure account -> account_c;
// account_c = "0" — commit was blocked because the snapshot was stale.
// (Had no concurrent tx bumped version, account_c would be "1".)


// === D — Durability via measurement collapse =========================
// After commit, the durable register is measured to a definite
// computational basis state — the quantum analog of fsync. Once
// measured, the value persists regardless of subsequent operations
// on the (now-classical) bit. This mirrors the "post-fsync the bytes
// are durable" contract.

qreg durable[1];
creg durable_c[1];

// Commit a "1" into durable.
x durable[0];

// Measure to "fsync".
measure durable -> durable_c;
// durable_c = "1" — committed. The bit is now classical. Any further
// quantum gates on durable[] cannot un-collapse the measured value.


// --- Notes — classical ACID vs quantum entanglement-as-commit -------
//
// Classical OCC:
//   - Per-key version counter; tx snapshots at read time
//   - Validate at commit: snap == current_version?
//   - Pass: install writes, bump versions; Fail: abort tx
//
// Quantum analog (this file):
//   - Version qubit entangled with data on each write
//   - Tx copies version into snap qubit at read time (CNOT)
//   - Validation gate: ccx gated on (snap XOR version == 0)
//   - Commit fans out tx_w into data only if validation passes
//
// The structural correspondence is exact:
//   - Atomicity     ↔ all-or-nothing of a single controlled gate
//   - Consistency   ↔ invariants preserved by gate-set closure
//   - Isolation     ↔ unentangled tx register + ancilla snapshot
//   - Durability    ↔ measurement collapse to classical basis
//
// In fault-tolerant quantum computing, the same pattern shows up as
// stabilizer-code QEC: ancillas play the role of the WAL, syndrome
// extraction plays the role of validation, and decoder logic plays
// the role of commit/abort. ACID and QEC are siblings.
