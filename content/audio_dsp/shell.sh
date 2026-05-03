#!/usr/bin/env bash
# Vidya — Audio DSP — Bash port. Q15 fixed-point.
# Helpers return via _RET (subshell-clobbers-stateful-helpers gotcha).

set -euo pipefail

SCALE=15
ONE=32768
SMAX=32767
SMIN=-32767

_RET=0

q_mul() {
    local a=$1 b=$2
    local p=$(( a * b ))
    if (( p < 0 )); then
        _RET=$(( -((-p) >> SCALE) ))
    else
        _RET=$(( p >> SCALE ))
    fi
}

abs_i() { _RET=$(( $1 < 0 ? -$1 : $1 )); }

clip() {
    local s=$1
    if (( s > SMAX )); then _RET=$SMAX
    elif (( s < SMIN )); then _RET=$SMIN
    else _RET=$s; fi
}

# Biquad state
declare bq_b0=0 bq_b1=0 bq_b2=0 bq_a1=0 bq_a2=0
declare bq_x1=0 bq_x2=0 bq_y1=0 bq_y2=0

biquad_set() {
    bq_b0=$1; bq_b1=$2; bq_b2=$3; bq_a1=$4; bq_a2=$5
    bq_x1=0; bq_x2=0; bq_y1=0; bq_y2=0
}

biquad_lowpass_1pole() {
    local a_q15=$1
    biquad_set "$a_q15" 0 0 $(( a_q15 - ONE )) 0
}

biquad_step() {
    local x=$1 t y
    q_mul "$bq_b0" "$x"; y=$_RET
    q_mul "$bq_b1" "$bq_x1"; t=$_RET; y=$(( y + t ))
    q_mul "$bq_b2" "$bq_x2"; t=$_RET; y=$(( y + t ))
    q_mul "$bq_a1" "$bq_y1"; t=$_RET; y=$(( y - t ))
    q_mul "$bq_a2" "$bq_y2"; t=$_RET; y=$(( y - t ))
    bq_x2=$bq_x1; bq_x1=$x
    bq_y2=$bq_y1; bq_y1=$y
    _RET=$y
}

# FIR uses parallel arrays passed by name reference.
fir_step() {
    local -n taps=$1
    local -n history=$2
    local x_new=$3
    local n=${#taps[@]} i j t acc=0
    for (( i=n-1; i>0; i-- )); do history[i]=${history[$((i-1))]}; done
    history[0]=$x_new
    for (( j=0; j<n; j++ )); do
        q_mul "${taps[j]}" "${history[j]}"; t=$_RET
        acc=$(( acc + t ))
    done
    _RET=$acc
}

peak() {
    local -n buf=$1
    local p=0 i a
    for s in "${buf[@]}"; do
        abs_i "$s"; a=$_RET
        if (( a > p )); then p=$a; fi
    done
    _RET=$p
}

mean_absolute() {
    local -n buf=$1
    local sum=0 a n=${#buf[@]}
    for s in "${buf[@]}"; do
        abs_i "$s"; a=$_RET
        sum=$(( sum + a ))
    done
    _RET=$(( sum / n ))
}

pass_count=0
fail_count=0
check() {
    if (( $1 == 1 )); then pass_count=$(( pass_count + 1 ))
    else fail_count=$(( fail_count + 1 )); echo "  FAIL: $2" >&2; fi
}
eq() { [[ $1 -eq $2 ]] && _RET=1 || _RET=0; }
between() { (( $1 >= $2 && $1 <= $3 )) && _RET=1 || _RET=0; }

q_mul $ONE 100;       eq $_RET 100;       check $_RET "ONE * 100 = 100"
q_mul $((ONE/2)) $((ONE/2)); eq $_RET $((ONE/4)); check $_RET "0.5 * 0.5 = 0.25"
q_mul $((ONE/2)) $SMAX; between $_RET 16383 16384; check $_RET "0.5 * SMAX in [16383,16384]"

clip 50000;  eq $_RET $SMAX; check $_RET "clip(50000) = SMAX"
clip -50000; eq $_RET $SMIN; check $_RET "clip(-50000) = SMIN"
clip 1234;   eq $_RET 1234;  check $_RET "clip(1234) unchanged"

biquad_lowpass_1pole 3277
for (( i=0; i<200; i++ )); do biquad_step 30000; done
between $bq_y1 29900 30100; check $_RET "DC settled near 30000"

biquad_lowpass_1pole 3277
for (( i=0; i<200; i++ )); do
    if (( (i & 1) == 0 )); then biquad_step 20000; else biquad_step -20000; fi
done
abs_i $bq_y1; (( _RET < 2000 )) && check 1 "Nyquist heavily attenuated" || check 0 "Nyquist heavily attenuated"

declare -a taps_id=($ONE 0 0)
declare -a hist_id=(0 0 0)
fir_step taps_id hist_id 1234; eq $_RET 1234; check $_RET "identity 1234"
fir_step taps_id hist_id 5678; eq $_RET 5678; check $_RET "identity 5678"

third=$(( ONE / 3 ))
declare -a taps_avg=($third $third $third)
declare -a hist_avg=(0 0 0)
fir_step taps_avg hist_avg 9000
fir_step taps_avg hist_avg 9000
fir_step taps_avg hist_avg 9000
between $_RET 8990 9010; check $_RET "moving avg = 9000"

declare -a peakbuf=(100 -5000 200 3000 -1500)
peak peakbuf; eq $_RET 5000; check $_RET "peak = 5000"

declare -a constbuf=(4000 4000 4000 4000 4000 4000 4000 4000)
mean_absolute constbuf; eq $_RET 4000; check $_RET "mean-abs constant = constant"

declare -a altbuf=(4000 -4000 4000 -4000 4000 -4000 4000 -4000)
mean_absolute altbuf; eq $_RET 4000; check $_RET "mean-abs alternating = 4000"

echo "=== audio_dsp ==="
echo "$pass_count passed, $fail_count failed ($(( pass_count + fail_count )) total)"
[[ $fail_count -eq 0 ]] || exit 1
