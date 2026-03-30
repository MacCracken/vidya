# Vidya — Iterators in OpenQASM (Circuit Composition)
#
# Quantum circuits are built by composing gates sequentially and in
# parallel. "Iteration" in quantum computing means: parameterized
# circuits, gate repetition, circuit layers, and sweeping over
# parameter spaces. Qiskit provides the composition primitives.

from qiskit import QuantumCircuit
from qiskit_aer import AerSimulator
import math

sim = AerSimulator()

def run(qc, shots=1024):
    qc_m = qc.copy()
    qc_m.measure_all()
    return sim.run(qc_m, shots=shots).result().get_counts()


def main():
    # ── Sequential gate composition ─────────────────────────────────
    # Apply gates one after another — the quantum equivalent of a pipeline
    qc = QuantumCircuit(1)
    qc.h(0)     # superposition
    qc.s(0)     # phase gate (π/2 rotation)
    qc.h(0)     # back to computational basis
    # H·S·H = effectively an X rotation

    counts = run(qc)
    assert len(counts) <= 2, "result is a valid quantum state"

    # ── Repeated gate application ───────────────────────────────────
    # Apply H twice: H·H = I (identity)
    qc = QuantumCircuit(1)
    for _ in range(2):
        qc.h(0)
    counts = run(qc)
    assert counts.get("0", 0) == 1024, "H·H = identity, always |0⟩"

    # ── Parameterized rotation sweep ────────────────────────────────
    # Sweep RY angle from 0 to π, measuring probability of |1⟩
    angles = [0, math.pi / 4, math.pi / 2, 3 * math.pi / 4, math.pi]
    probabilities = []

    for angle in angles:
        qc = QuantumCircuit(1)
        qc.ry(angle, 0)
        counts = run(qc, shots=4096)
        prob_1 = counts.get("1", 0) / 4096
        probabilities.append(prob_1)

    # P(|1⟩) = sin²(θ/2): should increase from 0 to 1
    assert probabilities[0] < 0.05, f"angle=0: P(1)={probabilities[0]:.3f}"
    assert probabilities[-1] > 0.95, f"angle=π: P(1)={probabilities[-1]:.3f}"
    assert probabilities[2] > 0.3 and probabilities[2] < 0.7, "angle=π/2: ~50%"

    # ── Circuit composition: append circuits ────────────────────────
    # Build reusable sub-circuits and compose them
    bell_prep = QuantumCircuit(2, name="bell")
    bell_prep.h(0)
    bell_prep.cx(0, 1)

    full = QuantumCircuit(2)
    full.compose(bell_prep, inplace=True)
    counts = run(full)
    assert "00" in counts and "11" in counts, "Bell state"
    assert "01" not in counts and "10" not in counts, "no anti-correlated"

    # ── Iterate over qubits: apply H to all ─────────────────────────
    n = 4
    qc = QuantumCircuit(n)
    for i in range(n):
        qc.h(i)
    # Creates equal superposition of all 2^n states
    counts = run(qc, shots=4096)
    assert len(counts) >= 12, f"should have many outcomes, got {len(counts)}"

    # ── Layer-by-layer circuit construction ──────────────────────────
    # Alternating layers of single-qubit and two-qubit gates
    n = 3
    qc = QuantumCircuit(n)

    # Layer 1: Hadamard on all qubits
    for i in range(n):
        qc.h(i)

    # Layer 2: CNOT chain
    for i in range(n - 1):
        qc.cx(i, i + 1)

    # Layer 3: Rotations
    for i in range(n):
        qc.rz(math.pi / (i + 1), i)

    counts = run(qc)
    assert len(counts) >= 2, "layered circuit produces superposition"

    # ── Map pattern: apply same operation to each qubit ─────────────
    qc = QuantumCircuit(4)
    # "Map" X gate over all qubits
    for i in range(4):
        qc.x(i)
    counts = run(qc)
    assert "1111" in counts, "X mapped to all qubits"

    # ── Fold/reduce: accumulate entanglement ────────────────────────
    # GHZ state: fold CNOT across all qubits
    n = 5
    qc = QuantumCircuit(n)
    qc.h(0)
    for i in range(n - 1):
        qc.cx(i, i + 1)  # "fold" entanglement across the chain

    counts = run(qc)
    # GHZ state: only |00000⟩ and |11111⟩
    assert "0" * n in counts, "GHZ has all-zeros"
    assert "1" * n in counts, "GHZ has all-ones"
    total = sum(counts.values())
    ghz_frac = (counts.get("0" * n, 0) + counts.get("1" * n, 0)) / total
    assert ghz_frac > 0.95, f"GHZ should dominate: {ghz_frac:.3f}"

    # ── Circuit depth as iteration count ────────────────────────────
    qc = QuantumCircuit(1)
    for _ in range(10):
        qc.h(0)
    assert qc.depth() == 10, f"depth should be 10: {qc.depth()}"

    print("All iterator examples passed.")


if __name__ == "__main__":
    main()
