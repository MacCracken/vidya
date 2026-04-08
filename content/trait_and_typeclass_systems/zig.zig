// Vidya — Trait and Typeclass Systems in Zig
//
// Zig has no traits, interfaces, or typeclasses. Instead:
//   1. Comptime duck typing — functions accept anytype, checked at compile time
//   2. @typeInfo for reflection — inspect types at comptime
//   3. Vtable pattern — *anyopaque + function pointers for runtime polymorphism
//   4. std.mem.Allocator — the stdlib's canonical interface pattern
//
// The philosophy: traits constrain what you can pass. Zig constrains
// what you can do with what you receive. If it compiles, it works.

const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const mem = std.mem;

// ── 1. Comptime duck typing ─────────────────────────────────────────
//
// anytype accepts any type. The compiler checks usage at the call site.
// If Circle has .area(), it works. If u32 doesn't, it fails at comptime.
// This is like Go's structural typing, but resolved at compile time.

const Circle = struct {
    radius: f64,

    fn area(self: Circle) f64 {
        return std.math.pi * self.radius * self.radius;
    }

    fn name(_: Circle) []const u8 {
        return "Circle";
    }
};

const Rectangle = struct {
    width: f64,
    height: f64,

    fn area(self: Rectangle) f64 {
        return self.width * self.height;
    }

    fn name(_: Rectangle) []const u8 {
        return "Rectangle";
    }
};

const Triangle = struct {
    base: f64,
    height: f64,

    fn area(self: Triangle) f64 {
        return 0.5 * self.base * self.height;
    }

    fn name(_: Triangle) []const u8 {
        return "Triangle";
    }
};

/// Works with any type that has .area() -> f64 and .name() -> []const u8.
/// No trait bound declaration — just use it. Compiler errors if missing.
fn printArea(shape: anytype) f64 {
    const a = shape.area();
    print("   {s}: area = {d:.2}\n", .{ shape.name(), a });
    return a;
}

/// Comptime generic: works with any type that has .area().
/// Returns the total area of a slice of shapes (all same type).
fn totalArea(shapes: anytype) f64 {
    var sum: f64 = 0;
    for (shapes) |s| {
        sum += s.area();
    }
    return sum;
}

// ── 2. @typeInfo for compile-time reflection ─────────────────────────
//
// @typeInfo returns a tagged union describing any type's structure.
// Use it to build generic code that adapts to type shape.

/// Count the number of fields in a struct at compile time.
fn fieldCount(comptime T: type) usize {
    return switch (@typeInfo(T)) {
        .@"struct" => |info| info.fields.len,
        else => 0,
    };
}

/// Check if a type has a specific declaration at compile time.
/// @hasDecl checks both public and private declarations.
fn hasMethod(comptime T: type, comptime name: []const u8) bool {
    return @hasDecl(T, name);
}

/// Comptime type constraint: assert a type has required methods.
/// This is the closest Zig gets to a trait bound declaration.
fn assertShape(comptime T: type) void {
    if (!hasMethod(T, "area")) {
        @compileError("Type must have an area() method");
    }
    if (!hasMethod(T, "name")) {
        @compileError("Type must have a name() method");
    }
}

/// Generic function with explicit comptime constraint.
fn describeShape(shape: anytype) []const u8 {
    const T = @TypeOf(shape);
    comptime assertShape(T);
    return shape.name();
}

// ── 3. Vtable pattern — runtime polymorphism ─────────────────────────
//
// Zig has no dyn Trait. For runtime dispatch, build a vtable manually:
// a struct with function pointers + an erased *anyopaque pointer.
// This is exactly what Rust's dyn Trait compiles to under the hood.

const ShapeVTable = struct {
    areaFn: *const fn (ctx: *const anyopaque) f64,
    nameFn: *const fn (ctx: *const anyopaque) []const u8,
    ctx: *const anyopaque,

    fn area(self: ShapeVTable) f64 {
        return self.areaFn(self.ctx);
    }

    fn name(self: ShapeVTable) []const u8 {
        return self.nameFn(self.ctx);
    }
};

/// Create a vtable from any concrete shape type.
/// This is the "impl Trait for T" equivalent — done at comptime.
fn shapeVTable(comptime T: type, ptr: *const T) ShapeVTable {
    return .{
        .areaFn = struct {
            fn f(ctx: *const anyopaque) f64 {
                const self: *const T = @ptrCast(@alignCast(ctx));
                return self.area();
            }
        }.f,
        .nameFn = struct {
            fn f(ctx: *const anyopaque) []const u8 {
                const self: *const T = @ptrCast(@alignCast(ctx));
                return self.name();
            }
        }.f,
        .ctx = @ptrCast(ptr),
    };
}

/// Accept any shape via vtable — runtime polymorphism.
fn computeArea(shape: ShapeVTable) f64 {
    return shape.area();
}

// ── 4. std.mem.Allocator pattern ─────────────────────────────────────
//
// The stdlib Allocator is Zig's canonical interface pattern:
//   - A struct with a pointer (*anyopaque) and a vtable
//   - Implementations provide the vtable, callers use the interface
//   - No dynamic dispatch overhead when the compiler can inline
//
// We replicate this pattern for a Writer interface.

const Writer = struct {
    ctx: *anyopaque,
    writeFn: *const fn (ctx: *anyopaque, data: []const u8) usize,

    fn write(self: Writer, data: []const u8) usize {
        return self.writeFn(self.ctx, data);
    }
};

const BufferWriter = struct {
    buf: [256]u8 = undefined,
    pos: usize = 0,

    fn write(ctx: *anyopaque, data: []const u8) usize {
        const self: *BufferWriter = @ptrCast(@alignCast(ctx));
        const len = @min(data.len, 256 - self.pos);
        @memcpy(self.buf[self.pos..][0..len], data[0..len]);
        self.pos += len;
        return len;
    }

    fn writer(self: *BufferWriter) Writer {
        return .{
            .ctx = @ptrCast(self),
            .writeFn = BufferWriter.write,
        };
    }

    fn written(self: *const BufferWriter) []const u8 {
        return self.buf[0..self.pos];
    }
};

const CountingWriter = struct {
    total: usize = 0,

    fn write(ctx: *anyopaque, data: []const u8) usize {
        const self: *CountingWriter = @ptrCast(@alignCast(ctx));
        self.total += data.len;
        return data.len;
    }

    fn writer(self: *CountingWriter) Writer {
        return .{
            .ctx = @ptrCast(self),
            .writeFn = CountingWriter.write,
        };
    }
};

/// Function that accepts the Writer interface — works with any impl.
fn writeGreeting(w: Writer, name: []const u8) usize {
    var total: usize = 0;
    total += w.write("Hello, ");
    total += w.write(name);
    total += w.write("!");
    return total;
}

// ── 5. Inline dispatch with tagged union ─────────────────────────────
//
// When the set of types is known, use a tagged union instead of vtable.
// Switch dispatch — no pointer indirection, cache-friendly.

const AnyShape = union(enum) {
    circle: Circle,
    rectangle: Rectangle,
    triangle: Triangle,

    fn area(self: AnyShape) f64 {
        return switch (self) {
            .circle => |c| c.area(),
            .rectangle => |r| r.area(),
            .triangle => |t| t.area(),
        };
    }

    fn name(self: AnyShape) []const u8 {
        return switch (self) {
            .circle => |c| c.name(),
            .rectangle => |r| r.name(),
            .triangle => |t| t.name(),
        };
    }
};

// ── Main ─────────────────────────────────────────────────────────────

pub fn main() void {
    print("Trait and Typeclass Systems — Zig's alternatives:\n\n", .{});

    // ── Comptime duck typing ─────────────────────────────────────
    print("1. Comptime duck typing (anytype):\n", .{});
    const c = Circle{ .radius = 5.0 };
    const r = Rectangle{ .width = 3.0, .height = 4.0 };
    const t = Triangle{ .base = 6.0, .height = 4.0 };

    const ca = printArea(c);
    const ra = printArea(r);
    const ta = printArea(t);
    assert(@abs(ca - 78.539) < 0.01);
    assert(ra == 12.0);
    assert(ta == 12.0);

    // Generic over slices of same type
    const circles = [_]Circle{
        .{ .radius = 1.0 },
        .{ .radius = 2.0 },
        .{ .radius = 3.0 },
    };
    const total = totalArea(&circles);
    assert(@abs(total - 43.982) < 0.01); // pi*(1+4+9)
    print("   Total area of 3 circles: {d:.2}\n\n", .{total});

    // ── @typeInfo reflection ─────────────────────────────────────
    print("2. @typeInfo compile-time reflection:\n", .{});
    assert(fieldCount(Circle) == 1);
    assert(fieldCount(Rectangle) == 2);
    assert(fieldCount(Triangle) == 2);
    print("   Circle fields: {d}\n", .{fieldCount(Circle)});
    print("   Rectangle fields: {d}\n", .{fieldCount(Rectangle)});

    assert(hasMethod(Circle, "area"));
    assert(hasMethod(Circle, "name"));
    assert(!hasMethod(Circle, "perimeter"));
    print("   Circle has area: true\n", .{});
    print("   Circle has perimeter: false\n", .{});

    // Comptime constraint check
    const desc = describeShape(c);
    assert(mem.eql(u8, desc, "Circle"));
    print("   describeShape(circle) = \"{s}\"\n\n", .{desc});

    // ── Vtable pattern ───────────────────────────────────────────
    print("3. Vtable pattern (runtime polymorphism):\n", .{});
    const shapes = [_]ShapeVTable{
        shapeVTable(Circle, &c),
        shapeVTable(Rectangle, &r),
        shapeVTable(Triangle, &t),
    };

    var vtable_total: f64 = 0;
    for (shapes) |s| {
        const a = computeArea(s);
        print("   {s} via vtable: {d:.2}\n", .{ s.name(), a });
        vtable_total += a;
    }
    assert(@abs(vtable_total - (ca + ra + ta)) < 0.001);
    print("   Total via vtable: {d:.2}\n\n", .{vtable_total});

    // ── Writer interface (Allocator pattern) ─────────────────────
    print("4. Writer interface (std.mem.Allocator pattern):\n", .{});

    var buf_writer = BufferWriter{};
    const bw_len = writeGreeting(buf_writer.writer(), "Zig");
    assert(bw_len == 11); // "Hello, Zig!"
    assert(mem.eql(u8, buf_writer.written(), "Hello, Zig!"));
    print("   BufferWriter: \"{s}\"\n", .{buf_writer.written()});

    var cnt_writer = CountingWriter{};
    const cw_len = writeGreeting(cnt_writer.writer(), "World");
    assert(cw_len == 13); // "Hello, World!"
    assert(cnt_writer.total == 13);
    print("   CountingWriter: {d} bytes\n\n", .{cnt_writer.total});

    // ── Tagged union dispatch ────────────────────────────────────
    print("5. Tagged union dispatch (closed set):\n", .{});
    const any_shapes = [_]AnyShape{
        .{ .circle = c },
        .{ .rectangle = r },
        .{ .triangle = t },
    };

    var union_total: f64 = 0;
    for (any_shapes) |s| {
        print("   {s}: {d:.2}\n", .{ s.name(), s.area() });
        union_total += s.area();
    }
    assert(@abs(union_total - vtable_total) < 0.001);
    print("   Total: {d:.2}\n", .{union_total});

    print("\nAll tests passed.\n", .{});
}
