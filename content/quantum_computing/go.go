// Vidya — Quantum Computing in Go
//
// Go has built-in complex types (complex64, complex128) with ordinary
// arithmetic operators, plus math/cmplx — exactly what we need. State
// vectors are []complex128, gates are matrix operations, and measurement
// is |amplitude|^2. Noise needs a density matrix (a mixed state has no
// single state vector), so the noise channels apply Kraus operators to a
// 2x2 one.

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

// ── Noise: Kraus channels on a one-qubit density matrix ──────────────
type mat2 = [2][2]complex128

func mul2(a, b mat2) mat2 {
	var c mat2
	for i := 0; i < 2; i++ {
		for j := 0; j < 2; j++ {
			c[i][j] = a[i][0]*b[0][j] + a[i][1]*b[1][j]
		}
	}
	return c
}

func dagger(a mat2) mat2 {
	return mat2{{cmplx.Conj(a[0][0]), cmplx.Conj(a[1][0])}, {cmplx.Conj(a[0][1]), cmplx.Conj(a[1][1])}}
}

// applyChannel returns Σ K ρ K† for the channel's Kraus operators.
func applyChannel(rho mat2, kraus []mat2) mat2 {
	var out mat2
	for _, k := range kraus {
		t := mul2(mul2(k, rho), dagger(k))
		for i := range out {
			for j := range out[i] {
				out[i][j] += t[i][j]
			}
		}
	}
	return out
}

func scale(a mat2, f float64) mat2 {
	c := complex(f, 0)
	return mat2{{c * a[0][0], c * a[0][1]}, {c * a[1][0], c * a[1][1]}}
}

func testNoiseChannels() {
	I := mat2{{1, 0}, {0, 1}}
	X := mat2{{0, 1}, {1, 0}}
	Y := mat2{{0, -1i}, {1i, 0}}
	Z := mat2{{1, 0}, {0, -1}}
	zero := mat2{{1, 0}, {0, 0}}         // |0⟩⟨0|
	one := mat2{{0, 0}, {0, 1}}          // |1⟩⟨1|
	plus := mat2{{0.5, 0.5}, {0.5, 0.5}} // |+⟩⟨+|
	trace := func(r mat2) float64 { return real(r[0][0] + r[1][1]) }

	// Depolarizing: with prob p apply X, Y or Z (p/3 each).
	p := 0.1
	dep := []mat2{scale(I, math.Sqrt(1-p)), scale(X, math.Sqrt(p/3)), scale(Y, math.Sqrt(p/3)), scale(Z, math.Sqrt(p/3))}
	r := applyChannel(zero, dep)
	assertNear(real(r[0][0]), 1-2*p/3, "depolarized |0⟩ keeps P(0) = 1 - 2p/3")
	assertNear(trace(r), 1.0, "depolarize preserves trace")

	// Amplitude damping: |1⟩ decays to |0⟩ with probability gamma.
	gamma := 0.05
	damp := []mat2{{{1, 0}, {0, complex(math.Sqrt(1-gamma), 0)}}, {{0, complex(math.Sqrt(gamma), 0)}, {0, 0}}}
	r = applyChannel(one, damp)
	assertNear(real(r[1][1]), 1-gamma, "damped |1⟩: P(1) = 1 - gamma")
	assertNear(real(r[0][0]), gamma, "damped |1⟩: P(0) = gamma")

	// Dephasing: Z with prob lam/2 shrinks coherence by (1 - lam),
	// populations untouched.
	lam := 0.2
	deph := []mat2{scale(I, math.Sqrt(1-lam/2)), scale(Z, math.Sqrt(lam/2))}
	r = applyChannel(plus, deph)
	assertNear(real(r[0][1]), 0.5*(1-lam), "dephased coherence")
	assertNear(real(r[0][0]), 0.5, "dephasing leaves populations alone")

	nGates := 100
	gateErr := 0.001
	fidelity := math.Pow(1-gateErr, float64(nGates))
	if math.Abs(fidelity-0.9048) > 0.001 {
		panic(fmt.Sprintf("fidelity: %f", fidelity))
	}
}
