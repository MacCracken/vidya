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
// In real quantum cryptography (BB84, E91), this is exactly how
// authenticated key exchange works: entanglement IS the shared
// secret, and measurements collapse it into a classical key that
// both parties hold. Quantum-resistant TLS variants (Kyber/Dilithium
// in TLS 1.3 hybrid mode) will eventually move the handshake into
// this domain.

OPENQASM 2.0;
include "qelib1.inc";

qreg q[4];
creg c[4];

// ECDHE: client and server agree on shared secret via entanglement
h q[0];
cx q[0], q[1];

// Cert verification: only after shared secret
cx q[1], q[2];

// App data: only after cert
cx q[2], q[3];

measure q -> c;
