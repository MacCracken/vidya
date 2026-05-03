#!/usr/bin/env bash
# Vidya — Audio Synthesis — Bash port. Q15 fixed-point.
# Helpers return via _RET (subshell-clobbers-stateful-helpers gotcha).

set -euo pipefail

SCALE=15
ONE=32768
PHASE_MASK=65535
PHASE_HALF=32768

_RET=0

q_mul() {
    local a=$1 b=$2
    local p=$(( a * b ))
    if (( p < 0 )); then _RET=$(( -((-p) >> SCALE) ))
    else _RET=$(( p >> SCALE )); fi
}

phase_advance() {
    _RET=$(( ($1 + $2) & PHASE_MASK ))
}

declare -a SINE_TABLE=(
    0 12540 23170 30274 32767 30274 23170 12540
    0 -12540 -23170 -30274 -32767 -30274 -23170 -12540
)

osc_sine()   { local idx=$(( $1 >> 12 )); _RET=${SINE_TABLE[$idx]}; }
osc_saw()    { _RET=$(( $1 - PHASE_HALF )); }
osc_square() { (( $1 < PHASE_HALF )) && _RET=32767 || _RET=-32767; }

# Envelope state
ENV_IDLE=0
ENV_ATTACK=1
ENV_DECAY=2
ENV_SUSTAIN=3
ENV_RELEASE=4

declare env_state=0 env_level=0 env_stage_samples=0 env_release_start=0
declare env_attack_samples=0 env_decay_samples=0 env_sustain_level=0 env_release_samples=0

env_set_params() {
    env_attack_samples=$1
    env_decay_samples=$2
    env_sustain_level=$3
    env_release_samples=$4
}

env_reset() {
    env_state=$ENV_IDLE
    env_level=0
    env_stage_samples=0
    env_release_start=0
}

env_gate_on() {
    env_state=$ENV_ATTACK
    env_stage_samples=0
}

env_gate_off() {
    if (( env_state == ENV_IDLE )); then _RET=0; return; fi
    env_release_start=$env_level
    env_state=$ENV_RELEASE
    env_stage_samples=0
    _RET=1
}

env_step() {
    if (( env_state == ENV_IDLE )); then env_level=0; _RET=0; return; fi

    if (( env_state == ENV_ATTACK )); then
        local inc=$(( ONE / env_attack_samples ))
        env_level=$(( env_level + inc ))
        env_stage_samples=$(( env_stage_samples + 1 ))
        if (( env_stage_samples >= env_attack_samples )); then
            env_level=$ONE
            env_state=$ENV_DECAY
            env_stage_samples=0
        fi
        _RET=$env_level
        return
    fi

    if (( env_state == ENV_DECAY )); then
        local diff=$(( ONE - env_sustain_level ))
        local dec=$(( diff / env_decay_samples ))
        env_level=$(( env_level - dec ))
        env_stage_samples=$(( env_stage_samples + 1 ))
        if (( env_stage_samples >= env_decay_samples )); then
            env_level=$env_sustain_level
            env_state=$ENV_SUSTAIN
            env_stage_samples=0
        fi
        _RET=$env_level
        return
    fi

    if (( env_state == ENV_SUSTAIN )); then
        env_level=$env_sustain_level
        _RET=$env_level
        return
    fi

    if (( env_state == ENV_RELEASE )); then
        local dec=$(( env_release_start / env_release_samples ))
        env_level=$(( env_level - dec ))
        env_stage_samples=$(( env_stage_samples + 1 ))
        if (( env_stage_samples >= env_release_samples )); then
            env_level=0
            env_state=$ENV_IDLE
            env_stage_samples=0
        fi
        _RET=$env_level
        return
    fi

    _RET=0
}

# Voice
WAVE_SINE=0
WAVE_SAW=1
WAVE_SQUARE=2

declare voice_waveform=0 voice_phase=0 voice_phase_inc=0

voice_init() {
    voice_waveform=$1
    voice_phase=0
    voice_phase_inc=$2
}

voice_oscillator() {
    if (( voice_waveform == WAVE_SINE )); then osc_sine "$1"; return; fi
    if (( voice_waveform == WAVE_SAW )); then osc_saw "$1"; return; fi
    if (( voice_waveform == WAVE_SQUARE )); then osc_square "$1"; return; fi
    _RET=0
}

voice_step() {
    voice_oscillator "$voice_phase"; local osc=$_RET
    phase_advance "$voice_phase" "$voice_phase_inc"
    voice_phase=$_RET
    env_step; local e=$_RET
    q_mul "$osc" "$e"
}

pass_count=0
fail_count=0
check() {
    if (( $1 == 1 )); then pass_count=$(( pass_count + 1 ))
    else fail_count=$(( fail_count + 1 )); echo "  FAIL: $2" >&2; fi
}
eq() { [[ $1 -eq $2 ]] && _RET=1 || _RET=0; }

# Tests
phase_advance 60000 10000; eq $_RET 4464; check $_RET "phase wraps"
phase_advance 0 1000;      eq $_RET 1000; check $_RET "phase advances"

osc_sine 0;     eq $_RET 0;     check $_RET "sin(0)"
osc_sine 16384; eq $_RET 32767; check $_RET "sin(π/2)"
osc_sine 32768; eq $_RET 0;     check $_RET "sin(π)"
osc_sine 49152; eq $_RET -32767; check $_RET "sin(3π/2)"

osc_saw 0;          eq $_RET -$PHASE_HALF; check $_RET "saw(0)"
osc_saw $PHASE_HALF; eq $_RET 0;            check $_RET "saw(π)"
osc_saw 65535;      eq $_RET 32767;        check $_RET "saw(near max)"

osc_square 0;          eq $_RET 32767;  check $_RET "square first half"
osc_square $PHASE_HALF; eq $_RET -32767; check $_RET "square second half"
osc_square 32767;      eq $_RET 32767;  check $_RET "square just before half"
osc_square 65535;      eq $_RET -32767; check $_RET "square at end"

# env attack
env_set_params 4 4 16384 4
env_reset
env_gate_on
for i in 1 2 3 4; do env_step; done
eq $env_state $ENV_DECAY; check $_RET "attack → decay"
eq $env_level $ONE;       check $_RET "level = ONE"

# env decay → sustain
env_set_params 4 4 16384 4
env_reset
env_gate_on
for i in 1 2 3 4 5 6 7 8; do env_step; done
eq $env_state $ENV_SUSTAIN; check $_RET "decay → sustain"
eq $env_level 16384;        check $_RET "level = sustain"

# env sustain holds
env_set_params 4 4 16384 4
env_reset
env_gate_on
for i in 1 2 3 4 5 6 7 8; do env_step; done
for (( i=0; i<100; i++ )); do env_step; done
eq $env_state $ENV_SUSTAIN; check $_RET "sustain holds"
eq $env_level 16384;        check $_RET "level held"

# env release → idle
env_set_params 4 4 16384 4
env_reset
env_gate_on
for i in 1 2 3 4 5 6 7 8; do env_step; done
env_gate_off
eq $env_release_start 16384; check $_RET "release_start captured"
for i in 1 2 3 4; do env_step; done
eq $env_state $ENV_IDLE; check $_RET "release → idle"
eq $env_level 0;         check $_RET "level = 0"

# gate_off during attack
env_set_params 8 4 16384 4
env_reset
env_gate_on
env_step; env_step
env_gate_off
eq $env_release_start 8192; check $_RET "release captures partial-attack level"

# voice silent when idle
env_set_params 4 4 16384 4
env_reset
voice_init $WAVE_SINE 8192
voice_step; eq $_RET 0; check $_RET "voice silent when idle"

# voice audible when gated
env_set_params 4 4 16384 4
env_reset
voice_init $WAVE_SINE 8192
env_gate_on
any_nonzero=0
for (( i=0; i<16; i++ )); do
    voice_step
    if (( _RET != 0 )); then any_nonzero=1; fi
done
eq $any_nonzero 1; check $_RET "voice audible when gated"

echo "=== audio_synthesis ==="
echo "$pass_count passed, $fail_count failed ($(( pass_count + fail_count )) total)"
[[ $fail_count -eq 0 ]] || exit 1
