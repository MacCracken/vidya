// Vidya — Write-Ahead Logging in Zig
//
// In-memory WAL: append a 24-byte log record (op, key, val) BEFORE
// mutating the data store, then replay the durable prefix on recovery.
// Zig's `[6144]u8` is the natural cousin of cyrius's flat byte buffer;
// `std.mem.writeInt`/`readInt` give us the load64/store64 primitives
// with explicit endianness — we pick `.little` to match cyrius. The
// 256-record cap and the OP_INVALID/SET/DEL constants mirror the
// reference. No real fsync — `log_committed` snapshots the durable
// prefix.

const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;

const REC_SZ: usize = 24;
const LOG_CAP_BYTES: usize = 6144;
const OP_INVALID: i64 = 0;
const OP_SET: i64 = 1;
const OP_DEL: i64 = 2;
const STORE_KEYS: usize = 16;

var log_buf: [LOG_CAP_BYTES]u8 = [_]u8{0} ** LOG_CAP_BYTES;
var log_offset: usize = 0;
var log_committed: usize = 0;

var data_vals: [STORE_KEYS]i64 = [_]i64{0} ** STORE_KEYS;
var data_present: [STORE_KEYS]u8 = [_]u8{0} ** STORE_KEYS;

fn logReset() void {
    log_offset = 0;
    log_committed = 0;
}

fn storeClear() void {
    var i: usize = 0;
    while (i < STORE_KEYS) : (i += 1) {
        data_vals[i] = 0;
        data_present[i] = 0;
    }
}

fn resetAll() void {
    logReset();
    storeClear();
    // Wipe the buffer so leftover bytes from a prior test don't ghost
    // into a fresh replay.
    var i: usize = 0;
    while (i < LOG_CAP_BYTES) : (i += 1) log_buf[i] = 0;
}

fn store64(off: usize, v: i64) void {
    std.mem.writeInt(i64, log_buf[off..][0..8], v, .little);
}

fn load64(off: usize) i64 {
    return std.mem.readInt(i64, log_buf[off..][0..8], .little);
}

// Returns 1 on success, 0 if buffer is full — matches cyrius.
fn logAppend(op: i64, key: i64, val: i64) i64 {
    if (log_offset + REC_SZ > LOG_CAP_BYTES) return 0;
    store64(log_offset + 0, op);
    store64(log_offset + 8, key);
    store64(log_offset + 16, val);
    log_offset += REC_SZ;
    return 1;
}

fn logCommit() usize {
    // Real implementations call fsync(wal_fd); we model durability with
    // an offset snapshot.
    log_committed = log_offset;
    return log_committed;
}

fn storeSet(key: i64, val: i64) i64 {
    if (key < 0 or key >= @as(i64, @intCast(STORE_KEYS))) return 0;
    // WAL rule: log BEFORE data.
    if (logAppend(OP_SET, key, val) == 0) return 0;
    const k: usize = @intCast(key);
    data_vals[k] = val;
    data_present[k] = 1;
    return 1;
}

fn storeDel(key: i64) i64 {
    if (key < 0 or key >= @as(i64, @intCast(STORE_KEYS))) return 0;
    if (logAppend(OP_DEL, key, 0) == 0) return 0;
    const k: usize = @intCast(key);
    data_vals[k] = 0;
    data_present[k] = 0;
    return 1;
}

fn storeGet(key: i64) i64 {
    if (key < 0 or key >= @as(i64, @intCast(STORE_KEYS))) return -1;
    const k: usize = @intCast(key);
    if (data_present[k] == 0) return -1;
    return data_vals[k];
}

fn replay() i64 {
    storeClear();
    var pos: usize = 0;
    var applied: i64 = 0;
    while (pos < log_committed) {
        const op = load64(pos + 0);
        const key = load64(pos + 8);
        const val = load64(pos + 16);
        if (op == OP_SET) {
            const k: usize = @intCast(key);
            data_vals[k] = val;
            data_present[k] = 1;
            applied += 1;
        } else if (op == OP_DEL) {
            const k: usize = @intCast(key);
            data_vals[k] = 0;
            data_present[k] = 0;
            applied += 1;
        }
        pos += REC_SZ;
    }
    return applied;
}

pub fn main() !void {
    _ = OP_INVALID; // referenced by spec

    // test_append_and_replay
    resetAll();
    _ = storeSet(0, 100);
    _ = storeSet(1, 200);
    _ = storeSet(2, 300);
    _ = logCommit();
    storeClear();
    assert(replay() == 3);
    assert(storeGet(0) == 100);
    assert(storeGet(1) == 200);
    assert(storeGet(2) == 300);

    // test_log_before_data_invariant
    resetAll();
    assert(storeSet(5, 42) == 1);
    assert(load64(0) == OP_SET);
    assert(load64(8) == 5);
    assert(load64(16) == 42);
    assert(storeGet(5) == 42);

    // test_uncommitted_writes_lost_on_crash
    resetAll();
    _ = storeSet(0, 1);
    _ = storeSet(1, 2);
    _ = logCommit();
    _ = storeSet(2, 3);
    _ = storeSet(3, 4);
    storeClear();
    assert(replay() == 2);
    assert(storeGet(0) == 1);
    assert(storeGet(1) == 2);
    assert(storeGet(2) == -1);
    assert(storeGet(3) == -1);

    // test_delete_replays_correctly
    resetAll();
    _ = storeSet(0, 100);
    _ = storeSet(1, 200);
    _ = storeDel(0);
    _ = logCommit();
    storeClear();
    _ = replay();
    assert(storeGet(0) == -1);
    assert(storeGet(1) == 200);

    // test_overwrite_uses_last_record
    resetAll();
    _ = storeSet(7, 100);
    _ = storeSet(7, 200);
    _ = storeSet(7, 300);
    _ = logCommit();
    storeClear();
    _ = replay();
    assert(storeGet(7) == 300);

    // test_sequential_offsets_monotonic
    resetAll();
    var prev: usize = log_offset;
    var i: i64 = 0;
    while (i < 5) : (i += 1) {
        _ = storeSet(i, i * 10);
        const now = log_offset;
        assert(now > prev);
        prev = now;
    }

    // test_log_capacity_limit
    resetAll();
    var failures: usize = 0;
    var j: i64 = 0;
    while (j < 300) : (j += 1) {
        if (storeSet(0, j) == 0) failures += 1;
    }
    assert(failures > 0);

    print("All write_ahead_logging examples passed.\n", .{});
}
