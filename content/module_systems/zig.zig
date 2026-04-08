// Vidya — Module Systems in Zig
//
// Zig's module system is file-based and minimal:
//   1. @import — bring in a file or package as a namespace
//   2. pub — public visibility (default is private)
//   3. Struct namespacing — structs act as namespaces
//   4. build.zig — the build system and package manager
//   5. Packages — declared in build.zig.zon
//
// No header files (C), no mod.rs (Rust), no __init__.py (Python).
// Every .zig file is implicitly a struct. @import returns that struct.
// Visibility is binary: pub or private. No pub(crate), no friend.

const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const mem = std.mem;

// ── 1. @import — files as modules ────────────────────────────────────
//
// @import("std") — the standard library
// @import("foo.zig") — a local file
// @import("pkg") — a dependency declared in build.zig.zon
//
// Each import returns a struct. You bind it to a const:
//   const std = @import("std");
//   const math = std.math;     // sub-namespace
//   const print = std.debug.print;  // specific decl

// Simulating what an imported module looks like. Every .zig file
// is implicitly a struct with all its top-level declarations.

const math_module = struct {
    // pub declarations are visible to importers
    pub const pi: f64 = 3.14159265358979;
    pub const e: f64 = 2.71828182845904;

    pub fn square(x: f64) f64 {
        return x * x;
    }

    pub fn clamp(val: f64, lo: f64, hi: f64) f64 {
        if (val < lo) return lo;
        if (val > hi) return hi;
        return val;
    }

    // Private — not visible to importers. Like Rust's non-pub items.
    fn internalHelper() void {}
};

// ── 2. pub visibility ────────────────────────────────────────────────
//
// Default is private (file-scoped). Only pub items are visible
// to other files that @import this one.
//
// Zig has no pub(crate) or pub(super) like Rust. It's binary:
//   - pub: visible to everyone who imports this file
//   - (default): visible only within this file

const visibility_demo = struct {
    pub const PUBLIC_CONST: i32 = 42;
    const PRIVATE_CONST: i32 = 99; // only visible in this struct

    pub fn publicFn() i32 {
        return privateFn() + 1; // private fn usable internally
    }

    fn privateFn() i32 {
        return PRIVATE_CONST;
    }
};

// ── 3. Struct namespacing ────────────────────────────────────────────
//
// Zig uses structs as namespaces. No separate module/namespace keyword.
// Methods, constants, and nested types live inside the struct.
// This is the idiomatic way to organize related code.

const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    // Associated constants — like Rust's impl block constants
    pub const RED = Color{ .r = 255, .g = 0, .b = 0 };
    pub const GREEN = Color{ .r = 0, .g = 255, .b = 0 };
    pub const BLUE = Color{ .r = 0, .g = 0, .b = 255 };
    pub const WHITE = Color{ .r = 255, .g = 255, .b = 255 };

    // Methods use the struct as first parameter
    pub fn eql(self: Color, other: Color) bool {
        return self.r == other.r and self.g == other.g and self.b == other.b;
    }

    pub fn mix(self: Color, other: Color) Color {
        return .{
            .r = @intCast((@as(u16, self.r) + @as(u16, other.r)) / 2),
            .g = @intCast((@as(u16, self.g) + @as(u16, other.g)) / 2),
            .b = @intCast((@as(u16, self.b) + @as(u16, other.b)) / 2),
        };
    }

    // Nested namespace for utilities
    pub const utils = struct {
        pub fn brightness(c: Color) u16 {
            return @as(u16, c.r) + @as(u16, c.g) + @as(u16, c.b);
        }
    };
};

// ── 4. Opaque types — encapsulation ──────────────────────────────────
//
// Zig structs with only pub methods and private fields enforce
// encapsulation. External code cannot access internals.

const Counter = struct {
    value: i64, // private field — not accessible outside this struct

    pub fn init(start: i64) Counter {
        return .{ .value = start };
    }

    pub fn increment(self: *Counter) void {
        self.value += 1;
    }

    pub fn decrement(self: *Counter) void {
        self.value -= 1;
    }

    pub fn get(self: Counter) i64 {
        return self.value;
    }
};

// ── 5. Comptime namespaces — conditional compilation ─────────────────
//
// Zig's comptime replaces C's #ifdef for platform-specific code.
// No preprocessor, no feature flags — just comptime if.

const platform = struct {
    const os = @import("std").Target.Os.Tag;

    pub fn pageSize() usize {
        // comptime switch on build target — like Rust's cfg!
        return switch (@import("builtin").os.tag) {
            .linux => 4096,
            .macos => 16384, // Apple Silicon uses 16K pages
            .windows => 4096,
            else => 4096,
        };
    }

    pub fn pathSeparator() u8 {
        return if (@import("builtin").os.tag == .windows) '\\' else '/';
    }
};

// ── 6. Re-exporting — selective pub const ────────────────────────────
//
// Zig has no `pub use` (Rust) or `export` (JS). Instead, you
// re-export by making a pub const that refers to the import:
//   pub const Thing = @import("thing.zig").Thing;

const inner_module = struct {
    pub const Value = struct {
        data: i32,

        pub fn double(self: Value) i32 {
            return self.data * 2;
        }
    };

    pub const Error = error{ InvalidInput, Overflow };
};

// Re-export: consumers see top-level names
// In a multi-file project, this would be in a different file from inner_module.
// Here we use a different name to avoid shadowing the nested definition.
const ReexportedValue = inner_module.Value;
const ModuleError = inner_module.Error;

// ── 7. build.zig — the build system as a module ──────────────────────
//
// build.zig is itself Zig code. It declares:
//   - Executables, libraries, tests
//   - Dependencies (from build.zig.zon)
//   - Install targets
//   - Custom build steps
//
// Example build.zig (not executable here, just documented):
//
//   const std = @import("std");
//
//   pub fn build(b: *std.Build) void {
//       const target = b.standardTargetOptions(.{});
//       const optimize = b.standardOptimizeOption(.{});
//
//       const exe = b.addExecutable(.{
//           .name = "myapp",
//           .root_source_file = b.path("src/main.zig"),
//           .target = target,
//           .optimize = optimize,
//       });
//
//       // Add a dependency declared in build.zig.zon
//       const dep = b.dependency("some_lib", .{});
//       exe.root_module.addImport("some_lib", dep.module("some_lib"));
//
//       b.installArtifact(exe);
//   }
//
// build.zig.zon declares packages:
//
//   .dependencies = .{
//       .some_lib = .{
//           .url = "https://...",
//           .hash = "...",
//       },
//   },

// ── Main ─────────────────────────────────────────────────────────────

pub fn main() void {
    print("Module Systems — Zig's file-based modules:\n\n", .{});

    // ── @import and namespace access ─────────────────────────────
    print("1. @import — files as structs:\n", .{});
    assert(math_module.pi > 3.14 and math_module.pi < 3.15);
    assert(math_module.square(5.0) == 25.0);
    assert(math_module.clamp(10.0, 0.0, 5.0) == 5.0);
    assert(math_module.clamp(-1.0, 0.0, 5.0) == 0.0);
    print("   math_module.pi = {d:.4}\n", .{math_module.pi});
    print("   math_module.square(5) = {d:.0}\n", .{math_module.square(5.0)});
    print("   math_module.clamp(10, 0, 5) = {d:.0}\n\n", .{math_module.clamp(10.0, 0.0, 5.0)});

    // ── pub visibility ───────────────────────────────────────────
    print("2. pub visibility:\n", .{});
    assert(visibility_demo.PUBLIC_CONST == 42);
    assert(visibility_demo.publicFn() == 100);
    // visibility_demo.PRIVATE_CONST — would be compile error from outside
    // visibility_demo.privateFn() — would be compile error from outside
    print("   PUBLIC_CONST = {d}\n", .{visibility_demo.PUBLIC_CONST});
    print("   publicFn() = {d} (calls private internals)\n\n", .{visibility_demo.publicFn()});

    // ── Struct namespacing ───────────────────────────────────────
    print("3. Struct namespacing:\n", .{});
    const red = Color.RED;
    const blue = Color.BLUE;
    assert(red.r == 255 and red.g == 0 and red.b == 0);
    assert(red.eql(Color.RED));
    assert(!red.eql(blue));
    print("   Color.RED = ({d}, {d}, {d})\n", .{ red.r, red.g, red.b });

    const mixed = red.mix(blue);
    assert(mixed.r == 127 and mixed.g == 0 and mixed.b == 127);
    print("   RED.mix(BLUE) = ({d}, {d}, {d})\n", .{ mixed.r, mixed.g, mixed.b });

    // Nested namespace
    const bright = Color.utils.brightness(Color.WHITE);
    assert(bright == 765);
    print("   Color.utils.brightness(WHITE) = {d}\n\n", .{bright});

    // ── Encapsulation ────────────────────────────────────────────
    print("4. Encapsulation via pub/private:\n", .{});
    var counter = Counter.init(0);
    counter.increment();
    counter.increment();
    counter.increment();
    counter.decrement();
    assert(counter.get() == 2);
    // counter.value — accessible here (same file), but would be
    // private from another file that @imports this one.
    print("   Counter: init(0) + 3 inc - 1 dec = {d}\n\n", .{counter.get()});

    // ── Platform-specific compilation ────────────────────────────
    print("5. comptime platform selection:\n", .{});
    const page_sz = platform.pageSize();
    assert(page_sz > 0);
    print("   Page size: {d}\n", .{page_sz});
    const sep = platform.pathSeparator();
    assert(sep == '/' or sep == '\\');
    print("   Path separator: '{c}'\n\n", .{sep});

    // ── Re-exports ───────────────────────────────────────────────
    print("6. Re-exporting:\n", .{});
    const v = ReexportedValue{ .data = 21 };
    assert(v.double() == 42);
    print("   ReexportedValue{{.data=21}}.double() = {d}\n", .{v.double()});
    // ModuleError is accessible at top level, not inner_module.Error
    _ = ModuleError;
    print("   ModuleError re-exported from inner_module\n\n", .{});

    // ── std library structure ────────────────────────────────────
    print("7. std library module structure:\n", .{});
    print("   std.mem      — memory operations\n", .{});
    print("   std.math     — math functions\n", .{});
    print("   std.heap     — allocators (GPA, Arena, FixedBuffer)\n", .{});
    print("   std.debug    — print, assert\n", .{});
    print("   std.testing  — test framework\n", .{});
    print("   std.fs       — filesystem\n", .{});
    print("   std.Thread   — threading\n", .{});
    print("   std.atomic   — atomic operations\n", .{});
    print("   std.Build    — build system API\n", .{});

    print("\nAll tests passed.\n", .{});
}
