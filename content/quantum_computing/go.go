// Vidya — Quantum Computing in Go
//
// Go lacks complex number support in the type system beyond complex128,
// but that's exactly what we need. State vectors are []complex128,
// gates are matrix operations, and measurement is |amplitude|^2.

package main

import (
	"fmt"
	"math"
	"math/cmplx"
)

func main() {
	testQubitBasics()
	testHadamardGate()
	testCnotGate()
	testBellState()
	testGrover2Qubit()
	testQuantumPhase()
	testGHZState()
	testNoiseChannels()

	fmt.Println("All quantum computing examples passed.")
}

// ── State vector ──────────────────────────────────────────────────────
func newState(nQubits int) []complex128 {
	size := 1 << nQubits
	state := make([]complex128, size)
	state[0] = 1
	return state
}

func prob(state []complex128, index int) float64 {
	a := state[index]
	return real(a)*real(a) + imag(a)*imag(a)
}

func assertNear(a, b float64, msg string) {
	if math.Abs(a-b) > 1e-10 {
		panic(fmt.Sprintf("FAIL %s: %f != %f", msg, a, b))
	}
}

// ── Gates ─────────────────────────────────────────────────────────────
var hVal = 1.0 / math.Sqrt(2.0)

func applyGate(state []complex128, target, nQubits int, gate [2][2]complex128) {
	size := 1 << nQubits
	mask := 1 << target
	for i := 0; i < size; i++ {
		if i&mask != 0 {
			continue
		}
		j := i | mask
		a, b := state[i], state[j]
		state[i] = gate[0][0]*a + gate[0][1]*b
		state[j] = gate[1][0]*a + gate[1][1]*b
	}
}

func hadamard(state []complex128, target, nQubits int) {
	h := complex(hVal, 0)
	gate := [2][2]complex128{{h, h}, {h, -h}}
	applyGate(state, target, nQubits, gate)
}

func pauliX(state []complex128, target, nQubits int) {
	gate := [2][2]complex128{{0, 1}, {1, 0}}
	applyGate(state, target, nQubits, gate)
}

func pauliZ(state []complex128, target, nQubits int) {
	gate := [2][2]complex128{{1, 0}, {0, -1}}
	applyGate(state, target, nQubits, gate)
}

func phaseGate(state []complex128, target, nQubits int, theta float64) {
	gate := [2][2]complex128{{1, 0}, {0, cmplx.Rect(1, theta)}}
	applyGate(state, target, nQubits, gate)
}

func cnot(state []complex128, control, target, nQubits int) {
	size := 1 << nQubits
	cmask := 1 << control
	tmask := 1 << target
	for i := 0; i < size; i++ {
		if (i&cmask != 0) && (i&tmask == 0) {
			j := i | tmask
			state[i], state[j] = state[j], state[i]
		}
	}
}

func cz(state []complex128, q0, q1, nQubits int) {
	size := 1 << nQubits
	m0, m1 := 1<<q0, 1<<q1
	for i := 0; i < size; i++ {
		if (i&m0 != 0) && (i&m1 != 0) {
			state[i] = -state[i]
		}
	}
}

// ── Tests ─────────────────────────────────────────────────────────────
func testQubitBasics() {
	state := newState(1)
	assertNear(prob(state, 0), 1.0, "|0⟩")
	assertNear(prob(state, 1), 0.0, "|1⟩")

	state = newState(1)
	pauliX(state, 0, 1)
	assertNear(prob(state, 1), 1.0, "X|0⟩→|1⟩")
}

func testHadamardGate() {
	state := newState(1)
	hadamard(state, 0, 1)
	assertNear(prob(state, 0), 0.5, "H|0⟩")
	assertNear(prob(state, 1), 0.5, "H|0⟩")

	hadamard(state, 0, 1)
	assertNear(prob(state, 0), 1.0, "HH=I")
}

func testCnotGate() {
	state := newState(2)
	pauliX(state, 1, 2)
	cnot(state, 1, 0, 2)
	assertNear(prob(state, 0b11), 1.0, "CNOT|10⟩=|11⟩")
}

func testBellState() {
	state := newState(2)
	hadamard(state, 0, 2)
	cnot(state, 0, 1, 2)
	assertNear(prob(state, 0b00), 0.5, "Bell |00⟩")
	assertNear(prob(state, 0b11), 0.5, "Bell |11⟩")
	assertNear(prob(state, 0b01), 0.0, "Bell |01⟩")
}

func testGrover2Qubit() {
	state := newState(2)
	hadamard(state, 0, 2)
	hadamard(state, 1, 2)
	cz(state, 0, 1, 2)
	hadamard(state, 0, 2)
	hadamard(state, 1, 2)
	for i := 1; i < 4; i++ {
		state[i] = -state[i]
	}
	hadamard(state, 0, 2)
	hadamard(state, 1, 2)
	assertNear(prob(state, 0b11), 1.0, "Grover found |11⟩")
}

func testQuantumPhase() {
	plus := newState(1)
	hadamard(plus, 0, 1)
	minus := newState(1)
	hadamard(minus, 0, 1)
	pauliZ(minus, 0, 1)

	assertNear(prob(plus, 0), prob(minus, 0), "same probs")
	assertNear(real(plus[1]), hVal, "|+⟩")
	assertNear(real(minus[1]), -hVal, "|−⟩")

	state := newState(1)
	pauliX(state, 0, 1)
	phaseGate(state, 0, 1, math.Pi/4)
	assertNear(prob(state, 1), 1.0, "phase preserves prob")
}

func testGHZState() {
	state := newState(3)
	hadamard(state, 0, 3)
	cnot(state, 0, 1, 3)
	cnot(state, 0, 2, 3)
	assertNear(prob(state, 0b000), 0.5, "GHZ |000⟩")
	assertNear(prob(state, 0b111), 0.5, "GHZ |111⟩")

	total := 0.0
	for _, a := range state {
		total += real(a)*real(a) + imag(a)*imag(a)
	}
	assertNear(total, 1.0, "normalization")
}

func testNoiseChannels() {
	p := 0.1
	noisyP0 := 1.0 - 2*p/3
	noisyP1 := 2 * p / 3
	assertNear(noisyP0+noisyP1, 1.0, "depolarize norm")

	gamma := 0.05
	assertNear(gamma+(1-gamma), 1.0, "damping norm")

	lam := 0.2
	dephased := 0.5 * (1 - lam)
	assertNear(dephased, 0.4, "dephased coherence")

	nGates := 100
	gateErr := 0.001
	fidelity := math.Pow(1-gateErr, float64(nGates))
	if math.Abs(fidelity-0.9048) > 0.001 {
		panic(fmt.Sprintf("fidelity: %f", fidelity))
	}
}
