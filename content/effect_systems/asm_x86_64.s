# Vidya — Effect Systems in x86_64 Assembly
#
# A program that yields effect requests (Ask, Log, Fail) instead of doing
# I/O, handlers that decide what each one means (resume with an answer, or
# stop), state threaded through step(state, input), capabilities passed as
# parameters, and a pure core behind a thin shell. Mirrors all 49 checks
# of cyrius.cyr.
#
# OCaml 5, Koka, Unison and Eff have native effect handlers. Here the
# program is a step function that returns its next request as a (tag,
# payload) pair in rax:rdx; the interpreter dispatches on the tag through
# the handler's table of arm addresses and feeds the answer back in rsi.

.intel_syntax noprefix
.global _start

# Effect tags (an arm table is indexed by the first three) and outcomes.
.equ EFF_ASK, 0
.equ EFF_LOG, 1
.equ EFF_FAIL, 2
.equ EFF_DONE, 3
.equ FINISHED, 0
.equ STOPPED, 1

# Program state: [pc, qty, rate, steps, msg[LINE_CAP]].
.equ P_PC, 0
.equ P_QTY, 8
.equ P_RATE, 16
.equ P_STEPS, 24
.equ P_MSG, 32
.equ LINE_CAP, 32
.equ P_SIZE, 32 + LINE_CAP

# Log buffer: [count, then LOG_CAP lines of LINE_CAP bytes].
.equ LOG_CAP, 8
.equ LOG_SIZE, 8 + LOG_CAP * LINE_CAP

# Thermostat commands.
.equ HEAT_ON, 1
.equ HEAT_OFF, 2
.equ ALARM, 3

.equ HEAP_SIZE, 8192

# CHECK cc, "name": after a cmp or test, carry on if condition cc holds,
# else print "FAIL: name" and exit 1.
.macro CHECK cc, msg
    j\cc    .Lok\@
    .pushsection .rodata
.Lmsg\@: .ascii "\msg"
.Lend\@:
    .popsection
    lea     rsi, [rip + .Lmsg\@]
    mov     edx, .Lend\@ - .Lmsg\@
    jmp     fail
.Lok\@:
.endm

.section .bss
.align 8
heap:            .skip HEAP_SIZE
heap_top:        .skip 8
g_stdout_lines:  .skip 8        # lines the production handlers wrote
g_clock_reads:   .skip 8        # reads of the production "system clock"
g_heater_pin:    .skip 8        # the device the shell drives
g_alarms_raised: .skip 8

.section .data
.align 8
g_config_rate:   .quad 4        # the process configuration prod_ask reads
g_sys_time:      .quad 1000     # the deterministic "system clock"
# The production handler: [arm table, env]. It captures nothing.
prod_handler:    .quad prod_table, 0

.section .rodata
.align 8
# A handler's arm table: one code address per effect tag, indexed by tag.
prod_table:      .quad prod_ask, prod_log, prod_fail
test_table:      .quad test_ask, test_log, test_fail
forgetful_table: .quad forgetful_ask, forgetful_log, forgetful_fail

inputs:          .quad 5, 10, 20
# Every threshold is hit exactly (19 and 21 emit nothing, 15 alarms, 16
# does not), and 17 / 23 arrive with the heater already on / off.
events:          .quad 19, 18, 17, 21, 22, 23, 15, 16, 14

str_rate:        .asciz "rate"
str_rate_eq:     .asciz "rate="
str_total_eq:    .asciz "total="
str_empty_order: .asciz "empty order"
str_unknown_key: .asciz "unknown key"
str_valid_at:    .asciz "valid at "
str_expired_at:  .asciz "expired at "
exp_rate3:       .asciz "rate=3"
exp_total30:     .asciz "total=30"
exp_rate5:       .asciz "rate=5"
exp_valid100:    .asciz "valid at 100"
exp_expired200:  .asciz "expired at 200"

str_prod:        .ascii "  [prod] "
str_prod_len = . - str_prod
msg_pass:        .ascii "All effect system examples passed.\n"
msg_pass_len = . - msg_pass
msg_fail:        .ascii "FAIL: "
msg_fail_len = . - msg_fail
msg_oom:         .ascii "arena exhausted"
msg_oom_len = . - msg_oom
msg_nl:          .ascii "\n"

.section .text

# ---------------------------------------------------------------------------
# --- Shared helpers: an arena, strings, a log buffer, stdout ---

# alloc(rdi = bytes, a multiple of 8) -> rax. A bump arena in .bss that
# never frees (and so hands out zeroed memory). Clobbers rcx, rdx.
alloc:
    mov     rax, [rip + heap_top]
    lea     rdx, [rax + rdi]
    lea     rcx, [rip + heap + HEAP_SIZE]
    cmp     rdx, rcx
    ja      .alloc_full
    mov     [rip + heap_top], rdx
    ret
.alloc_full:
    lea     rsi, [rip + msg_oom]
    mov     edx, msg_oom_len
    jmp     fail

# str_is(rdi = p, rsi = s) -> rax = 1 if the NUL-terminated strings match.
# Null-safe for the checks: p = 0 (a missing line or reason) is 0, not a crash.
str_is:
    xor     eax, eax
    test    rdi, rdi
    jz      .si_ret
.si_loop:
    mov     cl, [rdi]
    cmp     cl, [rsi]
    jne     .si_ret
    test    cl, cl
    jz      .si_yes
    inc     rdi
    inc     rsi
    jmp     .si_loop
.si_yes:
    mov     eax, 1
.si_ret:
    ret

# strlen(rdi) -> rax.
strlen:
    xor     eax, eax
.sl_loop:
    cmp     byte ptr [rdi + rax], 0
    je      .sl_ret
    inc     rax
    jmp     .sl_loop
.sl_ret:
    ret

# msg_kv(rdi = dst, rsi = prefix, rdx = n >= 0) -> rax = dst.
# "rate=" + 3 -> "rate=3". A leaf: the digits are built backwards in the
# red zone below rsp, then copied out. The longest prefix (11) plus 20
# digits and the NUL fits LINE_CAP.
msg_kv:
    mov     r10, rdi
    mov     r8, rdi                 # write cursor
.mk_prefix:
    mov     cl, [rsi]
    test    cl, cl
    jz      .mk_digits
    mov     [r8], cl
    inc     rsi
    inc     r8
    jmp     .mk_prefix
.mk_digits:
    mov     rax, rdx
    lea     r9, [rsp - 1]
    mov     ecx, 10
    xor     r11d, r11d              # digit count
.mk_div:
    xor     edx, edx
    div     rcx                     # rax = n / 10, rdx = n % 10
    add     dl, '0'
    mov     [r9], dl
    dec     r9
    inc     r11
    test    rax, rax
    jnz     .mk_div
.mk_copy:
    inc     r9
    mov     cl, [r9]
    mov     [r8], cl
    inc     r8
    dec     r11
    jnz     .mk_copy
    mov     byte ptr [r8], 0
    mov     rax, r10
    ret

# log_new() -> rax = an empty log buffer.
log_new:
    mov     edi, LOG_SIZE
    call    alloc
    mov     qword ptr [rax], 0
    ret

# log_push(rdi = log, rsi = msg): copy msg into the next line. A copy, not
# the pointer: a Log payload points into the program's state, which the
# next step overwrites.
log_push:
    mov     rax, [rdi]
    cmp     rax, LOG_CAP
    jae     .lp_full
    mov     rcx, rax
    imul    rcx, LINE_CAP
    lea     r8, [rdi + 8 + rcx]     # this line's slot
    mov     r9d, LINE_CAP - 1       # room, leaving the NUL
.lp_copy:
    mov     dl, [rsi]
    test    dl, dl
    jz      .lp_end
    test    r9, r9
    jz      .lp_end
    mov     [r8], dl
    inc     rsi
    inc     r8
    dec     r9
    jmp     .lp_copy
.lp_end:
    mov     byte ptr [r8], 0
    inc     qword ptr [rdi]
.lp_full:
    ret

# log_line_is(rdi = log, rsi = i, rdx = s) -> rax = 1 if line i exists
# and equals s.
log_line_is:
    cmp     rsi, [rdi]
    jae     .lli_no
    imul    rsi, LINE_CAP
    lea     rdi, [rdi + 8 + rsi]
    mov     rsi, rdx
    jmp     str_is
.lli_no:
    xor     eax, eax
    ret

# stdout_line(rdi = msg): "  [prod] msg\n" to stdout, and count it. The
# one real output channel, used only by the production handlers.
stdout_line:
    push    rbx
    mov     rbx, rdi
    mov     eax, 1
    mov     edi, 1
    lea     rsi, [rip + str_prod]
    mov     edx, str_prod_len
    syscall
    mov     rdi, rbx
    call    strlen
    mov     rdx, rax
    mov     eax, 1
    mov     edi, 1
    mov     rsi, rbx
    syscall
    mov     eax, 1
    mov     edi, 1
    lea     rsi, [rip + msg_nl]
    mov     edx, 1
    syscall
    inc     qword ptr [rip + g_stdout_lines]
    pop     rbx
    ret

# ---------------------------------------------------------------------------
# --- 1. Effects as data, and an interpreter ---
# A request is (tag, payload) in rax:rdx: Ask(key), Log(msg), Fail(reason),
# or Done(value), which is not an effect but how the program returns. The
# program never performs an effect; it hands the request back.
#
# The program, as it would read with native handlers (OCaml 5, Koka):
#   rate = perform Ask("rate")
#   perform Log("rate=" ^ rate)
#   if qty <= 0 then perform Fail("empty order")
#   perform Log("total=" ^ qty * rate)
#   return qty * rate
# checkout_step is that program cut at each effect. Its state record is the
# suspended rest of the program; `steps` counts how many times it ran, so a
# check can see what a handler cut short.

# checkout_new(rdi = qty) -> rax = a fresh program state.
checkout_new:
    push    rbx
    mov     rbx, rdi
    mov     edi, P_SIZE
    call    alloc
    mov     qword ptr [rax + P_PC], 0
    mov     [rax + P_QTY], rbx
    mov     qword ptr [rax + P_RATE], 0
    mov     qword ptr [rax + P_STEPS], 0
    pop     rbx
    ret

# checkout_step(rdi = state, rsi = answer) -> rax = tag, rdx = payload.
checkout_step:
    push    rbx
    mov     rbx, rdi
    inc     qword ptr [rbx + P_STEPS]
    mov     rax, [rbx + P_PC]
    test    rax, rax
    jz      .cs_ask
    cmp     rax, 1
    je      .cs_rate
    cmp     rax, 2
    je      .cs_total
    mov     qword ptr [rbx + P_PC], 4
    mov     rdx, [rbx + P_QTY]
    imul    rdx, [rbx + P_RATE]
    mov     eax, EFF_DONE
    pop     rbx
    ret
.cs_ask:
    mov     qword ptr [rbx + P_PC], 1
    mov     eax, EFF_ASK
    lea     rdx, [rip + str_rate]
    pop     rbx
    ret
.cs_rate:
    mov     [rbx + P_RATE], rsi     # resumed with Ask's answer
    mov     qword ptr [rbx + P_PC], 2
    lea     rdi, [rbx + P_MSG]
    mov     rdx, rsi
    lea     rsi, [rip + str_rate_eq]
    call    msg_kv
    mov     eax, EFF_LOG
    lea     rdx, [rbx + P_MSG]
    pop     rbx
    ret
.cs_total:
    mov     qword ptr [rbx + P_PC], 3
    cmp     qword ptr [rbx + P_QTY], 0
    jle     .cs_fail
    lea     rdi, [rbx + P_MSG]
    mov     rdx, [rbx + P_QTY]
    imul    rdx, [rbx + P_RATE]
    lea     rsi, [rip + str_total_eq]
    call    msg_kv
    mov     eax, EFF_LOG
    lea     rdx, [rbx + P_MSG]
    pop     rbx
    ret
.cs_fail:
    mov     eax, EFF_FAIL
    lea     rdx, [rip + str_empty_order]
    pop     rbx
    ret

# handle_with(rdi = handler, rsi = step code, rdx = state)
#   -> rax = FINISHED or STOPPED, rdx = the value or the stop's reason.
# A handler is a record [arm table, env]; an arm is (rdi = env,
# rsi = payload) -> rax = resume (1) or stop (0), rdx = the answer or the
# reason. The interpreter knows nothing about what an effect means: it
# calls the arm the tag selects. Resume = the answer goes into the next
# step call. Stop = it never calls step again.
handle_with:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi                # handler
    mov     r12, rsi                # step
    mov     r13, rdx                # program state
    xor     r14d, r14d              # answer
.hw_loop:
    mov     rdi, r13
    mov     rsi, r14
    call    r12                     # rax = tag, rdx = payload
    cmp     rax, EFF_DONE
    je      .hw_finished
    ja      .hw_no_arm              # a tag with no arm: stop, no reason
    mov     rcx, [rbx]              # the arm table
    mov     rdi, [rbx + 8]          # the env
    mov     rsi, rdx
    call    qword ptr [rcx + rax * 8]
    test    rax, rax
    jz      .hw_stopped
    mov     r14, rdx                # resume with the answer
    jmp     .hw_loop
.hw_no_arm:
    xor     edx, edx
.hw_stopped:
    mov     eax, STOPPED
    jmp     .hw_ret
.hw_finished:
    mov     eax, FINISHED
.hw_ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# Production handler: Ask reads the process configuration, Log writes to
# stdout, Fail is reported and stops the program.
prod_ask:
    mov     rdi, rsi
    lea     rsi, [rip + str_rate]
    call    str_is
    test    rax, rax
    jz      .pa_unknown
    mov     eax, 1
    mov     rdx, [rip + g_config_rate]
    ret
.pa_unknown:
    xor     eax, eax
    lea     rdx, [rip + str_unknown_key]
    ret

prod_log:
    mov     rdi, rsi
    call    stdout_line
    mov     eax, 1
    xor     edx, edx
    ret

prod_fail:
    push    rbx
    mov     rbx, rsi
    mov     rdi, rsi
    call    stdout_line
    xor     eax, eax
    mov     rdx, rbx
    pop     rbx
    ret

# make_handler(rdi = table, rsi = rate, rdx = log) -> rax = a handler
# record [table, env] with its env [rate, log] right after it: a closure,
# written out. No I/O, nothing global.
make_handler:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     edi, 32
    call    alloc
    mov     [rax], rbx
    lea     rcx, [rax + 16]
    mov     [rax + 8], rcx
    mov     [rax + 16], r12
    mov     [rax + 24], r13
    pop     r13
    pop     r12
    pop     rbx
    ret

# Test handler: answers Ask from its env, records Log into its log buffer.
test_ask:
    push    rbx
    mov     rbx, rdi
    mov     rdi, rsi
    lea     rsi, [rip + str_rate]
    call    str_is
    test    rax, rax
    jz      .ta_unknown
    mov     eax, 1
    mov     rdx, [rbx]              # env.rate
    pop     rbx
    ret
.ta_unknown:
    xor     eax, eax
    lea     rdx, [rip + str_unknown_key]
    pop     rbx
    ret

test_log:
    mov     rdi, [rdi + 8]          # env.log
    call    log_push
    mov     eax, 1
    xor     edx, edx
    ret

test_fail:                          # do not resume: the failure is the result
    xor     eax, eax
    mov     rdx, rsi
    ret

# --- 2. Resumable handlers ---
# Ask is answered and the program RESUMES with the answer: handle_with
# passes the arm's rdx to the next checkout_step call in rsi. Two handlers
# that answer differently get different results from the same program.
# (A native handler resumes a captured continuation, and OCaml 5's are
# one-shot. Here the continuation is a state record in memory, so a copy
# could be resumed twice: nothing stops that.)

# --- 3. A non-resuming effect is an early exit ---
# test_fail answers by NOT resuming, so the rest of the program never runs:
# no "total=" line, and no further steps. That is an exception built from
# a handler. The same mechanism is the gotcha when it is an accident: an
# arm that forgets to resume after Log stops the program just as silently.
forgetful_ask:
    mov     eax, 1
    mov     rdx, [rdi]              # env.rate
    ret

forgetful_log:
    mov     rdi, [rdi + 8]
    call    log_push
    xor     eax, eax                # BUG: should be mov eax, 1 (resume)
    xor     edx, edx
    ret

forgetful_fail:
    xor     eax, eax
    mov     rdx, rsi
    ret

# ---------------------------------------------------------------------------
# --- 4. State as an effect ---
# step(state, input) -> (output, new_state). The state is a value the
# caller threads through, not a hidden variable: tally_step allocates a
# new record [count, total] and never writes the one it was given, so
# every earlier state is still readable. A State effect (Get / Put)
# interpreted by a handler comes down to exactly this threading.

# tally_new(rdi = count, rsi = total) -> rax.
tally_new:
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    mov     edi, 16
    call    alloc
    mov     [rax], rbx
    mov     [rax + 8], r12
    pop     r12
    pop     rbx
    ret

# tally_step(rdi = state, rsi = x) -> rax = running mean total / count
# (idiv truncates, which is the floor for these non-negative totals),
# rdx = the new state.
tally_step:
    mov     rax, [rdi + 8]
    add     rsi, rax                # total + x
    mov     rdi, [rdi]
    inc     rdi                     # count + 1
    call    tally_new
    mov     r8, rax
    mov     rax, [r8 + 8]
    cqo
    idiv    qword ptr [r8]
    mov     rdx, r8
    ret

# ---------------------------------------------------------------------------
# --- 5. Capability passing ---
# session_check needs the time and a logger. It takes them as a capability
# record [now_code, now_env, log_code, log_env] whose address arrives in a
# register, instead of reaching for globals, so a test can pass a fake
# clock and a recording logger.

# caps_new(rdi = now_code, rsi = now_env, rdx = log_code, rcx = log_env)
#   -> rax = the record.
caps_new:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx
    mov     edi, 32
    call    alloc
    mov     [rax], rbx
    mov     [rax + 8], r12
    mov     [rax + 16], r13
    mov     [rax + 24], r14
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# session_check(rdi = caps, rsi = expires_at) -> rax = 1 valid, 0 expired.
session_check:
    push    rbx
    push    r12
    push    r13
    sub     rsp, LINE_CAP           # the log line
    mov     rbx, rdi
    mov     r12, rsi
    mov     rdi, [rbx + 8]
    call    qword ptr [rbx]         # now = caps.now()
    mov     r13, rax
    mov     rdi, rsp
    mov     rdx, r13
    lea     rsi, [rip + str_valid_at]
    cmp     r13, r12
    jl      .sc_log
    lea     rsi, [rip + str_expired_at]
.sc_log:
    call    msg_kv
    mov     rdi, [rbx + 24]
    mov     rsi, rsp
    call    qword ptr [rbx + 16]    # caps.log(line)
    xor     eax, eax
    cmp     r13, r12
    setl    al
    add     rsp, LINE_CAP
    pop     r13
    pop     r12
    pop     rbx
    ret

# Production capabilities. A real program would read clock_gettime
# (syscall 228); this file stays deterministic, so the "system clock" is a
# global that moves forward on every read. That global is exactly the
# hidden state the capability keeps out of session_check.
sys_clock:
    inc     qword ptr [rip + g_clock_reads]
    mov     rax, [rip + g_sys_time]
    lea     rcx, [rax + 1]
    mov     [rip + g_sys_time], rcx
    ret

sys_log:
    mov     rdi, rsi
    jmp     stdout_line

# Test capabilities. A clock stopped at t keeps t itself in the env word
# (a capture by value needs no memory); the logger's env is its buffer.
fake_clock:
    mov     rax, rdi
    ret

fake_logger:
    jmp     log_push                # rdi = env = log, rsi = msg

# ---------------------------------------------------------------------------
# --- 6. Functional core, imperative shell ---
# A thermostat. The core, decide(heater, temp) -> (new_heater, commands),
# is pure: it reads only its arguments and returns the commands as data,
# a list [count, then (tag, temp) pairs] in fresh arena memory.
# Hysteresis: heat on below 19, off above 21; an alarm at 15 or below. The
# shell is the only code that touches the device.

# cmds_new(rdi = capacity) -> rax.
cmds_new:
    shl     rdi, 4
    add     rdi, 8
    call    alloc
    mov     qword ptr [rax], 0
    ret

# cmds_push(rdi = list, rsi = tag, rdx = temp).
cmds_push:
    mov     rax, [rdi]
    mov     rcx, rax
    shl     rcx, 4
    mov     [rdi + 8 + rcx], rsi
    mov     [rdi + 16 + rcx], rdx
    inc     rax
    mov     [rdi], rax
    ret

# cmds_append(rdi = dst, rsi = src): push every command of src onto dst.
cmds_append:
    mov     r8, [rsi]
    xor     r9d, r9d
.ca_loop:
    cmp     r9, r8
    jge     .ca_done
    mov     rcx, r9
    shl     rcx, 4
    mov     r10, [rsi + 8 + rcx]
    mov     r11, [rsi + 16 + rcx]
    mov     rax, [rdi]
    mov     rdx, rax
    shl     rdx, 4
    mov     [rdi + 8 + rdx], r10
    mov     [rdi + 16 + rdx], r11
    inc     rax
    mov     [rdi], rax
    inc     r9
    jmp     .ca_loop
.ca_done:
    ret

# cmd_is(rdi = list, rsi = i, rdx = tag, rcx = temp) -> rax = 1 if
# command i exists and is (tag, temp).
cmd_is:
    xor     eax, eax
    cmp     rsi, [rdi]
    jae     .ci_ret
    shl     rsi, 4
    cmp     [rdi + 8 + rsi], rdx
    jne     .ci_ret
    cmp     [rdi + 16 + rsi], rcx
    jne     .ci_ret
    mov     eax, 1
.ci_ret:
    ret

# decide(rdi = heater 0/1, rsi = temp) -> rax = new heater, rdx = commands.
decide:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi                # heater
    mov     r12, rsi                # temp
    mov     edi, 2
    call    cmds_new
    mov     r13, rax                # out
    mov     r14, rbx                # next = heater
    test    rbx, rbx
    jnz     .d_on
    cmp     r12, 19                 # off and temp < 19: heat on
    jge     .d_alarm
    mov     r14d, 1
    mov     rdi, r13
    mov     esi, HEAT_ON
    mov     rdx, r12
    call    cmds_push
    jmp     .d_alarm
.d_on:
    cmp     r12, 21                 # on and temp > 21: heat off
    jle     .d_alarm
    xor     r14d, r14d
    mov     rdi, r13
    mov     esi, HEAT_OFF
    mov     rdx, r12
    call    cmds_push
.d_alarm:
    cmp     r12, 15                 # temp <= 15: alarm as well
    jg      .d_ret
    mov     rdi, r13
    mov     esi, ALARM
    mov     rdx, r12
    call    cmds_push
.d_ret:
    mov     rax, r14
    mov     rdx, r13
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# core_run(rdi = events, rsi = n) -> rax = final heater, rdx = every
# command, in order. Still pure: it only calls decide.
core_run:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    mov     r12, rsi
    lea     rdi, [r12 + r12]
    call    cmds_new
    mov     r13, rax                # all
    xor     r14d, r14d              # heater off
    xor     r15d, r15d              # i
.cr_loop:
    cmp     r15, r12
    jge     .cr_done
    mov     rdi, r14
    mov     rsi, [rbx + r15 * 8]
    call    decide
    mov     r14, rax
    mov     rdi, r13
    mov     rsi, rdx
    call    cmds_append
    inc     r15
    jmp     .cr_loop
.cr_done:
    mov     rax, r14
    mov     rdx, r13
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# shell_execute(rdi = commands): drive the device.
shell_execute:
    mov     r8, [rdi]
    xor     r9d, r9d
.se_loop:
    cmp     r9, r8
    jge     .se_done
    mov     rcx, r9
    shl     rcx, 4
    mov     rax, [rdi + 8 + rcx]
    cmp     rax, HEAT_ON
    jne     .se_off
    mov     qword ptr [rip + g_heater_pin], 1
.se_off:
    cmp     rax, HEAT_OFF
    jne     .se_alarm
    mov     qword ptr [rip + g_heater_pin], 0
.se_alarm:
    cmp     rax, ALARM
    jne     .se_next
    inc     qword ptr [rip + g_alarms_raised]
.se_next:
    inc     r9
    jmp     .se_loop
.se_done:
    ret

# shell_run(rdi = events, rsi = n) -> rax = final heater. The shell: it
# calls the same core and executes what it returns.
shell_run:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    mov     r12, rsi
    xor     r13d, r13d              # heater
    xor     r14d, r14d              # i
.sr_loop:
    cmp     r14, r12
    jge     .sr_done
    mov     rdi, r13
    mov     rsi, [rbx + r14 * 8]
    call    decide
    mov     r13, rax
    mov     rdi, rdx
    call    shell_execute
    inc     r14
    jmp     .sr_loop
.sr_done:
    mov     rax, r13
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# ---------------------------------------------------------------------------
# === Tests ===

test_effects_as_data:
    push    rbx
    push    r12
    push    r13
    call    log_new
    mov     rbx, rax                # log
    lea     rdi, [rip + test_table]
    mov     esi, 3
    mov     rdx, rbx
    call    make_handler
    mov     r12, rax
    mov     edi, 10
    call    checkout_new
    mov     rdi, r12
    lea     rsi, [rip + checkout_step]
    mov     rdx, rax
    call    handle_with
    mov     r12, rdx
    cmp     rax, FINISHED
    CHECK   e, "test handler: checkout(10) finished"
    cmp     r12, 30
    CHECK   e, "test handler: checkout(10) at rate 3 = 30"
    cmp     qword ptr [rbx], 2
    CHECK   e, "test handler captured 2 log lines"
    mov     rdi, rbx
    xor     esi, esi
    lea     rdx, [rip + exp_rate3]
    call    log_line_is
    test    rax, rax
    CHECK   nz, "log line 0 is \"rate=3\""
    mov     rdi, rbx
    mov     esi, 1
    lea     rdx, [rip + exp_total30]
    call    log_line_is
    test    rax, rax
    CHECK   nz, "log line 1 is \"total=30\""

    # The same program under the production handler: real output.
    mov     rbx, [rip + g_stdout_lines]
    mov     edi, 10
    call    checkout_new
    lea     rdi, [rip + prod_handler]
    lea     rsi, [rip + checkout_step]
    mov     rdx, rax
    call    handle_with
    mov     r12, rdx
    cmp     rax, FINISHED
    CHECK   e, "production handler: checkout(10) finished"
    cmp     r12, 40
    CHECK   e, "production handler: config rate 4 gives 40"
    mov     rax, [rip + g_stdout_lines]
    sub     rax, rbx
    cmp     rax, 2
    CHECK   e, "production handler wrote its 2 log lines to stdout"
    pop     r13
    pop     r12
    pop     rbx
    ret

# run_test_checkout(rdi = rate, rsi = log, rdx = qty) -> rax:rdx = outcome.
run_test_checkout:
    push    rbx
    push    r12
    mov     r12, rdx
    mov     rdx, rsi
    mov     rsi, rdi
    lea     rdi, [rip + test_table]
    call    make_handler
    mov     rbx, rax
    mov     rdi, r12
    call    checkout_new
    mov     rdi, rbx
    lea     rsi, [rip + checkout_step]
    mov     rdx, rax
    call    handle_with
    pop     r12
    pop     rbx
    ret

test_resumable:
    push    rbx
    push    r12
    push    r13
    call    log_new
    mov     rsi, rax
    mov     edi, 3
    mov     edx, 10
    call    run_test_checkout
    mov     rbx, rdx                # v3
    call    log_new
    mov     r13, rax                # log5
    mov     edi, 5
    mov     rsi, r13
    mov     edx, 10
    call    run_test_checkout
    mov     r12, rdx                # v5
    cmp     rbx, 30
    CHECK   e, "resumed with 3: 10 * 3 = 30"
    cmp     r12, 50
    CHECK   e, "resumed with 5: 10 * 5 = 50"
    cmp     rbx, r12
    CHECK   ne, "the answer the handler supplies decides the result"
    mov     rdi, r13
    xor     esi, esi
    lea     rdx, [rip + exp_rate5]
    call    log_line_is
    test    rax, rax
    CHECK   nz, "the resumed program logged the answer it got"
    pop     r13
    pop     r12
    pop     rbx
    ret

test_early_exit:
    push    rbx
    push    r12
    push    r13
    push    r14
    call    log_new
    mov     rbx, rax                # log
    lea     rdi, [rip + test_table]
    mov     esi, 3
    mov     rdx, rbx
    call    make_handler
    mov     r12, rax
    xor     edi, edi
    call    checkout_new
    mov     r13, rax                # state, read after the run
    mov     rdi, r12
    lea     rsi, [rip + checkout_step]
    mov     rdx, r13
    call    handle_with
    mov     r14, rdx                # reason
    cmp     rax, STOPPED
    CHECK   e, "Fail is not resumed: the run stops"
    mov     rdi, r14
    lea     rsi, [rip + str_empty_order]
    call    str_is
    test    rax, rax
    CHECK   nz, "the handler returns the failure, \"empty order\""
    cmp     qword ptr [rbx], 1
    CHECK   e, "only \"rate=3\" was logged: the \"total=\" step never ran"
    cmp     qword ptr [r13 + P_STEPS], 3
    CHECK   e, "the program ran 3 steps (Ask, Log, Fail), not 4"

    # The gotcha: a handler that forgets to resume after Log.
    call    log_new
    lea     rdi, [rip + forgetful_table]
    mov     esi, 3
    mov     rdx, rax
    call    make_handler
    mov     r12, rax
    mov     edi, 10
    call    checkout_new
    mov     r13, rax
    mov     rdi, r12
    lea     rsi, [rip + checkout_step]
    mov     rdx, r13
    call    handle_with
    mov     r14, rdx
    cmp     rax, STOPPED
    CHECK   e, "forgetful handler: the run stopped after the first Log"
    test    r14, r14
    CHECK   z, "forgetful handler: and the stop carries no reason at all"
    cmp     qword ptr [r13 + P_STEPS], 2
    CHECK   e, "forgetful handler: 2 steps ran (Ask, Log), not 4"
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

test_state_threading:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    xor     edi, edi
    xor     esi, esi
    call    tally_new
    mov     rbx, rax                # s0
    lea     r12, [rip + inputs]
    sub     rsp, 24                 # outs[3]
    mov     r13, rbx                # st
    xor     r14d, r14d              # i
.tst_loop:
    mov     rdi, r13
    mov     rsi, [r12 + r14 * 8]
    call    tally_step
    mov     [rsp + r14 * 8], rax
    mov     r13, rdx
    inc     r14
    cmp     r14, 3
    jl      .tst_loop
    cmp     qword ptr [rsp], 5
    CHECK   e, "running mean after 5: 5 / 1 = 5"
    cmp     qword ptr [rsp + 8], 7
    CHECK   e, "running mean after 10: 15 / 2 = 7"
    cmp     qword ptr [rsp + 16], 11
    CHECK   e, "running mean after 20: 35 / 3 = 11"
    add     rsp, 24
    cmp     qword ptr [r13], 3
    CHECK   e, "final state: count 3"
    cmp     qword ptr [r13 + 8], 35
    CHECK   e, "final state: total 35"
    cmp     qword ptr [rbx], 0
    CHECK   e, "initial state unchanged: count still 0"
    cmp     qword ptr [rbx + 8], 0
    CHECK   e, "initial state unchanged: total still 0"

    # Replaying from s0 gives the same final state: nothing hidden moved.
    mov     r15, rbx
    xor     r14d, r14d
.tst_replay:
    mov     rdi, r15
    mov     rsi, [r12 + r14 * 8]
    call    tally_step
    mov     r15, rdx
    inc     r14
    cmp     r14, 3
    jl      .tst_replay
    mov     rax, [r15 + 8]
    cmp     rax, [r13 + 8]
    CHECK   e, "replaying from s0 reaches the same total"
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

test_capabilities:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, [rip + g_clock_reads]      # reads0
    mov     r12, [rip + g_stdout_lines]     # lines0

    call    log_new
    mov     r13, rax                        # log_a
    lea     rdi, [rip + fake_clock]
    mov     esi, 100
    lea     rdx, [rip + fake_logger]
    mov     rcx, r13
    call    caps_new
    mov     rdi, rax
    mov     esi, 150
    call    session_check
    cmp     rax, 1
    CHECK   e, "fake clock at 100, expiry 150: valid"
    mov     rdi, r13
    xor     esi, esi
    lea     rdx, [rip + exp_valid100]
    call    log_line_is
    test    rax, rax
    CHECK   nz, "fake logger recorded \"valid at 100\""

    call    log_new
    mov     r13, rax                        # log_b
    lea     rdi, [rip + fake_clock]
    mov     esi, 200
    lea     rdx, [rip + fake_logger]
    mov     rcx, r13
    call    caps_new
    mov     rdi, rax
    mov     esi, 150
    call    session_check
    test    rax, rax
    CHECK   z, "fake clock at 200, expiry 150: expired"
    mov     rdi, r13
    xor     esi, esi
    lea     rdx, [rip + exp_expired200]
    call    log_line_is
    test    rax, rax
    CHECK   nz, "fake logger recorded \"expired at 200\""

    cmp     [rip + g_clock_reads], rbx
    CHECK   e, "the fakes never read the system clock"
    cmp     [rip + g_stdout_lines], r12
    CHECK   e, "the fakes never wrote to stdout"

    # The same function with the production capabilities.
    lea     rdi, [rip + sys_clock]
    xor     esi, esi
    lea     rdx, [rip + sys_log]
    xor     ecx, ecx
    call    caps_new
    mov     rdi, rax
    mov     esi, 150
    call    session_check
    test    rax, rax
    CHECK   z, "production clock at 1000, expiry 150: expired"
    mov     rax, [rip + g_clock_reads]
    sub     rax, rbx
    cmp     rax, 1
    CHECK   e, "production read the system clock once"
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

test_functional_core:
    push    rbx
    push    r12
    # Every threshold is hit exactly, so an off-by-one comparison fails:
    # 19 while off and 21 while on emit nothing (not below 19, not above
    # 21), 15 alarms and 16 does not. 17 arrives while the heater is on
    # and 23 while it is off, so a decide that ignores its state fails
    # too, and 14 alarms with the heater already on.
    # The pure core alone: no device, just the commands it returns.
    lea     rdi, [rip + events]
    mov     esi, 9
    call    core_run
    mov     rbx, rax                # heater
    mov     r12, rdx                # commands
    cmp     qword ptr [r12], 5
    CHECK   e, "core emitted 5 commands for 9 events"
    mov     rdi, r12
    xor     esi, esi
    mov     edx, HEAT_ON
    mov     ecx, 18
    call    cmd_is
    test    rax, rax
    CHECK   nz, "command 0 is HEAT_ON(18)"
    mov     rdi, r12
    mov     esi, 1
    mov     edx, HEAT_OFF
    mov     ecx, 22
    call    cmd_is
    test    rax, rax
    CHECK   nz, "command 1 is HEAT_OFF(22)"
    mov     rdi, r12
    mov     esi, 2
    mov     edx, HEAT_ON
    mov     ecx, 15
    call    cmd_is
    test    rax, rax
    CHECK   nz, "command 2 is HEAT_ON(15)"
    mov     rdi, r12
    mov     esi, 3
    mov     edx, ALARM
    mov     ecx, 15
    call    cmd_is
    test    rax, rax
    CHECK   nz, "command 3 is ALARM(15)"
    mov     rdi, r12
    mov     esi, 4
    mov     edx, ALARM
    mov     ecx, 14
    call    cmd_is
    test    rax, rax
    CHECK   nz, "command 4 is ALARM(14)"
    cmp     rbx, 1
    CHECK   e, "core's final state: heater on"

    mov     edi, 1
    mov     esi, 20
    call    decide
    mov     rbx, rax
    cmp     qword ptr [rdx], 0
    CHECK   e, "decide(on, 20): inside the band, no commands"
    cmp     rbx, 1
    CHECK   e, "decide(on, 20): the heater stays on"
    mov     rax, [rip + g_heater_pin]
    add     rax, [rip + g_alarms_raised]
    CHECK   z, "the core never touched the device"

    # The shell runs the same core and executes what it returns. The
    # first 6 events end just after HEAT_OFF(22): the pin must be off
    # there, which the final pin (on again) cannot show.
    lea     rdi, [rip + events]
    mov     esi, 6
    call    shell_run
    cmp     qword ptr [rip + g_heater_pin], 0
    CHECK   e, "shell, first 6 events: HEAT_OFF(22) drove the pin off"
    lea     rdi, [rip + events]
    mov     esi, 9
    call    shell_run
    cmp     rax, 1
    CHECK   e, "shell: final state heater on"
    cmp     qword ptr [rip + g_heater_pin], 1
    CHECK   e, "shell drove the heater pin on"
    cmp     qword ptr [rip + g_alarms_raised], 2
    CHECK   e, "shell raised the alarm twice"
    pop     r12
    pop     rbx
    ret

_start:
    lea     rax, [rip + heap]
    mov     [rip + heap_top], rax
    call    test_effects_as_data
    call    test_resumable
    call    test_early_exit
    call    test_state_threading
    call    test_capabilities
    call    test_functional_core

    mov     eax, 1
    mov     edi, 1
    lea     rsi, [rip + msg_pass]
    mov     edx, msg_pass_len
    syscall
    mov     eax, 60
    xor     edi, edi
    syscall

# fail(rsi = name, rdx = its length): "FAIL: name" on stderr, exit 1.
fail:
    mov     r12, rsi
    mov     r13, rdx
    mov     eax, 1
    mov     edi, 2
    lea     rsi, [rip + msg_fail]
    mov     edx, msg_fail_len
    syscall
    mov     eax, 1
    mov     edi, 2
    mov     rsi, r12
    mov     rdx, r13
    syscall
    mov     eax, 1
    mov     edi, 2
    lea     rsi, [rip + msg_nl]
    mov     edx, 1
    syscall
    mov     eax, 60
    mov     edi, 1
    syscall
