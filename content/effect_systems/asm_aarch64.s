// Vidya — Effect Systems in AArch64 Assembly
//
// A program that yields effect requests (Ask, Log, Fail) instead of doing
// I/O, handlers that decide what each one means (resume with an answer, or
// stop), state threaded through step(state, input), capabilities passed as
// parameters, and a pure core behind a thin shell. Mirrors all 49 checks
// of cyrius.cyr.
//
// OCaml 5, Koka, Unison and Eff have native effect handlers. Here the
// program is a step function that returns its next request as a (tag,
// payload) pair in x0:x1; the interpreter dispatches on the tag through
// the handler's table of arm addresses and feeds the answer back in x1.

.global _start

// Effect tags (an arm table is indexed by the first three) and outcomes.
.equ EFF_ASK, 0
.equ EFF_LOG, 1
.equ EFF_FAIL, 2
.equ EFF_DONE, 3
.equ FINISHED, 0
.equ STOPPED, 1

// Program state: [pc, qty, rate, steps, msg[LINE_CAP]].
.equ P_PC, 0
.equ P_QTY, 8
.equ P_RATE, 16
.equ P_STEPS, 24
.equ P_MSG, 32
.equ LINE_CAP, 32
.equ P_SIZE, 32 + LINE_CAP

// Log buffer: [count, then LOG_CAP lines of LINE_CAP bytes].
.equ LOG_CAP, 8
.equ LOG_SIZE, 8 + LOG_CAP * LINE_CAP

// Thermostat commands.
.equ HEAT_ON, 1
.equ HEAT_OFF, 2
.equ ALARM, 3

.equ HEAP_SIZE, 8192
.equ SYS_WRITE, 64
.equ SYS_EXIT, 93

.macro LDADDR reg, sym
    adrp    \reg, \sym
    add     \reg, \reg, :lo12:\sym
.endm

// CHECK cc, "name": after a cmp, carry on if condition cc holds, else
// print "FAIL: name" and exit 1.
.macro CHECK cc, msg
    b.\cc   .Lok\@
    .pushsection .rodata
.Lmsg\@: .ascii "\msg"
.Lend\@:
    .popsection
    LDADDR  x1, .Lmsg\@
    mov     x2, #(.Lend\@ - .Lmsg\@)
    b       fail
.Lok\@:
.endm

.section .bss
.align 3
heap:            .skip HEAP_SIZE
heap_end:
heap_top:        .skip 8
g_stdout_lines:  .skip 8        // lines the production handlers wrote
g_clock_reads:   .skip 8        // reads of the production "system clock"
g_heater_pin:    .skip 8        // the device the shell drives
g_alarms_raised: .skip 8

.section .data
.align 3
g_config_rate:   .quad 4        // the process configuration prod_ask reads
g_sys_time:      .quad 1000     // the deterministic "system clock"
// The production handler: [arm table, env]. It captures nothing.
prod_handler:    .quad prod_table, 0

.section .rodata
.align 3
// A handler's arm table: one code address per effect tag, indexed by tag.
prod_table:      .quad prod_ask, prod_log, prod_fail
test_table:      .quad test_ask, test_log, test_fail
forgetful_table: .quad forgetful_ask, forgetful_log, forgetful_fail

inputs:          .quad 5, 10, 20
// Every threshold is hit exactly (19 and 21 emit nothing, 15 alarms, 16
// does not), and 17 / 23 arrive with the heater already on / off.
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

.text

// ---------------------------------------------------------------------------
// --- Shared helpers: an arena, strings, a log buffer, stdout ---

// alloc(x0 = bytes, a multiple of 8) -> x0. A bump arena in .bss that
// never frees (and so hands out zeroed memory). Clobbers x9-x12.
alloc:
    LDADDR  x9, heap_top
    ldr     x10, [x9]
    add     x11, x10, x0
    LDADDR  x12, heap_end
    cmp     x11, x12
    b.hi    .alloc_full
    str     x11, [x9]
    mov     x0, x10
    ret
.alloc_full:
    LDADDR  x1, msg_oom
    mov     x2, #msg_oom_len
    b       fail

// str_is(x0 = p, x1 = s) -> x0 = 1 if the NUL-terminated strings match.
// Null-safe for the checks: p = 0 (a missing line or reason) is 0, not a
// crash.
str_is:
    cbz     x0, .si_ret
.si_loop:
    ldrb    w2, [x0], #1
    ldrb    w3, [x1], #1
    cmp     w2, w3
    b.ne    .si_no
    cbnz    w2, .si_loop
    mov     x0, #1
    ret
.si_no:
    mov     x0, #0
.si_ret:
    ret

// strlen(x0) -> x0.
strlen:
    mov     x1, x0
.sl_loop:
    ldrb    w2, [x1]
    cbz     w2, .sl_done
    add     x1, x1, #1
    b       .sl_loop
.sl_done:
    sub     x0, x1, x0
    ret

// msg_kv(x0 = dst, x1 = prefix, x2 = n >= 0) -> x0 = dst.
// "rate=" + 3 -> "rate=3". AAPCS64 has no red zone, so the digits are
// built backwards in a 32-byte frame, then copied out. The longest prefix
// (11) plus 20 digits and the NUL fits LINE_CAP.
msg_kv:
    sub     sp, sp, #32
    mov     x9, x0                  // write cursor
.mk_prefix:
    ldrb    w10, [x1], #1
    cbz     w10, .mk_digits
    strb    w10, [x9], #1
    b       .mk_prefix
.mk_digits:
    add     x11, sp, #32            // digits grow down from the frame's top
    mov     x12, #10
.mk_div:
    udiv    x13, x2, x12
    msub    x14, x13, x12, x2       // n % 10
    add     w14, w14, #48           // '0'
    strb    w14, [x11, #-1]!
    mov     x2, x13
    cbnz    x2, .mk_div
    add     x12, sp, #32
.mk_copy:
    ldrb    w10, [x11], #1
    strb    w10, [x9], #1
    cmp     x11, x12
    b.lo    .mk_copy
    strb    wzr, [x9]
    add     sp, sp, #32
    ret

// log_new() -> x0 = an empty log buffer.
log_new:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     x0, #LOG_SIZE
    bl      alloc
    str     xzr, [x0]
    ldp     x29, x30, [sp], #16
    ret

// log_push(x0 = log, x1 = msg): copy msg into the next line. A copy, not
// the pointer: a Log payload points into the program's state, which the
// next step overwrites.
log_push:
    ldr     x2, [x0]
    cmp     x2, #LOG_CAP
    b.hs    .lp_full
    mov     x4, #LINE_CAP
    add     x3, x0, #8
    madd    x3, x2, x4, x3          // this line's slot
    mov     x4, #(LINE_CAP - 1)     // room, leaving the NUL
.lp_copy:
    ldrb    w5, [x1], #1
    cbz     w5, .lp_end
    cbz     x4, .lp_end
    strb    w5, [x3], #1
    sub     x4, x4, #1
    b       .lp_copy
.lp_end:
    strb    wzr, [x3]
    add     x2, x2, #1
    str     x2, [x0]
.lp_full:
    ret

// log_line_is(x0 = log, x1 = i, x2 = s) -> x0 = 1 if line i exists and
// equals s.
log_line_is:
    ldr     x3, [x0]
    cmp     x1, x3
    b.hs    .lli_no
    mov     x4, #LINE_CAP
    add     x0, x0, #8
    madd    x0, x1, x4, x0
    mov     x1, x2
    b       str_is
.lli_no:
    mov     x0, #0
    ret

// stdout_line(x0 = msg): "  [prod] msg\n" to stdout, and count it. The
// one real output channel, used only by the production handlers.
stdout_line:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    mov     x19, x0
    mov     x0, #1
    LDADDR  x1, str_prod
    mov     x2, #str_prod_len
    mov     x8, #SYS_WRITE
    svc     #0
    mov     x0, x19
    bl      strlen
    mov     x2, x0
    mov     x0, #1
    mov     x1, x19
    mov     x8, #SYS_WRITE
    svc     #0
    mov     x0, #1
    LDADDR  x1, msg_nl
    mov     x2, #1
    mov     x8, #SYS_WRITE
    svc     #0
    LDADDR  x9, g_stdout_lines
    ldr     x10, [x9]
    add     x10, x10, #1
    str     x10, [x9]
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// ---------------------------------------------------------------------------
// --- 1. Effects as data, and an interpreter ---
// A request is (tag, payload) in x0:x1: Ask(key), Log(msg), Fail(reason),
// or Done(value), which is not an effect but how the program returns. The
// program never performs an effect; it hands the request back.
//
// The program, as it would read with native handlers (OCaml 5, Koka):
//   rate = perform Ask("rate")
//   perform Log("rate=" ^ rate)
//   if qty <= 0 then perform Fail("empty order")
//   perform Log("total=" ^ qty * rate)
//   return qty * rate
// checkout_step is that program cut at each effect. Its state record is the
// suspended rest of the program; `steps` counts how many times it ran, so a
// check can see what a handler cut short.

// checkout_new(x0 = qty) -> x0 = a fresh program state.
checkout_new:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    mov     x19, x0
    mov     x0, #P_SIZE
    bl      alloc
    str     xzr, [x0, #P_PC]
    str     x19, [x0, #P_QTY]
    str     xzr, [x0, #P_RATE]
    str     xzr, [x0, #P_STEPS]
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// checkout_step(x0 = state, x1 = answer) -> x0 = tag, x1 = payload.
checkout_step:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    mov     x19, x0
    ldr     x2, [x19, #P_STEPS]
    add     x2, x2, #1
    str     x2, [x19, #P_STEPS]
    ldr     x2, [x19, #P_PC]
    cbz     x2, .cs_ask
    cmp     x2, #1
    b.eq    .cs_rate
    cmp     x2, #2
    b.eq    .cs_total
    mov     x2, #4
    str     x2, [x19, #P_PC]
    ldr     x2, [x19, #P_QTY]
    ldr     x3, [x19, #P_RATE]
    mul     x1, x2, x3
    mov     x0, #EFF_DONE
    b       .cs_ret
.cs_ask:
    mov     x2, #1
    str     x2, [x19, #P_PC]
    mov     x0, #EFF_ASK
    LDADDR  x1, str_rate
    b       .cs_ret
.cs_rate:
    str     x1, [x19, #P_RATE]      // resumed with Ask's answer
    mov     x2, #2
    str     x2, [x19, #P_PC]
    mov     x2, x1
    add     x0, x19, #P_MSG
    LDADDR  x1, str_rate_eq
    bl      msg_kv
    mov     x0, #EFF_LOG
    add     x1, x19, #P_MSG
    b       .cs_ret
.cs_total:
    mov     x2, #3
    str     x2, [x19, #P_PC]
    ldr     x2, [x19, #P_QTY]
    cmp     x2, #0
    b.le    .cs_fail
    ldr     x3, [x19, #P_RATE]
    mul     x2, x2, x3
    add     x0, x19, #P_MSG
    LDADDR  x1, str_total_eq
    bl      msg_kv
    mov     x0, #EFF_LOG
    add     x1, x19, #P_MSG
    b       .cs_ret
.cs_fail:
    mov     x0, #EFF_FAIL
    LDADDR  x1, str_empty_order
.cs_ret:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// handle_with(x0 = handler, x1 = step code, x2 = state)
//   -> x0 = FINISHED or STOPPED, x1 = the value or the stop's reason.
// A handler is a record [arm table, env]; an arm is (x0 = env,
// x1 = payload) -> x0 = resume (1) or stop (0), x1 = the answer or the
// reason. The interpreter knows nothing about what an effect means: it
// calls the arm the tag selects. Resume = the answer goes into the next
// step call. Stop = it never calls step again.
handle_with:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    mov     x19, x0                 // handler
    mov     x20, x1                 // step
    mov     x21, x2                 // program state
    mov     x22, #0                 // answer
.hw_loop:
    mov     x0, x21
    mov     x1, x22
    blr     x20                     // x0 = tag, x1 = payload
    cmp     x0, #EFF_DONE
    b.eq    .hw_finished
    b.hi    .hw_no_arm              // a tag with no arm: stop, no reason
    ldr     x9, [x19]               // the arm table
    ldr     x9, [x9, x0, lsl #3]    // the arm for this tag
    ldr     x0, [x19, #8]           // the env
    blr     x9
    cbz     x0, .hw_stopped
    mov     x22, x1                 // resume with the answer
    b       .hw_loop
.hw_no_arm:
    mov     x1, #0
.hw_stopped:
    mov     x0, #STOPPED
    b       .hw_ret
.hw_finished:
    mov     x0, #FINISHED
.hw_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// Production handler: Ask reads the process configuration, Log writes to
// stdout, Fail is reported and stops the program.
prod_ask:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     x0, x1
    LDADDR  x1, str_rate
    bl      str_is
    cbz     x0, .pa_unknown
    mov     x0, #1
    LDADDR  x1, g_config_rate
    ldr     x1, [x1]
    b       .pa_ret
.pa_unknown:
    mov     x0, #0
    LDADDR  x1, str_unknown_key
.pa_ret:
    ldp     x29, x30, [sp], #16
    ret

prod_log:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     x0, x1
    bl      stdout_line
    mov     x0, #1
    mov     x1, #0
    ldp     x29, x30, [sp], #16
    ret

prod_fail:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    mov     x19, x1
    mov     x0, x1
    bl      stdout_line
    mov     x0, #0
    mov     x1, x19
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// make_handler(x0 = table, x1 = rate, x2 = log) -> x0 = a handler record
// [table, env] with its env [rate, log] right after it: a closure, written
// out. No I/O, nothing global.
make_handler:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x0, #32
    bl      alloc
    str     x19, [x0]
    add     x9, x0, #16
    str     x9, [x0, #8]
    str     x20, [x0, #16]
    str     x21, [x0, #24]
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// Test handler: answers Ask from its env, records Log into its log buffer.
test_ask:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    mov     x19, x0
    mov     x0, x1
    LDADDR  x1, str_rate
    bl      str_is
    cbz     x0, .ta_unknown
    mov     x0, #1
    ldr     x1, [x19]               // env.rate
    b       .ta_ret
.ta_unknown:
    mov     x0, #0
    LDADDR  x1, str_unknown_key
.ta_ret:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

test_log:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    ldr     x0, [x0, #8]            // env.log
    bl      log_push
    mov     x0, #1
    mov     x1, #0
    ldp     x29, x30, [sp], #16
    ret

test_fail:                          // do not resume: the failure is the result
    mov     x0, #0                  // x1 is already the reason
    ret

// --- 2. Resumable handlers ---
// Ask is answered and the program RESUMES with the answer: handle_with
// passes the arm's x1 to the next checkout_step call in x1. Two handlers
// that answer differently get different results from the same program.
// (A native handler resumes a captured continuation, and OCaml 5's are
// one-shot. Here the continuation is a state record in memory, so a copy
// could be resumed twice: nothing stops that.)

// --- 3. A non-resuming effect is an early exit ---
// test_fail answers by NOT resuming, so the rest of the program never runs:
// no "total=" line, and no further steps. That is an exception built from
// a handler. The same mechanism is the gotcha when it is an accident: an
// arm that forgets to resume after Log stops the program just as silently.
forgetful_ask:
    ldr     x1, [x0]                // env.rate
    mov     x0, #1
    ret

forgetful_log:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    ldr     x0, [x0, #8]
    bl      log_push
    mov     x0, #0                  // BUG: should be mov x0, #1 (resume)
    mov     x1, #0
    ldp     x29, x30, [sp], #16
    ret

forgetful_fail:
    mov     x0, #0
    ret

// ---------------------------------------------------------------------------
// --- 4. State as an effect ---
// step(state, input) -> (output, new_state). The state is a value the
// caller threads through, not a hidden variable: tally_step allocates a
// new record [count, total] and never writes the one it was given, so
// every earlier state is still readable. A State effect (Get / Put)
// interpreted by a handler comes down to exactly this threading.

// tally_new(x0 = count, x1 = total) -> x0.
tally_new:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    mov     x19, x0
    mov     x20, x1
    mov     x0, #16
    bl      alloc
    str     x19, [x0]
    str     x20, [x0, #8]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// tally_step(x0 = state, x1 = x) -> x0 = running mean total / count (sdiv
// truncates, which is the floor for these non-negative totals), x1 = the
// new state.
tally_step:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    ldr     x2, [x0, #8]
    add     x1, x1, x2              // total + x
    ldr     x0, [x0]
    add     x0, x0, #1              // count + 1
    bl      tally_new
    ldr     x2, [x0]
    ldr     x3, [x0, #8]
    mov     x1, x0
    sdiv    x0, x3, x2
    ldp     x29, x30, [sp], #16
    ret

// ---------------------------------------------------------------------------
// --- 5. Capability passing ---
// session_check needs the time and a logger. It takes them as a capability
// record [now_code, now_env, log_code, log_env] whose address arrives in a
// register, instead of reaching for globals, so a test can pass a fake
// clock and a recording logger.

// caps_new(x0 = now_code, x1 = now_env, x2 = log_code, x3 = log_env)
//   -> x0 = the record.
caps_new:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x0, #32
    bl      alloc
    stp     x19, x20, [x0]
    stp     x21, x22, [x0, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// session_check(x0 = caps, x1 = expires_at) -> x0 = 1 valid, 0 expired.
// Frame: fp/lr, x19-x21, then the 32-byte log line at sp + 48.
session_check:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]
    mov     x19, x0
    mov     x20, x1
    ldr     x9, [x19]
    ldr     x0, [x19, #8]
    blr     x9                      // now = caps.now()
    mov     x21, x0
    add     x0, sp, #48
    mov     x2, x21
    LDADDR  x1, str_valid_at
    cmp     x21, x20
    b.lt    .sc_log
    LDADDR  x1, str_expired_at
.sc_log:
    bl      msg_kv
    ldr     x9, [x19, #16]
    ldr     x0, [x19, #24]
    add     x1, sp, #48
    blr     x9                      // caps.log(line)
    cmp     x21, x20
    cset    x0, lt
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret

// Production capabilities. A real program would read clock_gettime
// (syscall 113); this file stays deterministic, so the "system clock" is a
// global that moves forward on every read. That global is exactly the
// hidden state the capability keeps out of session_check.
sys_clock:
    LDADDR  x9, g_clock_reads
    ldr     x10, [x9]
    add     x10, x10, #1
    str     x10, [x9]
    LDADDR  x9, g_sys_time
    ldr     x0, [x9]
    add     x10, x0, #1
    str     x10, [x9]
    ret

sys_log:
    mov     x0, x1
    b       stdout_line

// Test capabilities. A clock stopped at t keeps t itself in the env word
// (a capture by value needs no memory), so it returns its x0 unchanged;
// the logger's env is its buffer.
fake_clock:
    ret

fake_logger:
    b       log_push                // x0 = env = log, x1 = msg

// ---------------------------------------------------------------------------
// --- 6. Functional core, imperative shell ---
// A thermostat. The core, decide(heater, temp) -> (new_heater, commands),
// is pure: it reads only its arguments and returns the commands as data,
// a list [count, then (tag, temp) pairs] in fresh arena memory.
// Hysteresis: heat on below 19, off above 21; an alarm at 15 or below. The
// shell is the only code that touches the device.

// cmds_new(x0 = capacity) -> x0.
cmds_new:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    lsl     x0, x0, #4
    add     x0, x0, #8
    bl      alloc
    str     xzr, [x0]
    ldp     x29, x30, [sp], #16
    ret

// cmds_push(x0 = list, x1 = tag, x2 = temp).
cmds_push:
    ldr     x3, [x0]
    add     x4, x0, x3, lsl #4
    stp     x1, x2, [x4, #8]
    add     x3, x3, #1
    str     x3, [x0]
    ret

// cmds_append(x0 = dst, x1 = src): push every command of src onto dst.
cmds_append:
    ldr     x2, [x1]
    mov     x3, #0
.ca_loop:
    cmp     x3, x2
    b.ge    .ca_done
    add     x4, x1, x3, lsl #4
    ldp     x5, x6, [x4, #8]
    ldr     x7, [x0]
    add     x4, x0, x7, lsl #4
    stp     x5, x6, [x4, #8]
    add     x7, x7, #1
    str     x7, [x0]
    add     x3, x3, #1
    b       .ca_loop
.ca_done:
    ret

// cmd_is(x0 = list, x1 = i, x2 = tag, x3 = temp) -> x0 = 1 if command i
// exists and is (tag, temp).
cmd_is:
    ldr     x4, [x0]
    cmp     x1, x4
    b.hs    .ci_no
    add     x4, x0, x1, lsl #4
    ldp     x5, x6, [x4, #8]
    cmp     x5, x2
    b.ne    .ci_no
    cmp     x6, x3
    b.ne    .ci_no
    mov     x0, #1
    ret
.ci_no:
    mov     x0, #0
    ret

// decide(x0 = heater 0/1, x1 = temp) -> x0 = new heater, x1 = commands.
decide:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    mov     x19, x0                 // heater
    mov     x20, x1                 // temp
    mov     x0, #2
    bl      cmds_new
    mov     x21, x0                 // out
    mov     x22, x19                // next = heater
    cbnz    x19, .d_on
    cmp     x20, #19                // off and temp < 19: heat on
    b.ge    .d_alarm
    mov     x22, #1
    mov     x0, x21
    mov     x1, #HEAT_ON
    mov     x2, x20
    bl      cmds_push
    b       .d_alarm
.d_on:
    cmp     x20, #21                // on and temp > 21: heat off
    b.le    .d_alarm
    mov     x22, #0
    mov     x0, x21
    mov     x1, #HEAT_OFF
    mov     x2, x20
    bl      cmds_push
.d_alarm:
    cmp     x20, #15                // temp <= 15: alarm as well
    b.gt    .d_ret
    mov     x0, x21
    mov     x1, #ALARM
    mov     x2, x20
    bl      cmds_push
.d_ret:
    mov     x0, x22
    mov     x1, x21
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// core_run(x0 = events, x1 = n) -> x0 = final heater, x1 = every command,
// in order. Still pure: it only calls decide.
core_run:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    str     x23, [sp, #48]
    mov     x19, x0                 // events
    mov     x20, x1                 // n
    lsl     x0, x20, #1
    bl      cmds_new
    mov     x21, x0                 // all
    mov     x22, #0                 // heater off
    mov     x23, #0                 // i
.cr_loop:
    cmp     x23, x20
    b.ge    .cr_done
    mov     x0, x22
    ldr     x1, [x19, x23, lsl #3]
    bl      decide
    mov     x22, x0
    mov     x0, x21
    bl      cmds_append             // x1 = this event's commands
    add     x23, x23, #1
    b       .cr_loop
.cr_done:
    mov     x0, x22
    mov     x1, x21
    ldr     x23, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// shell_execute(x0 = commands): drive the device.
shell_execute:
    ldr     x2, [x0]
    mov     x3, #0
    mov     x7, #1
.se_loop:
    cmp     x3, x2
    b.ge    .se_done
    add     x4, x0, x3, lsl #4
    ldr     x5, [x4, #8]
    cmp     x5, #HEAT_ON
    b.ne    .se_off
    LDADDR  x6, g_heater_pin
    str     x7, [x6]
.se_off:
    cmp     x5, #HEAT_OFF
    b.ne    .se_alarm
    LDADDR  x6, g_heater_pin
    str     xzr, [x6]
.se_alarm:
    cmp     x5, #ALARM
    b.ne    .se_next
    LDADDR  x6, g_alarms_raised
    ldr     x8, [x6]
    add     x8, x8, #1
    str     x8, [x6]
.se_next:
    add     x3, x3, #1
    b       .se_loop
.se_done:
    ret

// shell_run(x0 = events, x1 = n) -> x0 = final heater. The shell: it calls
// the same core and executes what it returns.
shell_run:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    mov     x19, x0
    mov     x20, x1
    mov     x21, #0                 // heater
    mov     x22, #0                 // i
.sr_loop:
    cmp     x22, x20
    b.ge    .sr_done
    mov     x0, x21
    ldr     x1, [x19, x22, lsl #3]
    bl      decide
    mov     x21, x0
    mov     x0, x1
    bl      shell_execute
    add     x22, x22, #1
    b       .sr_loop
.sr_done:
    mov     x0, x21
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// ---------------------------------------------------------------------------
// === Tests ===

test_effects_as_data:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]
    bl      log_new
    mov     x19, x0                 // log
    LDADDR  x0, test_table
    mov     x1, #3
    mov     x2, x19
    bl      make_handler
    mov     x20, x0
    mov     x0, #10
    bl      checkout_new
    mov     x2, x0
    mov     x0, x20
    LDADDR  x1, checkout_step
    bl      handle_with
    mov     x20, x1
    cmp     x0, #FINISHED
    CHECK   eq, "test handler: checkout(10) finished"
    cmp     x20, #30
    CHECK   eq, "test handler: checkout(10) at rate 3 = 30"
    ldr     x0, [x19]
    cmp     x0, #2
    CHECK   eq, "test handler captured 2 log lines"
    mov     x0, x19
    mov     x1, #0
    LDADDR  x2, exp_rate3
    bl      log_line_is
    cmp     x0, #1
    CHECK   eq, "log line 0 is \"rate=3\""
    mov     x0, x19
    mov     x1, #1
    LDADDR  x2, exp_total30
    bl      log_line_is
    cmp     x0, #1
    CHECK   eq, "log line 1 is \"total=30\""

    // The same program under the production handler: real output.
    LDADDR  x9, g_stdout_lines
    ldr     x19, [x9]               // before
    mov     x0, #10
    bl      checkout_new
    mov     x2, x0
    LDADDR  x0, prod_handler
    LDADDR  x1, checkout_step
    bl      handle_with
    mov     x20, x1
    cmp     x0, #FINISHED
    CHECK   eq, "production handler: checkout(10) finished"
    cmp     x20, #40
    CHECK   eq, "production handler: config rate 4 gives 40"
    LDADDR  x9, g_stdout_lines
    ldr     x0, [x9]
    sub     x0, x0, x19
    cmp     x0, #2
    CHECK   eq, "production handler wrote its 2 log lines to stdout"
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// run_test_checkout(x0 = rate, x1 = log, x2 = qty) -> x0:x1 = outcome.
run_test_checkout:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    mov     x20, x2
    mov     x2, x1
    mov     x1, x0
    LDADDR  x0, test_table
    bl      make_handler
    mov     x19, x0
    mov     x0, x20
    bl      checkout_new
    mov     x2, x0
    mov     x0, x19
    LDADDR  x1, checkout_step
    bl      handle_with
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

test_resumable:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]
    bl      log_new
    mov     x1, x0
    mov     x0, #3
    mov     x2, #10
    bl      run_test_checkout
    mov     x19, x1                 // v3
    bl      log_new
    mov     x21, x0                 // log5
    mov     x0, #5
    mov     x1, x21
    mov     x2, #10
    bl      run_test_checkout
    mov     x20, x1                 // v5
    cmp     x19, #30
    CHECK   eq, "resumed with 3: 10 * 3 = 30"
    cmp     x20, #50
    CHECK   eq, "resumed with 5: 10 * 5 = 50"
    cmp     x19, x20
    CHECK   ne, "the answer the handler supplies decides the result"
    mov     x0, x21
    mov     x1, #0
    LDADDR  x2, exp_rate5
    bl      log_line_is
    cmp     x0, #1
    CHECK   eq, "the resumed program logged the answer it got"
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

test_early_exit:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    bl      log_new
    mov     x19, x0                 // log
    LDADDR  x0, test_table
    mov     x1, #3
    mov     x2, x19
    bl      make_handler
    mov     x20, x0
    mov     x0, #0
    bl      checkout_new
    mov     x21, x0                 // state, read after the run
    mov     x0, x20
    LDADDR  x1, checkout_step
    mov     x2, x21
    bl      handle_with
    mov     x22, x1                 // reason
    cmp     x0, #STOPPED
    CHECK   eq, "Fail is not resumed: the run stops"
    mov     x0, x22
    LDADDR  x1, str_empty_order
    bl      str_is
    cmp     x0, #1
    CHECK   eq, "the handler returns the failure, \"empty order\""
    ldr     x0, [x19]
    cmp     x0, #1
    CHECK   eq, "only \"rate=3\" was logged: the \"total=\" step never ran"
    ldr     x0, [x21, #P_STEPS]
    cmp     x0, #3
    CHECK   eq, "the program ran 3 steps (Ask, Log, Fail), not 4"

    // The gotcha: a handler that forgets to resume after Log.
    bl      log_new
    mov     x2, x0
    LDADDR  x0, forgetful_table
    mov     x1, #3
    bl      make_handler
    mov     x20, x0
    mov     x0, #10
    bl      checkout_new
    mov     x21, x0
    mov     x0, x20
    LDADDR  x1, checkout_step
    mov     x2, x21
    bl      handle_with
    mov     x22, x1
    cmp     x0, #STOPPED
    CHECK   eq, "forgetful handler: the run stopped after the first Log"
    cmp     x22, #0
    CHECK   eq, "forgetful handler: and the stop carries no reason at all"
    ldr     x0, [x21, #P_STEPS]
    cmp     x0, #2
    CHECK   eq, "forgetful handler: 2 steps ran (Ask, Log), not 4"
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// Frame: fp/lr, x19-x23, then outs[3] at sp + 64.
test_state_threading:
    stp     x29, x30, [sp, #-96]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    str     x23, [sp, #48]
    mov     x0, #0
    mov     x1, #0
    bl      tally_new
    mov     x19, x0                 // s0
    LDADDR  x20, inputs
    mov     x21, x19                // st
    mov     x22, #0                 // i
.tst_loop:
    mov     x0, x21
    ldr     x1, [x20, x22, lsl #3]
    bl      tally_step
    add     x9, sp, #64
    str     x0, [x9, x22, lsl #3]   // outs[i]
    mov     x21, x1
    add     x22, x22, #1
    cmp     x22, #3
    b.lt    .tst_loop
    ldr     x0, [sp, #64]
    cmp     x0, #5
    CHECK   eq, "running mean after 5: 5 / 1 = 5"
    ldr     x0, [sp, #72]
    cmp     x0, #7
    CHECK   eq, "running mean after 10: 15 / 2 = 7"
    ldr     x0, [sp, #80]
    cmp     x0, #11
    CHECK   eq, "running mean after 20: 35 / 3 = 11"
    ldr     x0, [x21]
    cmp     x0, #3
    CHECK   eq, "final state: count 3"
    ldr     x0, [x21, #8]
    cmp     x0, #35
    CHECK   eq, "final state: total 35"
    ldr     x0, [x19]
    cmp     x0, #0
    CHECK   eq, "initial state unchanged: count still 0"
    ldr     x0, [x19, #8]
    cmp     x0, #0
    CHECK   eq, "initial state unchanged: total still 0"

    // Replaying from s0 gives the same final state: nothing hidden moved.
    mov     x23, x19
    mov     x22, #0
.tst_replay:
    mov     x0, x23
    ldr     x1, [x20, x22, lsl #3]
    bl      tally_step
    mov     x23, x1
    add     x22, x22, #1
    cmp     x22, #3
    b.lt    .tst_replay
    ldr     x0, [x23, #8]
    ldr     x1, [x21, #8]
    cmp     x0, x1
    CHECK   eq, "replaying from s0 reaches the same total"
    ldr     x23, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #96
    ret

test_capabilities:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]
    LDADDR  x9, g_clock_reads
    ldr     x19, [x9]               // reads0
    LDADDR  x9, g_stdout_lines
    ldr     x20, [x9]               // lines0

    bl      log_new
    mov     x21, x0                 // log_a
    LDADDR  x0, fake_clock
    mov     x1, #100
    LDADDR  x2, fake_logger
    mov     x3, x21
    bl      caps_new
    mov     x1, #150
    bl      session_check
    cmp     x0, #1
    CHECK   eq, "fake clock at 100, expiry 150: valid"
    mov     x0, x21
    mov     x1, #0
    LDADDR  x2, exp_valid100
    bl      log_line_is
    cmp     x0, #1
    CHECK   eq, "fake logger recorded \"valid at 100\""

    bl      log_new
    mov     x21, x0                 // log_b
    LDADDR  x0, fake_clock
    mov     x1, #200
    LDADDR  x2, fake_logger
    mov     x3, x21
    bl      caps_new
    mov     x1, #150
    bl      session_check
    cmp     x0, #0
    CHECK   eq, "fake clock at 200, expiry 150: expired"
    mov     x0, x21
    mov     x1, #0
    LDADDR  x2, exp_expired200
    bl      log_line_is
    cmp     x0, #1
    CHECK   eq, "fake logger recorded \"expired at 200\""

    LDADDR  x9, g_clock_reads
    ldr     x0, [x9]
    cmp     x0, x19
    CHECK   eq, "the fakes never read the system clock"
    LDADDR  x9, g_stdout_lines
    ldr     x0, [x9]
    cmp     x0, x20
    CHECK   eq, "the fakes never wrote to stdout"

    // The same function with the production capabilities.
    LDADDR  x0, sys_clock
    mov     x1, #0
    LDADDR  x2, sys_log
    mov     x3, #0
    bl      caps_new
    mov     x1, #150
    bl      session_check
    cmp     x0, #0
    CHECK   eq, "production clock at 1000, expiry 150: expired"
    LDADDR  x9, g_clock_reads
    ldr     x0, [x9]
    sub     x0, x0, x19
    cmp     x0, #1
    CHECK   eq, "production read the system clock once"
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

test_functional_core:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    // Every threshold is hit exactly, so an off-by-one comparison fails:
    // 19 while off and 21 while on emit nothing (not below 19, not above
    // 21), 15 alarms and 16 does not. 17 arrives while the heater is on
    // and 23 while it is off, so a decide that ignores its state fails
    // too, and 14 alarms with the heater already on.
    // The pure core alone: no device, just the commands it returns.
    LDADDR  x0, events
    mov     x1, #9
    bl      core_run
    mov     x19, x0                 // heater
    mov     x20, x1                 // commands
    ldr     x0, [x20]
    cmp     x0, #5
    CHECK   eq, "core emitted 5 commands for 9 events"
    mov     x0, x20
    mov     x1, #0
    mov     x2, #HEAT_ON
    mov     x3, #18
    bl      cmd_is
    cmp     x0, #1
    CHECK   eq, "command 0 is HEAT_ON(18)"
    mov     x0, x20
    mov     x1, #1
    mov     x2, #HEAT_OFF
    mov     x3, #22
    bl      cmd_is
    cmp     x0, #1
    CHECK   eq, "command 1 is HEAT_OFF(22)"
    mov     x0, x20
    mov     x1, #2
    mov     x2, #HEAT_ON
    mov     x3, #15
    bl      cmd_is
    cmp     x0, #1
    CHECK   eq, "command 2 is HEAT_ON(15)"
    mov     x0, x20
    mov     x1, #3
    mov     x2, #ALARM
    mov     x3, #15
    bl      cmd_is
    cmp     x0, #1
    CHECK   eq, "command 3 is ALARM(15)"
    mov     x0, x20
    mov     x1, #4
    mov     x2, #ALARM
    mov     x3, #14
    bl      cmd_is
    cmp     x0, #1
    CHECK   eq, "command 4 is ALARM(14)"
    cmp     x19, #1
    CHECK   eq, "core's final state: heater on"

    mov     x0, #1
    mov     x1, #20
    bl      decide
    mov     x19, x0
    ldr     x0, [x1]
    cmp     x0, #0
    CHECK   eq, "decide(on, 20): inside the band, no commands"
    cmp     x19, #1
    CHECK   eq, "decide(on, 20): the heater stays on"
    LDADDR  x9, g_heater_pin
    ldr     x0, [x9]
    LDADDR  x9, g_alarms_raised
    ldr     x1, [x9]
    add     x0, x0, x1
    cmp     x0, #0
    CHECK   eq, "the core never touched the device"

    // The shell runs the same core and executes what it returns. The
    // first 6 events end just after HEAT_OFF(22): the pin must be off
    // there, which the final pin (on again) cannot show.
    LDADDR  x0, events
    mov     x1, #6
    bl      shell_run
    LDADDR  x9, g_heater_pin
    ldr     x0, [x9]
    cmp     x0, #0
    CHECK   eq, "shell, first 6 events: HEAT_OFF(22) drove the pin off"
    LDADDR  x0, events
    mov     x1, #9
    bl      shell_run
    cmp     x0, #1
    CHECK   eq, "shell: final state heater on"
    LDADDR  x9, g_heater_pin
    ldr     x0, [x9]
    cmp     x0, #1
    CHECK   eq, "shell drove the heater pin on"
    LDADDR  x9, g_alarms_raised
    ldr     x0, [x9]
    cmp     x0, #2
    CHECK   eq, "shell raised the alarm twice"
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

_start:
    LDADDR  x0, heap
    LDADDR  x1, heap_top
    str     x0, [x1]
    bl      test_effects_as_data
    bl      test_resumable
    bl      test_early_exit
    bl      test_state_threading
    bl      test_capabilities
    bl      test_functional_core

    mov     x0, #1
    LDADDR  x1, msg_pass
    mov     x2, #msg_pass_len
    mov     x8, #SYS_WRITE
    svc     #0
    mov     x0, #0
    mov     x8, #SYS_EXIT
    svc     #0

// fail(x1 = name, x2 = its length): "FAIL: name" on stderr, exit 1.
fail:
    mov     x19, x1
    mov     x20, x2
    mov     x0, #2
    LDADDR  x1, msg_fail
    mov     x2, #msg_fail_len
    mov     x8, #SYS_WRITE
    svc     #0
    mov     x0, #2
    mov     x1, x19
    mov     x2, x20
    mov     x8, #SYS_WRITE
    svc     #0
    mov     x0, #2
    LDADDR  x1, msg_nl
    mov     x2, #1
    mov     x8, #SYS_WRITE
    svc     #0
    mov     x0, #1
    mov     x8, #SYS_EXIT
    svc     #0
