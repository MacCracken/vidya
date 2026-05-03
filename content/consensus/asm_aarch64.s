// Vidya — Consensus and Raft — AArch64 Assembly
//
// Election state machine focus (no log replication — see cyrius.cyr).
// Same 6 tests / 12 asserts as the x86_64 port.

.global _start

.equ N_NODES,        3
.equ ROLE_FOLLOWER,  0
.equ ROLE_CANDIDATE, 1
.equ ROLE_LEADER,    2
.equ QUORUM,         2

.bss
.align 8
node_role:      .skip 24
node_term:      .skip 24
node_voted_for: .skip 24

.section .rodata
msg_pass: .ascii "consensus: 12/12 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail: .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

.macro LDADDR reg, sym
    adrp    \reg, \sym
    add     \reg, \reg, :lo12:\sym
.endm

cluster_init:
    mov     x0, #0
.ci_loop:
    cmp     x0, #N_NODES
    b.ge    .ci_done
    LDADDR  x1, node_role
    str     xzr, [x1, x0, lsl #3]
    LDADDR  x1, node_term
    str     xzr, [x1, x0, lsl #3]
    LDADDR  x1, node_voted_for
    mov     x2, #-1
    str     x2, [x1, x0, lsl #3]
    add     x0, x0, #1
    b       .ci_loop
.ci_done:
    ret

// start_election(x0=node) -> x0=new_term
start_election:
    LDADDR  x1, node_term
    ldr     x2, [x1, x0, lsl #3]
    add     x2, x2, #1
    str     x2, [x1, x0, lsl #3]
    LDADDR  x3, node_voted_for
    str     x0, [x3, x0, lsl #3]
    LDADDR  x3, node_role
    mov     x4, #ROLE_CANDIDATE
    str     x4, [x3, x0, lsl #3]
    mov     x0, x2
    ret

// request_vote(x0=voter, x1=candidate, x2=cand_term) -> x0=1/0
request_vote:
    LDADDR  x3, node_term
    ldr     x4, [x3, x0, lsl #3]                // voter_term
    cmp     x2, x4
    b.lt    .rv_reject
    b.eq    .rv_no_step
    // cand_term > voter_term: step down
    str     x2, [x3, x0, lsl #3]
    LDADDR  x5, node_voted_for
    mov     x6, #-1
    str     x6, [x5, x0, lsl #3]
    LDADDR  x5, node_role
    mov     x6, #ROLE_FOLLOWER
    str     x6, [x5, x0, lsl #3]
.rv_no_step:
    LDADDR  x5, node_voted_for
    ldr     x6, [x5, x0, lsl #3]
    cmn     x6, #1                              // compare with -1
    b.eq    .rv_grant
    cmp     x6, x1
    b.ne    .rv_reject
.rv_grant:
    str     x1, [x5, x0, lsl #3]
    mov     x0, #1
    ret
.rv_reject:
    mov     x0, #0
    ret

// run_election(x0=candidate) -> x0=votes
run_election:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]                      // save x19 (candidate)
    str     x20, [sp, #24]                      // save x20 (cand_term)
    mov     x19, x0
    mov     x21, #1                             // votes (caller-saved x21 ok within funct, but no calls trash x21? request_vote doesn't, OK)
    LDADDR  x1, node_term
    ldr     x20, [x1, x19, lsl #3]
    mov     x22, #0                             // v
.re_loop:
    cmp     x22, #N_NODES
    b.ge    .re_done
    cmp     x22, x19
    b.eq    .re_skip
    mov     x0, x22
    mov     x1, x19
    mov     x2, x20
    bl      request_vote
    cmp     x0, #0
    b.eq    .re_skip
    add     x21, x21, #1
.re_skip:
    add     x22, x22, #1
    b       .re_loop
.re_done:
    cmp     x21, #QUORUM
    b.lt    .re_no_promote
    LDADDR  x1, node_role
    mov     x2, #ROLE_LEADER
    str     x2, [x1, x19, lsl #3]
.re_no_promote:
    mov     x0, x21
    ldr     x20, [sp, #24]
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

assert_eq:
    cmp     x0, x1
    b.ne    .ae_fail
    ret
.ae_fail:
    mov     x8, #64
    mov     x0, #2
    LDADDR  x1, msg_fail
    mov     x2, #msg_fail_len
    svc     #0
    mov     x8, #93
    mov     x0, #1
    svc     #0

_start:
    // Test 1: init
    bl      cluster_init
    LDADDR  x2, node_role
    ldr     x0, [x2, #0]
    mov     x1, #ROLE_FOLLOWER
    bl      assert_eq
    LDADDR  x2, node_term
    ldr     x0, [x2, #0]
    mov     x1, #0
    bl      assert_eq
    LDADDR  x2, node_voted_for
    ldr     x0, [x2, #0]
    mov     x1, #-1
    bl      assert_eq

    // Test 2: start_election
    bl      cluster_init
    mov     x0, #0
    bl      start_election
    mov     x1, #1
    bl      assert_eq
    LDADDR  x2, node_role
    ldr     x0, [x2, #0]
    mov     x1, #ROLE_CANDIDATE
    bl      assert_eq
    LDADDR  x2, node_voted_for
    ldr     x0, [x2, #0]
    mov     x1, #0
    bl      assert_eq

    // Test 3: run_election → leader
    bl      cluster_init
    mov     x0, #0
    bl      start_election
    mov     x0, #0
    bl      run_election
    mov     x1, #3
    bl      assert_eq
    LDADDR  x2, node_role
    ldr     x0, [x2, #0]
    mov     x1, #ROLE_LEADER
    bl      assert_eq

    // Test 4: stale RPC rejected
    bl      cluster_init
    LDADDR  x2, node_term
    mov     x0, #5
    str     x0, [x2, #8]
    mov     x0, #1
    mov     x1, #0
    mov     x2, #1
    bl      request_vote
    mov     x1, #0
    bl      assert_eq
    LDADDR  x2, node_term
    ldr     x0, [x2, #8]
    mov     x1, #5
    bl      assert_eq

    // Test 5: higher-term steps down
    bl      cluster_init
    mov     x0, #0
    bl      start_election
    mov     x0, #0
    bl      run_election
    mov     x0, #0
    mov     x1, #2
    mov     x2, #5
    bl      request_vote
    mov     x1, #1
    bl      assert_eq
    LDADDR  x2, node_term
    ldr     x0, [x2, #0]
    mov     x1, #5
    bl      assert_eq
    LDADDR  x2, node_role
    ldr     x0, [x2, #0]
    mov     x1, #ROLE_FOLLOWER
    bl      assert_eq

    // Test 6: vote uniqueness
    bl      cluster_init
    mov     x0, #2
    mov     x1, #0
    mov     x2, #1
    bl      request_vote
    mov     x1, #1
    bl      assert_eq
    mov     x0, #2
    mov     x1, #1
    mov     x2, #1
    bl      request_vote
    mov     x1, #0
    bl      assert_eq

    // success
    mov     x8, #64
    mov     x0, #1
    LDADDR  x1, msg_pass
    mov     x2, #msg_pass_len
    svc     #0
    mov     x8, #93
    mov     x0, #0
    svc     #0
