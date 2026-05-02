// Vidya — Game Loop Architecture in Zig
//
// Fixed-timestep accumulator loop with spiral-of-death cap. The driver
// `loopStep` takes an elapsed-microsecond delta and returns the number
// of fixed-step updates fired this frame. Zig's `i64` (with no implicit
// conversions) makes the monotonic-time math explicit at every step —
// no surprises from u32 wrap or signed/unsigned mixups. A real game
// would source deltas from std.time.nanoTimestamp(); tests below use
// deterministic deltas to stay reproducible across CI.

const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

const DT_US: i64 = 16667;
const MAX_ACCUM: i64 = 5 * DT_US; // 83335

const GameLoop = struct {
    accum: i64,
    update_count: i64,
    render_count: i64,
};

fn newLoop() GameLoop {
    return GameLoop{ .accum = 0, .update_count = 0, .render_count = 0 };
}

fn loopStep(g: *GameLoop, elapsed_us: i64) i64 {
    var accum: i64 = g.accum + elapsed_us;
    // Spiral-of-death cap: never let the accumulator exceed MAX_ACCUM.
    if (accum > MAX_ACCUM) accum = MAX_ACCUM;
    var updates: i64 = 0;
    while (accum >= DT_US) {
        accum -= DT_US;
        updates += 1;
    }
    g.accum = accum;
    g.update_count += updates;
    g.render_count += 1;
    return updates;
}

pub fn main() !void {
    // test_exact_dt_fires_one_update
    var g = newLoop();
    var u = loopStep(&g, DT_US);
    assert(u == 1);
    assert(g.update_count == 1);

    // test_under_dt_no_update
    g = newLoop();
    u = loopStep(&g, @divTrunc(DT_US, 2));
    assert(u == 0);

    // test_catchup_50ms
    g = newLoop();
    u = loopStep(&g, 50000);
    assert(u == 2);

    // test_spiral_of_death_cap
    g = newLoop();
    u = loopStep(&g, 1000000);
    assert(u == 5);

    // test_render_per_frame
    g = newLoop();
    _ = loopStep(&g, DT_US);
    _ = loopStep(&g, DT_US);
    _ = loopStep(&g, DT_US);
    assert(g.render_count == 3);
    assert(g.update_count == 3);

    // test_accumulator_remainder
    g = newLoop();
    const one_and_half: i64 = DT_US + @divTrunc(DT_US, 2);
    _ = loopStep(&g, one_and_half);
    assert(g.accum > @divTrunc(DT_US, 4));
    assert(g.accum < DT_US);

    // test_input_update_render_separation
    g = newLoop();
    _ = loopStep(&g, 30000);
    _ = loopStep(&g, 5000);
    _ = loopStep(&g, 30000);
    assert(g.update_count == 3);
    assert(g.render_count == 3);

    print("All game_loop_architecture examples passed.\n", .{});
}
