# Vidya — Design Patterns in x86_64 Assembly
#
# Assembly patterns: function pointer dispatch (strategy), state
# transition table lookup (state machine), cleanup via structured
# call/ret (RAII-like resource management). At this level, every
# "pattern" is just data layout + control flow.

.intel_syntax noprefix
.global _start

.section .rodata
msg_pass:   .ascii "All design patterns examples passed.\n"
msg_len = . - msg_pass

# ── Strategy: function pointer table ──────────────────────────────────
# Each strategy is a function address. Caller loads and calls through
# the pointer — runtime polymorphism at the hardware level.

.align 8
strategy_table:
    .quad   strat_no_discount     # index 0
    .quad   strat_ten_percent     # index 1
    .quad   strat_flat_five       # index 2

# ── State machine: transition table ───────────────────────────────────
# States: 0=locked, 1=closed, 2=open
# Actions: 0=unlock, 1=open, 2=close, 3=lock
# Table[state][action] = next_state, 0xFF = invalid
# 3 states x 4 actions = 12 bytes

transition_table:
    # locked: unlock→closed, open→invalid, close→invalid, lock→invalid
    .byte 1, 0xFF, 0xFF, 0xFF
    # closed: unlock→invalid, open→open, close→invalid, lock→locked
    .byte 0xFF, 2, 0xFF, 0
    # open: unlock→invalid, open→invalid, close→closed, lock→invalid
    .byte 0xFF, 0xFF, 1, 0xFF

.section .text

_start:
    # ── Test 1: strategy — no discount on 100 → 100 ──────────────────
    lea     rsi, [strategy_table]
    mov     edi, 100
    mov     ecx, 0              # strategy index
    call    apply_strategy
    cmp     eax, 100
    jne     fail

    # ── Test 2: strategy — 10% off 100 → 90 ──────────────────────────
    lea     rsi, [strategy_table]
    mov     edi, 100
    mov     ecx, 1
    call    apply_strategy
    cmp     eax, 90
    jne     fail

    # ── Test 3: strategy — $5 off 100 → 95 ───────────────────────────
    lea     rsi, [strategy_table]
    mov     edi, 100
    mov     ecx, 2
    call    apply_strategy
    cmp     eax, 95
    jne     fail

    # ── Test 4: strategy — $5 off 3 → 0 (floor) ─────────────────────
    lea     rsi, [strategy_table]
    mov     edi, 3
    mov     ecx, 2
    call    apply_strategy
    cmp     eax, 0
    jne     fail

    # ── Test 5: state machine — locked → unlock → closed ─────────────
    mov     edi, 0              # state = locked
    mov     esi, 0              # action = unlock
    call    state_transition
    cmp     eax, 1              # expect closed
    jne     fail

    # ── Test 6: state machine — closed → open → open ─────────────────
    mov     edi, 1              # state = closed
    mov     esi, 1              # action = open
    call    state_transition
    cmp     eax, 2              # expect open
    jne     fail

    # ── Test 7: state machine — open → close → closed ────────────────
    mov     edi, 2              # state = open
    mov     esi, 2              # action = close
    call    state_transition
    cmp     eax, 1              # expect closed
    jne     fail

    # ── Test 8: state machine — closed → lock → locked ───────────────
    mov     edi, 1              # state = closed
    mov     esi, 3              # action = lock
    call    state_transition
    cmp     eax, 0              # expect locked
    jne     fail

    # ── Test 9: state machine — invalid: locked → open ───────────────
    mov     edi, 0              # state = locked
    mov     esi, 1              # action = open
    call    state_transition
    cmp     eax, -1             # expect invalid
    jne     fail

    # ── Test 10: cleanup pattern — acquire/release ordering ──────────
    # Simulate resource management: track acquire/release in a counter.
    # acquire increments, release decrements. Structured cleanup ensures
    # we return to 0.
    call    test_cleanup
    cmp     eax, 0              # should be back to 0
    jne     fail

    # ── Test 11: full state cycle ─────────────────────────────────────
    # locked → unlock → open → close → lock → locked
    mov     edi, 0
    mov     esi, 0              # unlock
    call    state_transition
    mov     edi, eax            # closed
    mov     esi, 1              # open
    call    state_transition
    mov     edi, eax            # open
    mov     esi, 2              # close
    call    state_transition
    mov     edi, eax            # closed
    mov     esi, 3              # lock
    call    state_transition
    cmp     eax, 0              # back to locked
    jne     fail

    # ── All passed ────────────────────────────────────────────────────
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

# ── apply_strategy(rsi=table, edi=price, ecx=index) → eax ────────────
# Loads function pointer from table[index] and calls it with price.
apply_strategy:
    mov     rax, [rsi + rcx*8]  # load function pointer
    # edi already has price
    jmp     rax                 # tail call — strategy returns via ret

# ── Strategy implementations ──────────────────────────────────────────
# Each takes edi=price, returns eax=result.

strat_no_discount:
    mov     eax, edi
    ret

strat_ten_percent:
    # price * 9 / 10
    mov     eax, edi
    imul    eax, 9
    xor     edx, edx
    mov     ecx, 10
    div     ecx
    ret

strat_flat_five:
    mov     eax, edi
    sub     eax, 5
    jns     .sf_done
    xor     eax, eax            # floor at 0
.sf_done:
    ret

# ── state_transition(edi=state, esi=action) → eax (next or -1) ───────
# Looks up transition_table[state * 4 + action].
state_transition:
    lea     rcx, [transition_table]
    mov     eax, edi
    shl     eax, 2              # state * 4
    add     eax, esi            # + action
    movzx   eax, byte ptr [rcx + rax]
    cmp     al, 0xFF
    je      .st_invalid
    ret
.st_invalid:
    mov     eax, -1
    ret

# ── test_cleanup() → eax (resource counter, should be 0) ─────────────
# Demonstrates structured acquire/release: nested resource management
# using call/ret discipline ensures proper cleanup ordering.
test_cleanup:
    xor     eax, eax            # counter = 0
    inc     eax                 # acquire resource 1 (counter = 1)
    push    rax
    inc     eax                 # acquire resource 2 (counter = 2)
    push    rax
    inc     eax                 # acquire resource 3 (counter = 3)
    # Now release in reverse order (LIFO — like stack unwinding)
    dec     eax                 # release resource 3 (counter = 2)
    pop     rcx                 # restore after resource 2 acquire
    dec     eax                 # release resource 2 (counter = 1)
    pop     rcx                 # restore after resource 1 acquire
    dec     eax                 # release resource 1 (counter = 0)
    ret
