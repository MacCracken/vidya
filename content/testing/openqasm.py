# Vidya — Testing in OpenQASM (Circuit Verification)
#
# Testing quantum circuits is fundamentally different: outcomes are
# probabilistic, so assertions must be statistical. Key techniques:
# statevector simulation (exact), shot-based testing (statistical),
# circuit identity checks, and expectation value verification.

from qiskit import QuantumCircuit
from qiskit_aer import AerSimulator, StatevectorSimulator
import math

shot_sim = AerSimulator()
sv_sim = StatevectorSimulator()

# ── Test framework ──────────────────────────────────────────────────

tests_run = 0
tests_passed = 0

def check(condition, name):
    global tests_run, tests_passed
    tests_run += 1
    if condition:
        tests_passed += 1
    else:
        print(f"  FAIL: {name}")

def check_eq(got, expected, name):
    check(got == expected, f"{name}: got {got}, expected {expected}")

def check_near(got, expected, tol, name):
    check(abs(got - expected) < tol, f"{name}: got {got:.4f}, expected {expected:.4f}")


def run_shots(qc, shots=4096):
    qc_m = qc.copy()
    qc_m.measure_all()
    return shot_sim.run(qc_m, shots=shots).result().get_counts()

def get_statevector(qc):
    return sv_sim.run(qc).result().get_statevector()


def main():
    global tests_run, tests_passed

    # ── Statevector testing: exact verification ─────────────────────
    # Statevector gives exact amplitudes — no statistical noise

    # Test: H|0⟩ = |+⟩ = (|0⟩ + |1⟩)/√2
    qc = QuantumCircuit(1)
    qc.h(0)
    sv = get_statevector(qc)
    probs = sv.probabilities()
    check_near(probs[0], 0.5, 1e-10, "H|0⟩ → P(0)=0.5")
    check_near(probs[1], 0.5, 1e-10, "H|0⟩ → P(1)=0.5")

    # Test: X|0⟩ = |1⟩
    qc = QuantumCircuit(1)
    qc.x(0)
    sv = get_statevector(qc)
    probs = sv.probabilities()
    check_near(probs[0], 0.0, 1e-10, "X|0⟩ → P(0)=0")
    check_near(probs[1], 1.0, 1e-10, "X|0⟩ → P(1)=1")

    # ── Bell state verification ─────────────────────────────────────
    qc = QuantumCircuit(2)
    qc.h(0)
    qc.cx(0, 1)
    sv = get_statevector(qc)
    probs = sv.probabilities()
    check_near(probs[0], 0.5, 1e-10, "Bell P(00)=0.5")  # |00⟩
    check_near(probs[1], 0.0, 1e-10, "Bell P(01)=0")     # |01⟩
    check_near(probs[2], 0.0, 1e-10, "Bell P(10)=0")     # |10⟩
    check_near(probs[3], 0.5, 1e-10, "Bell P(11)=0.5")   # |11⟩

    # ── Shot-based testing: statistical assertions ──────────────────
    # With finite shots, use confidence intervals

    qc = QuantumCircuit(1)
    qc.h(0)
    counts = run_shots(qc, shots=4096)
    p0 = counts.get("0", 0) / 4096
    p1 = counts.get("1", 0) / 4096
    check_near(p0, 0.5, 0.05, "shot test: P(0)≈0.5")
    check_near(p1, 0.5, 0.05, "shot test: P(1)≈0.5")

    # ── Circuit identity testing ────────────────────────────────────
    # Verify that a circuit equals identity: apply then inverse

    qc = QuantumCircuit(2)
    qc.h(0)
    qc.cx(0, 1)
    qc.rz(math.pi / 4, 1)

    # Apply circuit then its inverse
    identity_test = qc.compose(qc.inverse())
    sv = get_statevector(identity_test)
    probs = sv.probabilities()
    check_near(probs[0], 1.0, 1e-10, "circuit·inverse = identity")

    # ── Gate equivalence testing ────────────────────────────────────
    # Verify: HZH = X
    qc1 = QuantumCircuit(1)
    qc1.x(0)

    qc2 = QuantumCircuit(1)
    qc2.h(0)
    qc2.z(0)
    qc2.h(0)

    sv1 = get_statevector(qc1)
    sv2 = get_statevector(qc2)
    # Compare statevectors (up to global phase)
    fidelity = abs(sv1.inner(sv2)) ** 2
    check_near(fidelity, 1.0, 1e-10, "HZH = X (up to phase)")

    # ── Parametric testing: sweep and verify ────────────────────────
    # RY(θ)|0⟩ should give P(|1⟩) = sin²(θ/2)
    for angle_frac in [0, 0.25, 0.5, 0.75, 1.0]:
        angle = angle_frac * math.pi
        qc = QuantumCircuit(1)
        qc.ry(angle, 0)
        sv = get_statevector(qc)
        probs = sv.probabilities()
        expected = math.sin(angle / 2) ** 2
        check_near(probs[1], expected, 1e-10,
                   f"RY({angle_frac:.2f}π): P(1)={expected:.4f}")

    # ── Entanglement verification ───────────────────────────────────
    # A state is entangled if it can't be written as a product state
    # Test via correlation: measure both qubits, check they always agree
    qc = QuantumCircuit(2)
    qc.h(0)
    qc.cx(0, 1)
    counts = run_shots(qc, shots=1000)
    anti_correlated = counts.get("01", 0) + counts.get("10", 0)
    check_eq(anti_correlated, 0, "Bell pair: no anti-correlation")

    # ── Depth/gate count assertions ─────────────────────────────────
    qc = QuantumCircuit(3)
    qc.h(0)
    qc.cx(0, 1)
    qc.cx(1, 2)
    check_eq(qc.depth(), 3, "circuit depth")
    check_eq(qc.size(), 3, "gate count")

    # ── Report ──────────────────────────────────────────────────────
    if tests_passed != tests_run:
        print(f"FAILED: {tests_passed}/{tests_run} passed")
        exit(1)

    print("All testing examples passed.")


if __name__ == "__main__":
    main()
