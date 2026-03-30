# Vidya — Memory Management in OpenQASM (Qubit Resources)
#
# Quantum "memory" is qubits — the scarcest resource. Current hardware
# has 50-1000 qubits. Managing qubit allocation, reuse (via reset),
# circuit depth (decoherence budget), and ancilla qubits is the quantum
# equivalent of memory management.

from qiskit import QuantumCircuit
from qiskit_aer import AerSimulator

sim = AerSimulator()

def run(qc, shots=1024):
    qc_m = qc.copy()
    qc_m.measure_all()
    return sim.run(qc_m, shots=shots).result().get_counts()


def main():
    # ── Qubit allocation: declare what you need ─────────────────────
    # Quantum circuits declare qubit count upfront — no dynamic allocation
    qc = QuantumCircuit(3, 2)  # 3 qubits, 2 classical bits
    assert qc.num_qubits == 3
    assert qc.num_clbits == 2

    # ── Qubit reset: reuse instead of allocate ──────────────────────
    # Reset returns a qubit to |0⟩ mid-circuit (like free + malloc)
    qc = QuantumCircuit(1)
    qc.x(0)        # qubit is |1⟩
    qc.reset(0)    # back to |0⟩ — qubit "freed" and reinitialized
    qc.h(0)        # reuse for new computation

    counts = run(qc)
    # After reset+H: should be in superposition
    assert "0" in counts and "1" in counts, "reset then reuse"

    # ── Ancilla qubits: temporary workspace ─────────────────────────
    # Ancillas are "scratch" qubits used for intermediate computation
    # Like stack-allocated temp variables — used and returned to |0⟩

    # Toffoli (CCNOT) with ancilla verification
    qc = QuantumCircuit(4)  # q0, q1 = controls, q2 = target, q3 = ancilla
    qc.x(0)  # control 1 = |1⟩
    qc.x(1)  # control 2 = |1⟩
    qc.ccx(0, 1, 2)  # Toffoli: flip q2 only if both controls are |1⟩

    counts = run(qc)
    # q2 should be |1⟩ (flipped), ancilla q3 stays |0⟩
    assert "0111" in counts, f"Toffoli result: {counts}"

    # ── Circuit depth: the decoherence budget ───────────────────────
    # Every gate takes time. More depth = more decoherence = more errors.
    # Depth is like memory pressure — minimize it.

    # Deep circuit: 20 sequential gates on 1 qubit
    deep = QuantumCircuit(1)
    for _ in range(20):
        deep.h(0)
    assert deep.depth() == 20

    # Shallow equivalent: H·H = I, so 20 H gates = I
    shallow = QuantumCircuit(1)
    # No gates needed — same result!
    assert shallow.depth() == 0, "optimized to zero depth"

    # ── Qubit width vs depth tradeoff ───────────────────────────────
    # More qubits can reduce depth (parallelize), less qubits need more depth
    # Like space-time tradeoff in classical computing

    # Wide: 4 independent operations in parallel (depth 1)
    wide = QuantumCircuit(4)
    wide.h(0)
    wide.h(1)
    wide.h(2)
    wide.h(3)
    assert wide.depth() == 1, "parallel gates: depth 1"

    # Narrow: same operations on 1 qubit sequentially (depth 4)
    narrow = QuantumCircuit(1)
    for _ in range(4):
        narrow.h(0)
    assert narrow.depth() == 4, "sequential gates: depth 4"

    # ── Classical register allocation ───────────────────────────────
    # Classical bits store measurement results
    qc = QuantumCircuit(3, 3)
    qc.h(0)
    qc.cx(0, 1)
    qc.cx(0, 2)
    qc.measure([0, 1, 2], [0, 1, 2])

    result = sim.run(qc, shots=100).result().get_counts()
    assert "000" in result or "111" in result, "GHZ measurement"

    # ── Uncomputation: clean up ancillas ─────────────────────────────
    # To reuse ancillas, reverse the computation to return them to |0⟩
    # Like RAII: the cleanup mirrors the setup

    qc = QuantumCircuit(2)
    # Compute: entangle qubits
    qc.h(0)
    qc.cx(0, 1)
    # Uncompute: reverse to disentangle
    qc.cx(0, 1)
    qc.h(0)
    # Both qubits back to |0⟩

    counts = run(qc)
    assert counts.get("00", 0) == 1024, f"uncomputation restores |00⟩: {counts}"

    # ── Gate count as resource usage ────────────────────────────────
    qc = QuantumCircuit(3)
    qc.h(0)
    qc.cx(0, 1)
    qc.cx(1, 2)
    qc.h(2)

    gate_count = sum(qc.count_ops().values())
    assert gate_count == 4, f"4 gates used: {gate_count}"

    # ── Circuit size metrics ────────────────────────────────────────
    qc = QuantumCircuit(5)
    for i in range(4):
        qc.h(i)
        qc.cx(i, i + 1)

    assert qc.num_qubits == 5, "qubit count"
    assert qc.depth() > 0, "has depth"
    assert qc.size() > 0, "has gates"

    print("All memory management examples passed.")


if __name__ == "__main__":
    main()
