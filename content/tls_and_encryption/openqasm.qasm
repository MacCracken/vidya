// Vidya — TLS and Encryption in OpenQASM (handshake-as-entanglement analog)
//
// Classical TLS 1.3: a 1-RTT handshake establishes a shared secret
// (ECDHE) and authenticates the server (cert chain + signature). The
// quantum analog is *Bell-pair distribution + measurement-based
// authentication*: the H + CNOT pair generates a shared "key"
// (entanglement); subsequent CNOTs to neighbor qubits propagate the
// authenticated state through the connection — exactly the way TLS
// derives application traffic keys from the shared secret.
//
// 4-qubit register represents the four phases of the TLS handshake:
//   q[0] — client KEM share (Hadamard puts it in superposition)
//   q[1] — server KEM share (entangled with q[0] via CNOT — the
//          ECDHE shared secret)
//   q[2] — server certificate verified (entangled via CNOT from q[1]
//          — only valid after the shared secret is established)
//   q[3] — application data flowing (entangled via CNOT from q[2] —
//          only valid after cert verification)
//
// In real quantum cryptography, E91 works this way: shared entangled
// pairs are the source of the secret, and measurements collapse them
// into a classical key that both parties hold (BB84 gets the same
// result by prepare-and-measure, with no entanglement). Neither
// authenticates anyone: QKD needs an already-authenticated classical
// channel, which is the job TLS's certificate chain does.
//
// Post-quantum TLS is a different thing. Hybrid key exchange such as
// X25519MLKEM768 (ML-KEM, FIPS 203 — formerly Kyber), deployed in
// browsers since 2024, is classical math chosen to resist quantum
// attackers. It runs on ordinary computers and involves no qubits.

OPENQASM 3.1;
include "stdgates.inc";

qubit[4] q;
bit[4] c;

// ECDHE: client and server agree on shared secret via entanglement
h q[0];
cx q[0], q[1];

// Cert verification: only after shared secret
cx q[1], q[2];

// App data: only after cert
cx q[2], q[3];

c = measure q;
// All four agree: 0000 or 1111, each half the time
// @expect c in {0, 15}
