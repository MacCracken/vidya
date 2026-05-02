// Vidya — Game AI Decision Making in Go
//
// Stat-driven AI scoring with PCG PRNG, urgency-multiplied shooting,
// and weighted action selection. Go's `uint64` overflow wraps silently
// (defined behavior), so the PCG state update is a one-liner with no
// explicit masking. iota typed constants give readable Action variants
// at zero runtime cost.

package main

import "fmt"

type Action int
const (
	ActShoot Action = iota
	ActDunk; ActPass; ActDrive; ActSteal
)

type Stats struct {
	Speed, Shooting, Dunking, Passing  int64
	Stealing, Blocking, Clutch, Rebounding int64
}

const (
	pcgMult uint64 = 6364136223846793005
	pcgInc  uint64 = 1442695040888963407
)

var rngState uint64 = 12345

func rngSeed(s uint64) { rngState = s }

func rngNext() int64 {
	rngState = rngState*pcgMult + pcgInc // uint64 wraps silently
	return int64((rngState >> 33) & 0x7fffffff)
}

func rngRange(max int64) int64 {
	if max <= 0 {
		return 0
	}
	return rngNext() % max
}

func probCheck(stat int64) bool {
	return rngRange(100) < stat*10
}

func evaluateShoot(shooting, distFx int64) int64 {
	base := shooting * 10
	distUnits := distFx >> 16
	score := base - distUnits
	if score < 0 {
		return 0
	}
	return score
}

func evaluateDunk(dunking, distFx int64) int64 {
	if (distFx >> 16) > 3 {
		return 0
	}
	return dunking * 15
}

func evaluatePass(passing int64) int64 { return passing * 8 }
func evaluateDrive(speed int64) int64  { return speed * 6 }

func applyUrgency(score, shotClock int64) int64 {
	urgency := (24 - shotClock) / 4
	if urgency < 1 {
		urgency = 1
	}
	return score * urgency
}

func addNoise(score int64) int64 {
	noise := rngRange(21) - 10
	r := score + noise
	if r < 0 {
		return 0
	}
	return r
}

func aiDecideOffense(s *Stats, distFx, shotClock int64) Action {
	shoot := addNoise(applyUrgency(evaluateShoot(s.Shooting, distFx), shotClock))
	dunk := addNoise(evaluateDunk(s.Dunking, distFx))
	pass := addNoise(evaluatePass(s.Passing))
	drive := addNoise(evaluateDrive(s.Speed))

	best := ActShoot
	bestScore := shoot
	if dunk > bestScore {
		best, bestScore = ActDunk, dunk
	}
	if pass > bestScore {
		best, bestScore = ActPass, pass
	}
	if drive > bestScore {
		best, bestScore = ActDrive, drive
	}
	_ = bestScore
	return best
}

func mustEq[T comparable](got, want T, msg string) {
	if got != want {
		panic(fmt.Sprintf("FAIL: %s: got %v, want %v", msg, got, want))
	}
}

func mustTrue(cond bool, msg string) {
	if !cond {
		panic("FAIL: " + msg)
	}
}

func main() {
	// evaluate_shoot
	mustEq(evaluateShoot(9, 3<<16), int64(87), "shoot: 9*10 - 3")
	mustEq(evaluateShoot(1, 20<<16), int64(0), "low stat + far = 0")
	mustEq(evaluateShoot(10, 0), int64(100), "stat 10 at rim")

	// evaluate_dunk
	mustEq(evaluateDunk(8, 2<<16), int64(120), "dunk: stat 8 * 15")
	mustEq(evaluateDunk(10, 10<<16), int64(0), "too far to dunk")

	// urgency
	mustEq(applyUrgency(50, 24), int64(50), "full clock")
	mustEq(applyUrgency(50, 2), int64(250), "low clock x5")
	mustEq(applyUrgency(50, 0), int64(300), "empty clock x6")

	// prob_check
	rngSeed(42)
	for i := 0; i < 20; i++ {
		mustTrue(probCheck(10), "stat 10 always passes")
	}
	rngSeed(99)
	for i := 0; i < 20; i++ {
		mustTrue(!probCheck(0), "stat 0 always fails")
	}

	// PRNG determinism
	rngSeed(77777)
	a1 := rngNext()
	a2 := rngNext()
	rngSeed(77777)
	b1 := rngNext()
	b2 := rngNext()
	mustEq(a1, b1, "same seed first")
	mustEq(a2, b2, "same seed second")

	// PRNG variation
	rngSeed(42)
	v1 := rngNext()
	v2 := rngNext()
	mustTrue(v1 != v2, "consecutive PRNG values differ")

	// Difficulty scaling
	mustTrue(evaluateShoot(9, 5<<16) > evaluateShoot(3, 5<<16), "hard shoots better")
	mustTrue(evaluateDunk(9, 2<<16) > evaluateDunk(2, 2<<16), "hard dunks better")

	// ai_decide_offense: high dunk stat at close range -> DUNK
	rngSeed(100)
	s := Stats{Speed: 5, Shooting: 5, Dunking: 10, Passing: 3,
		Stealing: 3, Blocking: 3, Clutch: 3, Rebounding: 3}
	act := aiDecideOffense(&s, 1<<16, 20)
	mustEq(act, ActDunk, "high dunk at close range -> Dunk")

	fmt.Println("All game_ai_decisions examples passed.")
}
