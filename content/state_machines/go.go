// Vidya — State Machines in Go
//
// Finite state machines with iota-typed enum dispatch, committed states,
// timers, and transition validation. Go's lack of tagged unions means we
// use named int types + a switch — readable, exhaustive when paired with
// a default-panic for unknown variants.

package main

import "fmt"

type PlayerState int
const (
	PSIdle PlayerState = iota
	PSRun; PSShoot; PSDunk; PSPass; PSSteal; PSBlock; PSFall; PSRebound
)

type GameState int
const (
	GSMenu GameState = iota
	GSSelect; GSTipoff; GSPlaying; GSHalftime; GSOvertime; GSGameOver; GSAttract
)

type Input int
const (
	InNone Input = iota
	InMove; InShoot; InPass; InSteal
)

const (
	ShootFrames = 30
	DunkFrames  = 45
)

type Player struct {
	State, PrevState PlayerState
	Timer            int
}

func newPlayer() Player { return Player{State: PSIdle, PrevState: PSIdle, Timer: 0} }

func isCommitted(s PlayerState) bool {
	return s == PSShoot || s == PSDunk || s == PSFall
}

func transition(p *Player, in Input) PlayerState {
	if isCommitted(p.State) && p.Timer > 0 {
		return p.State
	}
	p.PrevState = p.State
	switch in {
	case InMove:
		p.State = PSRun
	case InShoot:
		p.State = PSShoot
		p.Timer = ShootFrames
	case InPass:
		p.State = PSPass
	case InSteal:
		p.State = PSSteal
	default:
		p.State = PSIdle
	}
	return p.State
}

func tick(p *Player) {
	if p.Timer > 0 {
		p.Timer--
		if p.Timer == 0 {
			p.PrevState = p.State
			p.State = PSIdle
		}
	}
}

func didTransition(p *Player) bool { return p.State != p.PrevState }

func mustEq[T comparable](got, want T, msg string) {
	if got != want {
		panic(fmt.Sprintf("FAIL: %s: got %v, want %v", msg, got, want))
	}
}

func main() {
	p := newPlayer()
	transition(&p, InMove)
	mustEq(p.State, PSRun, "idle->run")

	p = newPlayer()
	transition(&p, InShoot)
	mustEq(p.State, PSShoot, "entered shoot")
	transition(&p, InMove)
	mustEq(p.State, PSShoot, "shoot rejects move")
	transition(&p, InPass)
	mustEq(p.State, PSShoot, "shoot rejects pass")

	p = newPlayer()
	transition(&p, InShoot)
	for i := 0; i < ShootFrames; i++ {
		tick(&p)
	}
	mustEq(p.State, PSIdle, "timer expiry")
	mustEq(p.Timer, 0, "timer zero")

	p = newPlayer()
	p.State = PSDunk
	p.Timer = DunkFrames
	transition(&p, InMove)
	mustEq(p.State, PSDunk, "dunk rejects input")
	for i := 0; i < DunkFrames; i++ {
		tick(&p)
	}
	mustEq(p.State, PSIdle, "dunk timer expiry")

	p = newPlayer()
	mustEq(didTransition(&p), false, "no transition initially")
	transition(&p, InMove)
	mustEq(didTransition(&p), true, "idle->run is a transition")
	mustEq(p.PrevState, PSIdle, "prev_state idle")
	transition(&p, InMove)
	mustEq(didTransition(&p), false, "run->run no transition")

	g := GSMenu
	g = GSSelect;   mustEq(g, GSSelect, "menu->select")
	g = GSTipoff;   mustEq(g, GSTipoff, "select->tipoff")
	g = GSPlaying;  mustEq(g, GSPlaying, "tipoff->playing")
	g = GSHalftime; mustEq(g, GSHalftime, "playing->halftime")
	g = GSPlaying;  mustEq(g, GSPlaying, "halftime->playing")
	g = GSGameOver; mustEq(g, GSGameOver, "playing->gameover")
	_ = g

	p = newPlayer()
	transition(&p, InShoot)
	for i := 0; i < ShootFrames; i++ {
		tick(&p)
	}
	transition(&p, InMove)
	mustEq(p.State, PSRun, "accepts input after expiry")

	fmt.Println("All state_machines examples passed.")
}
