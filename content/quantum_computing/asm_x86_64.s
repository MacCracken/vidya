# Vidya — Quantum Computing in x86_64 Assembly
#
# Quantum concepts at the register level: fixed-point probability
# arithmetic, state space calculations, Grover iteration counting,
# and resource estimation. Assembly shows the bare metal cost of
# quantum simulation — each amplitude needs complex multiplication.

.intel_syntax noprefix
.global _start

.section .rodata
msg_pass:   .ascii "All quantum computing examples passed.\n"
msg_len = . - msg_pass

.section .text

_start:
    # ── Test 1: State space size = 2^n ─────────────────────────────────
    # 1 qubit → 2 amplitudes
    mov     ecx, 1
    mov     eax, 1
    shl     eax, cl
    cmp     eax, 2
    jne     fail

    # 10 qubits → 1024 amplitudes
    mov     ecx, 10
    mov     eax, 1
    shl     eax, cl
    cmp     eax, 1024
    jne     fail

    # 20 qubits → 1048576 amplitudes
    mov     ecx, 20
    mov     eax, 1
    shl     eax, cl
    cmp     eax, 1048576
    jne     fail

    # ── Test 2: Memory for simulation = 2^n × 16 bytes (complex128) ───
    # 20 qubits: 1048576 × 16 = 16777216 bytes (16MB)
    mov     ecx, 20
    mov     rax, 1
    shl     rax, cl
    shl     rax, 4              # × 16 bytes per complex
    mov     rbx, 16777216
    cmp     rax, rbx
    jne     fail

    # 30 qubits: 2^30 × 16 = 17179869184 (16GB)
    mov     ecx, 30
    mov     rax, 1
    shl     rax, cl
    shl     rax, 4
    mov     rbx, 17179869184
    cmp     rax, rbx
    jne     fail

    # ── Test 3: Grover iterations for N=4 ──────────────────────────────
    # floor(π/4 × √N) ≈ floor(0.785 × 2) = floor(1.57) = 1
    # We use fixed-point: 785 × 2 / 1000 = 1
    mov     eax, 785            # π/4 × 1000
    mov     ecx, 2              # √4 = 2
    mul     ecx                 # eax = 1570
    mov     ecx, 1000
    xor     edx, edx
    div     ecx                 # eax = 1
    cmp     eax, 1
    jne     fail

    # ── Test 4: Grover iterations for N=1M ─────────────────────────────
    # floor(0.785 × 1000) = floor(785) = 785
    mov     eax, 785
    mov     ecx, 1000           # √1000000 = 1000
    mul     ecx                 # eax = 785000
    mov     ecx, 1000
    xor     edx, edx
    div     ecx                 # eax = 785
    cmp     eax, 785
    jne     fail

    # ── Test 5: Physical qubits = logical × overhead ───────────────────
    # Shor's: 4000 logical × 1000 overhead = 4,000,000
    mov     rax, 4000
    mov     rcx, 1000
    mul     rcx
    mov     rbx, 4000000
    cmp     rax, rbx
    jne     fail

    # ── Test 6: Gate budget within coherence time ──────────────────────
    # T2=100μs, gate=20ns → 100000ns/20ns = 5000 gates
    mov     eax, 100000         # T2 in nanoseconds
    xor     edx, edx
    mov     ecx, 20             # gate time in ns
    div     ecx
    cmp     eax, 5000
    jne     fail

    # ── Test 7: Quantum volume = 2^n ───────────────────────────────────
    # QV 32 = 2^5
    mov     ecx, 5
    mov     eax, 1
    shl     eax, cl
    cmp     eax, 32
    jne     fail

    # QV 1024 = 2^10
    mov     ecx, 10
    mov     eax, 1
    shl     eax, cl
    cmp     eax, 1024
    jne     fail

    # ── Test 8: Complex multiply operation count ───────────────────────
    # Each complex mul = 4 real muls + 2 adds = 6 FLOPs
    # Gate on n-qubit state: 2^n complex muls → 6 × 2^n FLOPs
    # 20-qubit Hadamard: 6 × 2^20 = 6291456 FLOPs
    mov     ecx, 20
    mov     rax, 1
    shl     rax, cl
    mov     rcx, 6
    mul     rcx
    mov     rbx, 6291456
    cmp     rax, rbx
    jne     fail

    # ── All passed ─────────────────────────────────────────────────────
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [msg_pass]
    mov     rdx, msg_len
    syscall

    mov     rax, 60
    xor     rdi, rdi
    syscall

fail:
    mov     rax, 60
    mov     rdi, 1
    syscall
