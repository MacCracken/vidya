// Vidya — Maze Generation in Zig
//
// Recursive backtracker (iterative DFS) on an 8x8 grid. Each cell is a
// bitmask of present walls (N=1, S=2, E=4, W=8). Generation carves
// passages by clearing the wall bit on both the current and the
// neighbour cell.
//
// Zig has no implicit overflow on `*` or `+`, so we use the wrapping
// operators `*%` and `+%` for the PCG state update. Overflow is part
// of the algorithm and the operators surface that at the call site —
// byte-for-byte parity with cyrius is preserved.

const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

const GW: usize = 8;
const GH: usize = 8;
const GN: usize = GW * GH;

const WN: u8 = 1;
const WS: u8 = 2;
const WE: u8 = 4;
const WW: u8 = 8;
const WALLS_ALL: u8 = 15;

const PCG_MULT: u64 = 6364136223846793005;
const PCG_INC: u64 = 1442695040888963407;

var rng_state: u64 = 12345;

fn rngSeed(s: u64) void {
    rng_state = s;
}

fn rngNext() i64 {
    // *% and +% are the explicit wrap-on-overflow forms — that's the
    // mod-2^64 step PCG depends on.
    rng_state = rng_state *% PCG_MULT +% PCG_INC;
    return @intCast((rng_state >> 33) & 0x7fffffff);
}

fn rngRange(max: i64) i64 {
    if (max <= 0) return 0;
    return @mod(rngNext(), max);
}

var maze_cells: [GN]u8 = [_]u8{WALLS_ALL} ** GN;
var visited: [GN]bool = [_]bool{false} ** GN;

fn idx(x: usize, y: usize) usize {
    return y * GW + x;
}

fn opposite(d: u8) u8 {
    return switch (d) {
        WN => WS,
        WS => WN,
        WE => WW,
        WW => WE,
        else => 0,
    };
}

fn mazeInit() void {
    var i: usize = 0;
    while (i < GN) : (i += 1) {
        maze_cells[i] = WALLS_ALL;
        visited[i] = false;
    }
}

fn carve(x: usize, y: usize, d: u8, nx: usize, ny: usize) void {
    const ci = idx(x, y);
    const ni = idx(nx, ny);
    const od = opposite(d);
    // Clear the wall on both sides; a one-sided clear would fail the
    // wall-consistency check.
    maze_cells[ci] &= ~d;
    maze_cells[ni] &= ~od;
}

const Neighbour = struct { dir: u8, nx: usize, ny: usize };

fn collectUnvisited(x: usize, y: usize, buf: []Neighbour) usize {
    var n: usize = 0;
    if (y > 0 and !visited[idx(x, y - 1)]) {
        buf[n] = .{ .dir = WN, .nx = x, .ny = y - 1 };
        n += 1;
    }
    if (y < GH - 1 and !visited[idx(x, y + 1)]) {
        buf[n] = .{ .dir = WS, .nx = x, .ny = y + 1 };
        n += 1;
    }
    if (x > 0 and !visited[idx(x - 1, y)]) {
        buf[n] = .{ .dir = WW, .nx = x - 1, .ny = y };
        n += 1;
    }
    if (x < GW - 1 and !visited[idx(x + 1, y)]) {
        buf[n] = .{ .dir = WE, .nx = x + 1, .ny = y };
        n += 1;
    }
    return n;
}

fn mazeGenerate(sx: usize, sy: usize) void {
    mazeInit();
    var stack: [GN]usize = undefined;
    var sp: usize = 0;
    stack[sp] = idx(sx, sy);
    sp += 1;
    visited[idx(sx, sy)] = true;
    var buf: [4]Neighbour = undefined;
    while (sp > 0) {
        const top = stack[sp - 1];
        const tx = top % GW;
        const ty = top / GW;
        const k = collectUnvisited(tx, ty, &buf);
        if (k == 0) {
            sp -= 1;
        } else {
            const pick: usize = @intCast(rngRange(@intCast(k)));
            const n = buf[pick];
            carve(tx, ty, n.dir, n.nx, n.ny);
            visited[idx(n.nx, n.ny)] = true;
            stack[sp] = idx(n.nx, n.ny);
            sp += 1;
        }
    }
}

fn countVisited() usize {
    var n: usize = 0;
    for (visited) |v| if (v) {
        n += 1;
    };
    return n;
}

fn countRemovedWalls() usize {
    var removed: usize = 0;
    var y: usize = 0;
    while (y < GH) : (y += 1) {
        var x: usize = 0;
        while (x < GW) : (x += 1) {
            const w = maze_cells[idx(x, y)];
            if (y > 0 and (w & WN) == 0) removed += 1;
            if (x > 0 and (w & WW) == 0) removed += 1;
        }
    }
    return removed;
}

fn wallsConsistent() bool {
    var y: usize = 0;
    while (y < GH) : (y += 1) {
        var x: usize = 0;
        while (x < GW) : (x += 1) {
            const w = maze_cells[idx(x, y)];
            if (x < GW - 1) {
                const nw = maze_cells[idx(x + 1, y)];
                if (((w & WE) == 0) != ((nw & WW) == 0)) return false;
            }
            if (y < GH - 1) {
                const sw = maze_cells[idx(x, y + 1)];
                if (((w & WS) == 0) != ((sw & WN) == 0)) return false;
            }
        }
    }
    return true;
}

pub fn main() !void {
    // init state
    mazeInit();
    assert(maze_cells[0] == WALLS_ALL);
    assert(maze_cells[63] == WALLS_ALL);
    assert(!visited[0]);

    // full coverage
    rngSeed(42);
    mazeGenerate(0, 0);
    assert(countVisited() == GN);

    // perfect maze wall count
    rngSeed(42);
    mazeGenerate(0, 0);
    assert(countRemovedWalls() == GN - 1);

    // wall consistency
    rngSeed(42);
    mazeGenerate(0, 0);
    assert(wallsConsistent());

    // determinism
    rngSeed(42);
    mazeGenerate(0, 0);
    const c0 = maze_cells[0];
    const c27 = maze_cells[27];
    const c63 = maze_cells[63];
    rngSeed(42);
    mazeGenerate(0, 0);
    assert(maze_cells[0] == c0);
    assert(maze_cells[27] == c27);
    assert(maze_cells[63] == c63);

    // different seeds differ
    rngSeed(1);
    mazeGenerate(0, 0);
    var sum1: u64 = 0;
    for (maze_cells) |v| sum1 += v;
    rngSeed(2);
    mazeGenerate(0, 0);
    var sum2: u64 = 0;
    for (maze_cells) |v| sum2 += v;
    assert(sum1 != sum2);

    // starting cell visited (non-corner start)
    rngSeed(42);
    mazeGenerate(3, 5);
    assert(visited[idx(3, 5)]);
    assert(countVisited() == GN);

    // cross-language byte parity (matches cyrius reference)
    rngSeed(42);
    mazeGenerate(0, 0);
    assert(maze_cells[0] == 13);
    assert(maze_cells[27] == 12);
    assert(maze_cells[63] == 6);

    print("All maze_generation examples passed.\n", .{});
}
