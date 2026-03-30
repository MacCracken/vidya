#define _GNU_SOURCE
// Vidya — Quantum Computing in C
//
// C quantum simulation: complex numbers from <complex.h>, state
// vectors as arrays, gate application via direct pointer arithmetic.
// This is how high-performance simulators work at the lowest level.

#include <assert.h>
#include <complex.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

typedef double complex cx;

static const double H_VAL = M_SQRT1_2; // 1/√2

// ── State vector operations ───────────────────────────────────────────
static void state_init(cx *state, int n_qubits) {
    int size = 1 << n_qubits;
    memset(state, 0, sizeof(cx) * (size_t)size);
    state[0] = 1.0;
}

static double prob(const cx *state, int index) {
    return creal(state[index]) * creal(state[index])
         + cimag(state[index]) * cimag(state[index]);
}

static void assert_near(double a, double b, const char *msg) {
    assert(fabs(a - b) < 1e-10);
    (void)msg;
}

// ── Single-qubit gate application ─────────────────────────────────────
static void apply_gate(cx *state, int target, int n_qubits, cx gate[2][2]) {
    int size = 1 << n_qubits;
    int mask = 1 << target;
    for (int i = 0; i < size; i++) {
        if (i & mask) continue;
        int j = i | mask;
        cx a = state[i], b = state[j];
        state[i] = gate[0][0] * a + gate[0][1] * b;
        state[j] = gate[1][0] * a + gate[1][1] * b;
    }
}

static void hadamard(cx *state, int target, int n_qubits) {
    cx gate[2][2] = {{H_VAL, H_VAL}, {H_VAL, -H_VAL}};
    apply_gate(state, target, n_qubits, gate);
}

static void pauli_x(cx *state, int target, int n_qubits) {
    cx gate[2][2] = {{0, 1}, {1, 0}};
    apply_gate(state, target, n_qubits, gate);
}

static void pauli_z(cx *state, int target, int n_qubits) {
    cx gate[2][2] = {{1, 0}, {0, -1}};
    apply_gate(state, target, n_qubits, gate);
}

static void phase_gate(cx *state, int target, int n_qubits, double theta) {
    cx gate[2][2] = {{1, 0}, {0, cos(theta) + I * sin(theta)}};
    apply_gate(state, target, n_qubits, gate);
}

// ── Two-qubit gates ───────────────────────────────────────────────────
static void cnot(cx *state, int control, int target, int n_qubits) {
    int size = 1 << n_qubits;
    int cmask = 1 << control;
    int tmask = 1 << target;
    for (int i = 0; i < size; i++) {
        if ((i & cmask) && !(i & tmask)) {
            int j = i | tmask;
            cx tmp = state[i];
            state[i] = state[j];
            state[j] = tmp;
        }
    }
}

static void cz_gate(cx *state, int q0, int q1, int n_qubits) {
    int size = 1 << n_qubits;
    int m0 = 1 << q0, m1 = 1 << q1;
    for (int i = 0; i < size; i++) {
        if ((i & m0) && (i & m1)) {
            state[i] = -state[i];
        }
    }
}

// ── Tests ─────────────────────────────────────────────────────────────
static void test_qubit_basics(void) {
    cx state[2];
    state_init(state, 1);
    assert_near(prob(state, 0), 1.0, "|0⟩");
    assert_near(prob(state, 1), 0.0, "|1⟩");

    state_init(state, 1);
    pauli_x(state, 0, 1);
    assert_near(prob(state, 1), 1.0, "X|0⟩");
}

static void test_hadamard(void) {
    cx state[2];
    state_init(state, 1);
    hadamard(state, 0, 1);
    assert_near(prob(state, 0), 0.5, "H|0⟩");
    assert_near(prob(state, 1), 0.5, "H|0⟩");

    hadamard(state, 0, 1);
    assert_near(prob(state, 0), 1.0, "HH=I");
}

static void test_cnot(void) {
    cx state[4];
    state_init(state, 2);
    pauli_x(state, 1, 2);
    cnot(state, 1, 0, 2);
    assert_near(prob(state, 0x3), 1.0, "CNOT|10⟩=|11⟩");
}

static void test_bell_state(void) {
    cx state[4];
    state_init(state, 2);
    hadamard(state, 0, 2);
    cnot(state, 0, 1, 2);
    assert_near(prob(state, 0), 0.5, "Bell |00⟩");
    assert_near(prob(state, 3), 0.5, "Bell |11⟩");
    assert_near(prob(state, 1), 0.0, "Bell |01⟩");
}

static void test_grover(void) {
    cx state[4];
    state_init(state, 2);
    hadamard(state, 0, 2);
    hadamard(state, 1, 2);
    cz_gate(state, 0, 1, 2);
    hadamard(state, 0, 2);
    hadamard(state, 1, 2);
    for (int i = 1; i < 4; i++) state[i] = -state[i];
    hadamard(state, 0, 2);
    hadamard(state, 1, 2);
    assert_near(prob(state, 0x3), 1.0, "Grover |11⟩");
}

static void test_phase(void) {
    cx plus[2], minus[2];
    state_init(plus, 1);
    hadamard(plus, 0, 1);
    state_init(minus, 1);
    hadamard(minus, 0, 1);
    pauli_z(minus, 0, 1);

    assert_near(prob(plus, 0), prob(minus, 0), "same probs");
    assert_near(creal(plus[1]), H_VAL, "|+⟩");
    assert_near(creal(minus[1]), -H_VAL, "|−⟩");

    cx state[2];
    state_init(state, 1);
    pauli_x(state, 0, 1);
    phase_gate(state, 0, 1, M_PI / 4.0);
    assert_near(prob(state, 1), 1.0, "phase preserves prob");
}

static void test_ghz(void) {
    cx state[8];
    state_init(state, 3);
    hadamard(state, 0, 3);
    cnot(state, 0, 1, 3);
    cnot(state, 0, 2, 3);
    assert_near(prob(state, 0), 0.5, "GHZ |000⟩");
    assert_near(prob(state, 7), 0.5, "GHZ |111⟩");

    double total = 0;
    for (int i = 0; i < 8; i++) total += prob(state, i);
    assert_near(total, 1.0, "normalization");
}

static void test_noise(void) {
    double p = 0.1;
    double noisy_p0 = 1.0 - 2 * p / 3;
    assert_near(noisy_p0 + 2 * p / 3, 1.0, "depolarize");

    double gamma = 0.05;
    assert_near(gamma + (1 - gamma), 1.0, "damping");

    double fidelity = pow(1 - 0.001, 100);
    assert(fabs(fidelity - 0.9048) < 0.001);
}

int main(void) {
    test_qubit_basics();
    test_hadamard();
    test_cnot();
    test_bell_state();
    test_grover();
    test_phase();
    test_ghz();
    test_noise();

    printf("All quantum computing examples passed.\n");
    return 0;
}
