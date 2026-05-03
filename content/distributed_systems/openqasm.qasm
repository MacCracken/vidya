// Vidya — Distributed Systems Foundations in OpenQASM
//                                  (entanglement-as-replication)
//
// Classical Dynamo-style replication: a write is sent to W of N
// replicas; a read collects from R of N. R + W > N guarantees
// intersection — every read quorum overlaps every write quorum.
//
// The quantum analog is *entanglement-as-replication*: write
// gates entangle a "data" qubit with multiple "replica" qubits;
// read gates measure multiple replica qubits and the read result
// agrees with the write iff the read set overlaps the write set.
// The intersection property falls out of how CNOT propagates
// classical correlations through entangled qubits.
//
// Three primitives illustrated:
//   1. A 3-qubit replica register (one qubit per replica).
//   2. A "client write" qubit fanned-out to a write-quorum subset
//      of replicas via CNOT (W=2).
//   3. A read-quorum subset measured (R=2). Because W+R > N=3, at
//      least one measured qubit was in the write quorum.
//
// Plus a vector-clock analog: phase-encoded counter qubits that
// commute (causal) or anti-commute (concurrent) under combination.

OPENQASM 2.0;
include "qelib1.inc";

// === Quorum write to W=2 of N=3, then read R=2 =======================
//
// Initial state: all replicas |0> (no value). The "write client"
// qubit is prepared in |1> (the value being written). CNOTs from
// the write client to replicas 0 and 1 fan the value out to the
// write quorum {0, 1}. Replica 2 is not in the write quorum.
//
// Then a read quorum measures replicas {1, 2}. Because the read
// quorum overlaps the write quorum at replica 1, the read sees
// the written value with certainty.

qreg replicas[3];
qreg write_client[1];
creg read_q[2];           // measure replicas {1, 2}

// Prepare the value to write: |1>.
x write_client[0];

// Write to W=2 of 3: replicas {0, 1}.
cx write_client[0], replicas[0];
cx write_client[0], replicas[1];

// Read R=2 of 3: replicas {1, 2}.
measure replicas[1] -> read_q[0];
measure replicas[2] -> read_q[1];
// read_q[0] = 1 (replica 1 was in write quorum, has the value).
// read_q[1] = 0 (replica 2 not in write quorum).
// The reader sees value=1 (max-seq wins), agreeing with the write.


// === Partition: minority side cannot achieve write quorum =========
//
// Model the partition by "removing" two replicas from the write
// quorum's reach (we just don't apply CNOT to them). The write
// then only lands on 1 replica — less than W=2 — and a quorum
// reader from the other side returns the stale (|0>) value.

qreg part_replicas[3];
qreg part_client[1];
creg part_read[2];

x part_client[0];

// Only one CNOT: writes to replica 0 only (1 < W=2).
cx part_client[0], part_replicas[0];

// Read quorum {1, 2}: both still in |0>. Reader sees stale.
measure part_replicas[1] -> part_read[0];
measure part_replicas[2] -> part_read[1];
// part_read = "00" — reader missed the write.


// === Vector-clock analog: causal vs concurrent phases =============
//
// Each "node" has a phase qubit. Local events apply Z (advance
// causally). Two nodes that each apply Z independently end up in
// states whose product reveals concurrency: identical Z's (same
// node) commute (causal); different-node Z's, prepared on
// independently-superposed qubits, do NOT collapse to a single
// total order — they're concurrent.
//
// Here we just demonstrate the phase advancement; concurrency
// detection in OpenQASM 2.0 requires interference experiments
// that exceed the corpus's static-circuit scope.

qreg vclock[3];
creg vclock_c[3];

// Node 0 records 1 local event: Z phase.
h vclock[0];
z vclock[0];
h vclock[0];
// vclock[0] now in a phase-tagged superposition: |1> with prob 1
// after the H-Z-H sequence (X-equivalent). Modelling that node 0's
// component has incremented.

// Node 1 records 1 local event: same.
h vclock[1];
z vclock[1];
h vclock[1];

// Node 2 unchanged (still |0>) — no local events.

measure vclock -> vclock_c;
// vclock_c = "011" (read MSB-first) — two components at 1, one at 0.
// Modelling vc = [1, 1, 0].


// --- Notes — distributed systems vs entanglement-as-replication --
//
// Classical Dynamo:
//   - Write to W replicas, succeed if W ack
//   - Read from R replicas, return max-seq value
//   - R + W > N guarantees read sees latest write
//   - Partition: minority side fails writes (or accepts and
//     reconciles later)
//
// Quantum analog (this file):
//   - CNOT fan-out from write client to W replica qubits
//   - Measurement of R replica qubits returns |1> if any in
//     overlap with write set
//   - Partition: drop CNOTs, read sees stale (|0>) qubits
//   - Vector clock: phase qubits per node track local events
//
// In real fault-tolerant quantum computing, similar entanglement
// patterns appear in *quantum error correction stabilizers*: data
// qubits are entangled with ancilla "syndrome" qubits, and
// measurement of the ancillas detects errors without collapsing
// the data — exactly the quorum read pattern in spirit.
