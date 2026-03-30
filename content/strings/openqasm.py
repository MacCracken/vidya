# Vidya — Strings in OpenQASM (Quantum Data Encoding)
#
# Quantum computers don't have "strings" — they have qubits in
# superposition. But encoding classical data into quantum states is
# fundamental. Basis encoding maps bit strings to computational basis
# states: "01" → |01⟩. This is how classical information enters and
# exits quantum circuits.

from qiskit import QuantumCircuit
from qiskit_aer import AerSimulator

sim = AerSimulator()

def run(qc, shots=1024):
    qc_m = qc.copy()
    qc_m.measure_all()
    return sim.run(qc_m, shots=shots).result().get_counts()


def main():
    # ── Basis encoding: classical bits → qubit states ───────────────
    # Encode "101" into 3 qubits
    # |0⟩ → |1⟩ via X gate (NOT), leave |0⟩ as-is
    qc = QuantumCircuit(3)
    qc.x(0)  # qubit 0 → |1⟩
    # qubit 1 stays |0⟩
    qc.x(2)  # qubit 2 → |1⟩

    counts = run(qc)
    # Qiskit bit ordering is reversed: qubit 0 is rightmost
    assert "101" in counts, f"expected '101' in {counts}"
    assert counts["101"] == 1024, "deterministic encoding"

    # ── Superposition: one qubit encodes two values simultaneously ──
    qc = QuantumCircuit(1)
    qc.h(0)  # Hadamard: |0⟩ → (|0⟩ + |1⟩)/√2

    counts = run(qc)
    assert "0" in counts and "1" in counts, "superposition has both outcomes"
    # Each outcome ~50% (statistical, not exact)
    assert abs(counts.get("0", 0) - 512) < 150, "roughly 50/50"

    # ── Multi-qubit strings: encoding "hello" in binary ─────────────
    # ASCII 'h' = 0b01101000 — encode the low 4 bits: 1000
    qc = QuantumCircuit(4)
    qc.x(3)  # bit 3 = 1 → encodes 0b1000 = 8

    counts = run(qc)
    assert "1000" in counts, f"expected '1000' in {counts}"

    # ── Quantum string comparison: equality check via CNOT ──────────
    # Compare two 2-bit "strings" by XORing into ancilla qubits
    # If strings are equal, ancillas remain |00⟩
    qc = QuantumCircuit(6, 2)  # 2 string qubits + 2 string qubits + 2 check
    # String A = "10" (qubits 0,1)
    qc.x(0)
    # String B = "10" (qubits 2,3)
    qc.x(2)
    # XOR bit 0: A[0] ⊕ B[0] → ancilla[4]
    qc.cx(0, 4)
    qc.cx(2, 4)
    # XOR bit 1: A[1] ⊕ B[1] → ancilla[5]
    qc.cx(1, 5)
    qc.cx(3, 5)
    # Measure ancillas — 00 means strings are equal
    qc.measure([4, 5], [0, 1])

    result = sim.run(qc, shots=100).result().get_counts()
    assert "00" in result and result["00"] == 100, f"strings should be equal: {result}"

    # ── Phase encoding: data in rotation angles ─────────────────────
    # Encode a value as a rotation angle (amplitude encoding)
    import math
    qc = QuantumCircuit(1)
    angle = math.pi / 6  # small angle
    qc.ry(angle, 0)      # RY rotation encodes in amplitude

    counts = run(qc)
    # P(|1⟩) = sin²(θ/2) ≈ 0.067
    total = sum(counts.values())
    prob_1 = counts.get("1", 0) / total
    assert prob_1 < 0.2, f"phase encoding: P(1)={prob_1:.3f}"

    # ── Measurement: reading quantum "strings" back ─────────────────
    # Measurement collapses superposition to a definite bit string
    qc = QuantumCircuit(3)
    qc.x(0)
    qc.x(2)
    # Without measurement, the state is |101⟩
    # Measurement projects to classical bits
    counts = run(qc, shots=1)
    assert len(counts) == 1, "deterministic state gives one outcome"

    print("All string examples passed.")


if __name__ == "__main__":
    main()
