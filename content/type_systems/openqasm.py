# Vidya — Type Systems in OpenQASM (Quantum Types & Registers)
#
# Quantum computing has its own type system: qubits vs classical bits,
# quantum vs classical registers, unitary gates vs measurements.
# Qiskit enforces these at the circuit construction level — you can't
# apply a gate to a classical bit or measure a classical bit.

from qiskit import QuantumCircuit, QuantumRegister, ClassicalRegister
from qiskit_aer import AerSimulator

sim = AerSimulator()

def run(qc, shots=1024):
    qc_m = qc.copy()
    qc_m.measure_all()
    return sim.run(qc_m, shots=shots).result().get_counts()


def main():
    # ── Qubit type: quantum register ────────────────────────────────
    # Qubits exist in superposition — fundamentally different from bits
    qr = QuantumRegister(3, name="q")
    assert len(qr) == 3
    assert qr.name == "q"

    # ── Classical bit type: classical register ──────────────────────
    # Classical bits hold measurement results — normal 0/1 values
    cr = ClassicalRegister(3, name="c")
    assert len(cr) == 3
    assert cr.name == "c"

    # ── Circuit with typed registers ────────────────────────────────
    qc = QuantumCircuit(qr, cr)
    assert qc.num_qubits == 3
    assert qc.num_clbits == 3

    # ── Named registers: semantic typing ────────────────────────────
    # Like newtypes — give meaning to qubit groups
    data = QuantumRegister(2, name="data")
    ancilla = QuantumRegister(1, name="ancilla")
    output = ClassicalRegister(2, name="output")

    qc = QuantumCircuit(data, ancilla, output)
    assert qc.num_qubits == 3  # 2 data + 1 ancilla

    # Access by register name — clearer than raw indices
    qc.h(data[0])
    qc.cx(data[0], data[1])
    qc.measure(data, output)

    result = sim.run(qc, shots=100).result().get_counts()
    # Bell state on data qubits, ancilla untouched
    for key in result:
        bits = key.replace(" ", "")
        assert bits in ("00", "11"), f"Bell state: {result}"

    # ── Gate types: single-qubit, two-qubit, multi-qubit ────────────
    qc = QuantumCircuit(3)

    # Single-qubit gates: H, X, Y, Z, S, T, Rx, Ry, Rz
    qc.h(0)     # Hadamard
    qc.x(1)     # Pauli-X (NOT)
    qc.z(2)     # Pauli-Z (phase flip)

    # Two-qubit gates: CX (CNOT), CZ, SWAP, CP
    qc.cx(0, 1)    # controlled-X
    qc.cz(1, 2)    # controlled-Z
    qc.swap(0, 2)  # swap qubit states

    # Three-qubit gate: Toffoli (CCX)
    qc.ccx(0, 1, 2)  # controlled-controlled-X

    ops = qc.count_ops()
    assert "h" in ops
    assert "cx" in ops
    assert "ccx" in ops

    # ── Parameterized gates: continuous types ───────────────────────
    import math
    qc = QuantumCircuit(1)
    qc.rx(math.pi, 0)      # rotation around X axis
    qc.ry(math.pi / 2, 0)  # rotation around Y axis
    qc.rz(math.pi / 4, 0)  # rotation around Z axis

    # Parameters are floats (angles in radians)
    # This is the "type" of rotation gates: float → gate

    # ── Measurement: quantum → classical type conversion ────────────
    # Measurement is the only way to convert quantum to classical
    qc = QuantumCircuit(2, 2)
    qc.h(0)
    qc.cx(0, 1)
    qc.measure([0, 1], [0, 1])  # quantum bits → classical bits

    result = sim.run(qc, shots=100).result().get_counts()
    assert all(k in ("00", "11") for k in result), "measurement collapses"

    # ── Barrier: type-level circuit separator ───────────────────────
    # Barriers prevent gate reordering across sections
    qc = QuantumCircuit(2)
    qc.h(0)
    qc.barrier()    # logical separator — no gates cross this
    qc.cx(0, 1)
    assert qc.depth() >= 2, "barrier enforces ordering"

    # ── Circuit as a type: composable units ─────────────────────────
    # Circuits are first-class — compose, repeat, invert

    # Create a reusable "module"
    bell = QuantumCircuit(2, name="bell_pair")
    bell.h(0)
    bell.cx(0, 1)

    # Compose into larger circuit
    full = QuantumCircuit(4)
    full.compose(bell, qubits=[0, 1], inplace=True)
    full.compose(bell, qubits=[2, 3], inplace=True)

    counts = run(full)
    # Two independent Bell pairs
    for key in counts:
        first_pair = key[2:]   # last two qubits (Qiskit ordering)
        second_pair = key[:2]  # first two qubits
        assert first_pair in ("00", "11"), f"pair 1: {first_pair}"
        assert second_pair in ("00", "11"), f"pair 2: {second_pair}"

    # ── Inverse: type-level reversibility ───────────────────────────
    # Every unitary gate has an inverse — quantum computation is reversible
    qc = QuantumCircuit(2)
    qc.h(0)
    qc.cx(0, 1)

    # Invert the circuit
    inv = qc.inverse()
    # Apply then invert = identity
    full = qc.compose(inv)
    counts = run(full)
    assert counts.get("00", 0) == 1024, f"circuit + inverse = identity: {counts}"

    print("All type system examples passed.")


if __name__ == "__main__":
    main()
