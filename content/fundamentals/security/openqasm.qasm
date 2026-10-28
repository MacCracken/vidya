// Vidya — Security Practices in OpenQASM (Quantum Security)
//
// Quantum security: BB84 key distribution uses conjugate bases to
// detect eavesdropping. Quantum random number generation provides
// true randomness from measurement. The no-cloning theorem is the
// fundamental security primitive — quantum states can't be copied.

OPENQASM 3.1;
include "stdgates.inc";

// ── BB84 Quantum Key Distribution ─────────────────────────────────────
// Alice encodes bits in two conjugate bases:
//   Standard basis (Z): |0⟩ = 0, |1⟩ = 1
//   Hadamard basis (X): |+⟩ = 0, |−⟩ = 1
// Eve's interception disturbs the state — detectable via error rate.

// Alice prepares 4 key bits in mixed bases (Z, X, X, Z)
qubit[4] alice;
bit[4] bob_result;

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
bob_result = measure alice;
// Here Bob measures every qubit in the Z basis: bits 0 and 3 (Z-encoded)
// come out as Alice sent them, 1 and 0; bits 1 and 2 (X-encoded) are
// random and would be discarded at the basis comparison.
// @expect bob_result in {1, 3, 5, 7}

// ── Quantum Random Number Generation ──────────────────────────────────
// Hadamard + measurement = true 50/50 random bit from quantum mechanics.
// Unlike PRNGs, this randomness is provably unpredictable (Born rule) —
// on quantum hardware. Under a simulator, as when this file is checked,
// the "measurement" is a seeded classical PRNG and the byte is exactly
// reproducible: a QRNG's security comes from the device, not the code.

qubit[8] rng;
bit[8] random_byte;

// Each qubit: H puts it in equal superposition, measurement collapses
h rng[0];
h rng[1];
h rng[2];
h rng[3];
h rng[4];
h rng[5];
h rng[6];
h rng[7];

random_byte = measure rng;
// random_byte is a true random 8-bit value

// ── Entanglement Verification (Bell Test) ─────────────────────────────
// Verify that a shared EPR pair hasn't been tampered with.
// If entanglement is intact, measurements are perfectly correlated
// in the same basis. An eavesdropper breaks this correlation — but
// only in SOME basis: one who measures in Z and resends leaves the Z
// results below perfectly correlated (her disturbance shows up as 50%
// disagreement in the X basis). A real check compares several bases,
// as BB84 does, or runs a full CHSH Bell test; this section shows the
// single-basis step.

qubit[1] epr_a;
qubit[1] epr_b;
bit[1] verify_a;
bit[1] verify_b;

// Create Bell pair |Φ+⟩ = (|00⟩ + |11⟩)/√2
h epr_a[0];
cx epr_a[0], epr_b[0];

// Both measure in Z basis — results MUST agree
// Disagreement indicates eavesdropping or channel noise
verify_a[0] = measure epr_a[0];
verify_b[0] = measure epr_b[0];
// Each is 0 or 1 at random; with the pair intact they always agree.
// @expect verify_a in {0, 1}
// @expect verify_b in {0, 1}

// ── Quantum One-Time Pad ──────────────────────────────────────────────
// Encrypt a qubit using two classical key bits.
// key = (k1, k2): apply X^k1 Z^k2 to the message qubit.
// Provably secure: without the key, the encrypted state is maximally
// mixed (no information leaks).

qubit[1] msg;
qubit[2] key_src;
bit[2] key_bits;
bit[1] decrypted;

// Prepare message: |1⟩
x msg[0];

// Generate quantum random key bits
h key_src[0];
h key_src[1];
key_bits[0] = measure key_src[0];
key_bits[1] = measure key_src[1];
// @expect key_bits in {0, 1, 2, 3}

// Encrypt: conditionally apply X and Z based on key. OpenQASM 3's `if`
// tests one measured bit, so the key drives the gates directly.
if (key_bits[0]) x msg[0];    // key bit 0 = 1: bit flip
if (key_bits[1]) z msg[0];    // key bit 1 = 1: phase flip

// (Without the key, msg is now maximally mixed: measuring it here would
// read 0 or 1 at random whatever the message was.)

// Decrypt: apply the same Paulis in reverse order (each is its own
// inverse), recovering the message.
if (key_bits[1]) z msg[0];
if (key_bits[0]) x msg[0];
decrypted[0] = measure msg[0];
// decrypted = 1 on every shot: the message |1⟩, whatever the key was
// @expect decrypted == 1

// ── Decoy State Protocol (concept) ───────────────────────────────────
// In practical QKD, Alice randomly varies photon intensity to detect
// photon-number-splitting attacks. Decoy states have different mean
// photon numbers but the same encoding.

qubit[2] decoy;
bit[2] decoy_result;

// Signal state: standard encoding
x decoy[0];              // encode bit 1

// Decoy state: same encoding, different intensity (represented
// by a separate qubit — in hardware this is optical attenuation)
x decoy[1];

decoy_result = measure decoy;
// Both carry bit 1: decoy_result = 11
// @expect decoy_result == 3

// ── No-Cloning Theorem (demonstration) ────────────────────────────────
// You CANNOT copy an unknown quantum state. CNOT only "clones" |0⟩
// and |1⟩, NOT superpositions. This is why quantum key distribution
// is secure — Eve cannot copy qubits without disturbing them.

qubit[1] original;
qubit[1] copy_target;
bit[2] clone_test;

// Prepare superposition state |+⟩
h original[0];

// Attempt to "clone" via CNOT — this creates entanglement, NOT a copy
cx original[0], copy_target[0];
// Result is (|00⟩ + |11⟩)/√2 (Bell state), NOT |+⟩|+⟩

clone_test[0] = measure original[0];
clone_test[1] = measure copy_target[0];
// Measurements are correlated but NOT independent copies of |+⟩: two
// real copies would read all four outcomes; this reads only 00 or 11.
// @expect clone_test in {0, 3}
