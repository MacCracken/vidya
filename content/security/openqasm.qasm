// Vidya — Security Practices in OpenQASM (Quantum Security)
//
// Quantum security: BB84 key distribution uses conjugate bases to
// detect eavesdropping. Quantum random number generation provides
// true randomness from measurement. The no-cloning theorem is the
// fundamental security primitive — quantum states can't be copied.

OPENQASM 2.0;
include "qelib1.inc";

// ── BB84 Quantum Key Distribution ─────────────────────────────────────
// Alice encodes bits in two conjugate bases:
//   Standard basis (Z): |0⟩ = 0, |1⟩ = 1
//   Hadamard basis (X): |+⟩ = 0, |−⟩ = 1
// Eve's interception disturbs the state — detectable via error rate.

// Alice prepares 4 key bits in alternating bases
qreg alice[4];
creg bob_result[4];

// Bit 0: value=1 in Z basis (apply X)
x alice[0];

// Bit 1: value=0 in X basis (apply H)
h alice[1];

// Bit 2: value=1 in X basis (apply X then H)
x alice[2];
h alice[2];

// Bit 3: value=0 in Z basis (identity — already |0⟩)

// Bob measures — if he picks the right basis, he gets Alice's bit.
// If wrong basis, result is random (50/50). After measurement,
// Alice and Bob publicly compare bases (not values) and keep only
// the matching-basis bits.
measure alice -> bob_result;

// ── Quantum Random Number Generation ──────────────────────────────────
// Hadamard + measurement = true 50/50 random bit from quantum mechanics.
// Unlike PRNGs, this randomness is provably unpredictable (Born rule).

qreg rng[8];
creg random_byte[8];

// Each qubit: H puts it in equal superposition, measurement collapses
h rng[0];
h rng[1];
h rng[2];
h rng[3];
h rng[4];
h rng[5];
h rng[6];
h rng[7];

measure rng -> random_byte;
// random_byte is a true random 8-bit value

// ── Entanglement Verification (Bell Test) ─────────────────────────────
// Verify that a shared EPR pair hasn't been tampered with.
// If entanglement is intact, measurements are perfectly correlated
// in the same basis. An eavesdropper breaks this correlation.

qreg epr_a[1];
qreg epr_b[1];
creg verify_a[1];
creg verify_b[1];

// Create Bell pair |Φ+⟩ = (|00⟩ + |11⟩)/√2
h epr_a[0];
cx epr_a[0], epr_b[0];

// Both measure in Z basis — results MUST agree
// Disagreement indicates eavesdropping or channel noise
measure epr_a[0] -> verify_a[0];
measure epr_b[0] -> verify_b[0];

// ── Quantum One-Time Pad ──────────────────────────────────────────────
// Encrypt a qubit using two classical key bits.
// key = (k1, k2): apply X^k1 Z^k2 to the message qubit.
// Provably secure: without the key, the encrypted state is maximally
// mixed (no information leaks).

qreg msg[1];
qreg key_src[2];
creg key_bits[2];
creg decrypted[1];

// Prepare message: |1⟩
x msg[0];

// Generate quantum random key bits
h key_src[0];
h key_src[1];
measure key_src[0] -> key_bits[0];
measure key_src[1] -> key_bits[1];

// Encrypt: conditionally apply X and Z based on key
// (In real QKD, Alice applies these gates based on her classical key)
// Here we demonstrate the gate structure:
// if key_bits[0] == 1: apply X (bit flip)
// if key_bits[1] == 1: apply Z (phase flip)

// ── Decoy State Protocol (concept) ───────────────────────────────────
// In practical QKD, Alice randomly varies photon intensity to detect
// photon-number-splitting attacks. Decoy states have different mean
// photon numbers but the same encoding.

qreg decoy[2];
creg decoy_result[2];

// Signal state: standard encoding
x decoy[0];              // encode bit 1

// Decoy state: same encoding, different intensity (represented
// by a separate qubit — in hardware this is optical attenuation)
x decoy[1];

measure decoy -> decoy_result;

// ── No-Cloning Theorem (demonstration) ────────────────────────────────
// You CANNOT copy an unknown quantum state. CNOT only "clones" |0⟩
// and |1⟩, NOT superpositions. This is why quantum key distribution
// is secure — Eve cannot copy qubits without disturbing them.

qreg original[1];
qreg copy_target[1];
creg clone_test[2];

// Prepare superposition state |+⟩
h original[0];

// Attempt to "clone" via CNOT — this creates entanglement, NOT a copy
cx original[0], copy_target[0];
// Result is (|00⟩ + |11⟩)/√2 (Bell state), NOT |+⟩|+⟩

measure original[0] -> clone_test[0];
measure copy_target[0] -> clone_test[1];
// Measurements are correlated but NOT independent copies of |+⟩
