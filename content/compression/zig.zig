// Vidya — Compression (LZ77-shaped) in Zig
//
// Two-byte token stream matching cyrius.cyr:
//   {0, BYTE}      literal
//   {OFFSET, LEN}  match: copy LEN bytes from out[pos - OFFSET..]
// Greedy O(n^2) match-finder, 255-byte window. Decoder enforces an
// output-cap. Match copy is byte-by-byte so offset=1 acts as RLE.

const std = @import("std");

const MIN_MATCH: usize = 3;
const MAX_MATCH: usize = 255;
const WIN_SIZE: usize = 255;
const BUF_CAP: usize = 512;

fn matchLenAt(src: []const u8, hist: usize, pos: usize) usize {
    var n: usize = 0;
    var max = src.len - pos;
    if (max > MAX_MATCH) max = MAX_MATCH;
    while (n < max and src[hist + n] == src[pos + n]) : (n += 1) {}
    return n;
}

fn bestMatch(src: []const u8, pos: usize) ?struct { off: u8, len: u8 } {
    const win_start = if (pos > WIN_SIZE) pos - WIN_SIZE else 0;
    var best_off: usize = 0;
    var best_len: usize = 0;
    var i = win_start;
    while (i < pos) : (i += 1) {
        const n = matchLenAt(src, i, pos);
        if (n > best_len) {
            best_len = n;
            best_off = pos - i;
        }
    }
    if (best_len >= MIN_MATCH) return .{ .off = @intCast(best_off), .len = @intCast(best_len) };
    return null;
}

fn encode(src: []const u8, tok: *[BUF_CAP]u8) usize {
    var tpos: usize = 0;
    var pos: usize = 0;
    while (pos < src.len) {
        if (bestMatch(src, pos)) |m| {
            tok[tpos] = m.off;
            tok[tpos + 1] = m.len;
            tpos += 2;
            pos += m.len;
        } else {
            tok[tpos] = 0;
            tok[tpos + 1] = src[pos];
            tpos += 2;
            pos += 1;
        }
    }
    return tpos;
}

// Returns null on bomb-guard trigger, else decoded length.
fn decode(tok: []const u8, out_cap: usize, out: *[BUF_CAP]u8) ?usize {
    var pos: usize = 0;
    var i: usize = 0;
    while (i + 1 < tok.len) : (i += 2) {
        const b0 = tok[i];
        const b1 = tok[i + 1];
        if (b0 == 0) {
            if (pos + 1 > out_cap) return null;
            out[pos] = b1;
            pos += 1;
        } else {
            if (pos + b1 > out_cap) return null;
            var k: usize = 0;
            while (k < b1) : (k += 1) {
                out[pos + k] = out[pos - b0 + k];
            }
            pos += b1;
        }
    }
    return pos;
}

pub fn main() !void {
    var tok: [BUF_CAP]u8 = undefined;
    var out: [BUF_CAP]u8 = undefined;

    // 1. Round-trip with substring match
    const s1 = "ABCABCABC";
    const t1 = encode(s1, &tok);
    if (t1 == 0) return error.EncodeEmpty;
    const d1 = decode(tok[0..t1], BUF_CAP, &out) orelse return error.DecodeBomb;
    if (d1 != s1.len or !std.mem.eql(u8, out[0..d1], s1)) return error.BadRoundtrip1;

    // 2. Overlapping (RLE)
    const s2 = "AAAAAAAA";
    const t2 = encode(s2, &tok);
    const d2 = decode(tok[0..t2], BUF_CAP, &out) orelse return error.DecodeBomb;
    if (d2 != s2.len or !std.mem.eql(u8, out[0..d2], s2)) return error.BadRoundtrip2;
    if (t2 >= s2.len + 4) return error.NoCompression;

    // 3. Mostly literals
    const s3 = "Hello, World!";
    const t3 = encode(s3, &tok);
    const d3 = decode(tok[0..t3], BUF_CAP, &out) orelse return error.DecodeBomb;
    if (d3 != s3.len or !std.mem.eql(u8, out[0..d3], s3)) return error.BadRoundtrip3;

    // 4. Bomb guard
    const bomb = [_]u8{ 1, 200 };
    if (decode(&bomb, 10, &out) != null) return error.BombNotCaught;

    // 5. Empty input
    const t5 = encode("", &tok);
    if (t5 != 0) return error.EmptyEncodeBad;
    const d5 = decode(&[_]u8{}, BUF_CAP, &out) orelse return error.DecodeBomb;
    if (d5 != 0) return error.EmptyDecodeBad;

    std.debug.print("compression: 11/11 ok\n", .{});
}
