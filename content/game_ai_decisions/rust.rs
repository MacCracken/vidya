// Vidya — Game AI Decision Making in Rust
//
// Stat-driven AI scoring with PCG PRNG, urgency-multiplied shooting,
// and weighted action selection. Rust's `wrapping_mul` / `wrapping_add`
// give us the same modular 64-bit arithmetic as the C-shaped PCG
// reference (overflow is defined behavior — we just have to ask for
// it). `match` on a `#[repr(i64)]` enum gives self-documenting
// dispatch with compiler-checked exhaustiveness.

#![allow(dead_code, unused_assignments)]

#[derive(Copy, Clone, PartialEq, Eq, Debug)]
#[repr(i64)]
enum Action {
    Shoot = 0,
    Dunk = 1,
    Pass = 2,
    Drive = 3,
    Steal = 4,
}

#[derive(Copy, Clone, Debug)]
struct Stats {
    speed: i64,
    shooting: i64,
    dunking: i64,
    passing: i64,
    stealing: i64,
    blocking: i64,
    clutch: i64,
    rebounding: i64,
}

const PCG_MULT: u64 = 6364136223846793005;
const PCG_INC: u64 = 1442695040888963407;

struct Rng {
    state: u64,
}

impl Rng {
    fn new(seed: u64) -> Self {
        Rng { state: seed }
    }

    fn seed(&mut self, s: u64) {
        self.state = s;
    }

    fn next(&mut self) -> i64 {
        // Wrapping arithmetic is required: u64 PCG state overflows by design.
        self.state = self.state.wrapping_mul(PCG_MULT).wrapping_add(PCG_INC);
        ((self.state >> 33) & 0x7fff_ffff) as i64
    }

    fn range(&mut self, max: i64) -> i64 {
        if max <= 0 {
            return 0;
        }
        let r = self.next();
        r % max
    }
}

fn prob_check(rng: &mut Rng, stat: i64) -> bool {
    let threshold = stat * 10;
    let roll = rng.range(100);
    roll < threshold
}

fn evaluate_shoot(shooting: i64, distance_fx: i64) -> i64 {
    let base = shooting * 10;
    let dist_units = distance_fx >> 16;
    let score = base - dist_units;
    score.max(0)
}

fn evaluate_dunk(dunking: i64, distance_fx: i64) -> i64 {
    let dist_units = distance_fx >> 16;
    if dist_units > 3 {
        return 0;
    }
    dunking * 15
}

fn evaluate_pass(passing: i64) -> i64 {
    passing * 8
}

fn evaluate_drive(speed: i64) -> i64 {
    speed * 6
}

fn apply_urgency(score: i64, shot_clock: i64) -> i64 {
    let mut urgency = (24 - shot_clock) / 4;
    if urgency < 1 {
        urgency = 1;
    }
    score * urgency
}

fn add_noise(rng: &mut Rng, score: i64) -> i64 {
    let noise = rng.range(21) - 10;
    (score + noise).max(0)
}

fn ai_decide_offense(rng: &mut Rng, stats: &Stats, distance_fx: i64, shot_clock: i64) -> Action {
    let mut shoot_score = evaluate_shoot(stats.shooting, distance_fx);
    shoot_score = apply_urgency(shoot_score, shot_clock);
    shoot_score = add_noise(rng, shoot_score);

    let mut dunk_score = evaluate_dunk(stats.dunking, distance_fx);
    dunk_score = add_noise(rng, dunk_score);

    let mut pass_score = evaluate_pass(stats.passing);
    pass_score = add_noise(rng, pass_score);

    let mut drive_score = evaluate_drive(stats.speed);
    drive_score = add_noise(rng, drive_score);

    let mut best = Action::Shoot;
    let mut best_score = shoot_score;
    if dunk_score > best_score {
        best = Action::Dunk;
        best_score = dunk_score;
    }
    if pass_score > best_score {
        best = Action::Pass;
        best_score = pass_score;
    }
    if drive_score > best_score {
        best = Action::Drive;
        best_score = drive_score;
    }
    let _ = best_score;
    best
}

fn main() {
    // evaluate_shoot
    assert_eq!(evaluate_shoot(9, 3 << 16), 87, "shoot: 9*10 - 3");
    assert_eq!(evaluate_shoot(1, 20 << 16), 0, "low stat + far = 0");
    assert_eq!(evaluate_shoot(10, 0), 100, "stat 10 at rim");

    // evaluate_dunk
    assert_eq!(evaluate_dunk(8, 2 << 16), 120, "dunk: stat 8 * 15");
    assert_eq!(evaluate_dunk(10, 10 << 16), 0, "too far to dunk");

    // urgency
    assert_eq!(apply_urgency(50, 24), 50, "full clock no urgency");
    assert_eq!(apply_urgency(50, 2), 250, "low clock x5");
    assert_eq!(apply_urgency(50, 0), 300, "empty clock x6");

    // prob_check: stat 10 always passes, stat 0 always fails
    let mut rng = Rng::new(42);
    for _ in 0..20 {
        assert!(prob_check(&mut rng, 10), "stat 10 always passes");
    }
    rng.seed(99);
    for _ in 0..20 {
        assert!(!prob_check(&mut rng, 0), "stat 0 always fails");
    }

    // PRNG determinism: same seed -> same sequence
    let mut a = Rng::new(77777);
    let a1 = a.next();
    let a2 = a.next();
    let mut b = Rng::new(77777);
    let b1 = b.next();
    let b2 = b.next();
    assert_eq!(a1, b1, "same seed: first value matches");
    assert_eq!(a2, b2, "same seed: second value matches");

    // PRNG variation: consecutive values differ
    let mut r = Rng::new(42);
    let v1 = r.next();
    let v2 = r.next();
    assert!(v1 != v2, "consecutive PRNG values differ");

    // Difficulty scaling: hard AI scores higher than easy AI
    assert!(
        evaluate_shoot(9, 5 << 16) > evaluate_shoot(3, 5 << 16),
        "hard shoots better"
    );
    assert!(
        evaluate_dunk(9, 2 << 16) > evaluate_dunk(2, 2 << 16),
        "hard dunks better"
    );

    // ai_decide_offense: high dunk stat at close range -> Dunk
    let mut rng = Rng::new(100);
    let stats = Stats {
        speed: 5,
        shooting: 5,
        dunking: 10,
        passing: 3,
        stealing: 3,
        blocking: 3,
        clutch: 3,
        rebounding: 3,
    };
    let action = ai_decide_offense(&mut rng, &stats, 1 << 16, 20);
    assert_eq!(action, Action::Dunk, "high dunk at close range -> Dunk");

    println!("All game_ai_decisions examples passed.");
}
