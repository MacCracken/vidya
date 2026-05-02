// Vidya — Game AI Decision Making in Zig
//
// Stat-driven AI scoring with PCG PRNG, urgency-multiplied shooting,
// and weighted action selection. Zig has no implicit overflow in `*`
// or `+`, so we use the wrapping operators `*%` and `+%` for the PCG
// state update — overflow is part of the algorithm, and the operators
// make that explicit at the call site. The `Action` enum is `i64`-
// backed for parity with the Cyrius integer encoding.

const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

const Action = enum(i64) {
    Shoot = 0,
    Dunk = 1,
    Pass = 2,
    Drive = 3,
    Steal = 4,
};

const Stats = struct {
    speed: i64,
    shooting: i64,
    dunking: i64,
    passing: i64,
    stealing: i64,
    blocking: i64,
    clutch: i64,
    rebounding: i64,
};

const PCG_MULT: u64 = 6364136223846793005;
const PCG_INC: u64 = 1442695040888963407;

var rng_state: u64 = 12345;

fn rngSeed(s: u64) void {
    rng_state = s;
}

fn rngNext() i64 {
    // *% and +% are the wrapping operators — overflow is the design.
    rng_state = rng_state *% PCG_MULT +% PCG_INC;
    return @intCast((rng_state >> 33) & 0x7fffffff);
}

fn rngRange(max: i64) i64 {
    if (max <= 0) return 0;
    return @mod(rngNext(), max);
}

fn probCheck(stat: i64) bool {
    return rngRange(100) < stat * 10;
}

fn evaluateShoot(shooting: i64, distance_fx: i64) i64 {
    const base = shooting * 10;
    const dist_units = distance_fx >> 16;
    const score = base - dist_units;
    return if (score < 0) 0 else score;
}

fn evaluateDunk(dunking: i64, distance_fx: i64) i64 {
    if ((distance_fx >> 16) > 3) return 0;
    return dunking * 15;
}

fn evaluatePass(passing: i64) i64 {
    return passing * 8;
}

fn evaluateDrive(speed: i64) i64 {
    return speed * 6;
}

fn applyUrgency(score: i64, shot_clock: i64) i64 {
    var urgency = @divTrunc(24 - shot_clock, 4);
    if (urgency < 1) urgency = 1;
    return score * urgency;
}

fn addNoise(score: i64) i64 {
    const noise = rngRange(21) - 10;
    const r = score + noise;
    return if (r < 0) 0 else r;
}

fn aiDecideOffense(s: *const Stats, distance_fx: i64, shot_clock: i64) Action {
    var shoot_score = evaluateShoot(s.shooting, distance_fx);
    shoot_score = applyUrgency(shoot_score, shot_clock);
    shoot_score = addNoise(shoot_score);

    var dunk_score = evaluateDunk(s.dunking, distance_fx);
    dunk_score = addNoise(dunk_score);

    var pass_score = evaluatePass(s.passing);
    pass_score = addNoise(pass_score);

    var drive_score = evaluateDrive(s.speed);
    drive_score = addNoise(drive_score);

    var best: Action = .Shoot;
    var best_score = shoot_score;
    if (dunk_score > best_score) {
        best = .Dunk;
        best_score = dunk_score;
    }
    if (pass_score > best_score) {
        best = .Pass;
        best_score = pass_score;
    }
    if (drive_score > best_score) {
        best = .Drive;
        best_score = drive_score;
    }
    return best;
}

pub fn main() !void {
    // evaluate_shoot
    assert(evaluateShoot(9, 3 << 16) == 87);
    assert(evaluateShoot(1, 20 << 16) == 0);
    assert(evaluateShoot(10, 0) == 100);

    // evaluate_dunk
    assert(evaluateDunk(8, 2 << 16) == 120);
    assert(evaluateDunk(10, 10 << 16) == 0);

    // urgency
    assert(applyUrgency(50, 24) == 50);
    assert(applyUrgency(50, 2) == 250);
    assert(applyUrgency(50, 0) == 300);

    // prob_check
    rngSeed(42);
    var i: i64 = 0;
    while (i < 20) : (i += 1) assert(probCheck(10));
    rngSeed(99);
    i = 0;
    while (i < 20) : (i += 1) assert(!probCheck(0));

    // PRNG determinism
    rngSeed(77777);
    const a1 = rngNext();
    const a2 = rngNext();
    rngSeed(77777);
    const b1 = rngNext();
    const b2 = rngNext();
    assert(a1 == b1);
    assert(a2 == b2);

    // PRNG variation
    rngSeed(42);
    const v1 = rngNext();
    const v2 = rngNext();
    assert(v1 != v2);

    // Difficulty scaling
    assert(evaluateShoot(9, 5 << 16) > evaluateShoot(3, 5 << 16));
    assert(evaluateDunk(9, 2 << 16) > evaluateDunk(2, 2 << 16));

    // ai_decide_offense: high dunk stat at close range -> Dunk
    rngSeed(100);
    const stats = Stats{
        .speed = 5,
        .shooting = 5,
        .dunking = 10,
        .passing = 3,
        .stealing = 3,
        .blocking = 3,
        .clutch = 3,
        .rebounding = 3,
    };
    const act = aiDecideOffense(&stats, 1 << 16, 20);
    assert(act == .Dunk);

    print("All game_ai_decisions examples passed.\n", .{});
}
