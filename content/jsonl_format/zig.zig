// Vidya — JSON Lines (JSONL) in Zig
//
// In-memory JSONL primitives mirroring cyrius.cyr.

const std = @import("std");

const BUF_CAP: usize = 1024;
const ESC_CAP: usize = 256;

var jsonl_buf: [BUF_CAP]u8 = undefined;
var jsonl_len: usize = 0;
var line_offsets: [64]usize = undefined;
var line_lengths: [64]usize = undefined;
var line_count: usize = 0;
var esc_buf: [ESC_CAP]u8 = undefined;
var unesc_buf: [ESC_CAP]u8 = undefined;

fn appendRecord(rec: []const u8) void {
    @memcpy(jsonl_buf[jsonl_len..jsonl_len + rec.len], rec);
    jsonl_len += rec.len;
    jsonl_buf[jsonl_len] = '\n';
    jsonl_len += 1;
}

fn buildIndex() void {
    line_count = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i < jsonl_len) : (i += 1) {
        if (jsonl_buf[i] == '\n') {
            line_offsets[line_count] = start;
            line_lengths[line_count] = i - start;
            line_count += 1;
            start = i + 1;
        }
    }
    if (start < jsonl_len) {
        line_offsets[line_count] = start;
        line_lengths[line_count] = jsonl_len - start;
        line_count += 1;
    }
}

// Returns escaped length, or -1 on bounds-check failure.
fn jsonEscape(dst: []u8, src: []const u8) i64 {
    if (src.len * 2 > dst.len) return -1;
    var w: usize = 0;
    for (src) |c| {
        switch (c) {
            '"'  => { dst[w] = '\\'; dst[w + 1] = '"'; w += 2; },
            '\\' => { dst[w] = '\\'; dst[w + 1] = '\\'; w += 2; },
            '\n' => { dst[w] = '\\'; dst[w + 1] = 'n'; w += 2; },
            '\t' => { dst[w] = '\\'; dst[w + 1] = 't'; w += 2; },
            '\r' => { dst[w] = '\\'; dst[w + 1] = 'r'; w += 2; },
            else => { dst[w] = c; w += 1; },
        }
    }
    return @intCast(w);
}

fn jsonUnescape(dst: []u8, src: []const u8) usize {
    var w: usize = 0;
    var i: usize = 0;
    while (i < src.len) {
        if (src[i] == '\\' and i + 1 < src.len) {
            switch (src[i + 1]) {
                '"'  => { dst[w] = '"';  w += 1; i += 2; },
                '\\' => { dst[w] = '\\'; w += 1; i += 2; },
                'n'  => { dst[w] = '\n'; w += 1; i += 2; },
                't'  => { dst[w] = '\t'; w += 1; i += 2; },
                'r'  => { dst[w] = '\r'; w += 1; i += 2; },
                else => { dst[w] = src[i]; w += 1; i += 1; },
            }
        } else {
            dst[w] = src[i];
            w += 1;
            i += 1;
        }
    }
    return w;
}

pub fn main() !void {
    // Test 1
    appendRecord("{\"id\":1}");
    appendRecord("{\"id\":2}");
    appendRecord("{\"id\":3}");
    buildIndex();
    if (line_count != 3) return error.BadCount;
    if (line_lengths[2] != 8) return error.BadLength;
    const third = jsonl_buf[line_offsets[2] .. line_offsets[2] + line_lengths[2]];
    if (!std.mem.eql(u8, third, "{\"id\":3}")) return error.BadBytes;

    // Test 2: no trailing newline
    if (jsonl_len > 0 and jsonl_buf[jsonl_len - 1] == '\n') jsonl_len -= 1;
    buildIndex();
    if (line_count != 3) return error.BadCountNoNl;

    // Test 3: escape
    const s3 = [_]u8{ 's', 'a', 'y', ' ', '"', 'h', 'i', '"', '\t', '\n', '\r', '\\' };
    const en = jsonEscape(&esc_buf, &s3);
    if (en != 18) return error.BadEscape;

    // Test 4: bounds check
    const s4 = [_]u8{ '"', '"', '"', '"' };
    var tiny: [4]u8 = undefined;
    if (jsonEscape(&tiny, &s4) != -1) return error.BoundsNotChecked;

    // Test 5: roundtrip
    const un = jsonUnescape(&unesc_buf, esc_buf[0..@intCast(en)]);
    if (un != 12) return error.BadUnescape;
    if (!std.mem.eql(u8, unesc_buf[0..un], &s3)) return error.RoundtripBytes;

    std.debug.print("jsonl_format: 8/8 ok\n", .{});
}
