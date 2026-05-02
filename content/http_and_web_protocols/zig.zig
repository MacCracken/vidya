// Vidya — HTTP and Web Protocols in Zig
//
// HTTP/1.1 request parser, sequential.

const std = @import("std");

const HEADER_CAP: usize = 16;
const STR_CAP: usize = 256;
const BODY_CAP: usize = 1024;

const Request = struct {
    method: [16]u8 = undefined,
    method_len: usize = 0,
    path: [STR_CAP]u8 = undefined,
    path_len: usize = 0,
    version: [16]u8 = undefined,
    version_len: usize = 0,
    headers_name: [HEADER_CAP][STR_CAP]u8 = undefined,
    headers_name_len: [HEADER_CAP]usize = undefined,
    headers_value: [HEADER_CAP][STR_CAP]u8 = undefined,
    headers_value_len: [HEADER_CAP]usize = undefined,
    header_count: usize = 0,
    body: [BODY_CAP]u8 = undefined,
    body_len: usize = 0,
};

fn find_crlf(buf: []const u8, start: usize) ?usize {
    var i = start;
    while (i + 1 < buf.len) : (i += 1) {
        if (buf[i] == '\r' and buf[i + 1] == '\n') return i;
    }
    return null;
}

fn to_lower(b: u8) u8 {
    if (b >= 'A' and b <= 'Z') return b + 32;
    return b;
}

fn parse_request(buf: []const u8, req: *Request) bool {
    req.method_len = 0;
    req.path_len = 0;
    req.version_len = 0;
    req.header_count = 0;
    req.body_len = 0;

    const rl_end = find_crlf(buf, 0) orelse return false;
    var sp1: ?usize = null;
    var i: usize = 0;
    while (i < rl_end) : (i += 1) {
        if (buf[i] == ' ') { sp1 = i; break; }
    }
    if (sp1 == null) return false;
    var sp2: ?usize = null;
    i = sp1.? + 1;
    while (i < rl_end) : (i += 1) {
        if (buf[i] == ' ') { sp2 = i; break; }
    }
    if (sp2 == null) return false;

    req.method_len = sp1.?;
    @memcpy(req.method[0..req.method_len], buf[0..req.method_len]);
    req.path_len = sp2.? - sp1.? - 1;
    @memcpy(req.path[0..req.path_len], buf[sp1.? + 1 .. sp2.?]);
    req.version_len = rl_end - sp2.? - 1;
    @memcpy(req.version[0..req.version_len], buf[sp2.? + 1 .. rl_end]);

    var pos = rl_end + 2;
    while (true) {
        if (pos + 1 >= buf.len) return false;
        if (buf[pos] == '\r' and buf[pos + 1] == '\n') {
            pos += 2;
            const bl = @min(buf.len - pos, BODY_CAP);
            req.body_len = bl;
            if (bl > 0) @memcpy(req.body[0..bl], buf[pos .. pos + bl]);
            return true;
        }
        const line_end = find_crlf(buf, pos) orelse return false;
        var colon: ?usize = null;
        i = pos;
        while (i < line_end) : (i += 1) {
            if (buf[i] == ':') { colon = i; break; }
        }
        if (colon == null) return false;
        if (req.header_count >= HEADER_CAP) return false;
        const name_len = colon.? - pos;
        var k: usize = 0;
        while (k < name_len) : (k += 1) {
            req.headers_name[req.header_count][k] = to_lower(buf[pos + k]);
        }
        req.headers_name_len[req.header_count] = name_len;
        var vstart = colon.? + 1;
        while (vstart < line_end and buf[vstart] == ' ') vstart += 1;
        const value_len = line_end - vstart;
        @memcpy(req.headers_value[req.header_count][0..value_len], buf[vstart..line_end]);
        req.headers_value_len[req.header_count] = value_len;
        req.header_count += 1;
        pos = line_end + 2;
    }
}

fn header_lookup(req: *const Request, name: []const u8) ?[]const u8 {
    var lower: [STR_CAP]u8 = undefined;
    var i: usize = 0;
    while (i < name.len) : (i += 1) lower[i] = to_lower(name[i]);
    var h: usize = 0;
    while (h < req.header_count) : (h += 1) {
        if (req.headers_name_len[h] == name.len) {
            if (std.mem.eql(u8, req.headers_name[h][0..name.len], lower[0..name.len])) {
                return req.headers_value[h][0..req.headers_value_len[h]];
            }
        }
    }
    return null;
}

pub fn main() !void {
    var r: Request = .{};

    const req1 = "GET /index.html HTTP/1.1\r\nHost: example.com\r\n\r\n";
    if (!parse_request(req1, &r)) return error.Req1;
    if (!std.mem.eql(u8, r.method[0..r.method_len], "GET")) return error.Method;
    if (!std.mem.eql(u8, r.path[0..r.path_len], "/index.html")) return error.Path;
    if (!std.mem.eql(u8, r.version[0..r.version_len], "HTTP/1.1")) return error.Version;
    if (r.header_count != 1) return error.HdrCount;

    for ([_][]const u8{ "host", "HOST", "Host" }) |n| {
        const v = header_lookup(&r, n) orelse return error.HdrLookup;
        if (!std.mem.eql(u8, v, "example.com")) return error.HostValue;
    }

    const req3 = "GET / HTTP/1.1\r\nHost: x\r\nUser-Agent: test/1.0\r\nAccept: */*\r\n\r\n";
    if (!parse_request(req3, &r)) return error.Req3;
    if (r.header_count != 3) return error.Hdr3Count;
    const ua = header_lookup(&r, "user-agent") orelse return error.UA;
    if (!std.mem.eql(u8, ua, "test/1.0")) return error.UAValue;

    const req4 = "POST /api HTTP/1.1\r\nContent-Length: 11\r\n\r\nhello world";
    if (!parse_request(req4, &r)) return error.Req4;
    if (!std.mem.eql(u8, r.method[0..r.method_len], "POST")) return error.Post;
    if (!std.mem.eql(u8, r.body[0..r.body_len], "hello world")) return error.Body;

    const req5 = "POST /a HTTP/1.1\r\nContent-Length: 13\r\n\r\nline1\r\nline2!";
    if (!parse_request(req5, &r)) return error.Req5;
    if (r.body_len != 13) return error.Body5Len;
    if (!std.mem.eql(u8, r.body[0..r.body_len], "line1\r\nline2!")) return error.Body5;

    const req6 = "GET / HTTP/1.1\r\nHost: x\r\n";
    if (parse_request(req6, &r)) return error.MalformedAccepted;

    _ = parse_request(req1, &r);
    if (header_lookup(&r, "authorization") != null) return error.Absent;

    std.debug.print("http_and_web_protocols: 24/24 ok\n", .{});
}
