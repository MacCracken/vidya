// Vidya — State Machines in Rust
//
// Finite state machines with enum dispatch, committed states, timers,
// and transition validation. Rust's `enum` + exhaustive `match` makes
// the dispatch self-documenting; the compiler enforces every variant
// is handled. `#[repr(i64)]` lets us round-trip through integer code
// for compatibility with the other-language ports.

#![allow(dead_code, unused_assignments)]

#[derive(Copy, Clone, PartialEq, Eq, Debug)]
#[repr(i64)]
enum PlayerState {
    Idle = 0, Run = 1, Shoot = 2, Dunk = 3, Pass = 4,
    Steal = 5, Block = 6, Fall = 7, Rebound = 8,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug)]
#[repr(i64)]
enum GameState {
    Menu = 0, Select = 1, Tipoff = 2, Playing = 3,
    Halftime = 4, Overtime = 5, GameOver = 6, Attract = 7,
}

impl GameState {
    /// Transition validation: the legal game-flow edges; anything else is rejected.
    fn can_go(self, to: GameState) -> bool {
        use GameState::*;
        matches!(
            (self, to),
            (Menu, Select) | (Menu, Attract) | (Attract, Menu)
                | (Select, Tipoff) | (Tipoff, Playing)
                | (Playing, Halftime) | (Halftime, Playing)
                | (Playing, Overtime) | (Overtime, GameOver)
                | (Playing, GameOver) | (GameOver, Menu)
        )
    }
}

#[derive(Copy, Clone, PartialEq, Eq, Debug)]
enum Input { None, Move, Shoot, Pass, Steal }

const SHOOT_FRAMES: i64 = 30;
const DUNK_FRAMES: i64 = 45;

#[derive(Copy, Clone, Debug)]
struct Player {
    state: PlayerState,
    prev_state: PlayerState,
    timer: i64,
}

impl Player {
    fn new() -> Self {
        Player { state: PlayerState::Idle, prev_state: PlayerState::Idle, timer: 0 }
    }

    fn is_committed(s: PlayerState) -> bool {
        matches!(s, PlayerState::Shoot | PlayerState::Dunk | PlayerState::Fall)
    }

    fn transition(&mut self, input: Input) -> PlayerState {
        if Self::is_committed(self.state) && self.timer > 0 {
            return self.state;
        }
        self.prev_state = self.state;
        self.state = match input {
            Input::Move => PlayerState::Run,
            Input::Shoot => { self.timer = SHOOT_FRAMES; PlayerState::Shoot }
            Input::Pass => PlayerState::Pass,
            Input::Steal => PlayerState::Steal,
            Input::None => PlayerState::Idle,
        };
        self.state
    }

    fn tick(&mut self) {
        if self.timer > 0 {
            self.timer -= 1;
            if self.timer == 0 {
                self.prev_state = self.state;
                self.state = PlayerState::Idle;
            }
        }
    }

    fn did_transition(&self) -> bool {
        self.state != self.prev_state
    }
}

fn main() {
    // idle -> run on move
    let mut p = Player::new();
    p.transition(Input::Move);
    assert_eq!(p.state, PlayerState::Run);

    // shoot is committed — rejects input
    let mut p = Player::new();
    p.transition(Input::Shoot);
    assert_eq!(p.state, PlayerState::Shoot);
    p.transition(Input::Move);
    assert_eq!(p.state, PlayerState::Shoot, "shoot rejects move (committed)");
    p.transition(Input::Pass);
    assert_eq!(p.state, PlayerState::Shoot, "shoot rejects pass (committed)");

    // timer expiry returns to idle
    let mut p = Player::new();
    p.transition(Input::Shoot);
    for _ in 0..SHOOT_FRAMES { p.tick(); }
    assert_eq!(p.state, PlayerState::Idle);
    assert_eq!(p.timer, 0);

    // dunk is committed (manually set, normally driven by game logic)
    let mut p = Player::new();
    p.state = PlayerState::Dunk;
    p.timer = DUNK_FRAMES;
    p.transition(Input::Move);
    assert_eq!(p.state, PlayerState::Dunk);
    for _ in 0..DUNK_FRAMES { p.tick(); }
    assert_eq!(p.state, PlayerState::Idle);

    // transition detection via prev_state
    let mut p = Player::new();
    assert!(!p.did_transition());
    p.transition(Input::Move);
    assert!(p.did_transition());
    assert_eq!(p.prev_state, PlayerState::Idle);
    p.transition(Input::Move);
    assert!(!p.did_transition(), "run->run is not a transition");

    // game state progression — every step must be a legal edge
    // (assigning a variant and asserting it back could never fail)
    use GameState::*;
    let flow = [Menu, Select, Tipoff, Playing, Halftime, Playing, GameOver];
    for w in flow.windows(2) {
        assert!(w[0].can_go(w[1]), "{:?} -> {:?} is legal", w[0], w[1]);
    }
    assert!(!Menu.can_go(Playing), "cannot skip select + tipoff");
    assert!(!GameOver.can_go(Playing), "a finished game cannot resume");

    // committed-then-free
    let mut p = Player::new();
    p.transition(Input::Shoot);
    for _ in 0..SHOOT_FRAMES { p.tick(); }
    p.transition(Input::Move);
    assert_eq!(p.state, PlayerState::Run);

    println!("All state_machines examples passed.");
}
