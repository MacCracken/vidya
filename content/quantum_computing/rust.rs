// Vidya — Quantum Computing in Rust
//
// Quantum simulation in Rust: state vectors as arrays of complex
// amplitudes, gates as matrix operations, measurement as probability
// sampling. This is how simulators like `qsim` work under the hood.
// Real quantum computers execute these operations in hardware.

use std::f64::consts::{FRAC_1_SQRT_2, PI};

fn main() {
    test_qubit_basics();
    test_hadamard_gate();
    test_cnot_gate();
    test_bell_state();
    test_grover_2qubit();
    test_quantum_phase();
    test_measurement_probability();
    test_noise_channel();

    println!("All quantum computing examples passed.");
}

// ── Complex number (minimal, no deps) ─────────────────────────────────
#[derive(Clone, Copy, Debug)]
struct Complex {
    re: f64,
    im: f64,
}

impl Complex {
    fn new(re: f64, im: f64) -> Self {
        Self { re, im }
    }
    fn zero() -> Self {
        Self { re: 0.0, im: 0.0 }
    }
    fn norm_sq(self) -> f64 {
        self.re * self.re + self.im * self.im
    }
    fn add(self, other: Self) -> Self {
        Self::new(self.re + other.re, self.im + other.im)
    }
    fn sub(self, other: Self) -> Self {
        Self::new(self.re - other.re, self.im - other.im)
    }
    fn mul(self, other: Self) -> Self {
        Self::new(
            self.re * other.re - self.im * other.im,
            self.re * other.im + self.im * other.re,
        )
    }
    fn scale(self, s: f64) -> Self {
        Self::new(self.re * s, self.im * s)
    }
}

// ── State vector (2^n amplitudes) ─────────────────────────────────────
type StateVec = Vec<Complex>;

fn new_state(n_qubits: usize) -> StateVec {
    let size = 1 << n_qubits;
    let mut state = vec![Complex::zero(); size];
    state[0] = Complex::new(1.0, 0.0); // |00...0⟩
    state
}

fn probability(state: &[Complex], index: usize) -> f64 {
    state[index].norm_sq()
}

fn assert_near(a: f64, b: f64, msg: &str) {
    assert!(
        (a - b).abs() < 1e-10,
        "{msg}: {a} != {b}"
    );
}

// ── Single-qubit gates ────────────────────────────────────────────────
// Apply gate matrix [[a,b],[c,d]] to qubit `target` in an n-qubit state
fn apply_single_gate(
    state: &mut StateVec,
    target: usize,
    n_qubits: usize,
    gate: [[Complex; 2]; 2],
) {
    let size = 1 << n_qubits;
    let mask = 1 << target;
    for i in 0..size {
        if i & mask != 0 {
            continue; // process pairs once
        }
        let j = i | mask;
        let a = state[i];
        let b = state[j];
        state[i] = gate[0][0].mul(a).add(gate[0][1].mul(b));
        state[j] = gate[1][0].mul(a).add(gate[1][1].mul(b));
    }
}

fn hadamard(state: &mut StateVec, target: usize, n_qubits: usize) {
    let h = FRAC_1_SQRT_2;
    let gate = [
        [Complex::new(h, 0.0), Complex::new(h, 0.0)],
        [Complex::new(h, 0.0), Complex::new(-h, 0.0)],
    ];
    apply_single_gate(state, target, n_qubits, gate);
}

fn pauli_x(state: &mut StateVec, target: usize, n_qubits: usize) {
    let gate = [
        [Complex::zero(), Complex::new(1.0, 0.0)],
        [Complex::new(1.0, 0.0), Complex::zero()],
    ];
    apply_single_gate(state, target, n_qubits, gate);
}

fn pauli_z(state: &mut StateVec, target: usize, n_qubits: usize) {
    let gate = [
        [Complex::new(1.0, 0.0), Complex::zero()],
        [Complex::zero(), Complex::new(-1.0, 0.0)],
    ];
    apply_single_gate(state, target, n_qubits, gate);
}

fn phase_gate(state: &mut StateVec, target: usize, n_qubits: usize, theta: f64) {
    let gate = [
        [Complex::new(1.0, 0.0), Complex::zero()],
        [Complex::zero(), Complex::new(theta.cos(), theta.sin())],
    ];
    apply_single_gate(state, target, n_qubits, gate);
}

// ── Two-qubit CNOT gate ───────────────────────────────────────────────
fn cnot(state: &mut StateVec, control: usize, target: usize, n_qubits: usize) {
    let size = 1 << n_qubits;
    let cmask = 1 << control;
    let tmask = 1 << target;
    for i in 0..size {
        // Only swap when control=1 and target=0
        if (i & cmask != 0) && (i & tmask == 0) {
            let j = i | tmask;
            state.swap(i, j);
        }
    }
}

// ── Controlled-Z gate ─────────────────────────────────────────────────
fn cz(state: &mut StateVec, q0: usize, q1: usize, n_qubits: usize) {
    let size = 1 << n_qubits;
    let m0 = 1 << q0;
    let m1 = 1 << q1;
    for i in 0..size {
        if (i & m0 != 0) && (i & m1 != 0) {
            state[i] = state[i].scale(-1.0);
        }
    }
}

// ── Tests ─────────────────────────────────────────────────────────────
fn test_qubit_basics() {
    // |0⟩ state
    let state = new_state(1);
    assert_near(probability(&state, 0), 1.0, "|0⟩ prob");
    assert_near(probability(&state, 1), 0.0, "|1⟩ prob");

    // |1⟩ state via X gate
    let mut state = new_state(1);
    pauli_x(&mut state, 0, 1);
    assert_near(probability(&state, 0), 0.0, "X|0⟩ → |1⟩");
    assert_near(probability(&state, 1), 1.0, "X|0⟩ → |1⟩");
}

fn test_hadamard_gate() {
    // H|0⟩ = |+⟩ = (|0⟩ + |1⟩)/√2
    let mut state = new_state(1);
    hadamard(&mut state, 0, 1);
    assert_near(probability(&state, 0), 0.5, "H|0⟩ prob(0)");
    assert_near(probability(&state, 1), 0.5, "H|0⟩ prob(1)");

    // HH|0⟩ = |0⟩ (H is its own inverse)
    hadamard(&mut state, 0, 1);
    assert_near(probability(&state, 0), 1.0, "HH = I");
    assert_near(probability(&state, 1), 0.0, "HH = I");
}

fn test_cnot_gate() {
    // CNOT|10⟩ = |11⟩ (control=1, flip target)
    let mut state = new_state(2);
    pauli_x(&mut state, 1, 2); // |10⟩ (qubit 1 = 1)
    cnot(&mut state, 1, 0, 2); // CNOT: control=1, target=0
    assert_near(probability(&state, 0b11), 1.0, "CNOT|10⟩ = |11⟩");

    // CNOT|00⟩ = |00⟩ (control=0, no flip)
    let mut state = new_state(2);
    cnot(&mut state, 1, 0, 2);
    assert_near(probability(&state, 0b00), 1.0, "CNOT|00⟩ = |00⟩");
}

fn test_bell_state() {
    // Bell state |Φ+⟩ = (|00⟩ + |11⟩)/√2
    let mut state = new_state(2);
    hadamard(&mut state, 0, 2);
    cnot(&mut state, 0, 1, 2);

    assert_near(probability(&state, 0b00), 0.5, "Bell |00⟩");
    assert_near(probability(&state, 0b01), 0.0, "Bell |01⟩");
    assert_near(probability(&state, 0b10), 0.0, "Bell |10⟩");
    assert_near(probability(&state, 0b11), 0.5, "Bell |11⟩");
}

fn test_grover_2qubit() {
    // Grover's search on 2 qubits (N=4), searching for |11⟩
    // Optimal iterations = floor(π/4 × √4) = 1
    let mut state = new_state(2);

    // Step 1: Uniform superposition
    hadamard(&mut state, 0, 2);
    hadamard(&mut state, 1, 2);

    // Step 2: Oracle — phase-flip |11⟩
    cz(&mut state, 0, 1, 2);

    // Step 3: Diffusion operator
    hadamard(&mut state, 0, 2);
    hadamard(&mut state, 1, 2);
    // Conditional phase flip on |00⟩: negate all except |00⟩
    for i in 1..4 {
        state[i] = state[i].scale(-1.0);
    }
    hadamard(&mut state, 0, 2);
    hadamard(&mut state, 1, 2);

    // |11⟩ should have probability 1.0 after 1 iteration
    assert_near(probability(&state, 0b11), 1.0, "Grover found |11⟩");
}

fn test_quantum_phase() {
    // Z gate on |+⟩ gives |−⟩: same probabilities, different phase
    let mut state_plus = new_state(1);
    hadamard(&mut state_plus, 0, 1);

    let mut state_minus = new_state(1);
    hadamard(&mut state_minus, 0, 1);
    pauli_z(&mut state_minus, 0, 1);

    // Same measurement probabilities
    assert_near(
        probability(&state_plus, 0),
        probability(&state_minus, 0),
        "Z doesn't change Z-basis probs",
    );

    // But different amplitudes (phase matters for interference)
    assert_near(state_plus[1].re, FRAC_1_SQRT_2, "|+⟩[1]");
    assert_near(state_minus[1].re, -FRAC_1_SQRT_2, "|−⟩[1]");

    // Phase gate: Rz(π/4) on |1⟩
    let mut state = new_state(1);
    pauli_x(&mut state, 0, 1);
    phase_gate(&mut state, 0, 1, PI / 4.0);
    assert_near(probability(&state, 1), 1.0, "phase doesn't change prob");
    assert_near(state[1].re, (PI / 4.0).cos(), "phase re");
    assert_near(state[1].im, (PI / 4.0).sin(), "phase im");
}

fn test_measurement_probability() {
    // 3-qubit GHZ state: (|000⟩ + |111⟩)/√2
    let mut state = new_state(3);
    hadamard(&mut state, 0, 3);
    cnot(&mut state, 0, 1, 3);
    cnot(&mut state, 0, 2, 3);

    // Only |000⟩ and |111⟩ have nonzero probability
    assert_near(probability(&state, 0b000), 0.5, "GHZ |000⟩");
    assert_near(probability(&state, 0b111), 0.5, "GHZ |111⟩");
    for i in 1..7 {
        if i != 0b111 {
            assert_near(probability(&state, i), 0.0, &format!("GHZ |{i:03b}⟩"));
        }
    }

    // Total probability = 1 (normalization)
    let total: f64 = state.iter().map(|c| c.norm_sq()).sum();
    assert_near(total, 1.0, "normalization");
}

fn test_noise_channel() {
    // Depolarizing noise: with probability p, replace state with
    // maximally mixed state (I/2). Models random errors on a qubit.
    //
    // ρ → (1-p)ρ + (p/3)(XρX + YρY + ZρZ)
    // For a pure |0⟩ state, prob(0) goes from 1.0 to 1-2p/3

    let p = 0.1; // 10% depolarizing error
    // After depolarizing noise on |0⟩:
    // prob(0) = 1 - 2p/3
    let noisy_prob_0 = 1.0 - 2.0 * p / 3.0;
    let noisy_prob_1 = 2.0 * p / 3.0;
    assert_near(noisy_prob_0, 1.0 - 2.0 / 30.0, "depolarize |0⟩");
    assert_near(noisy_prob_0 + noisy_prob_1, 1.0, "noise preserves norm");

    // Amplitude damping: |1⟩ decays to |0⟩ with probability γ (energy loss)
    // Models T1 relaxation in superconducting qubits
    let gamma = 0.05; // 5% decay probability
    // |1⟩ after amplitude damping: prob(0) = γ, prob(1) = 1-γ
    let damped_prob_0 = gamma;
    let damped_prob_1 = 1.0 - gamma;
    assert_near(damped_prob_0 + damped_prob_1, 1.0, "damping preserves norm");
    assert!(damped_prob_1 > damped_prob_0, "mostly stays |1⟩");

    // Dephasing: |+⟩ loses coherence, approaches (|0⟩⟨0| + |1⟩⟨1|)/2
    // Models T2 relaxation. Off-diagonal elements of density matrix decay.
    // For |+⟩ = (|0⟩+|1⟩)/√2, the off-diagonal term is 1/2.
    // After dephasing: off-diag → (1-λ)/2
    let lambda = 0.2;
    let rho_01_before = Complex::new(0.5, 0.0); // off-diagonal of |+⟩⟨+|
    let rho_01_after = rho_01_before.scale(1.0 - lambda);
    let coherence_loss = rho_01_before.sub(rho_01_after);
    assert!(coherence_loss.re > 0.0, "coherence decreased");
    assert_near(rho_01_after.re, 0.4, "dephased off-diagonal");
}
