// Vidya — Serialization in Zig
//
// Varint (LEB128) + length-prefix framing + stream parser + DoS guards.

const std = @import("std");

const MAX_VARINT_BYTES: usize = 10;
const MAX_MSG_SIZE: u64 = 1024;

fn encodeVarint(value_in: u64, out: []u8) usize {
    var value = value_in;
    var n: usize = 0;
    while (value >= 128) {
        out[n] = @intCast((value & 0x7F) | 0x80);
        value >>= 7;
        n += 1;
    }
    out[n] = @intCast(value & 0x7F);
    return n + 1;
}

const VarintResult = struct { value: u64, consumed: usize };

fn decodeVarint(buf: []const u8) ?VarintResult {
    var value: u64 = 0;
    var shift: u32 = 0;          // Wider than u6 so the +=7 at the
                                  // end of iteration 9 (shift=63→70)
                                  // doesn't trip an integer-overflow
                                  // panic before the loop boundary
                                  // check returns null.
    var i: usize = 0;
    while (i < MAX_VARINT_BYTES) : (i += 1) {
        if (i >= buf.len) return null;
        const b = buf[i];
        value += @as(u64, b & 0x7F) << @intCast(shift);
        if (b & 0x80 == 0) return VarintResult{ .value = value, .consumed = i + 1 };
        shift += 7;
    }
    return null;
}

fn encodeFrame(payload: []const u8, out: []u8) usize {
    const hdr = encodeVarint(payload.len, out);
    @memcpy(out[hdr..hdr + payload.len], payload);
    return hdr + payload.len;
}

const FrameResult = struct { len: usize, consumed: usize };

fn decodeFrame(buf: []const u8, max_msg: u64, payload_out: []u8) ?FrameResult {
    const r = decodeVarint(buf) orelse return null;
    if (r.value > max_msg) return null;
    const total = r.consumed + @as(usize, @intCast(r.value));
    if (total > buf.len) return null;
    @memcpy(payload_out[0..@intCast(r.value)], buf[r.consumed..total]);
    return FrameResult{ .len = @intCast(r.value), .consumed = total };
}

pub fn main() !void {
    var buf: [64]u8 = undefined;
    var pl: [64]u8 = undefined;

    if (encodeVarint(0, &buf) != 1 or buf[0] != 0) return error.V0;
    if (encodeVarint(127, &buf) != 1 or buf[0] != 0x7F) return error.V127;
    if (encodeVarint(128, &buf) != 2 or buf[0] != 0x80 or buf[1] != 0x01) return error.V128;
    if (encodeVarint(16383, &buf) != 2) return error.V16383;
    if (encodeVarint(16384, &buf) != 3) return error.V16384;

    const n = encodeVarint(1234567890, &buf);
    const r = decodeVarint(buf[0..n]) orelse return error.RoundtripDecode;
    if (r.value != 1234567890 or r.consumed != n) return error.Roundtrip;

    const bomb = [_]u8{0xFF} ** 11;
    if (decodeVarint(&bomb) != null) return error.Overflow;

    const payload = "hello, world";
    const fn_ = encodeFrame(payload, &buf);
    if (fn_ != 13 or buf[0] != 12) return error.Frame;
    const fr = decodeFrame(buf[0..fn_], MAX_MSG_SIZE, &pl) orelse return error.FrameDecode;
    if (fr.consumed != 13) return error.FrameConsumed;
    if (!std.mem.eql(u8, pl[0..fr.len], payload)) return error.FrameBytes;

    var stream: [256]u8 = undefined;
    var off: usize = 0;
    off += encodeFrame("AAA", stream[off..]);
    off += encodeFrame("BBBB", stream[off..]);
    off += encodeFrame("CCCCC", stream[off..]);
    var pos: usize = 0;
    var msgs: usize = 0;
    while (pos < off) {
        const dr = decodeFrame(stream[pos..off], MAX_MSG_SIZE, &pl) orelse break;
        msgs += 1;
        pos += dr.consumed;
    }
    if (msgs != 3) return error.Stream;

    const trunc = [_]u8{ 100, 'B', 'C', 'D', 'E', 'F' };
    if (decodeFrame(&trunc, MAX_MSG_SIZE, &pl) != null) return error.Trunc;

    var over: [16]u8 = undefined;
    const oh = encodeVarint(9999, &over);
    if (decodeFrame(over[0..oh], MAX_MSG_SIZE, &pl) != null) return error.Oversize;

    std.debug.print("serialization: 19/19 ok\n", .{});
}
