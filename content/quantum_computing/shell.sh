#!/usr/bin/env bash
# Vidya — Quantum Computing in Shell (Bash)
#
# Shell can't do complex arithmetic, but it can model quantum
# computing concepts: probability calculations, qubit counting,
# circuit depth analysis, and resource estimation. These are the
# back-of-envelope calculations quantum engineers do daily.

set -euo pipefail

assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
}

# ── State space size: 2^n amplitudes ───────────────────────────────────
state_size() {
    echo $(( 1 << $1 ))
}

assert_eq "$(state_size 1)" "2" "1 qubit"
assert_eq "$(state_size 3)" "8" "3 qubits"
assert_eq "$(state_size 10)" "1024" "10 qubits"
assert_eq "$(state_size 20)" "1048576" "20 qubits"

# ── Grover iterations: floor(π/4 × √(N/M)) ───────────────────────────
grover_iterations() {
    local n_items=$1 n_solutions=${2:-1}
    # floor(π/4 × √(N/M)) — compute at high scale then truncate
    echo "scale=10; x = (3.14159265 / 4) * sqrt($n_items / $n_solutions); scale=0; x / 1" | bc -l
}

assert_eq "$(grover_iterations 4 1)" "1" "grover N=4"
assert_eq "$(grover_iterations 1000000 1)" "785" "grover N=1M"

# ── Classical vs quantum query complexity ──────────────────────────────
classical_search() {
    local n=$1
    echo $(( n / 2 ))  # average case: N/2
}

quantum_search() {
    local n=$1
    # √N using bc
    echo "scale=0; sqrt($n) / 1" | bc -l
}

# Speedup for N=1,000,000
class_q=$(classical_search 1000000)
quant_q=$(quantum_search 1000000)
assert_eq "$class_q" "500000" "classical queries"
assert_eq "$quant_q" "1000" "quantum queries"

# ── Circuit fidelity: (1-p)^n ─────────────────────────────────────────
circuit_fidelity_pct() {
    local n_gates=$1 error_rate_permille=$2
    # error_rate_permille is error rate × 1000 (to avoid decimals)
    # fidelity = (1 - rate)^n × 100, computed with e^(n*ln(1-rate))
    echo "scale=10; e(${n_gates} * l(1 - ${error_rate_permille} / 1000)) * 100" | bc -l
}

# 100 gates at 0.1% error = ~90.5%
fidelity=$(circuit_fidelity_pct 100 1)
assert_eq "${fidelity%%.*}" "90" "100-gate fidelity"

# 1000 gates at 0.1% error = ~36.8%
fidelity=$(circuit_fidelity_pct 1000 1)
assert_eq "${fidelity%%.*}" "36" "1000-gate fidelity"

# ── Error correction overhead ──────────────────────────────────────────
# Surface code: ~1000 physical qubits per logical qubit (at current error rates)
physical_qubits_needed() {
    local logical=$1 overhead=${2:-1000}
    echo $(( logical * overhead ))
}

# Shor's for 2048-bit RSA: ~4000 logical qubits
assert_eq "$(physical_qubits_needed 4000 1000)" "4000000" "Shor physical qubits"
assert_eq "$(physical_qubits_needed 100 1000)" "100000" "100 logical qubits"

# ── Qubit coherence budget ─────────────────────────────────────────────
# Gates must complete within coherence time T2
max_gates_in_coherence() {
    local t2_us=$1         # coherence time in microseconds
    local gate_time_ns=$2  # gate time in nanoseconds
    echo $(( t2_us * 1000 / gate_time_ns ))
}

# Superconducting: T2 ~ 100μs, gate ~ 20ns
assert_eq "$(max_gates_in_coherence 100 20)" "5000" "superconducting budget"

# Trapped ion: T2 ~ 1000000μs (1s), gate ~ 100000ns (100μs)
assert_eq "$(max_gates_in_coherence 1000000 100000)" "10000" "trapped ion budget"

# ── Quantum volume estimation ──────────────────────────────────────────
# QV = 2^n where n = max circuit width that achieves >2/3 success probability
quantum_volume() {
    local effective_qubits=$1
    echo $(( 1 << effective_qubits ))
}

assert_eq "$(quantum_volume 5)" "32" "QV 32"
assert_eq "$(quantum_volume 7)" "128" "QV 128"
assert_eq "$(quantum_volume 10)" "1024" "QV 1024"

# ── Bell pair generation rate ──────────────────────────────────────────
# For quantum networking: EPR pairs per second
bell_pairs_per_second() {
    local rep_rate_mhz=$1  # repetition rate in MHz
    local success_prob_pct=$2  # success probability as percentage
    echo $(( rep_rate_mhz * 1000000 * success_prob_pct / 100 ))
}

assert_eq "$(bell_pairs_per_second 1 10)" "100000" "1MHz 10% success"

# ── Algorithm comparison table ─────────────────────────────────────────
print_comparison() {
    printf "%-20s %-15s %-15s\n" "Problem" "Classical" "Quantum"
    printf "%-20s %-15s %-15s\n" "Search (N items)" "O(N)" "O(√N)"
    printf "%-20s %-15s %-15s\n" "Factoring (n bits)" "O(exp(n^⅓))" "O(n³)"
    printf "%-20s %-15s %-15s\n" "Simulation (N elec)" "O(2^N)" "O(N)"
    printf "%-20s %-15s %-15s\n" "Optimization" "varies" "quadratic ↑"
}

# Verify the table generates without error
output=$(print_comparison)
line_count=$(echo "$output" | wc -l)
assert_eq "$line_count" "5" "comparison table lines"

echo "All quantum computing examples passed."
