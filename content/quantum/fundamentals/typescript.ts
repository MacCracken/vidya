// Vidya — Quantum Computing in TypeScript
//
// TypeScript quantum simulation: complex numbers as [re, im] tuples,
// state vectors as arrays, gate operations as matrix multiplication.
// TypeScript's type system helps document qubit indices and state sizes.

type Complex = [number, number]; // [real, imaginary]

function main(): void {
    testQubitBasics();
    testHadamardGate();
    testCnotGate();
    testBellState();
    testGrover2Qubit();
    testQuantumPhase();
    testGHZState();
    testNoiseChannels();

    console.log("All quantum computing examples passed.");
}

// ── Complex arithmetic ────────────────────────────────────────────────
const cxMul = (a: Complex, b: Complex): Complex =>
    [a[0] * b[0] - a[1] * b[1], a[0] * b[1] + a[1] * b[0]];
const cxAdd = (a: Complex, b: Complex): Complex =>
    [a[0] + b[0], a[1] + b[1]];
const cxScale = (a: Complex, s: number): Complex =>
    [a[0] * s, a[1] * s];
const cxNormSq = (a: Complex): number =>
    a[0] * a[0] + a[1] * a[1];

const H_VAL = 1 / Math.sqrt(2);

// ── State vector ──────────────────────────────────────────────────────
function newState(nQubits: number): Complex[] {
    const size = 1 << nQubits;
    const state: Complex[] = Array.from({ length: size }, (): Complex => [0, 0]);
    state[0] = [1, 0];
    return state;
}

function prob(state: Complex[], index: number): number {
    return cxNormSq(state[index]);
}

function assertNear(a: number, b: number, msg: string, tol = 1e-10): void {
    if (Math.abs(a - b) > tol) throw new Error(`FAIL ${msg}: ${a} != ${b}`);
}

// ── Gate application ──────────────────────────────────────────────────
type Gate2x2 = [[Complex, Complex], [Complex, Complex]];

function applyGate(state: Complex[], target: number, nQubits: number, gate: Gate2x2): void {
    const size = 1 << nQubits;
    const mask = 1 << target;
    for (let i = 0; i < size; i++) {
        if (i & mask) continue;
        const j = i | mask;
        const a = state[i], b = state[j];
        state[i] = cxAdd(cxMul(gate[0][0], a), cxMul(gate[0][1], b));
        state[j] = cxAdd(cxMul(gate[1][0], a), cxMul(gate[1][1], b));
    }
}

const H_GATE: Gate2x2 = [[[H_VAL, 0], [H_VAL, 0]], [[H_VAL, 0], [-H_VAL, 0]]];
const X_GATE: Gate2x2 = [[[0, 0], [1, 0]], [[1, 0], [0, 0]]];
const Z_GATE: Gate2x2 = [[[1, 0], [0, 0]], [[0, 0], [-1, 0]]];

function hadamard(state: Complex[], target: number, nQubits: number): void {
    applyGate(state, target, nQubits, H_GATE);
}
function pauliX(state: Complex[], target: number, nQubits: number): void {
    applyGate(state, target, nQubits, X_GATE);
}
function pauliZ(state: Complex[], target: number, nQubits: number): void {
    applyGate(state, target, nQubits, Z_GATE);
}
function phaseShift(state: Complex[], target: number, nQubits: number, theta: number): void {
    const gate: Gate2x2 = [[[1, 0], [0, 0]], [[0, 0], [Math.cos(theta), Math.sin(theta)]]];
    applyGate(state, target, nQubits, gate);
}

function cnot(state: Complex[], control: number, target: number, nQubits: number): void {
    const size = 1 << nQubits;
    const cmask = 1 << control, tmask = 1 << target;
    for (let i = 0; i < size; i++) {
        if ((i & cmask) && !(i & tmask)) {
            const j = i | tmask;
            [state[i], state[j]] = [state[j], state[i]];
        }
    }
}

function cz(state: Complex[], q0: number, q1: number, nQubits: number): void {
    const size = 1 << nQubits;
    const m0 = 1 << q0, m1 = 1 << q1;
    for (let i = 0; i < size; i++) {
        if ((i & m0) && (i & m1)) state[i] = cxScale(state[i], -1);
    }
}

// ── Tests ─────────────────────────────────────────────────────────────
function testQubitBasics(): void {
    let state = newState(1);
    assertNear(prob(state, 0), 1.0, "|0⟩");
    assertNear(prob(state, 1), 0.0, "|1⟩");

    state = newState(1);
    pauliX(state, 0, 1);
    assertNear(prob(state, 1), 1.0, "X|0⟩");
}

function testHadamardGate(): void {
    const state = newState(1);
    hadamard(state, 0, 1);
    assertNear(prob(state, 0), 0.5, "H|0⟩");
    assertNear(prob(state, 1), 0.5, "H|0⟩");
    hadamard(state, 0, 1);
    assertNear(prob(state, 0), 1.0, "HH=I");
}

function testCnotGate(): void {
    const state = newState(2);
    pauliX(state, 1, 2);
    cnot(state, 1, 0, 2);
    assertNear(prob(state, 0b11), 1.0, "CNOT|10⟩=|11⟩");
}

function testBellState(): void {
    const state = newState(2);
    hadamard(state, 0, 2);
    cnot(state, 0, 1, 2);
    assertNear(prob(state, 0b00), 0.5, "Bell |00⟩");
    assertNear(prob(state, 0b11), 0.5, "Bell |11⟩");
    assertNear(prob(state, 0b01), 0.0, "Bell |01⟩");
}

function testGrover2Qubit(): void {
    const state = newState(2);
    hadamard(state, 0, 2);
    hadamard(state, 1, 2);
    cz(state, 0, 1, 2);
    hadamard(state, 0, 2);
    hadamard(state, 1, 2);
    for (let i = 1; i < 4; i++) state[i] = cxScale(state[i], -1);
    hadamard(state, 0, 2);
    hadamard(state, 1, 2);
    assertNear(prob(state, 0b11), 1.0, "Grover |11⟩");
}

function testQuantumPhase(): void {
    const plus = newState(1);
    hadamard(plus, 0, 1);
    const minus = newState(1);
    hadamard(minus, 0, 1);
    pauliZ(minus, 0, 1);

    assertNear(prob(plus, 0), prob(minus, 0), "same probs");
    assertNear(plus[1][0], H_VAL, "|+⟩");
    assertNear(minus[1][0], -H_VAL, "|−⟩");

    const state = newState(1);
    pauliX(state, 0, 1);
    phaseShift(state, 0, 1, Math.PI / 4);
    assertNear(prob(state, 1), 1.0, "phase preserves prob");
    // The probability alone cannot see the phase; check the amplitude e^{iπ/4}
    assertNear(state[1][0], Math.cos(Math.PI / 4), "phase: real part");
    assertNear(state[1][1], Math.sin(Math.PI / 4), "phase: imaginary part");
}

function testGHZState(): void {
    const state = newState(3);
    hadamard(state, 0, 3);
    cnot(state, 0, 1, 3);
    cnot(state, 0, 2, 3);
    assertNear(prob(state, 0b000), 0.5, "GHZ |000⟩");
    assertNear(prob(state, 0b111), 0.5, "GHZ |111⟩");
    const total = state.reduce((sum, a) => sum + cxNormSq(a), 0);
    assertNear(total, 1.0, "normalization");
}

// ── Noise channels ────────────────────────────────────────────────────
// Noise turns a pure state into a statistical mixture, which a state
// vector cannot hold: apply it to the density matrix ρ = |ψ⟩⟨ψ| as
// ρ → Σ_k K_k ρ K_k†, with Kraus operators satisfying Σ_k K_k† K_k = I.
type Mat2 = Gate2x2;
const I2: Mat2 = [[[1, 0], [0, 0]], [[0, 0], [1, 0]]];
const Y_GATE: Mat2 = [[[0, 0], [0, -1]], [[0, 1], [0, 0]]];

function matMul(a: Mat2, b: Mat2): Mat2 {
    const e = (r: number, c: number): Complex =>
        cxAdd(cxMul(a[r][0], b[0][c]), cxMul(a[r][1], b[1][c]));
    return [[e(0, 0), e(0, 1)], [e(1, 0), e(1, 1)]];
}
function dagger(a: Mat2): Mat2 {
    const c = (z: Complex): Complex => [z[0], -z[1]];
    return [[c(a[0][0]), c(a[1][0])], [c(a[0][1]), c(a[1][1])]];
}
function scaleMat(a: Mat2, s: number): Mat2 {
    return [[cxScale(a[0][0], s), cxScale(a[0][1], s)], [cxScale(a[1][0], s), cxScale(a[1][1], s)]];
}
function densityOf(psi: Complex[]): Mat2 { // ρ_ij = ψ_i · conj(ψ_j)
    const e = (i: number, j: number): Complex => cxMul(psi[i], [psi[j][0], -psi[j][1]]);
    return [[e(0, 0), e(0, 1)], [e(1, 0), e(1, 1)]];
}
function applyChannel(rho: Mat2, kraus: Mat2[]): Mat2 {
    let out: Mat2 = [[[0, 0], [0, 0]], [[0, 0], [0, 0]]];
    for (const k of kraus) {
        const term = matMul(matMul(k, rho), dagger(k));
        out = [[cxAdd(out[0][0], term[0][0]), cxAdd(out[0][1], term[0][1])],
               [cxAdd(out[1][0], term[1][0]), cxAdd(out[1][1], term[1][1])]];
    }
    return out;
}
const trace = (rho: Mat2): number => rho[0][0][0] + rho[1][1][0];

function testNoiseChannels(): void {
    // Depolarizing: X, Y or Z each with probability p/3. On |0⟩, X and Y
    // flip the bit, so prob(1) = 2p/3.
    const p = 0.1;
    const depol = [scaleMat(I2, Math.sqrt(1 - p)), scaleMat(X_GATE, Math.sqrt(p / 3)),
                   scaleMat(Y_GATE, Math.sqrt(p / 3)), scaleMat(Z_GATE, Math.sqrt(p / 3))];
    const rhoD = applyChannel(densityOf(newState(1)), depol);
    assertNear(rhoD[1][1][0], 2 * p / 3, "depolarize: prob(1) = 2p/3");
    assertNear(trace(rhoD), 1.0, "depolarize preserves trace");

    // Amplitude damping (T1): |1⟩ decays to |0⟩ with probability γ
    const gamma = 0.05;
    const damp: Mat2[] = [[[[1, 0], [0, 0]], [[0, 0], [Math.sqrt(1 - gamma), 0]]],
                          [[[0, 0], [Math.sqrt(gamma), 0]], [[0, 0], [0, 0]]]];
    const one = newState(1);
    pauliX(one, 0, 1);
    const rhoA = applyChannel(densityOf(one), damp);
    assertNear(rhoA[0][0][0], gamma, "damping: prob(0) = γ");
    assertNear(rhoA[1][1][0], 1 - gamma, "damping: prob(1) = 1-γ");

    // Dephasing (T2) as a phase flip with probability λ/2: the populations
    // of |+⟩ stay 1/2, the coherence ρ01 = 1/2 decays to (1-λ)/2
    const lambda = 0.2;
    const dephase = [scaleMat(I2, Math.sqrt(1 - lambda / 2)), scaleMat(Z_GATE, Math.sqrt(lambda / 2))];
    const plus = newState(1);
    hadamard(plus, 0, 1);
    const rhoP = applyChannel(densityOf(plus), dephase);
    assertNear(rhoP[0][1][0], 0.4, "dephasing: coherence 0.5 → 0.4");
    assertNear(rhoP[0][0][0], 0.5, "dephasing keeps populations");

    // Independent gate errors compound: F ≈ (1-p)^n for n gates
    const fidelity = Math.pow(1 - 0.001, 100);
    assertNear(fidelity, 0.9048, "circuit fidelity", 0.001);
}

main();
