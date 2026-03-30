# Vidya — Concurrency in OpenQASM (Quantum Parallelism)
#
# Quantum computers exploit parallelism fundamentally differently:
# superposition processes all basis states simultaneously, entanglement
# creates correlations without communication, and quantum gates on
# different qubits execute in parallel naturally.

from qiskit import QuantumCircuit
from qiskit_aer import AerSimulator
import math

sim = AerSimulator()

def run(qc, shots=1024):
    qc_m = qc.copy()
    qc_m.measure_all()
    return sim.run(qc_m, shots=shots).result().get_counts()


def main():
    # ── Superposition: implicit parallelism ─────────────────────────
    # One qubit in superposition represents two states simultaneously
    # n qubits in superposition represent 2^n states
    n = 3
    qc = QuantumCircuit(n)
    for i in range(n):
        qc.h(i)

    counts = run(qc, shots=8192)
    # All 2^3 = 8 states should appear
    assert len(counts) == 8, f"expected 8 outcomes, got {len(counts)}"
    # Each with roughly equal probability
    for outcome, count in counts.items():
        assert abs(count - 1024) < 250, f"{outcome}: {count} not ~1024"

    # ── Independent qubit operations: true parallelism ──────────────
    # Gates on different qubits execute simultaneously (depth 1)
    qc = QuantumCircuit(4)
    qc.h(0)    # these four gates
    qc.x(1)    # all execute
    qc.z(2)    # in parallel
    qc.h(3)    # (depth = 1)
    assert qc.depth() == 1, "independent gates run in parallel"

    # ── Entanglement: correlated without communication ──────────────
    # EPR pair: two qubits share a quantum correlation
    # Measuring one instantly determines the other — no classical equivalent
    qc = QuantumCircuit(2)
    qc.h(0)
    qc.cx(0, 1)

    counts = run(qc, shots=1000)
    # Always correlated: 00 or 11, never 01 or 10
    assert "01" not in counts and "10" not in counts, "entangled correlation"
    assert "00" in counts and "11" in counts, "both correlated outcomes"

    # ── GHZ state: n-qubit entanglement ─────────────────────────────
    # All qubits correlated: either all |0⟩ or all |1⟩
    n = 5
    qc = QuantumCircuit(n)
    qc.h(0)
    for i in range(n - 1):
        qc.cx(i, i + 1)

    counts = run(qc, shots=1000)
    zeros = "0" * n
    ones = "1" * n
    total = counts.get(zeros, 0) + counts.get(ones, 0)
    assert total > 950, f"GHZ: {total}/1000 in |{zeros}⟩ or |{ones}⟩"

    # ── Quantum teleportation: entanglement as a resource ─────────────
    # Teleportation uses entanglement to transfer quantum state.
    # Full protocol requires classical conditional operations (c_if).
    # Here we demonstrate the entanglement + Bell measurement part.
    qc = QuantumCircuit(3)

    # Prepare state to teleport (on qubit 0)
    qc.rx(math.pi / 3, 0)

    # Create Bell pair between qubits 1 (Alice) and 2 (Bob)
    qc.h(1)
    qc.cx(1, 2)

    # Alice's Bell measurement
    qc.cx(0, 1)
    qc.h(0)

    # Measure Alice's qubits — result tells Bob which correction to apply
    counts = run(qc, shots=100)
    # All 4 outcomes possible (00, 01, 10, 11) — each maps to a correction
    assert len(counts) >= 2, f"teleportation produces multiple outcomes: {counts}"

    # ── Quantum walk: parallel exploration ──────────────────────────
    # A quantum walk explores multiple paths simultaneously
    # Simplified: 3-position walk on a line
    qc = QuantumCircuit(3)  # 1 coin + 2 position qubits
    qc.h(0)         # coin flip
    qc.cx(0, 1)     # conditional move right
    qc.x(0)
    qc.cx(0, 2)     # conditional move left
    qc.x(0)

    counts = run(qc)
    assert len(counts) >= 2, "quantum walk explores multiple positions"

    # ── No-cloning theorem: fundamental constraint ──────────────────
    # You CANNOT copy an unknown quantum state — no fan-out
    # This is a concurrency constraint: no broadcast
    # CNOT is NOT cloning — it entangles, not copies

    qc = QuantumCircuit(2)
    qc.h(0)          # unknown state (superposition)
    qc.cx(0, 1)      # this entangles, NOT copies
    counts = run(qc)
    # If it were a copy, we'd see all 4 outcomes
    # Instead, we only see 00 and 11 (entangled)
    assert "01" not in counts and "10" not in counts, "CNOT entangles, not clones"

    # ── Circuit depth = parallel execution time ─────────────────────
    # Depth is the critical path length — like makespan in scheduling
    qc = QuantumCircuit(4)
    # Layer 1: all parallel
    qc.h(0); qc.h(1); qc.h(2); qc.h(3)
    # Layer 2: two parallel CNOTs
    qc.cx(0, 1); qc.cx(2, 3)
    # Layer 3: one CNOT
    qc.cx(1, 2)

    assert qc.depth() == 3, f"3 parallel layers: depth={qc.depth()}"

    print("All concurrency examples passed.")


if __name__ == "__main__":
    main()
