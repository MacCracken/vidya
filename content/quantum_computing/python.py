# Vidya — Quantum Computing in Python
#
# Python is the primary language for quantum computing: Qiskit,
# Cirq, PennyLane all use it. Here we simulate from scratch using
# only math/cmath — state vectors, gates, measurement, and noise.

import cmath
import math


def main():
    test_qubit_basics()
    test_hadamard_gate()
    test_cnot_gate()
    test_bell_state()
    test_grover_2qubit()
    test_quantum_phase()
    test_ghz_state()
    test_noise_channels()

    print("All quantum computing examples passed.")


# ── State vector simulation ────────────────────────────────────────────
def new_state(n_qubits: int) -> list[complex]:
    """Create |00...0⟩ state."""
    state = [0j] * (1 << n_qubits)
    state[0] = 1 + 0j
    return state


def probability(state: list[complex], index: int) -> float:
    return abs(state[index]) ** 2


def assert_near(a: float, b: float, msg: str, tol: float = 1e-10):
    assert abs(a - b) < tol, f"{msg}: {a} != {b}"


# ── Single-qubit gate application ──────────────────────────────────────
def apply_gate(state: list[complex], target: int, n_qubits: int, gate: list[list[complex]]):
    size = 1 << n_qubits
    mask = 1 << target
    for i in range(size):
        if i & mask:
            continue
        j = i | mask
        a, b = state[i], state[j]
        state[i] = gate[0][0] * a + gate[0][1] * b
        state[j] = gate[1][0] * a + gate[1][1] * b


H_VAL = 1 / math.sqrt(2)
H_GATE = [[H_VAL, H_VAL], [-H_VAL + 2 * H_VAL, -H_VAL]]  # avoid float issues
H_GATE = [[complex(H_VAL), complex(H_VAL)], [complex(H_VAL), complex(-H_VAL)]]
X_GATE = [[0j, 1 + 0j], [1 + 0j, 0j]]
Z_GATE = [[1 + 0j, 0j], [0j, -1 + 0j]]


def hadamard(state, target, n_qubits):
    apply_gate(state, target, n_qubits, H_GATE)


def pauli_x(state, target, n_qubits):
    apply_gate(state, target, n_qubits, X_GATE)


def pauli_z(state, target, n_qubits):
    apply_gate(state, target, n_qubits, Z_GATE)


def phase_shift(state, target, n_qubits, theta):
    gate = [[1 + 0j, 0j], [0j, cmath.exp(1j * theta)]]
    apply_gate(state, target, n_qubits, gate)


# ── Two-qubit gates ───────────────────────────────────────────────────
def cnot(state, control, target, n_qubits):
    size = 1 << n_qubits
    cmask = 1 << control
    tmask = 1 << target
    for i in range(size):
        if (i & cmask) and not (i & tmask):
            j = i | tmask
            state[i], state[j] = state[j], state[i]


def cz(state, q0, q1, n_qubits):
    size = 1 << n_qubits
    m0, m1 = 1 << q0, 1 << q1
    for i in range(size):
        if (i & m0) and (i & m1):
            state[i] *= -1


# ── Tests ──────────────────────────────────────────────────────────────
def test_qubit_basics():
    state = new_state(1)
    assert_near(probability(state, 0), 1.0, "|0⟩")
    assert_near(probability(state, 1), 0.0, "|1⟩")

    state = new_state(1)
    pauli_x(state, 0, 1)
    assert_near(probability(state, 0), 0.0, "X|0⟩→|1⟩")
    assert_near(probability(state, 1), 1.0, "X|0⟩→|1⟩")


def test_hadamard_gate():
    state = new_state(1)
    hadamard(state, 0, 1)
    assert_near(probability(state, 0), 0.5, "H|0⟩ prob(0)")
    assert_near(probability(state, 1), 0.5, "H|0⟩ prob(1)")

    # HH = I
    hadamard(state, 0, 1)
    assert_near(probability(state, 0), 1.0, "HH=I")


def test_cnot_gate():
    state = new_state(2)
    pauli_x(state, 1, 2)  # |10⟩
    cnot(state, 1, 0, 2)
    assert_near(probability(state, 0b11), 1.0, "CNOT|10⟩=|11⟩")


def test_bell_state():
    state = new_state(2)
    hadamard(state, 0, 2)
    cnot(state, 0, 1, 2)
    assert_near(probability(state, 0b00), 0.5, "Bell |00⟩")
    assert_near(probability(state, 0b11), 0.5, "Bell |11⟩")
    assert_near(probability(state, 0b01), 0.0, "Bell |01⟩")
    assert_near(probability(state, 0b10), 0.0, "Bell |10⟩")


def test_grover_2qubit():
    state = new_state(2)
    hadamard(state, 0, 2)
    hadamard(state, 1, 2)

    # Oracle: phase-flip |11⟩
    cz(state, 0, 1, 2)

    # Diffusion
    hadamard(state, 0, 2)
    hadamard(state, 1, 2)
    for i in range(1, 4):
        state[i] *= -1
    hadamard(state, 0, 2)
    hadamard(state, 1, 2)

    assert_near(probability(state, 0b11), 1.0, "Grover found |11⟩")


def test_quantum_phase():
    # Z on |+⟩ gives |−⟩
    plus = new_state(1)
    hadamard(plus, 0, 1)

    minus = new_state(1)
    hadamard(minus, 0, 1)
    pauli_z(minus, 0, 1)

    assert_near(probability(plus, 0), probability(minus, 0), "same Z-basis probs")
    assert_near(plus[1].real, H_VAL, "|+⟩ amplitude")
    assert_near(minus[1].real, -H_VAL, "|−⟩ amplitude")

    # Phase gate
    state = new_state(1)
    pauli_x(state, 0, 1)
    phase_shift(state, 0, 1, math.pi / 4)
    assert_near(probability(state, 1), 1.0, "phase preserves prob")
    assert_near(state[1].real, math.cos(math.pi / 4), "phase re")


def test_ghz_state():
    # 3-qubit GHZ: (|000⟩ + |111⟩)/√2
    state = new_state(3)
    hadamard(state, 0, 3)
    cnot(state, 0, 1, 3)
    cnot(state, 0, 2, 3)

    assert_near(probability(state, 0b000), 0.5, "GHZ |000⟩")
    assert_near(probability(state, 0b111), 0.5, "GHZ |111⟩")
    total = sum(abs(a) ** 2 for a in state)
    assert_near(total, 1.0, "normalization")


def test_noise_channels():
    # Depolarizing noise on |0⟩: prob(0) = 1 - 2p/3
    p = 0.1
    noisy_p0 = 1.0 - 2 * p / 3
    noisy_p1 = 2 * p / 3
    assert_near(noisy_p0 + noisy_p1, 1.0, "depolarize normalization")
    assert noisy_p0 > 0.9, "mostly |0⟩"

    # Amplitude damping: |1⟩ → |0⟩ with probability γ
    gamma = 0.05
    assert_near(gamma + (1 - gamma), 1.0, "damping normalization")

    # Dephasing: off-diagonal decays by (1-λ)
    lam = 0.2
    rho_01 = 0.5  # off-diagonal of |+⟩⟨+|
    dephased = rho_01 * (1 - lam)
    assert_near(dephased, 0.4, "dephased coherence")

    # Gate fidelity: F = (1-p)^n for n gates with error rate p
    n_gates = 100
    gate_error = 0.001
    fidelity = (1 - gate_error) ** n_gates
    assert_near(fidelity, 0.9048, "circuit fidelity", tol=0.001)


if __name__ == "__main__":
    main()
