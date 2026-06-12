// Vidya — Grid Pathfinding in Zig
//
// BFS + A* on an 8x8 4-connected grid (0=walkable, 1=blocked).
// Zig uses fixed-size [64]u8 for the grid, a fixed-size queue array
// for BFS (no allocator needed for 64 cells), and `std.PriorityQueue`
// for A*'s open set with an explicit `lessThan` comparator over an
// (f, cell) record. Manhattan distance is the heuristic. Zig's lack
// of implicit conversion makes every i64 / usize boundary explicit.

const std = @import("std");
const Order = std.math.Order;
const PriorityQueue = std.PriorityQueue;
const print = std.debug.print;
const assert = std.debug.assert;

const GW: usize = 8;
const GH: usize = 8;
const GN: usize = GW * GH;

fn idx(x: usize, y: usize) usize { return y * GW + x; }

fn iabs(v: i64) i64 { return if (v < 0) -v else v; }

fn manhattan(ax: i64, ay: i64, bx: i64, by: i64) i64 {
    return iabs(ax - bx) + iabs(ay - by);
}

fn neighbours(curr: usize, out: *[4]usize) usize {
    const cx = curr % GW;
    const cy = curr / GW;
    var n: usize = 0;
    if (cy > 0)        { out[n] = curr - GW; n += 1; }
    if (cy < GH - 1)   { out[n] = curr + GW; n += 1; }
    if (cx > 0)        { out[n] = curr - 1;  n += 1; }
    if (cx < GW - 1)   { out[n] = curr + 1;  n += 1; }
    return n;
}

fn gridClear(g: *[GN]u8) void {
    for (g) |*c| c.* = 0;
}

fn gridBlock(g: *[GN]u8, x: usize, y: usize) void {
    g[idx(x, y)] = 1;
}

fn bfs(grid: *const [GN]u8, start: usize, goal: usize) i64 {
    if (start == goal) return 0;
    var visited = [_]bool{false} ** GN;
    var dist = [_]i64{-1} ** GN;
    var queue = [_]usize{0} ** GN;
    var head: usize = 0;
    var tail: usize = 0;
    queue[tail] = start; tail += 1;
    visited[start] = true;
    dist[start] = 0;
    var nb: [4]usize = undefined;
    while (head < tail) {
        const curr = queue[head];
        head += 1;
        if (curr == goal) return dist[curr];
        const nc = neighbours(curr, &nb);
        var i: usize = 0;
        while (i < nc) : (i += 1) {
            const n = nb[i];
            if (!visited[n] and grid[n] == 0) {
                visited[n] = true;
                dist[n] = dist[curr] + 1;
                queue[tail] = n; tail += 1;
            }
        }
    }
    return -1;
}

const Item = struct { f: i64, cell: usize };

fn itemLess(_: void, a: Item, b: Item) Order {
    return std.math.order(a.f, b.f);
}

fn astar(allocator: std.mem.Allocator, grid: *const [GN]u8,
         sx: usize, sy: usize, gx: usize, gy: usize) !i64 {
    const start = idx(sx, sy);
    const goal = idx(gx, gy);
    var g_score = [_]i64{std.math.maxInt(i64)} ** GN;
    var closed = [_]bool{false} ** GN;
    g_score[start] = 0;

    var open: PriorityQueue(Item, void, itemLess) = .empty;
    defer open.deinit(allocator);

    const h0 = manhattan(@as(i64, @intCast(sx)), @as(i64, @intCast(sy)),
                         @as(i64, @intCast(gx)), @as(i64, @intCast(gy)));
    try open.push(allocator, .{ .f = h0, .cell = start });

    var nb: [4]usize = undefined;
    while (open.pop()) |it| {
        const curr = it.cell;
        if (curr == goal) return g_score[goal];
        if (closed[curr]) continue;
        closed[curr] = true;
        const tg = g_score[curr] + 1;
        const nc = neighbours(curr, &nb);
        var i: usize = 0;
        while (i < nc) : (i += 1) {
            const n = nb[i];
            if (closed[n] or grid[n] != 0) continue;
            if (tg < g_score[n]) {
                g_score[n] = tg;
                const nx = @as(i64, @intCast(n % GW));
                const ny = @as(i64, @intCast(n / GW));
                const f = tg + manhattan(nx, ny,
                    @as(i64, @intCast(gx)), @as(i64, @intCast(gy)));
                try open.push(allocator, .{ .f = f, .cell = n });
            }
        }
    }
    return -1;
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // manhattan
    assert(manhattan(0, 0, 0, 0) == 0);
    assert(manhattan(0, 0, 3, 4) == 7);
    assert(manhattan(7, 7, 0, 0) == 14);
    assert(manhattan(2, 5, 5, 2) == 6);

    var grid: [GN]u8 = undefined;

    // bfs empty
    gridClear(&grid);
    assert(bfs(&grid, idx(0, 0), idx(7, 7)) == 14);

    // bfs same
    gridClear(&grid);
    assert(bfs(&grid, idx(3, 3), idx(3, 3)) == 0);

    // bfs around wall
    gridClear(&grid);
    {
        var y: usize = 0;
        while (y < 7) : (y += 1) gridBlock(&grid, 4, y);
    }
    assert(bfs(&grid, idx(0, 0), idx(7, 0)) == 21);

    // bfs unreachable
    gridClear(&grid);
    gridBlock(&grid, 6, 7);
    gridBlock(&grid, 7, 6);
    assert(bfs(&grid, idx(0, 0), idx(7, 7)) == -1);

    // astar empty
    gridClear(&grid);
    assert(try astar(alloc, &grid, 0, 0, 7, 7) == 14);

    // astar matches bfs around wall
    gridClear(&grid);
    {
        var y: usize = 0;
        while (y < 7) : (y += 1) gridBlock(&grid, 4, y);
    }
    const bfs_len = bfs(&grid, idx(0, 0), idx(7, 0));
    const astar_len = try astar(alloc, &grid, 0, 0, 7, 0);
    assert(bfs_len == astar_len);
    assert(astar_len == 21);

    // astar unreachable
    gridClear(&grid);
    gridBlock(&grid, 6, 7);
    gridBlock(&grid, 7, 6);
    assert(try astar(alloc, &grid, 0, 0, 7, 7) == -1);

    print("All grid_pathfinding examples passed.\n", .{});
}
