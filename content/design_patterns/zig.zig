// Vidya — Design Patterns in Zig
//
// Zig patterns: builder with init + chained methods, strategy via
// function pointers, state machine as enum with transition methods,
// RAII via defer, factory via tagged unions, and dependency injection
// via interface-like function pointers in a vtable struct.

const std = @import("std");
const expect = std.testing.expect;

pub fn main() !void {
    try testBuilderPattern();
    try testStrategyPattern();
    try testObserverPattern();
    try testStateMachine();
    try testRaiiDefer();
    try testFactoryPattern();
    try testDependencyInjection();

    std.debug.print("All design patterns examples passed.\n", .{});
}

// ── Builder pattern ──────────────────────────────────────────────────
// init + chained setter methods, build() validates required fields.

const Server = struct {
    host: []const u8,
    port: u16,
    max_connections: usize,
    timeout_ms: u64,
};

const ServerBuilder = struct {
    host: ?[]const u8 = null,
    port: ?u16 = null,
    max_connections: usize = 100,
    timeout_ms: u64 = 5000,

    fn init() ServerBuilder {
        return .{};
    }

    fn setHost(self: ServerBuilder, h: []const u8) ServerBuilder {
        var s = self;
        s.host = h;
        return s;
    }

    fn setPort(self: ServerBuilder, p: u16) ServerBuilder {
        var s = self;
        s.port = p;
        return s;
    }

    fn setMaxConnections(self: ServerBuilder, n: usize) ServerBuilder {
        var s = self;
        s.max_connections = n;
        return s;
    }

    fn setTimeoutMs(self: ServerBuilder, ms: u64) ServerBuilder {
        var s = self;
        s.timeout_ms = ms;
        return s;
    }

    fn build(self: ServerBuilder) !Server {
        return Server{
            .host = self.host orelse return error.HostRequired,
            .port = self.port orelse return error.PortRequired,
            .max_connections = self.max_connections,
            .timeout_ms = self.timeout_ms,
        };
    }
};

fn testBuilderPattern() !void {
    const server = try ServerBuilder.init()
        .setHost("localhost")
        .setPort(8080)
        .setMaxConnections(200)
        .setTimeoutMs(3000)
        .build();

    try expect(std.mem.eql(u8, server.host, "localhost"));
    try expect(server.port == 8080);
    try expect(server.max_connections == 200);
    try expect(server.timeout_ms == 3000);

    // Missing required field
    const result = ServerBuilder.init().setHost("localhost").build();
    try expect(result == error.PortRequired);
}

// ── Strategy pattern ─────────────────────────────────────────────────
// Function pointers — Zig's natural approach.

const DiscountFn = *const fn (f64) f64;

fn applyDiscount(price: f64, strategy: DiscountFn) f64 {
    return strategy(price);
}

fn noDiscount(p: f64) f64 {
    return p;
}

fn tenPercent(p: f64) f64 {
    return p * 0.9;
}

fn flatFive(p: f64) f64 {
    return if (p > 5.0) p - 5.0 else 0.0;
}

fn testStrategyPattern() !void {
    try expect(applyDiscount(100.0, noDiscount) == 100.0);
    try expect(applyDiscount(100.0, tenPercent) == 90.0);
    try expect(applyDiscount(100.0, flatFive) == 95.0);
    try expect(applyDiscount(3.0, flatFive) == 0.0);
}

// ── Observer pattern ─────────────────────────────────────────────────
// Array of function pointers for callbacks.

const MAX_LISTENERS = 8;

const EventEmitter = struct {
    listeners: [MAX_LISTENERS]?*const fn ([]const u8, *[64]u8, *usize) void = .{null} ** MAX_LISTENERS,
    count: usize = 0,

    fn on(self: *EventEmitter, cb: *const fn ([]const u8, *[64]u8, *usize) void) void {
        if (self.count < MAX_LISTENERS) {
            self.listeners[self.count] = cb;
            self.count += 1;
        }
    }

    fn emit(self: *const EventEmitter, event: []const u8, log: *[64]u8, log_pos: *usize) void {
        for (0..self.count) |i| {
            if (self.listeners[i]) |cb| {
                cb(event, log, log_pos);
            }
        }
    }
};

fn listenerA(event: []const u8, log: *[64]u8, pos: *usize) void {
    const prefix = "A:";
    @memcpy(log[pos.*..][0..prefix.len], prefix);
    pos.* += prefix.len;
    @memcpy(log[pos.*..][0..event.len], event);
    pos.* += event.len;
    log[pos.*] = ' ';
    pos.* += 1;
}

fn listenerB(event: []const u8, log: *[64]u8, pos: *usize) void {
    const prefix = "B:";
    @memcpy(log[pos.*..][0..prefix.len], prefix);
    pos.* += prefix.len;
    @memcpy(log[pos.*..][0..event.len], event);
    pos.* += event.len;
    log[pos.*] = ' ';
    pos.* += 1;
}

fn testObserverPattern() !void {
    var emitter = EventEmitter{};
    emitter.on(listenerA);
    emitter.on(listenerB);

    var log: [64]u8 = undefined;
    var pos: usize = 0;

    emitter.emit("click", &log, &pos);
    emitter.emit("hover", &log, &pos);

    // "A:click B:click A:hover B:hover "
    const expected = "A:click B:click A:hover B:hover ";
    try expect(std.mem.eql(u8, log[0..pos], expected));
}

// ── State machine as enum ────────────────────────────────────────────
// Each state is an enum variant. Transitions return error on invalid.

const DoorState = enum {
    locked,
    closed,
    open,

    fn unlock(self: DoorState) !DoorState {
        if (self == .locked) return .closed;
        return error.InvalidTransition;
    }

    fn doOpen(self: DoorState) !DoorState {
        if (self == .closed) return .open;
        return error.InvalidTransition;
    }

    fn doClose(self: DoorState) !DoorState {
        if (self == .open) return .closed;
        return error.InvalidTransition;
    }

    fn lock(self: DoorState) !DoorState {
        if (self == .closed) return .locked;
        return error.InvalidTransition;
    }
};

fn testStateMachine() !void {
    var door = DoorState.locked;
    door = try door.unlock();
    try expect(door == .closed);
    door = try door.doOpen();
    try expect(door == .open);
    door = try door.doClose();
    door = try door.lock();
    try expect(door == .locked);

    // Invalid transition
    const result = DoorState.locked.doOpen();
    try expect(result == error.InvalidTransition);
}

// ── RAII via defer ───────────────────────────────────────────────────
// defer ensures cleanup runs when scope exits — Zig's RAII.

fn testRaiiDefer() !void {
    var log: [4][16]u8 = undefined;
    var log_lens: [4]usize = .{0} ** 4;
    var log_count: usize = 0;

    {
        // Acquire db
        const msg1 = "acquire:db";
        @memcpy(log[log_count][0..msg1.len], msg1);
        log_lens[log_count] = msg1.len;
        log_count += 1;
        defer {
            const msg = "release:db";
            @memcpy(log[log_count][0..msg.len], msg);
            log_lens[log_count] = msg.len;
            log_count += 1;
        }

        // Acquire file
        const msg2 = "acquire:file";
        @memcpy(log[log_count][0..msg2.len], msg2);
        log_lens[log_count] = msg2.len;
        log_count += 1;
        defer {
            const msg = "release:file";
            @memcpy(log[log_count][0..msg.len], msg);
            log_lens[log_count] = msg.len;
            log_count += 1;
        }
    }

    try expect(log_count == 4);
    try expect(std.mem.eql(u8, log[0][0..log_lens[0]], "acquire:db"));
    try expect(std.mem.eql(u8, log[1][0..log_lens[1]], "acquire:file"));
    try expect(std.mem.eql(u8, log[2][0..log_lens[2]], "release:file")); // reverse order
    try expect(std.mem.eql(u8, log[3][0..log_lens[3]], "release:db"));
}

// ── Factory pattern ──────────────────────────────────────────────────
// Tagged union: each shape variant holds its own data.

const Shape = union(enum) {
    circle: struct { radius: f64 },
    rectangle: struct { width: f64, height: f64 },
    triangle: struct { base: f64, height: f64 },

    fn area(self: Shape) f64 {
        return switch (self) {
            .circle => |c| std.math.pi * c.radius * c.radius,
            .rectangle => |r| r.width * r.height,
            .triangle => |t| 0.5 * t.base * t.height,
        };
    }
};

fn shapeFactory(name: []const u8, params: []const f64) !Shape {
    if (std.mem.eql(u8, name, "circle")) {
        return Shape{ .circle = .{ .radius = params[0] } };
    } else if (std.mem.eql(u8, name, "rectangle")) {
        return Shape{ .rectangle = .{ .width = params[0], .height = params[1] } };
    } else if (std.mem.eql(u8, name, "triangle")) {
        return Shape{ .triangle = .{ .base = params[0], .height = params[1] } };
    }
    return error.UnknownShape;
}

fn testFactoryPattern() !void {
    const c = try shapeFactory("circle", &[_]f64{5.0});
    try expect(@abs(c.area() - 78.539) < 0.001);

    const r = try shapeFactory("rectangle", &[_]f64{ 3.0, 4.0 });
    try expect(r.area() == 12.0);

    const t = try shapeFactory("triangle", &[_]f64{ 6.0, 4.0 });
    try expect(t.area() == 12.0);

    const result = shapeFactory("hexagon", &[_]f64{1.0});
    try expect(result == error.UnknownShape);
}

// ── Dependency injection ─────────────────────────────────────────────
// Vtable-style: struct holds a function pointer for the log method.

const LoggerVTable = struct {
    logFn: *const fn (*anyopaque, []const u8, *[128]u8) usize,
    ptr: *anyopaque,

    fn log(self: LoggerVTable, msg: []const u8, buf: *[128]u8) usize {
        return self.logFn(self.ptr, msg, buf);
    }
};

const StdoutLogger = struct {
    fn log(ptr: *anyopaque, msg: []const u8, buf: *[128]u8) usize {
        _ = ptr;
        const prefix = "[stdout] ";
        @memcpy(buf[0..prefix.len], prefix);
        @memcpy(buf[prefix.len..][0..msg.len], msg);
        return prefix.len + msg.len;
    }

    fn vtable(self: *StdoutLogger) LoggerVTable {
        return .{
            .logFn = log,
            .ptr = @ptrCast(self),
        };
    }
};

const TestLoggerData = struct {
    entries: [8][64]u8 = undefined,
    entry_lens: [8]usize = .{0} ** 8,
    count: usize = 0,

    fn log(ptr: *anyopaque, msg: []const u8, buf: *[128]u8) usize {
        const self: *TestLoggerData = @ptrCast(@alignCast(ptr));
        const prefix = "[test] ";
        @memcpy(buf[0..prefix.len], prefix);
        @memcpy(buf[prefix.len..][0..msg.len], msg);
        const total = prefix.len + msg.len;
        // Record in entries
        @memcpy(self.entries[self.count][0..total], buf[0..total]);
        self.entry_lens[self.count] = total;
        self.count += 1;
        return total;
    }

    fn vtable(self: *TestLoggerData) LoggerVTable {
        return .{
            .logFn = log,
            .ptr = @ptrCast(self),
        };
    }
};

const ServiceZ = struct {
    logger: LoggerVTable,

    fn process(self: ServiceZ, item: []const u8, buf: *[128]u8) usize {
        var msg_buf: [128]u8 = undefined;
        const prefix = "processing ";
        @memcpy(msg_buf[0..prefix.len], prefix);
        @memcpy(msg_buf[prefix.len..][0..item.len], item);
        return self.logger.log(msg_buf[0 .. prefix.len + item.len], buf);
    }
};

fn testDependencyInjection() !void {
    // Production logger
    var stdout_logger = StdoutLogger{};
    const svc1 = ServiceZ{ .logger = stdout_logger.vtable() };
    var buf: [128]u8 = undefined;
    const len1 = svc1.process("order", &buf);
    try expect(std.mem.eql(u8, buf[0..len1], "[stdout] processing order"));

    // Test logger
    var test_logger = TestLoggerData{};
    const svc2 = ServiceZ{ .logger = test_logger.vtable() };
    _ = svc2.process("order-1", &buf);
    _ = svc2.process("order-2", &buf);
    try expect(test_logger.count == 2);
    try expect(std.mem.eql(u8, test_logger.entries[0][0..test_logger.entry_lens[0]], "[test] processing order-1"));
}
