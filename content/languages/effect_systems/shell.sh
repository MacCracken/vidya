#!/usr/bin/env bash
# Vidya — Effect Systems — Bash port.
#
# Side effects made explicit: a program that returns effect requests
# (Ask, Log, Fail), handlers that decide what each one means (resume with
# an answer, or stop), state threaded through step(state, input),
# capabilities passed as parameters, and a pure core behind a thin shell.
#
# OCaml 5, Koka, Unison and Eff have native effect handlers; bash has
# none, nor closures or coroutines. A request is a "TAG payload" string,
# the program a step function over a state array, and a handler a function
# name plus bound arguments ("test_handler 3 LOG") whose case statement
# decides whether to resume. Records are global arrays, passed by name.

set -euo pipefail

# Helpers return via globals (_RET, _RESUME, ...), never via stdout,
# because `$(...)` runs in a subshell and drops every counter and log
# line it touches (cyrius field note
# "bash_subshell_clobbers_stateful_helpers").

_RET=""
_RESUME=0

PASS=0
FAIL=0
# check GOT WANT NAME: string equality, so a missing log line ("") is a
# failed check with a name, not an unbound-variable abort.
check() {
    if [[ "$1" == "$2" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $3 (got '$1', want '$2')"
    fi
}

# --- Shared helpers: the one real output channel ---
# Counted beside the write, so a check can see who printed.
STDOUT_LINES=0
stdout_line() {
    echo "  [prod] $1"
    STDOUT_LINES=$((STDOUT_LINES + 1))
}

# --- 1. Effects as data, and an interpreter ---
# A request names an effect and carries its payload; the program never
# performs it. "Done VALUE" is not an effect: it is how the program
# returns.

# The program, as it would read with native handlers (OCaml 5, Koka):
#   rate = perform Ask("rate")
#   perform Log("rate=" ^ rate)
#   if qty <= 0 then perform Fail("empty order")
#   perform Log("total=" ^ qty * rate)
#   return qty * rate
# checkout_step is that program cut at each effect. Its state array is
# the suspended rest of the program: [pc, qty, rate, steps]. `steps`
# counts how many times it ran, so a check can see what a handler cut
# short.

# checkout_new NAME QTY: a fresh program state in the global array NAME.
checkout_new() {
    declare -gA "$1"
    local -n _new=$1
    _new=([pc]=0 [qty]=$2 [rate]=0 [steps]=0)
}

# checkout_step NAME ANSWER -> _RET = the next request
checkout_step() {
    local -n _prog=$1
    local answer=$2
    _prog[steps]=$(( _prog[steps] + 1 ))
    case ${_prog[pc]} in
        0)
            _prog[pc]=1
            _RET="Ask rate" ;;
        1)
            _prog[rate]=$answer            # resumed with Ask's answer
            _prog[pc]=2
            _RET="Log rate=$answer" ;;
        2)
            _prog[pc]=3
            if (( _prog[qty] <= 0 )); then
                _RET="Fail empty order"
            else
                _RET="Log total=$(( _prog[qty] * _prog[rate] ))"
            fi ;;
        *)
            _prog[pc]=4
            _RET="Done $(( _prog[qty] * _prog[rate] ))" ;;
    esac
}

# The interpreter: run any step-function program under any handler.
# handle_with "HANDLER ARGS..." STEP_FN STATE_NAME
#   -> _OUT = Finished or Stopped, _VAL = the value or the reason.
# A handler is called with the request appended to its bound arguments
# and sets _RESUME (1 = resume, 0 = stop) and _RET (the answer, or the
# reason). The interpreter does not know what Ask, Log or Fail mean: the
# handler decides.
handle_with() {
    local -a handler
    read -r -a handler <<< "$1"
    local step=$2 state=$3 answer=0 req
    while true; do
        "$step" "$state" "$answer"
        req=$_RET
        if [[ ${req%% *} == Done ]]; then
            _OUT=Finished
            _VAL=${req#* }
            return 0
        fi
        "${handler[@]}" "$req"
        if (( _RESUME == 0 )); then
            _OUT=Stopped
            _VAL=$_RET
            return 0
        fi
        answer=$_RET
    done
}

# Production handler: Ask reads the process configuration, Log writes
# to stdout, Fail is reported and stops the program.
declare -A CONFIG=([rate]=4)

# prod_handler REQUEST
prod_handler() {
    local tag=${1%% *} payload=${1#* }
    case $tag in
        Ask)
            if [[ -v CONFIG[$payload] ]]; then
                _RESUME=1; _RET=${CONFIG[$payload]}
            else
                _RESUME=0; _RET="unknown key"
            fi ;;
        Log)  stdout_line "$payload"; _RESUME=1; _RET=0 ;;
        Fail) stdout_line "$payload"; _RESUME=0; _RET=$payload ;;
        *)    _RESUME=0; _RET="" ;;
    esac
}

# Test handler: a fixed environment (the rate it answers) and a log
# buffer it records into, both bound as arguments. No I/O.
# test_handler RATE LOG_ARRAY_NAME REQUEST
test_handler() {
    local rate=$1 req=$3
    local -n _tlog=$2
    local tag=${req%% *} payload=${req#* }
    case $tag in
        Ask)
            if [[ $payload == rate ]]; then
                _RESUME=1; _RET=$rate
            else
                _RESUME=0; _RET="unknown key"
            fi ;;
        Log)  _tlog+=("$payload"); _RESUME=1; _RET=0 ;;
        Fail) _RESUME=0; _RET=$payload ;;   # do not resume: the failure is the result
        *)    _RESUME=0; _RET="" ;;
    esac
}

# --- 2. Resumable handlers ---
# Ask is answered and the program RESUMES with the answer: handle_with
# passes the handler's _RET to the next checkout_step call. Two handlers
# that answer differently get different results from the same program.
# (A native handler resumes a captured continuation; OCaml 5's are
# one-shot: a second `continue` raises Effect.Continuation_already_resumed.)

# --- 3. A non-resuming effect is an early exit ---
# The test handler answers Fail by NOT resuming, so the rest of the
# program never runs: no "total=" line, and no further steps. That is an
# exception built from a handler, and the same mechanism is the gotcha
# when it is an accident: a handler that forgets to resume after Log
# stops the program just as silently.
# forgetful_handler RATE LOG_ARRAY_NAME REQUEST
forgetful_handler() {
    local rate=$1 req=$3
    local -n _flog=$2
    case ${req%% *} in
        Ask) _RESUME=1; _RET=$rate ;;
        Log) _flog+=("${req#* }"); _RESUME=0; _RET="" ;;   # BUG: should be _RESUME=1
        *)   _RESUME=0; _RET=${req#* } ;;
    esac
}

# --- 4. State as an effect ---
# step(state, input) -> (output, new_state). The state is a value the
# caller threads through, not a hidden variable: tally_step builds a new
# record and never writes the one it was given, so every earlier state
# is still readable. A State effect (Get / Put) interpreted by a handler
# comes down to exactly this threading. The output is the running mean,
# total / count ($(( )) division truncates, which is floor here: nothing
# is negative). A record is a global array under a fresh name; passing
# the name passes a reference, so only discipline stops a write through
# it, and the check that s0 is unchanged is what catches one.
TALLY_N=0

# tally_new COUNT TOTAL -> _RET = the name of a new [count, total] record
tally_new() {
    TALLY_N=$((TALLY_N + 1))
    _RET="TALLY_$TALLY_N"
    declare -gA "$_RET"
    local -n _rec=$_RET
    _rec=([count]=$1 [total]=$2)
}

# tally_step STATE_NAME X -> _RET = output, _STATE = the new state's name
tally_step() {
    local -n _old=$1
    tally_new $(( _old[count] + 1 )) $(( _old[total] + $2 ))
    _STATE=$_RET
    local -n _next=$_STATE
    _RET=$(( _next[total] / _next[count] ))
}

# --- 5. Capability passing ---
# session_check needs the time and a logger. It takes them as a
# capability record [now, log] of handler-style specs (a function name
# plus bound arguments) instead of calling `date` and `echo`, so a test
# can pass a fake clock and a recording logger.
# caps_new NAME "CLOCK ARGS..." "LOGGER ARGS..."
caps_new() {
    declare -gA "$1"
    local -n _caps=$1
    _caps=([now]=$2 [log]=$3)
}

# session_check CAPS_NAME EXPIRES_AT -> _RET = 1 (valid) or 0 (expired)
session_check() {
    local -n _c=$1
    local -a clock logger
    read -r -a clock <<< "${_c[now]}"
    read -r -a logger <<< "${_c[log]}"
    "${clock[@]}"
    local now=$_RET
    if (( now < $2 )); then
        "${logger[@]}" "valid at $now"
        _RET=1
    else
        "${logger[@]}" "expired at $now"
        _RET=0
    fi
}

# Production capabilities. A real program would read `date +%s` (or
# $EPOCHSECONDS); this file stays deterministic, so the "system clock"
# is a global that moves forward on every read. That global is exactly
# the hidden state the capability keeps out of session_check.
SYS_TIME=1000
CLOCK_READS=0
sys_clock() {
    CLOCK_READS=$((CLOCK_READS + 1))
    _RET=$SYS_TIME
    SYS_TIME=$((SYS_TIME + 1))
}
sys_log() { stdout_line "$1"; }

# Test capabilities: a clock stopped at t, and a logger into an array.
fake_clock() { _RET=$1; }        # fake_clock T
fake_logger() {                  # fake_logger LOG_ARRAY_NAME MSG
    local -n _flines=$1
    _flines+=("$2")
}

# --- 6. Functional core, imperative shell ---
# A thermostat. The core, decide(heater, temp) -> (new_heater, commands),
# is pure: it reads only its arguments and returns the commands as data
# ("HEAT_ON 18"). _RET and _CMDS are its return channel, since a bash
# function cannot return values; it reads neither. Hysteresis: heat on
# below 19, off above 21; an alarm at 15 or below. Heater 0 = off,
# 1 = on. The shell is the only code that touches the device.

# decide HEATER TEMP -> _RET = new heater, _CMDS = commands
decide() {
    local heater=$1 temp=$2
    _CMDS=()
    _RET=$heater
    if (( heater == 0 && temp < 19 )); then
        _RET=1
        _CMDS+=("HEAT_ON $temp")
    fi
    if (( heater == 1 && temp > 21 )); then
        _RET=0
        _CMDS+=("HEAT_OFF $temp")
    fi
    if (( temp <= 15 )); then
        _CMDS+=("ALARM $temp")
    fi
}

# The core over a run of events: still pure (it only calls decide).
# core_run EVENTS... -> _RET = final heater, _ALL = every command
core_run() {
    local heater=0 temp
    local -a all=()
    for temp in "$@"; do
        decide "$heater" "$temp"
        heater=$_RET
        all+=("${_CMDS[@]}")
    done
    _ALL=("${all[@]}")
    _RET=$heater
}

# The shell: the device registers it drives, and the loop that executes
# each command the core returns.
HEATER_PIN=0
ALARMS_RAISED=0
shell_execute() {                # shell_execute CMD...
    local cmd
    for cmd in "$@"; do
        case ${cmd%% *} in
            HEAT_ON)  HEATER_PIN=1 ;;
            HEAT_OFF) HEATER_PIN=0 ;;
            ALARM)    ALARMS_RAISED=$((ALARMS_RAISED + 1)) ;;
        esac
    done
}
shell_run() {                    # shell_run EVENTS... -> _RET = final heater
    local heater=0 temp
    for temp in "$@"; do
        decide "$heater" "$temp"
        heater=$_RET
        shell_execute "${_CMDS[@]}"
    done
    _RET=$heater
}

# === Tests ===

test_effects_as_data() {
    LOG_T=()
    checkout_new PROG_T 10
    handle_with "test_handler 3 LOG_T" checkout_step PROG_T
    check "$_OUT" Finished "test handler: checkout(10) finished"
    check "$_VAL" 30 "test handler: checkout(10) at rate 3 = 30"
    check "${#LOG_T[@]}" 2 "test handler captured 2 log lines"
    check "${LOG_T[0]-}" "rate=3" 'log line 0 is "rate=3"'
    check "${LOG_T[1]-}" "total=30" 'log line 1 is "total=30"'

    # The same program under the production handler: real output.
    local before=$STDOUT_LINES
    checkout_new PROG_P 10
    handle_with prod_handler checkout_step PROG_P
    check "$_OUT" Finished "production handler: checkout(10) finished"
    check "$_VAL" 40 "production handler: config rate 4 gives 40"
    check $(( STDOUT_LINES - before )) 2 "production handler wrote its 2 log lines to stdout"
}

test_resumable() {
    LOG_3=()
    LOG_5=()
    checkout_new PROG_3 10
    handle_with "test_handler 3 LOG_3" checkout_step PROG_3
    local v3=$_VAL
    checkout_new PROG_5 10
    handle_with "test_handler 5 LOG_5" checkout_step PROG_5
    local v5=$_VAL
    check "$v3" 30 "resumed with 3: 10 * 3 = 30"
    check "$v5" 50 "resumed with 5: 10 * 5 = 50"
    local differ=0
    if [[ $v3 != "$v5" ]]; then differ=1; fi
    check "$differ" 1 "the answer the handler supplies decides the result"
    check "${LOG_5[0]-}" "rate=5" "the resumed program logged the answer it got"
}

test_early_exit() {
    LOG_E=()
    checkout_new PROG_E 0
    handle_with "test_handler 3 LOG_E" checkout_step PROG_E
    check "$_OUT" Stopped "Fail is not resumed: the run stops"
    check "$_VAL" "empty order" 'the handler returns the failure, "empty order"'
    check "${#LOG_E[@]}" 1 'only "rate=3" was logged: the "total=" step never ran'
    check "${PROG_E[steps]}" 3 "the program ran 3 steps (Ask, Log, Fail), not 4"

    # The gotcha: a handler that forgets to resume after Log.
    LOG_F=()
    checkout_new PROG_F 10
    handle_with "forgetful_handler 3 LOG_F" checkout_step PROG_F
    check "$_OUT" Stopped "forgetful handler: the run stopped after the first Log"
    check "$_VAL" "" "forgetful handler: and the stop carries no reason at all"
    check "${PROG_F[steps]}" 2 "forgetful handler: 2 steps ran (Ask, Log), not 4"
}

test_state_threading() {
    local inputs=(5 10 20) outs=() x
    tally_new 0 0
    local s0=$_RET st=$_RET
    for x in "${inputs[@]}"; do
        tally_step "$st" "$x"
        outs+=("$_RET")
        st=$_STATE
    done
    local -n _init=$s0 _final=$st
    check "${outs[0]-}" 5 "running mean after 5: 5 / 1 = 5"
    check "${outs[1]-}" 7 "running mean after 10: 15 / 2 = 7"
    check "${outs[2]-}" 11 "running mean after 20: 35 / 3 = 11"
    check "${_final[count]}" 3 "final state: count 3"
    check "${_final[total]}" 35 "final state: total 35"
    check "${_init[count]}" 0 "initial state unchanged: count still 0"
    check "${_init[total]}" 0 "initial state unchanged: total still 0"

    # Replaying from s0 gives the same final state: nothing hidden moved.
    local again=$s0
    for x in "${inputs[@]}"; do
        tally_step "$again" "$x"
        again=$_STATE
    done
    local -n _again=$again
    check "${_again[total]}" "${_final[total]}" "replaying from s0 reaches the same total"
}

test_capabilities() {
    local reads0=$CLOCK_READS lines0=$STDOUT_LINES

    LOG_A=()
    caps_new AT100 "fake_clock 100" "fake_logger LOG_A"
    session_check AT100 150
    check "$_RET" 1 "fake clock at 100, expiry 150: valid"
    check "${LOG_A[0]-}" "valid at 100" 'fake logger recorded "valid at 100"'

    LOG_B=()
    caps_new AT200 "fake_clock 200" "fake_logger LOG_B"
    session_check AT200 150
    check "$_RET" 0 "fake clock at 200, expiry 150: expired"
    check "${LOG_B[0]-}" "expired at 200" 'fake logger recorded "expired at 200"'

    check $(( CLOCK_READS - reads0 )) 0 "the fakes never read the system clock"
    check $(( STDOUT_LINES - lines0 )) 0 "the fakes never wrote to stdout"

    # The same function with the production capabilities.
    caps_new PROD sys_clock sys_log
    session_check PROD 150
    check "$_RET" 0 "production clock at 1000, expiry 150: expired"
    check $(( CLOCK_READS - reads0 )) 1 "production read the system clock once"
}

test_functional_core() {
    # Every threshold is hit exactly, so an off-by-one comparison fails:
    # 19 while off and 21 while on emit nothing (not below 19, not above
    # 21), 15 alarms and 16 does not. 17 arrives while the heater is on
    # and 23 while it is off, so a decide that ignores its state fails
    # too, and 14 alarms with the heater already on.
    local events=(19 18 17 21 22 23 15 16 14)

    # The pure core alone: no device, just the commands it returns.
    core_run "${events[@]}"
    local heater=$_RET
    check "${#_ALL[@]}" 5 "core emitted 5 commands for 9 events"
    check "${_ALL[0]-}" "HEAT_ON 18" "command 0 is HEAT_ON(18)"
    check "${_ALL[1]-}" "HEAT_OFF 22" "command 1 is HEAT_OFF(22)"
    check "${_ALL[2]-}" "HEAT_ON 15" "command 2 is HEAT_ON(15)"
    check "${_ALL[3]-}" "ALARM 15" "command 3 is ALARM(15)"
    check "${_ALL[4]-}" "ALARM 14" "command 4 is ALARM(14)"
    check "$heater" 1 "core's final state: heater on"

    decide 1 20
    check "${#_CMDS[@]}" 0 "decide(on, 20): inside the band, no commands"
    check "$_RET" 1 "decide(on, 20): the heater stays on"
    check $(( HEATER_PIN + ALARMS_RAISED )) 0 "the core never touched the device"

    # The shell runs the same core and executes what it returns. The
    # first 6 events end just after HEAT_OFF(22): the pin must be off
    # there, which the final pin (on again) cannot show.
    shell_run "${events[@]:0:6}"
    check "$HEATER_PIN" 0 "shell, first 6 events: HEAT_OFF(22) drove the pin off"
    shell_run "${events[@]}"
    check "$_RET" 1 "shell: final state heater on"
    check "$HEATER_PIN" 1 "shell drove the heater pin on"
    check "$ALARMS_RAISED" 2 "shell raised the alarm twice"
}

main() {
    test_effects_as_data
    test_resumable
    test_early_exit
    test_state_threading
    test_capabilities
    test_functional_core
    if (( FAIL > 0 )); then
        echo "$PASS passed, $FAIL failed"
        exit 1
    fi
    echo "All effect system examples passed."
}

main
exit 0
