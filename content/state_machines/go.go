// Vidya — State Machines in Go
//
// Finite state machines with iota-typed enum dispatch, committed states,
// timers, and transition validation. Go's lack of tagged unions means we
// use named int types + a switch. The compiler does NOT check a switch
// for exhaustiveness: a missed variant silently falls to default (or to
// nothing). A default that panics makes the miss loud at run time; the
// input switch below uses default deliberately (no input → Idle), and
// gameTransition validates against an explicit edge table.

package main

import "fmt"

type PlayerState int

const (
	PSIdle PlayerState = iota
	PSRun
	PSShoot
	PSDunk
	PSPass
	PSSteal
	PSBlock
	PSFall
	PSRebound
)

type GameState int

const (
	GSMenu GameState = iota
	GSSelect
	GSTipoff
	GSPlaying
	GSHalftime
	GSOvertime
	GSGameOver
	GSAttract
)

type Input int

const (
	InNone Input = iota
	InMove
	InShoot
	InPass
	InSteal
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

// gameTransition moves g to `to` only along an allowed edge; asserting a
// variable right after assigning it would test nothing.
func gameTransition(g *GameState, to GameState) bool {
	allowed := map[GameState][]GameState{
		GSAttract:  {GSMenu},
		GSMenu:     {GSSelect, GSAttract},
		GSSelect:   {GSTipoff, GSMenu},
		GSTipoff:   {GSPlaying},
		GSPlaying:  {GSHalftime, GSOvertime, GSGameOver},
		GSHalftime: {GSPlaying},
		GSOvertime: {GSOvertime, GSGameOver},
		GSGameOver: {GSMenu},
	}
	for _, s := range allowed[*g] {
		if s == to {
			*g = to
			return true
		}
	}
	return false
}

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
	mustEq(gameTransition(&g, GSPlaying), false, "menu->playing skips select+tipoff: rejected")
	mustEq(g, GSMenu, "rejected transition leaves state unchanged")
	mustEq(gameTransition(&g, GSSelect), true, "menu->select")
	mustEq(gameTransition(&g, GSTipoff), true, "select->tipoff")
	mustEq(gameTransition(&g, GSPlaying), true, "tipoff->playing")
	mustEq(gameTransition(&g, GSHalftime), true, "playing->halftime")
	mustEq(gameTransition(&g, GSGameOver), false, "halftime->gameover rejected")
	mustEq(gameTransition(&g, GSPlaying), true, "halftime->playing")
	mustEq(gameTransition(&g, GSGameOver), true, "playing->gameover")

	p = newPlayer()
	transition(&p, InShoot)
	for i := 0; i < ShootFrames; i++ {
		tick(&p)
	}
	transition(&p, InMove)
	mustEq(p.State, PSRun, "accepts input after expiry")

	fmt.Println("All state_machines examples passed.")
}
