// Vidya — Audio Synthesis — Go port. Q15 fixed-point.

package main

import (
	"fmt"
	"os"
)

const (
	SCALE      = 15
	ONE        = 32768
	PHASE_MASK = 65535
	PHASE_HALF = 32768
)

func qMul(a, b int64) int64 {
	p := a * b
	if p < 0 {
		return -((-p) >> SCALE)
	}
	return p >> SCALE
}

func phaseAdvance(current, inc int64) int64 {
	return (current + inc) & PHASE_MASK
}

var sineTable = [16]int64{
	0, 12540, 23170, 30274, 32767, 30274, 23170, 12540,
	0, -12540, -23170, -30274, -32767, -30274, -23170, -12540,
}

func oscSine(phase int64) int64 { return sineTable[phase>>12] }
func oscSaw(phase int64) int64  { return phase - PHASE_HALF }
func oscSquare(phase int64) int64 {
	if phase < PHASE_HALF {
		return 32767
	}
	return -32767
}

const (
	EnvIdle    = 0
	EnvAttack  = 1
	EnvDecay   = 2
	EnvSustain = 3
	EnvRelease = 4
)

type Adsr struct {
	state           int
	level           int64
	stageSamples    int64
	releaseStart    int64
	attackSamples   int64
	decaySamples    int64
	sustainLevel    int64
	releaseSamples  int64
}

func (a *Adsr) SetParams(attack, decay, sustain, release int64) {
	a.attackSamples = attack
	a.decaySamples = decay
	a.sustainLevel = sustain
	a.releaseSamples = release
}

func (a *Adsr) GateOn() {
	a.state = EnvAttack
	a.stageSamples = 0
}

func (a *Adsr) GateOff() bool {
	if a.state == EnvIdle {
		return false
	}
	a.releaseStart = a.level
	a.state = EnvRelease
	a.stageSamples = 0
	return true
}

func (a *Adsr) Step() int64 {
	switch a.state {
	case EnvIdle:
		a.level = 0
		return 0
	case EnvAttack:
		inc := int64(ONE) / a.attackSamples
		a.level += inc
		a.stageSamples++
		if a.stageSamples >= a.attackSamples {
			a.level = ONE
			a.state = EnvDecay
			a.stageSamples = 0
		}
		return a.level
	case EnvDecay:
		dec := (int64(ONE) - a.sustainLevel) / a.decaySamples
		a.level -= dec
		a.stageSamples++
		if a.stageSamples >= a.decaySamples {
			a.level = a.sustainLevel
			a.state = EnvSustain
			a.stageSamples = 0
		}
		return a.level
	case EnvSustain:
		a.level = a.sustainLevel
		return a.level
	case EnvRelease:
		dec := a.releaseStart / a.releaseSamples
		a.level -= dec
		a.stageSamples++
		if a.stageSamples >= a.releaseSamples {
			a.level = 0
			a.state = EnvIdle
			a.stageSamples = 0
		}
		return a.level
	}
	return 0
}

const (
	WaveSine   = 0
	WaveSaw    = 1
	WaveSquare = 2
)

type Voice struct {
	waveform int
	phase    int64
	phaseInc int64
}

func (v *Voice) oscillator(phase int64) int64 {
	switch v.waveform {
	case WaveSine:
		return oscSine(phase)
	case WaveSaw:
		return oscSaw(phase)
	case WaveSquare:
		return oscSquare(phase)
	}
	return 0
}

func (v *Voice) Step(env *Adsr) int64 {
	osc := v.oscillator(v.phase)
	v.phase = phaseAdvance(v.phase, v.phaseInc)
	e := env.Step()
	return qMul(osc, e)
}

var passCount, failCount int

func check(cond bool, name string) {
	if cond {
		passCount++
	} else {
		failCount++
		fmt.Println("  FAIL:", name)
	}
}

func main() {
	check(phaseAdvance(60000, 10000) == 4464, "phase wraps")
	check(phaseAdvance(0, 1000) == 1000, "phase advances")

	check(oscSine(0) == 0, "sin(0) = 0")
	check(oscSine(16384) == 32767, "sin(π/2) = ONE")
	check(oscSine(32768) == 0, "sin(π) = 0")
	check(oscSine(49152) == -32767, "sin(3π/2) = -ONE")

	check(oscSaw(0) == -PHASE_HALF, "saw(0) = -ONE")
	check(oscSaw(PHASE_HALF) == 0, "saw(π) = 0")
	check(oscSaw(65535) == 32767, "saw(near max)")

	check(oscSquare(0) == 32767, "square first half")
	check(oscSquare(PHASE_HALF) == -32767, "square second half")
	check(oscSquare(32767) == 32767, "square just before half")
	check(oscSquare(65535) == -32767, "square at end")

	{
		var e Adsr
		e.SetParams(4, 4, 16384, 4)
		e.GateOn()
		for i := 0; i < 4; i++ {
			e.Step()
		}
		check(e.state == EnvDecay, "attack → decay")
		check(e.level == ONE, "level = ONE")
	}
	{
		var e Adsr
		e.SetParams(4, 4, 16384, 4)
		e.GateOn()
		for i := 0; i < 8; i++ {
			e.Step()
		}
		check(e.state == EnvSustain, "decay → sustain")
		check(e.level == 16384, "level = sustain")
	}
	{
		var e Adsr
		e.SetParams(4, 4, 16384, 4)
		e.GateOn()
		for i := 0; i < 8; i++ {
			e.Step()
		}
		for i := 0; i < 100; i++ {
			e.Step()
		}
		check(e.state == EnvSustain, "sustain holds")
		check(e.level == 16384, "level held")
	}
	{
		var e Adsr
		e.SetParams(4, 4, 16384, 4)
		e.GateOn()
		for i := 0; i < 8; i++ {
			e.Step()
		}
		e.GateOff()
		check(e.releaseStart == 16384, "release_start captured")
		for i := 0; i < 4; i++ {
			e.Step()
		}
		check(e.state == EnvIdle, "release → idle")
		check(e.level == 0, "level = 0")
	}
	{
		var e Adsr
		e.SetParams(8, 4, 16384, 4)
		e.GateOn()
		e.Step()
		e.Step()
		e.GateOff()
		check(e.releaseStart == 8192, "release captures partial-attack level")
	}
	{
		var e Adsr
		e.SetParams(4, 4, 16384, 4)
		v := Voice{waveform: WaveSine, phaseInc: 8192}
		check(v.Step(&e) == 0, "voice silent when idle")
	}
	{
		var e Adsr
		e.SetParams(4, 4, 16384, 4)
		v := Voice{waveform: WaveSine, phaseInc: 8192}
		e.GateOn()
		anyNonzero := false
		for i := 0; i < 16; i++ {
			if v.Step(&e) != 0 {
				anyNonzero = true
			}
		}
		check(anyNonzero, "voice audible when gated")
	}

	fmt.Println("=== audio_synthesis ===")
	fmt.Printf("%d passed, %d failed (%d total)\n", passCount, failCount, passCount+failCount)
	if failCount > 0 {
		os.Exit(1)
	}
}
