# Vidya — Error Handling in OpenQASM (Quantum Error Correction)
#
# Quantum computers are noisy — qubits decohere and gates have errors.
# Quantum error correction (QEC) detects and corrects errors without
# measuring (and destroying) the quantum state. The simplest codes:
# 3-qubit bit-flip code and phase-flip code.

from qiskit import QuantumCircuit
from qiskit_aer import AerSimulator
from qiskit_aer.noise import NoiseModel, depolarizing_error

sim = AerSimulator()

def run(qc, shots=1024, noise_model=None):
    qc_m = qc.copy()
    qc_m.measure_all()
    return sim.run(qc_m, shots=shots, noise_model=noise_model).result().get_counts()


def main():
    # ── The problem: a single bit-flip error ────────────────────────
    # Without error correction, a single X error flips |0⟩ to |1⟩
    qc = QuantumCircuit(1)
    # Intended state: |0⟩
    qc.x(0)  # simulated error: bit flip!
    counts = run(qc)
    assert "1" in counts, "error flipped the qubit"

    # ── 3-qubit bit-flip code: detection ────────────────────────────
    # Encode 1 logical qubit into 3 physical qubits: |0⟩ → |000⟩
    # A single bit-flip on any qubit can be detected and corrected.

    # Encode |0⟩ → |000⟩
    qc = QuantumCircuit(5, 1)  # 3 data + 2 syndrome qubits
    # Data qubits: 0, 1, 2 (all start as |0⟩)
    qc.cx(0, 1)  # copy qubit 0 to qubit 1
    qc.cx(0, 2)  # copy qubit 0 to qubit 2
    # State is now |000⟩

    # Introduce error: flip qubit 1
    qc.x(1)  # error! state is now |010⟩

    # Syndrome measurement (detect which qubit flipped)
    # Syndrome qubit 3: parity of qubits 0,1
    qc.cx(0, 3)
    qc.cx(1, 3)
    # Syndrome qubit 4: parity of qubits 1,2
    qc.cx(1, 4)
    qc.cx(2, 4)

    # Measure syndromes
    qc_check = qc.copy()
    qc_check.measure_all()
    result = sim.run(qc_check, shots=100).result().get_counts()
    # Syndrome 11 indicates qubit 1 flipped (both parities differ)
    # Bit ordering: q4 q3 q2 q1 q0
    # We expect data=010, syndrome=11 → "11010"
    assert any("11" in k[:2] for k in result), f"syndrome should detect error: {result}"

    # Correction: if syndrome is 11, flip qubit 1 back
    qc.x(1)  # correct the error
    counts_corrected = run(qc)
    # After correction, data qubits (0,1,2) should all be 0
    dominant = max(counts_corrected, key=counts_corrected.get)
    # The last 3 bits (data qubits) should be 000
    assert dominant.replace(" ", "")[-3:] == "000", f"correction should restore |000⟩: {dominant}"

    # ── Encode |1⟩ → |111⟩ ──────────────────────────────────────────
    qc = QuantumCircuit(3)
    qc.x(0)      # start with |1⟩
    qc.cx(0, 1)  # |1⟩ → |11⟩
    qc.cx(0, 2)  # |11⟩ → |111⟩
    counts = run(qc)
    assert "111" in counts, f"encoded |1⟩ as |111⟩: {counts}"

    # ── Phase-flip code ─────────────────────────────────────────────
    # Protects against Z errors (phase flips: |1⟩ → -|1⟩)
    # Encode: H on each qubit transforms bit-flip code to phase-flip code
    qc = QuantumCircuit(3)
    qc.cx(0, 1)
    qc.cx(0, 2)
    # Transform to Hadamard basis
    qc.h(0)
    qc.h(1)
    qc.h(2)
    # Now a Z error on any qubit is detectable
    qc.z(1)  # phase flip error on qubit 1
    # Undo Hadamard basis
    qc.h(0)
    qc.h(1)
    qc.h(2)
    # Now it looks like a bit-flip in the computational basis
    # Can detect and correct with same syndrome approach

    counts = run(qc)
    # The error is now visible as a bit flip
    dominant = max(counts, key=counts.get)
    assert dominant != "000", "phase flip should be detectable"

    # ── Noisy simulation: realistic errors ──────────────────────────
    # Create a noise model with 1% depolarizing error per gate
    noise = NoiseModel()
    noise.add_all_qubit_quantum_error(depolarizing_error(0.01, 1), ['x', 'h'])
    noise.add_all_qubit_quantum_error(depolarizing_error(0.01, 2), ['cx'])

    # Without error correction: single qubit
    qc_noisy = QuantumCircuit(1)
    qc_noisy.x(0)  # prepare |1⟩
    counts = run(qc_noisy, shots=10000, noise_model=noise)
    # Should be mostly "1" but with some "0" errors
    error_rate = counts.get("0", 0) / 10000
    assert error_rate < 0.05, f"error rate {error_rate:.3f} too high"
    assert error_rate > 0, "noise should cause some errors"

    # ── Verification: state fidelity ────────────────────────────────
    # Run the same circuit without noise to verify expected behavior
    qc_clean = QuantumCircuit(1)
    qc_clean.x(0)
    counts_clean = run(qc_clean, shots=100)
    assert counts_clean.get("1", 0) == 100, "clean circuit is deterministic"

    print("All error handling examples passed.")


if __name__ == "__main__":
    main()
