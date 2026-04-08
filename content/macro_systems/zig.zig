// Vidya — Macro Systems in Zig
//
// Zig has no macros — no preprocessor, no proc macros, no syntax
// extensions. Instead, Zig uses comptime: the same language runs at
// compile time and runtime. Where C uses #define and Rust uses
// macro_rules!/proc_macro, Zig uses:
//
//   1. comptime functions — code generation at compile time
//   2. @typeInfo / @TypeOf — type reflection and introspection
//   3. inline for/while — unrolled loops over comptime-known data
//   4. comptime string building — format strings, build identifiers
//   5. Generic types via comptime parameters
//
// The key insight: macros exist because the base language cannot
// express compile-time computation. Zig's comptime makes the base
// language powerful enough that macros are unnecessary.

const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const mem = std.mem;

// ── 1. comptime functions as code generation ─────────────────────────
//
// C macro:     #define SQUARE(x) ((x) * (x))     — textual, no type safety
// Rust macro:  macro_rules! square { ($x:expr) => { $x * $x } }
// Zig:         comptime function — typed, debuggable, same language

/// Compile-time factorial. The result is baked into the binary.
fn factorial(comptime n: u64) u64 {
    if (n == 0) return 1;
    return n * factorial(n - 1);
}

/// Compile-time Fibonacci via memoization table.
fn fibonacci(comptime n: usize) u64 {
    comptime {
        var table: [n + 1]u64 = undefined;
        table[0] = 0;
        if (n > 0) table[1] = 1;
        for (2..n + 1) |i| {
            table[i] = table[i - 1] + table[i - 2];
        }
        return table[n];
    }
}

/// Compile-time lookup table generation.
/// C equivalent: static const int squares[] = {0, 1, 4, 9, ...};
/// But in C you'd either hand-write it or use a macro/codegen script.
fn SquareTable(comptime size: usize) type {
    return struct {
        const values = blk: {
            var table: [size]u64 = undefined;
            for (0..size) |i| {
                table[i] = i * i;
            }
            break :blk table;
        };

        fn get(index: usize) u64 {
            return values[index];
        }
    };
}

// ── 2. @typeInfo / @TypeOf — reflection replaces code generation ─────
//
// Rust proc macros parse token streams to generate code.
// Zig's @typeInfo gives you the same info without leaving the language.

/// Serialize any struct to "key=value" pairs.
/// Rust would need #[derive(Debug)] or a proc macro. Zig does it inline.
fn serializeStruct(value: anytype, buf: []u8) []const u8 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    comptime {
        if (info != .@"struct") {
            @compileError("serializeStruct requires a struct type");
        }
    }

    var pos: usize = 0;
    const fields = info.@"struct".fields;

    inline for (fields, 0..) |field, i| {
        const field_val = @field(value, field.name);

        // Write field name
        @memcpy(buf[pos..][0..field.name.len], field.name);
        pos += field.name.len;
        buf[pos] = '=';
        pos += 1;

        // Write field value based on type
        switch (@typeInfo(field.type)) {
            .int, .comptime_int => {
                const digits = formatInt(field_val, buf[pos..]);
                pos += digits;
            },
            .bool => {
                const s = if (field_val) "true" else "false";
                @memcpy(buf[pos..][0..s.len], s);
                pos += s.len;
            },
            .pointer => |ptr_info| {
                if (ptr_info.size == .slice and ptr_info.child == u8) {
                    @memcpy(buf[pos..][0..field_val.len], field_val);
                    pos += field_val.len;
                }
            },
            else => {
                const s = "?";
                @memcpy(buf[pos..][0..s.len], s);
                pos += s.len;
            },
        }

        if (i + 1 < fields.len) {
            buf[pos] = ',';
            pos += 1;
            buf[pos] = ' ';
            pos += 1;
        }
    }
    return buf[0..pos];
}

/// Simple integer-to-string for positive numbers.
fn formatInt(val: anytype, buf: []u8) usize {
    var v: u64 = if (val < 0) @intCast(-val) else @intCast(val);
    var tmp: [20]u8 = undefined;
    var len: usize = 0;

    if (v == 0) {
        buf[0] = '0';
        return 1;
    }

    while (v > 0) {
        tmp[len] = @intCast('0' + (v % 10));
        v /= 10;
        len += 1;
    }

    // Reverse into buf
    for (0..len) |i| {
        buf[i] = tmp[len - 1 - i];
    }
    return len;
}

// ── 3. inline for/while — unrolled iteration ─────────────────────────
//
// C macro: X-macros or repeated #define blocks.
// Rust macro: macro_rules! with $(...)* repetition.
// Zig: inline for over comptime arrays — the loop is fully unrolled.

/// Process a tuple of different types — heterogeneous iteration.
fn processTuple(tuple: anytype) usize {
    var total: usize = 0;
    // inline for unrolls this — each iteration handles a different type
    inline for (std.meta.fields(@TypeOf(tuple))) |field| {
        const val = @field(tuple, field.name);
        total += sizeContribution(val);
    }
    return total;
}

fn sizeContribution(val: anytype) usize {
    const T = @TypeOf(val);
    return switch (@typeInfo(T)) {
        .int => @sizeOf(T),
        .bool => 1,
        .pointer => |p| if (p.size == .slice) val.len else @sizeOf(T),
        else => 0,
    };
}

// ── 4. Generic types via comptime parameters ─────────────────────────
//
// C: void* + size parameter, or code generation with macros.
// C++: templates. Rust: generics with trait bounds.
// Zig: comptime type parameters — functions return types.

/// A fixed-capacity stack, generic over element type and capacity.
/// C would need a macro to generate this for each type.
/// Rust would use Vec<T> or a generic struct.
fn Stack(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        items: [capacity]T = undefined,
        len: usize = 0,

        fn push(self: *Self, val: T) bool {
            if (self.len >= capacity) return false;
            self.items[self.len] = val;
            self.len += 1;
            return true;
        }

        fn pop(self: *Self) ?T {
            if (self.len == 0) return null;
            self.len -= 1;
            return self.items[self.len];
        }

        fn peek(self: *const Self) ?T {
            if (self.len == 0) return null;
            return self.items[self.len - 1];
        }

        fn isEmpty(self: *const Self) bool {
            return self.len == 0;
        }
    };
}

// ── 5. comptime string building ──────────────────────────────────────
//
// Rust proc macros generate code as token streams.
// Zig builds strings (and types) at comptime using normal code.

/// Build a repeated string at compile time.
/// Returns a comptime-known slice baked into the binary.
fn repeatStr(comptime s: []const u8, comptime n: usize) []const u8 {
    const result = comptime blk: {
        var buf: [s.len * n]u8 = undefined;
        for (0..n) |i| {
            for (0..s.len) |j| {
                buf[i * s.len + j] = s[j];
            }
        }
        const final = buf;
        break :blk final;
    };
    return &result;
}

/// Compile-time string concatenation.
fn comptimeConcat(comptime a: []const u8, comptime b: []const u8) []const u8 {
    const result = comptime blk: {
        var buf: [a.len + b.len]u8 = undefined;
        for (0..a.len) |i| buf[i] = a[i];
        for (0..b.len) |i| buf[a.len + i] = b[i];
        const final = buf;
        break :blk final;
    };
    return &result;
}

// ── 6. Enum generation from comptime data ────────────────────────────
//
// Rust derive macros generate trait impls from enum definitions.
// Zig generates the enum itself at comptime.

/// Build a bitflag type from a list of names.
fn BitFlags(comptime names: []const []const u8) type {
    return struct {
        bits: u32 = 0,

        const Self = @This();

        fn set(self: *Self, comptime name: []const u8) void {
            const idx = comptime nameIndex(names, name);
            self.bits |= @as(u32, 1) << idx;
        }

        fn isSet(self: Self, comptime name: []const u8) bool {
            const idx = comptime nameIndex(names, name);
            return (self.bits >> idx) & 1 != 0;
        }

        fn clear(self: *Self, comptime name: []const u8) void {
            const idx = comptime nameIndex(names, name);
            self.bits &= ~(@as(u32, 1) << idx);
        }

        fn nameIndex(comptime ns: []const []const u8, comptime target: []const u8) u5 {
            for (ns, 0..) |n, i| {
                if (mem.eql(u8, n, target)) return @intCast(i);
            }
            @compileError("unknown flag: " ++ target);
        }
    };
}

// ── Main ─────────────────────────────────────────────────────────────

pub fn main() void {
    print("Macro Systems — Zig's comptime alternatives:\n\n", .{});

    // ── comptime functions ───────────────────────────────────────
    print("1. comptime functions (replaces C #define, Rust macros):\n", .{});

    // These are computed at compile time — zero runtime cost
    const fact10 = comptime factorial(10);
    assert(fact10 == 3628800);
    print("   factorial(10) = {d} (computed at compile time)\n", .{fact10});

    const fib20 = comptime fibonacci(20);
    assert(fib20 == 6765);
    print("   fibonacci(20) = {d} (computed at compile time)\n", .{fib20});

    // Lookup table generated at compile time
    const Sq = SquareTable(16);
    assert(Sq.get(0) == 0);
    assert(Sq.get(5) == 25);
    assert(Sq.get(15) == 225);
    print("   SquareTable(16): sq[5]={d}, sq[15]={d}\n\n", .{ Sq.get(5), Sq.get(15) });

    // ── @typeInfo reflection ─────────────────────────────────────
    print("2. @typeInfo reflection (replaces proc macros):\n", .{});

    const Config = struct {
        name: []const u8,
        port: u16,
        debug: bool,
    };

    const cfg = Config{ .name = "myapp", .port = 8080, .debug = true };
    var buf: [256]u8 = undefined;
    const serialized = serializeStruct(cfg, &buf);
    assert(mem.eql(u8, serialized, "name=myapp, port=8080, debug=true"));
    print("   Config serialized: \"{s}\"\n", .{serialized});

    // Works with any struct — no derive macro needed
    const Point = struct { x: i32, y: i32 };
    const pt = Point{ .x = 10, .y = 20 };
    var buf2: [64]u8 = undefined;
    const pt_s = serializeStruct(pt, &buf2);
    assert(mem.eql(u8, pt_s, "x=10, y=20"));
    print("   Point serialized: \"{s}\"\n\n", .{pt_s});

    // ── inline for ───────────────────────────────────────────────
    print("3. inline for (replaces macro repetition):\n", .{});

    const tuple = .{
        @as(u32, 42),      // 4 bytes
        @as(bool, true),   // 1 byte
        @as([]const u8, "hello"), // 5 bytes (slice len)
    };
    const total = processTuple(tuple);
    assert(total == 10); // 4 + 1 + 5
    print("   processTuple(u32, bool, []u8) = {d} bytes\n\n", .{total});

    // ── Generic types ────────────────────────────────────────────
    print("4. Generic types (replaces C macro-generated containers):\n", .{});

    var int_stack: Stack(i32, 8) = .{};
    assert(int_stack.push(10));
    assert(int_stack.push(20));
    assert(int_stack.push(30));
    assert(int_stack.peek().? == 30);
    assert(int_stack.pop().? == 30);
    assert(int_stack.pop().? == 20);
    assert(int_stack.len == 1);
    print("   Stack(i32, 8): push 10,20,30 -> pop 30,20 -> len={d}\n", .{int_stack.len});

    var str_stack: Stack([]const u8, 4) = .{};
    assert(str_stack.push("alpha"));
    assert(str_stack.push("beta"));
    assert(mem.eql(u8, str_stack.pop().?, "beta"));
    print("   Stack([]const u8, 4): push alpha,beta -> pop beta\n\n", .{});

    // ── comptime strings ─────────────────────────────────────────
    print("5. comptime string building:\n", .{});

    const repeated = repeatStr("ab", 4);
    assert(mem.eql(u8, repeated, "abababab"));
    print("   repeatStr(\"ab\", 4) = \"{s}\"\n", .{repeated});

    const joined = comptimeConcat("Hello", "World");
    assert(mem.eql(u8, joined, "HelloWorld"));
    print("   comptimeConcat(\"Hello\", \"World\") = \"{s}\"\n\n", .{joined});

    // ── Comptime-generated bitflags ──────────────────────────────
    print("6. Comptime enum/flag generation:\n", .{});

    const Perms = BitFlags(&.{ "read", "write", "execute" });
    var perms = Perms{};
    perms.set("read");
    perms.set("execute");
    assert(perms.isSet("read"));
    assert(!perms.isSet("write"));
    assert(perms.isSet("execute"));
    print("   Perms: read={}, write={}, execute={}\n", .{
        perms.isSet("read"),
        perms.isSet("write"),
        perms.isSet("execute"),
    });

    perms.clear("execute");
    assert(!perms.isSet("execute"));
    print("   After clear(execute): execute={}\n", .{perms.isSet("execute")});

    print("\nAll tests passed.\n", .{});
}
