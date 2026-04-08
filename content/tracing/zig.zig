// Vidya — Tracing in Zig
//
// Zig's approach to observability:
//   1. std.log — structured logging with scopes and levels
//   2. Log scopes — per-module log namespaces
//   3. Comptime log level filtering — zero-cost disabled levels
//   4. Custom log functions — override the default logger
//   5. std.debug.print — unstructured debug output
//
// std.log is designed for production observability. std.debug.print
// is for development debugging. The distinction matters: log messages
// can be filtered, routed, and structured; print is fire-and-forget.

const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const mem = std.mem;

// ── 1. Custom log function ───────────────────────────────────────────
//
// Override the default logger by declaring pub const std_options.
// This is how you customize log output format, destination, and
// filtering. In a real application, you'd write to a file, syslog,
// or structured JSON output.
//
// Note: In a real application (not a demo), you would set:
//   pub const std_options: std.Options = .{
//       .logFn = myLogFn,
//       .log_level = .info,
//   };
//
// We cannot override std_options here because we need to capture log
// output for testing. Instead, we build our own logging system that
// demonstrates the same patterns.

// ── Log levels ───────────────────────────────────────────────────────
//
// std.log.Level has four levels (most to least verbose):
//   .debug — development-only, compiled out in release
//   .info  — normal operation events
//   .warn  — potential problems
//   .err   — errors that need attention
//
// At compile time, Zig eliminates all log calls below the configured
// level. log.debug in a release build = zero instructions. This is
// better than runtime filtering because it cannot be accidentally
// enabled in production.

const LogLevel = enum(u8) {
    debug = 0,
    info = 1,
    warn = 2,
    err = 3,

    fn label(self: LogLevel) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO ",
            .warn => "WARN ",
            .err => "ERROR",
        };
    }
};

// ── 2. Log scopes ────────────────────────────────────────────────────
//
// std.log.scoped(.tag) creates a logger namespaced to a module or
// subsystem. Each scope can have its own log level. This lets you
// enable debug logging for one module without flooding the output
// with debug messages from every other module.
//
// const log = std.log.scoped(.http);   // all messages tagged [http]
// const db_log = std.log.scoped(.db);  // all messages tagged [db]

// ── Our logging system (demonstrates the patterns) ───────────────────

const MAX_LOG_ENTRIES = 32;
const MAX_MSG_LEN = 128;

const LogEntry = struct {
    level: LogLevel,
    scope: []const u8,
    msg: [MAX_MSG_LEN]u8 = [_]u8{0} ** MAX_MSG_LEN,
    msg_len: usize = 0,

    fn message(self: *const LogEntry) []const u8 {
        return self.msg[0..self.msg_len];
    }
};

const Logger = struct {
    entries: [MAX_LOG_ENTRIES]LogEntry = undefined,
    count: usize = 0,
    min_level: LogLevel = .debug,

    /// Log a message at the given level with scope.
    fn log(self: *Logger, level: LogLevel, scope: []const u8, msg: []const u8) void {
        // Level filtering: skip messages below minimum level
        if (@intFromEnum(level) < @intFromEnum(self.min_level)) return;
        if (self.count >= MAX_LOG_ENTRIES) return;

        var entry = &self.entries[self.count];
        entry.level = level;
        entry.scope = scope;
        const len = @min(msg.len, MAX_MSG_LEN);
        @memcpy(entry.msg[0..len], msg[0..len]);
        entry.msg_len = len;
        self.count += 1;
    }

    fn debug(self: *Logger, scope: []const u8, msg: []const u8) void {
        self.log(.debug, scope, msg);
    }

    fn info(self: *Logger, scope: []const u8, msg: []const u8) void {
        self.log(.info, scope, msg);
    }

    fn warn(self: *Logger, scope: []const u8, msg: []const u8) void {
        self.log(.warn, scope, msg);
    }

    fn err(self: *Logger, scope: []const u8, msg: []const u8) void {
        self.log(.err, scope, msg);
    }

    /// Count entries at a specific level.
    fn countLevel(self: *const Logger, level: LogLevel) usize {
        var n: usize = 0;
        for (self.entries[0..self.count]) |*entry| {
            if (entry.level == level) n += 1;
        }
        return n;
    }

    /// Count entries for a specific scope.
    fn countScope(self: *const Logger, scope: []const u8) usize {
        var n: usize = 0;
        for (self.entries[0..self.count]) |*entry| {
            if (mem.eql(u8, entry.scope, scope)) n += 1;
        }
        return n;
    }

    /// Get last entry.
    fn last(self: *const Logger) ?*const LogEntry {
        if (self.count == 0) return null;
        return &self.entries[self.count - 1];
    }

    fn reset(self: *Logger) void {
        self.count = 0;
    }
};

// ── 3. Scoped logger — per-module logging ────────────────────────────
//
// Wraps a Logger with a fixed scope name. Each module creates its own
// ScopedLog. This mirrors std.log.scoped(.tag).

fn ScopedLog(comptime scope_name: []const u8) type {
    return struct {
        logger: *Logger,

        const Self = @This();

        fn init(logger: *Logger) Self {
            return .{ .logger = logger };
        }

        fn debug(self: Self, msg: []const u8) void {
            self.logger.debug(scope_name, msg);
        }

        fn info(self: Self, msg: []const u8) void {
            self.logger.info(scope_name, msg);
        }

        fn warn(self: Self, msg: []const u8) void {
            self.logger.warn(scope_name, msg);
        }

        fn err(self: Self, msg: []const u8) void {
            self.logger.err(scope_name, msg);
        }
    };
}

// ── 4. Comptime log level filtering ──────────────────────────────────
//
// Zig's std.log eliminates disabled log levels at compile time.
// We demonstrate the same pattern: a comptime-parameterized logger
// where calls below the threshold compile to nothing.

fn ComptimeLogger(comptime min: LogLevel) type {
    return struct {
        call_count: usize = 0,

        const Self = @This();

        fn log(self: *Self, comptime level: LogLevel, msg: []const u8) void {
            // comptime check: if level < min, this entire function
            // body is eliminated. Zero runtime cost.
            if (comptime @intFromEnum(level) < @intFromEnum(min)) return;
            _ = msg;
            self.call_count += 1;
        }

        fn debug(self: *Self, msg: []const u8) void {
            self.log(.debug, msg);
        }

        fn info(self: *Self, msg: []const u8) void {
            self.log(.info, msg);
        }

        fn warn(self: *Self, msg: []const u8) void {
            self.log(.warn, msg);
        }

        fn err(self: *Self, msg: []const u8) void {
            self.log(.err, msg);
        }
    };
}

// ── 5. Structured log formatting ─────────────────────────────────────
//
// Production loggers output structured formats (JSON, logfmt).
// Here we demonstrate building structured output from log data.

fn formatLogEntry(entry: *const LogEntry, buf: []u8) []const u8 {
    var pos: usize = 0;

    // Level
    const lvl = entry.level.label();
    @memcpy(buf[pos..][0..lvl.len], lvl);
    pos += lvl.len;
    buf[pos] = ' ';
    pos += 1;

    // Scope
    buf[pos] = '[';
    pos += 1;
    @memcpy(buf[pos..][0..entry.scope.len], entry.scope);
    pos += entry.scope.len;
    buf[pos] = ']';
    pos += 1;
    buf[pos] = ' ';
    pos += 1;

    // Message
    const msg = entry.message();
    @memcpy(buf[pos..][0..msg.len], msg);
    pos += msg.len;

    return buf[0..pos];
}

// ── Main ─────────────────────────────────────────────────────────────

pub fn main() void {
    print("Tracing — Zig's logging and observability:\n\n", .{});

    // ── Basic logging with levels ────────────────────────────────
    print("1. Log levels and filtering:\n", .{});
    {
        var logger = Logger{};

        logger.debug("app", "initializing subsystems");
        logger.info("app", "server started on port 8080");
        logger.warn("app", "config file missing, using defaults");
        logger.err("app", "database connection failed");

        assert(logger.count == 4);
        assert(logger.countLevel(.debug) == 1);
        assert(logger.countLevel(.info) == 1);
        assert(logger.countLevel(.warn) == 1);
        assert(logger.countLevel(.err) == 1);
        print("   Logged 4 messages: 1 debug, 1 info, 1 warn, 1 err\n", .{});

        // Level filtering: set minimum to .warn
        logger.reset();
        logger.min_level = .warn;

        logger.debug("app", "this is filtered out");
        logger.info("app", "this is filtered out too");
        logger.warn("app", "this passes the filter");
        logger.err("app", "this also passes");

        assert(logger.count == 2);
        assert(logger.entries[0].level == .warn);
        assert(logger.entries[1].level == .err);
        print("   With min_level=warn: {d} messages passed filter\n\n", .{logger.count});
    }

    // ── Scoped logging ───────────────────────────────────────────
    print("2. Log scopes (per-module logging):\n", .{});
    {
        var logger = Logger{};

        const http_log = ScopedLog("http").init(&logger);
        const db_log = ScopedLog("db").init(&logger);
        const auth_log = ScopedLog("auth").init(&logger);

        http_log.info("request received: GET /api/users");
        db_log.debug("query: SELECT * FROM users");
        auth_log.warn("token expires in 5 minutes");
        http_log.info("response sent: 200 OK");
        db_log.err("connection pool exhausted");

        assert(logger.count == 5);
        assert(logger.countScope("http") == 2);
        assert(logger.countScope("db") == 2);
        assert(logger.countScope("auth") == 1);
        print("   http: {d}, db: {d}, auth: {d} messages\n", .{
            logger.countScope("http"),
            logger.countScope("db"),
            logger.countScope("auth"),
        });

        // Verify scope tags are correct
        assert(mem.eql(u8, logger.entries[0].scope, "http"));
        assert(mem.eql(u8, logger.entries[1].scope, "db"));
        assert(mem.eql(u8, logger.entries[2].scope, "auth"));
        print("   Scopes correctly tagged on each entry\n\n", .{});
    }

    // ── Comptime level filtering ─────────────────────────────────
    print("3. Comptime log level filtering (zero-cost):\n", .{});
    {
        // Logger with min level = .warn at compile time
        // Debug and info calls compile to nothing — zero instructions
        var warn_logger: ComptimeLogger(.warn) = .{};
        warn_logger.debug("compiled away");
        warn_logger.info("compiled away");
        warn_logger.warn("this executes");
        warn_logger.err("this executes");
        assert(warn_logger.call_count == 2);
        print("   ComptimeLogger(.warn): 4 calls, {d} executed\n", .{warn_logger.call_count});

        // Logger that only keeps errors
        var err_logger: ComptimeLogger(.err) = .{};
        err_logger.debug("no-op");
        err_logger.info("no-op");
        err_logger.warn("no-op");
        err_logger.err("this runs");
        assert(err_logger.call_count == 1);
        print("   ComptimeLogger(.err): 4 calls, {d} executed\n", .{err_logger.call_count});

        // Debug logger keeps everything
        var debug_logger: ComptimeLogger(.debug) = .{};
        debug_logger.debug("kept");
        debug_logger.info("kept");
        debug_logger.warn("kept");
        debug_logger.err("kept");
        assert(debug_logger.call_count == 4);
        print("   ComptimeLogger(.debug): 4 calls, {d} executed\n\n", .{debug_logger.call_count});
    }

    // ── Structured log formatting ────────────────────────────────
    print("4. Structured log formatting:\n", .{});
    {
        var logger = Logger{};
        logger.info("http", "request handled");
        logger.err("db", "connection timeout");

        var fmt_buf: [256]u8 = undefined;

        const line1 = formatLogEntry(&logger.entries[0], &fmt_buf);
        assert(mem.eql(u8, line1, "INFO  [http] request handled"));
        print("   {s}\n", .{line1});

        const line2 = formatLogEntry(&logger.entries[1], &fmt_buf);
        assert(mem.eql(u8, line2, "ERROR [db] connection timeout"));
        print("   {s}\n\n", .{line2});
    }

    // ── std.debug.print — debug output ───────────────────────────
    print("5. std.debug.print — unstructured debug output:\n", .{});
    {
        // std.debug.print writes to stderr, not stdout.
        // It cannot be filtered, redirected, or structured.
        // Use for development only. Use std.log for production.
        //
        // print("value = {d}\n", .{42});          — formatted
        // print("{s}: {any}\n", .{"key", value}); — any type
        // print("{x:0>8}\n", .{0xDEAD});          — hex with padding
        // print("{b:0>8}\n", .{0b1010});           — binary

        print("   std.debug.print: stderr, no filtering, dev only\n", .{});
        print("   std.log: structured, filtered, production ready\n", .{});
        print("   Key: use print to debug, log to observe\n\n", .{});
    }

    // ── Log level labels ─────────────────────────────────────────
    print("6. Log level semantics:\n", .{});
    {
        assert(mem.eql(u8, LogLevel.debug.label(), "DEBUG"));
        assert(mem.eql(u8, LogLevel.info.label(), "INFO "));
        assert(mem.eql(u8, LogLevel.warn.label(), "WARN "));
        assert(mem.eql(u8, LogLevel.err.label(), "ERROR"));

        print("   .debug — verbose development info, compiled out in release\n", .{});
        print("   .info  — normal operation events (startup, shutdown)\n", .{});
        print("   .warn  — degraded but functional (fallbacks, retries)\n", .{});
        print("   .err   — failures requiring attention (crashes, data loss)\n", .{});
    }

    // ── std.log in practice ──────────────────────────────────────
    print("\n7. std.log usage patterns (reference):\n", .{});
    {
        // Standard usage in a real Zig application:
        //
        //   const std = @import("std");
        //   const log = std.log.scoped(.my_module);
        //
        //   pub const std_options: std.Options = .{
        //       .log_level = .info,  // compile-time minimum
        //   };
        //
        //   pub fn main() void {
        //       log.info("starting up", .{});
        //       log.debug("this is compiled out if log_level > .debug", .{});
        //       log.err("fatal: {s}", .{error_msg});
        //   }
        //
        // Custom log function:
        //
        //   pub const std_options: std.Options = .{
        //       .logFn = myCustomLog,
        //   };
        //
        //   fn myCustomLog(
        //       comptime level: std.log.Level,
        //       comptime scope: @TypeOf(.enum_literal),
        //       comptime fmt: []const u8,
        //       args: anytype,
        //   ) void {
        //       // Write to file, syslog, JSON, etc.
        //   }

        print("   const log = std.log.scoped(.module_name);\n", .{});
        print("   log.info(\"message\", .{{}});\n", .{});
        print("   Override via pub const std_options\n", .{});
    }

    print("\nAll tests passed.\n", .{});
}
