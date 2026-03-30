# Vidya — Pattern Matching in OpenQASM (Measurement & State Discrimination)
#
# Quantum "pattern matching" is measurement: projecting a quantum state
# onto a basis and reading the outcome. Different measurement bases
# reveal different information. State discrimination determines which
# quantum state was prepared, analogous to matching on a value.

from qiskit import QuantumCircuit
from qiskit_aer import AerSimulator
import math

sim = AerSimulator()

def run(qc, shots=1024):
    qc_m = qc.copy()
    qc_m.measure_all()
    return sim.run(qc_m, shots=shots).result().get_counts()


def main():
    # ── Computational basis measurement (default) ───────────────────
    # Measuring in the Z basis: |0⟩ → "0", |1⟩ → "1"
    qc = QuantumCircuit(1)
    qc.x(0)  # prepare |1⟩
    counts = run(qc)
    assert counts.get("1", 0) == 1024, "deterministic Z measurement"

    # ── Hadamard basis measurement ──────────────────────────────────
    # Apply H before measurement to measure in X basis
    # |+⟩ = H|0⟩ → measures as "0" in X basis
    # |−⟩ = H|1⟩ → measures as "1" in X basis

    qc = QuantumCircuit(1)
    qc.h(0)   # prepare |+⟩
    qc.h(0)   # change to X basis measurement
    counts = run(qc)
    assert counts.get("0", 0) == 1024, "|+⟩ in X basis → always 0"

    qc = QuantumCircuit(1)
    qc.x(0)
    qc.h(0)   # prepare |−⟩
    qc.h(0)   # X basis measurement
    counts = run(qc)
    assert counts.get("1", 0) == 1024, "|−⟩ in X basis → always 1"

    # ── State discrimination: which state was prepared? ─────────────
    # Given |0⟩ or |1⟩, measurement perfectly discriminates them
    for prep in [0, 1]:
        qc = QuantumCircuit(1)
        if prep == 1:
            qc.x(0)
        counts = run(qc, shots=100)
        assert counts.get(str(prep), 0) == 100, f"discriminate |{prep}⟩"

    # ── Matching on Bell states ─────────────────────────────────────
    # Four Bell states form a complete basis for 2 qubits
    # Measurement in Bell basis distinguishes all four

    # |Φ+⟩ = (|00⟩ + |11⟩)/√2
    qc = QuantumCircuit(2)
    qc.h(0)
    qc.cx(0, 1)
    # Bell measurement: reverse the preparation
    qc.cx(0, 1)
    qc.h(0)
    counts = run(qc)
    dominant = max(counts, key=counts.get)
    assert counts.get(dominant, 0) == 1024, f"|Φ+⟩ Bell measurement: {counts}"

    # |Ψ+⟩ = (|01⟩ + |10⟩)/√2
    qc = QuantumCircuit(2)
    qc.x(1)
    qc.h(0)
    qc.cx(0, 1)
    # Bell measurement
    qc.cx(0, 1)
    qc.h(0)
    counts = run(qc)
    # Should produce a single deterministic outcome
    assert len(counts) == 1, f"|Ψ+⟩ Bell measurement should be deterministic: {counts}"

    # ── Measurement as projection ─────────────────────────────────────
    # Measurement projects superposition to a definite outcome
    # Repeated measurement of the same state gives the same result
    qc = QuantumCircuit(1, 1)
    qc.x(0)        # prepare |1⟩
    qc.measure(0, 0)

    result = sim.run(qc, shots=100).result().get_counts()
    assert result.get("1", 0) == 100, f"deterministic measurement: {result}"

    # ── Quantum phase estimation: extracting eigenvalue patterns ────
    # Phase estimation "matches" a unitary's eigenvalue
    # Simplified: detect phase of T gate (π/4)
    qc = QuantumCircuit(2)
    qc.h(0)       # control qubit in superposition
    qc.x(1)       # eigenstate of T gate
    qc.cp(math.pi / 4, 0, 1)  # controlled-T
    qc.h(0)       # extract phase into measurement

    counts = run(qc, shots=4096)
    # Result encodes the phase — should have a dominant outcome
    assert len(counts) <= 2, "phase estimation produces definite pattern"

    # ── Multi-outcome matching: 2-qubit measurement ─────────────────
    # Each measurement outcome is a "case" in the match
    qc = QuantumCircuit(2)
    qc.h(0)
    qc.h(1)
    counts = run(qc, shots=4096)
    # Uniform superposition: all 4 outcomes roughly equal
    for outcome in ["00", "01", "10", "11"]:
        assert outcome in counts, f"missing outcome {outcome}"
        assert abs(counts[outcome] - 1024) < 250, f"{outcome} not ~25%"

    # ── Quantum oracle: matching a hidden pattern ───────────────────
    # Deutsch-Jozsa: determine if a function is constant or balanced
    # with a single query (classical needs 2^(n-1)+1 queries)
    qc = QuantumCircuit(2)
    qc.x(1)       # ancilla
    qc.h(0)
    qc.h(1)
    qc.cx(0, 1)   # balanced oracle: f(x) = x
    qc.h(0)

    counts = run(qc)
    # If balanced: qubit 0 (rightmost bit in Qiskit ordering) measures |1⟩
    q0_is_one = sum(v for k, v in counts.items() if k[-1] == "1")
    assert q0_is_one > 900, f"balanced oracle: q0=1 count={q0_is_one}"

    print("All pattern matching examples passed.")


if __name__ == "__main__":
    main()
