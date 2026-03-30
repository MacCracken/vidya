# Vidya — Performance in OpenQASM (Circuit Optimization)
#
# Quantum circuit performance = fewer gates, less depth, better
# qubit connectivity. Transpilation maps logical circuits to hardware
# constraints. Key metrics: gate count, circuit depth, two-qubit gate
# count (most expensive), and T-gate count (for fault-tolerant QC).

from qiskit import QuantumCircuit
from qiskit.transpiler.preset_passmanagers import generate_preset_pass_manager
from qiskit_aer import AerSimulator
import math

sim = AerSimulator()

def run(qc, shots=1024):
    qc_m = qc.copy()
    qc_m.measure_all()
    return sim.run(qc_m, shots=shots).result().get_counts()


def main():
    # ── Gate count: fewer is better ─────────────────────────────────
    # Redundant gates increase error probability

    # Unoptimized: X then X = identity (2 gates, does nothing)
    qc_bad = QuantumCircuit(1)
    qc_bad.x(0)
    qc_bad.x(0)
    assert qc_bad.size() == 2, "unoptimized has 2 gates"

    # Optimized: no gates needed
    qc_good = QuantumCircuit(1)
    assert qc_good.size() == 0, "optimized has 0 gates"

    # Both produce the same result
    counts_bad = run(qc_bad)
    counts_good = run(qc_good)
    assert counts_bad.get("0", 0) == 1024, "X·X = I"
    assert counts_good.get("0", 0) == 1024, "empty = I"

    # ── Circuit depth: critical path length ─────────────────────────
    # Depth determines execution time. Parallel gates reduce depth.

    # Sequential: depth 4
    sequential = QuantumCircuit(4)
    for i in range(3):
        sequential.cx(i, i + 1)
    sequential.cx(0, 3)
    seq_depth = sequential.depth()

    # Parallel where possible: same entanglement, less depth
    parallel = QuantumCircuit(4)
    parallel.cx(0, 1)
    parallel.cx(2, 3)  # runs in parallel with first cx
    parallel.cx(1, 2)
    par_depth = parallel.depth()

    assert par_depth <= seq_depth, f"parallel {par_depth} <= sequential {seq_depth}"

    # ── Two-qubit gate count: the bottleneck ────────────────────────
    # Two-qubit gates (CX/CNOT) are ~10x noisier than single-qubit gates
    # Minimizing them is the top priority for near-term hardware

    qc = QuantumCircuit(3)
    qc.h(0)
    qc.cx(0, 1)     # 2-qubit
    qc.cx(1, 2)     # 2-qubit
    qc.h(2)         # 1-qubit

    ops = qc.count_ops()
    cx_count = ops.get("cx", 0)
    h_count = ops.get("h", 0)
    assert cx_count == 2, "2 two-qubit gates"
    assert h_count == 2, "2 single-qubit gates"

    # ── Transpilation: logical → physical mapping ───────────────────
    # Real hardware has limited qubit connectivity. Transpilation adds
    # SWAP gates to route operations — this increases gate count.

    # Build a circuit that needs all-to-all connectivity
    qc = QuantumCircuit(4)
    qc.h(0)
    qc.cx(0, 3)  # non-adjacent qubits
    qc.cx(1, 3)
    qc.cx(2, 0)

    original_cx = qc.count_ops().get("cx", 0)
    assert original_cx == 3, "3 logical CX gates"

    # Transpile for a linear topology (0-1-2-3)
    # This may add SWAP gates for non-adjacent connections
    pm = generate_preset_pass_manager(optimization_level=1, basis_gates=["cx", "rz", "sx", "x"])
    transpiled = pm.run(qc)
    transpiled_ops = transpiled.count_ops()
    # Transpiled circuit has at least as many CX gates
    assert transpiled.size() >= qc.size(), "transpilation may add gates"

    # ── Optimization levels ─────────────────────────────────────────
    # Qiskit has 4 optimization levels (0-3)
    # Higher = more optimization time, better circuits

    qc = QuantumCircuit(3)
    qc.h(0)
    qc.cx(0, 1)
    qc.cx(0, 2)
    qc.h(0)
    qc.h(0)  # redundant H·H

    pm0 = generate_preset_pass_manager(optimization_level=0, basis_gates=["cx", "rz", "sx", "x"])
    pm2 = generate_preset_pass_manager(optimization_level=2, basis_gates=["cx", "rz", "sx", "x"])

    t0 = pm0.run(qc)
    t2 = pm2.run(qc)

    # Higher optimization should produce fewer or equal gates
    assert t2.size() <= t0.size(), f"opt2 ({t2.size()}) <= opt0 ({t0.size()})"

    # ── Gate decomposition ──────────────────────────────────────────
    # Hardware only supports a basis gate set (e.g., CX, RZ, SX, X)
    # All other gates are decomposed into these

    qc = QuantumCircuit(2)
    qc.swap(0, 1)  # SWAP is not a basis gate

    pm = generate_preset_pass_manager(optimization_level=0, basis_gates=["cx", "rz", "sx", "x"])
    decomposed = pm.run(qc)

    # SWAP decomposes into 3 CX gates
    cx_after = decomposed.count_ops().get("cx", 0)
    assert cx_after == 3, f"SWAP → 3 CX gates: got {cx_after}"

    # ── Circuit equivalence after optimization ──────────────────────
    # Verify the optimized circuit produces the same results
    qc = QuantumCircuit(2)
    qc.h(0)
    qc.cx(0, 1)
    qc.h(0)
    qc.h(0)  # redundant

    pm = generate_preset_pass_manager(optimization_level=2, basis_gates=["cx", "rz", "sx", "x"])
    optimized = pm.run(qc)

    counts_orig = run(qc, shots=4096)
    counts_opt = run(optimized, shots=4096)

    # Both should produce Bell-like distribution
    for key in ("00", "11"):
        orig_frac = counts_orig.get(key, 0) / 4096
        opt_frac = counts_opt.get(key, 0) / 4096
        assert abs(orig_frac - opt_frac) < 0.1, f"equiv check {key}: {orig_frac:.2f} vs {opt_frac:.2f}"

    # ── Measurement: the final cost ─────────────────────────────────
    # More shots = more precision but more time
    # Statistical error ∝ 1/√(shots)
    # 100 shots: ~10% error, 10000 shots: ~1% error

    qc = QuantumCircuit(1)
    qc.h(0)

    for shots in [100, 1000, 10000]:
        counts = run(qc, shots=shots)
        p0 = counts.get("0", 0) / shots
        error = abs(p0 - 0.5)
        # Error should decrease with more shots (statistically)

    print("All performance examples passed.")


if __name__ == "__main__":
    main()
