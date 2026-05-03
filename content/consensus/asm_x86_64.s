# Vidya — Consensus and Raft — x86_64 Assembly
#
# Election state machine focus (no log replication — see cyrius.cyr
# for the full version). 3-node cluster, per-node {role, term,
# voted_for}. Demonstrates:
#
#   1. init: all FOLLOWER, term 0, voted_for -1
#   2. start_election bumps term, votes self, → CANDIDATE
#   3. run_election with 2 grants → 3 votes total, → LEADER
#   4. stale-term RPC rejected (term not regressed)
#   5. higher-term RPC: step down, term updated, voted_for cleared
#   6. vote uniqueness: same node can't vote twice in one term

.intel_syntax noprefix
.global _start

.equ N_NODES,        3
.equ ROLE_FOLLOWER,  0
.equ ROLE_CANDIDATE, 1
.equ ROLE_LEADER,    2
.equ QUORUM,         2

.section .bss
.align 8
node_role:      .skip 24       # 3 × i64
node_term:      .skip 24
node_voted_for: .skip 24

.section .rodata
msg_pass: .ascii "consensus: 12/12 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail: .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

# cluster_init: all followers, term 0, voted_for -1
cluster_init:
    xor     rcx, rcx
.ci_loop:
    cmp     rcx, N_NODES
    jge     .ci_done
    lea     r8, [rip + node_role]
    mov     qword ptr [r8 + rcx*8], ROLE_FOLLOWER
    lea     r8, [rip + node_term]
    mov     qword ptr [r8 + rcx*8], 0
    lea     r8, [rip + node_voted_for]
    mov     qword ptr [r8 + rcx*8], -1
    inc     rcx
    jmp     .ci_loop
.ci_done:
    ret

# start_election(rdi=node) -> rax=new_term
start_election:
    lea     r8, [rip + node_term]
    mov     rax, [r8 + rdi*8]
    inc     rax
    mov     [r8 + rdi*8], rax
    lea     r8, [rip + node_voted_for]
    mov     [r8 + rdi*8], rdi
    lea     r8, [rip + node_role]
    mov     qword ptr [r8 + rdi*8], ROLE_CANDIDATE
    ret

# request_vote(rdi=voter, rsi=candidate, rdx=cand_term) -> rax=1/0
# (No log-up-to-date check; asm port skips log state.)
request_vote:
    lea     r8, [rip + node_term]
    mov     r9, [r8 + rdi*8]              # voter_term
    cmp     rdx, r9
    jl      .rv_reject
    cmp     rdx, r9
    jle     .rv_no_step
    # cand_term > voter_term → step down, update term, clear vote
    mov     [r8 + rdi*8], rdx
    lea     r10, [rip + node_voted_for]
    mov     qword ptr [r10 + rdi*8], -1
    lea     r10, [rip + node_role]
    mov     qword ptr [r10 + rdi*8], ROLE_FOLLOWER
.rv_no_step:
    lea     r10, [rip + node_voted_for]
    mov     r11, [r10 + rdi*8]
    cmp     r11, -1
    je      .rv_grant
    cmp     r11, rsi
    jne     .rv_reject
.rv_grant:
    mov     [r10 + rdi*8], rsi
    mov     rax, 1
    ret
.rv_reject:
    xor     rax, rax
    ret

# run_election(rdi=candidate) -> rax=vote_count; promotes if quorum
run_election:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi                       # candidate
    mov     rbx, 1                         # votes (self)
    lea     r8, [rip + node_term]
    mov     r13, [r8 + r12*8]              # cand_term
    xor     rcx, rcx
.re_loop:
    cmp     rcx, N_NODES
    jge     .re_done
    cmp     rcx, r12
    je      .re_skip
    push    rcx
    mov     rdi, rcx
    mov     rsi, r12
    mov     rdx, r13
    call    request_vote
    pop     rcx
    test    rax, rax
    jz      .re_skip
    inc     rbx
.re_skip:
    inc     rcx
    jmp     .re_loop
.re_done:
    cmp     rbx, QUORUM
    jl      .re_no_promote
    lea     r8, [rip + node_role]
    mov     qword ptr [r8 + r12*8], ROLE_LEADER
.re_no_promote:
    mov     rax, rbx
    pop     r13
    pop     r12
    pop     rbx
    ret

assert_eq:
    cmp     rdi, rsi
    jne     .ae_fail
    ret
.ae_fail:
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [rip + msg_fail]
    mov     rdx, msg_fail_len
    syscall
    mov     rax, 60
    mov     rdi, 1
    syscall

_start:
    # Test 1: init state
    call    cluster_init
    lea     r8, [rip + node_role]
    mov     rdi, [r8 + 0]
    mov     rsi, ROLE_FOLLOWER
    call    assert_eq
    lea     r8, [rip + node_term]
    mov     rdi, [r8 + 0]
    mov     rsi, 0
    call    assert_eq
    lea     r8, [rip + node_voted_for]
    mov     rdi, [r8 + 0]
    mov     rsi, -1
    call    assert_eq

    # Test 2: start_election
    call    cluster_init
    mov     rdi, 0
    call    start_election
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    lea     r8, [rip + node_role]
    mov     rdi, [r8 + 0]
    mov     rsi, ROLE_CANDIDATE
    call    assert_eq
    lea     r8, [rip + node_voted_for]
    mov     rdi, [r8 + 0]
    mov     rsi, 0
    call    assert_eq

    # Test 3: run_election → leader
    call    cluster_init
    mov     rdi, 0
    call    start_election
    mov     rdi, 0
    call    run_election
    mov     rdi, rax
    mov     rsi, 3
    call    assert_eq
    lea     r8, [rip + node_role]
    mov     rdi, [r8 + 0]
    mov     rsi, ROLE_LEADER
    call    assert_eq

    # Test 4: stale RPC rejected
    call    cluster_init
    lea     r8, [rip + node_term]
    mov     qword ptr [r8 + 8], 5
    mov     rdi, 1
    mov     rsi, 0
    mov     rdx, 1
    call    request_vote
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq
    lea     r8, [rip + node_term]
    mov     rdi, [r8 + 8]
    mov     rsi, 5
    call    assert_eq

    # Test 5: higher-term steps down
    call    cluster_init
    mov     rdi, 0
    call    start_election
    mov     rdi, 0
    call    run_election                  # node 0 is leader
    mov     rdi, 0
    mov     rsi, 2
    mov     rdx, 5
    call    request_vote
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    lea     r8, [rip + node_term]
    mov     rdi, [r8 + 0]
    mov     rsi, 5
    call    assert_eq
    lea     r8, [rip + node_role]
    mov     rdi, [r8 + 0]
    mov     rsi, ROLE_FOLLOWER
    call    assert_eq

    # Test 6: vote uniqueness
    call    cluster_init
    mov     rdi, 2
    mov     rsi, 0
    mov     rdx, 1
    call    request_vote
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq                     # first vote granted
    mov     rdi, 2
    mov     rsi, 1
    mov     rdx, 1
    call    request_vote
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq                     # second denied

    # Success
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall
