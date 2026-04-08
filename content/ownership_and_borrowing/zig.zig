// Vidya — Ownership and Borrowing in Zig
//
// Zig has no borrow checker and no garbage collector. Instead:
//   1. Explicit allocators — every allocation names its allocator
//   2. defer/errdefer — deterministic cleanup at scope exit
//   3. Optionals — ?T replaces nullable pointers, no null derefs
//   4. Error unions — !T forces callers to handle allocation failure
//   5. Slices — pointer + length, bounds-checked in safe mode
//
// Where Rust uses ownership rules enforced at compile time, Zig uses
// conventions enforced by the programmer. The tradeoff: more freedom,
// more responsibility. Zig trusts you; Rust verifies you.

const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

pub fn main() !void {
    print("Ownership and Borrowing — Zig's approach:\n\n", .{});

    // ── 1. Explicit allocators ───────────────────────────────────
    // Rust: Box::new(42) uses the global allocator implicitly.
    // Zig: you pass the allocator explicitly. No hidden allocations.
    print("1. Explicit allocators:\n", .{});
    {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer {
            const check = gpa.deinit();
            // In debug mode, deinit returns .leak if memory was leaked
            assert(check == .ok);
        }
        const allocator = gpa.allocator();

        // Allocate a slice — must free it ourselves
        const buf = try allocator.alloc(u8, 32);
        defer allocator.free(buf);

        @memset(buf, 'A');
        assert(buf.len == 32);
        assert(buf[0] == 'A');
        print("   Allocated 32 bytes, filled with 'A', freed via defer\n", .{});
    }

    // ── 2. defer for deterministic cleanup ───────────────────────
    // Rust: Drop trait runs when owner goes out of scope.
    // Zig: defer runs at end of scope. You write it next to the
    //       acquisition — intent is visible, not hidden in Drop.
    print("\n2. defer — cleanup next to acquisition:\n", .{});
    {
        var order: [4]u8 = undefined;
        var idx: usize = 0;

        {
            order[idx] = 'A'; // acquire resource A
            idx += 1;
            defer {
                order[idx] = 'a'; // release A
                idx += 1;
            }

            order[idx] = 'B'; // acquire resource B
            idx += 1;
            defer {
                order[idx] = 'b'; // release B
                idx += 1;
            }
            // Defers run in reverse order: b then a
        }

        assert(idx == 4);
        assert(order[0] == 'A');
        assert(order[1] == 'B');
        assert(order[2] == 'b'); // LIFO: B released first
        assert(order[3] == 'a'); // then A
        print("   Acquire A, acquire B -> release B, release A (LIFO)\n", .{});
    }

    // ── 3. errdefer — cleanup only on error ──────────────────────
    // Rust: no direct equivalent. You'd use Drop or manual cleanup.
    // Zig: errdefer runs only when the function returns an error,
    //       preventing leaks on error paths.
    print("\n3. errdefer — cleanup on error path only:\n", .{});
    {
        const result = buildResource(true);
        assert(result != null);
        print("   buildResource(true)  -> got resource (no errdefer)\n", .{});

        const failed = buildResource(false);
        assert(failed == null);
        print("   buildResource(false) -> null (errdefer cleaned up)\n", .{});
    }

    // ── 4. Optionals — no null pointer derefs ────────────────────
    // Rust: Option<T> with pattern matching.
    // Zig: ?T with orelse, if, and .? unwrap.
    // Both prevent null pointer dereference at the type level.
    print("\n4. Optionals — ?T replaces null pointers:\n", .{});
    {
        var maybe: ?i32 = null;
        assert(maybe == null);

        maybe = 42;
        assert(maybe != null);
        assert(maybe.? == 42); // unwrap — panics in safe mode if null

        // orelse: provide a default (like Rust's unwrap_or)
        const val: i32 = maybe orelse 0;
        assert(val == 42);

        const nothing: ?i32 = null;
        const fallback = nothing orelse -1;
        assert(fallback == -1);
        print("   ?i32 = null -> orelse -1 = {d}\n", .{fallback});

        // if-capture: like Rust's if let Some(x) = ...
        if (maybe) |v| {
            assert(v == 42);
            print("   if (maybe) |v| -> v = {d}\n", .{v});
        }
    }

    // ── 5. Pointer semantics — no implicit copies ────────────────
    // Rust: move semantics by default, Copy for small types.
    // Zig: value types are copied on assignment. Pointers are
    //       explicit. No hidden moves, no hidden copies.
    print("\n5. Value semantics and explicit pointers:\n", .{});
    {
        var a = Point{ .x = 1, .y = 2 };
        const b = a; // copy — a is still valid (unlike Rust move)
        assert(b.x == 1 and b.y == 2);
        a.x = 99;
        assert(b.x == 1); // b has its own copy
        print("   Struct copy: a.x=99, b.x=1 (independent)\n", .{});

        // Explicit pointer — Rust's &mut equivalent
        var c = Point{ .x = 10, .y = 20 };
        mutatePoint(&c);
        assert(c.x == 11);
        print("   Pointer mutation: c.x = {d} (modified via *Point)\n", .{c.x});
    }

    // ── 6. Slices — bounded views ────────────────────────────────
    // Rust: &[T] with lifetime guarantees.
    // Zig: []T is pointer + length, bounds-checked in safe mode.
    // No lifetime annotations — the programmer tracks validity.
    print("\n6. Slices — pointer + length:\n", .{});
    {
        const data = [_]i32{ 10, 20, 30, 40, 50 };
        const slice: []const i32 = data[1..4]; // [20, 30, 40]
        assert(slice.len == 3);
        assert(slice[0] == 20);
        assert(slice[2] == 40);
        print("   data[1..4] = [{d}, {d}, {d}], len={d}\n", .{ slice[0], slice[1], slice[2], slice.len });

        // Sentinel-terminated: interop with C strings
        const c_str: [:0]const u8 = "hello";
        assert(c_str.len == 5);
        assert(c_str[5] == 0); // sentinel is accessible
        print("   Sentinel slice: \"{s}\", len={d}, sentinel=0\n", .{ c_str, c_str.len });
    }

    // ── 7. Error unions — allocation can fail ────────────────────
    // Rust: Box::new panics on OOM (or use Box::try_new).
    // Zig: allocator.alloc returns ![]T. You must handle the error.
    // try propagates it; catch handles it locally.
    print("\n7. Error unions — forced error handling:\n", .{});
    {
        var buf: [64]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        const alloc = fba.allocator();

        // Small allocation succeeds
        const small = alloc.alloc(u8, 16) catch unreachable;
        assert(small.len == 16);
        print("   alloc(16) in 64-byte buffer: ok\n", .{});

        // Large allocation fails — out of memory
        const too_big = alloc.alloc(u8, 1024);
        assert(too_big == error.OutOfMemory);
        print("   alloc(1024) in 64-byte buffer: OutOfMemory\n", .{});
    }

    // ── 8. No use-after-free at language level ───────────────────
    // Rust: borrow checker prevents use-after-free at compile time.
    // Zig: no compile-time prevention, but GeneralPurposeAllocator
    //       detects use-after-free in debug/safe builds at runtime.
    // Zig's philosophy: use tools (GPA, sanitizers) not type systems.
    print("\n8. Runtime safety (debug mode):\n", .{});
    {
        print("   GPA detects leaks on deinit()\n", .{});
        print("   Safe mode: bounds checks, null checks, overflow\n", .{});
        print("   ReleaseSafe: keeps safety checks in release builds\n", .{});
        print("   Debug + GPA = catches most memory bugs at runtime\n", .{});
    }

    // ── 9. Arena allocator — batch lifetime ──────────────────────
    // Rust: typed-arena crate or bumpalo.
    // Zig: std.heap.ArenaAllocator. Allocate many objects, free all
    //       at once. No individual free() needed. Perfect for
    //       request-scoped or parse-tree-scoped allocations.
    print("\n9. Arena allocator — batch lifetime:\n", .{});
    {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();

        var arena = std.heap.ArenaAllocator.init(gpa.allocator());
        defer arena.deinit(); // frees everything at once

        const a = try arena.allocator().alloc(u8, 100);
        const b = try arena.allocator().alloc(u8, 200);
        const c = try arena.allocator().alloc(u8, 300);
        _ = a;
        _ = b;
        _ = c;
        // No individual frees. arena.deinit() releases all 600 bytes.
        print("   Allocated 100 + 200 + 300 bytes, all freed by arena.deinit()\n", .{});
    }

    print("\nAll tests passed.\n", .{});
}

// ── Helper types and functions ───────────────────────────────────────

const Point = struct { x: i32, y: i32 };

fn mutatePoint(p: *Point) void {
    p.x += 1;
}

/// Demonstrates errdefer: if construction fails, partial work is cleaned up.
fn buildResource(succeed: bool) ?Resource {
    var r = Resource{ .stage = 0 };

    r.stage = 1; // step 1 done
    // If we fail after this, errdefer would clean up stage 1 work.
    // (In real code, this might be freeing allocated memory.)

    if (!succeed) {
        r.stage = 0; // simulate errdefer cleanup
        return null;
    }

    r.stage = 2; // fully constructed
    return r;
}

const Resource = struct {
    stage: u8,
};
