// Vidya — DNS in Zig
//
// In-memory resolver: zone, CNAME chains, TTL cache, negative cache.

const std = @import("std");

const RR_A: i32 = 1;
const RR_AAAA: i32 = 2;
const RR_CNAME: i32 = 3;
const RR_MX: i32 = 4;
const RR_TXT: i32 = 5;

const CNAME_MAX_DEPTH: i32 = 16;
const NXDOMAIN: i64 = -1;
const NEGATIVE_TTL: i64 = 300;

const ZONE_CAP: usize = 64;
const CACHE_CAP: usize = 32;

const Record = struct { name: u64, rtype: i32, ttl: i64, value: i64 };
const CacheEntry = struct { name: u64, rtype: i32, value: i64, expires: i64 };

var zone: [ZONE_CAP]Record = undefined;
var zone_count: usize = 0;
var cache: [CACHE_CAP]CacheEntry = undefined;
var cache_count: usize = 0;
var now_clock: i64 = 0;
var last_status: i32 = 0;

fn zone_add(name: u64, rtype: i32, ttl: i64, value: i64) void {
    if (zone_count < ZONE_CAP) {
        zone[zone_count] = .{ .name = name, .rtype = rtype, .ttl = ttl, .value = value };
        zone_count += 1;
    }
}

fn zone_lookup(name: u64, rtype: i32) i64 {
    var depth: i32 = 0;
    var cur = name;
    while (depth <= CNAME_MAX_DEPTH) {
        var i: usize = 0;
        while (i < zone_count) : (i += 1) {
            if (zone[i].name == cur and zone[i].rtype == rtype) return zone[i].value;
        }
        if (rtype == RR_A) {
            var cn: u64 = 0;
            i = 0;
            while (i < zone_count) : (i += 1) {
                if (zone[i].name == cur and zone[i].rtype == RR_CNAME) {
                    cn = @intCast(zone[i].value);
                    break;
                }
            }
            if (cn == 0) return NXDOMAIN;
            cur = cn;
            depth += 1;
        } else {
            return NXDOMAIN;
        }
    }
    return NXDOMAIN;
}

fn cache_init() void { cache_count = 0; now_clock = 0; }
fn advance_time(s: i64) void { now_clock += s; }

fn cache_insert(name: u64, rtype: i32, value: i64, ttl: i64) void {
    const exp = now_clock + ttl;
    var i: usize = 0;
    while (i < cache_count) : (i += 1) {
        if (cache[i].name == name and cache[i].rtype == rtype) {
            cache[i].value = value;
            cache[i].expires = exp;
            return;
        }
    }
    if (cache_count < CACHE_CAP) {
        cache[cache_count] = .{ .name = name, .rtype = rtype, .value = value, .expires = exp };
        cache_count += 1;
    }
}

fn cache_lookup(name: u64, rtype: i32) i64 {
    var i: usize = 0;
    while (i < cache_count) : (i += 1) {
        if (cache[i].name == name and cache[i].rtype == rtype and cache[i].expires > now_clock) {
            last_status = 1;
            return cache[i].value;
        }
    }
    last_status = 0;
    return NXDOMAIN;
}

fn resolve(name: u64, rtype: i32) i64 {
    const cached = cache_lookup(name, rtype);
    if (last_status == 1) return cached;
    const v = zone_lookup(name, rtype);
    if (v == NXDOMAIN) {
        cache_insert(name, rtype, NXDOMAIN, NEGATIVE_TTL);
        return NXDOMAIN;
    }
    var ttl: i64 = NEGATIVE_TTL;
    var i: usize = 0;
    while (i < zone_count) : (i += 1) {
        if (zone[i].name == name and zone[i].rtype == rtype) { ttl = zone[i].ttl; break; }
    }
    cache_insert(name, rtype, v, ttl);
    return v;
}

pub fn main() !void {
    zone_add(1, RR_A, 300, 0x7F000001);
    zone_add(1, RR_MX, 3600, 10);
    zone_add(1, RR_TXT, 60, 99);
    zone_add(2, RR_CNAME, 600, 1);
    zone_add(3, RR_CNAME, 600, 4);
    zone_add(4, RR_A, 60, 0x08080808);
    zone_add(5, RR_A, 3600, 0x0A000001);
    zone_add(10, RR_CNAME, 600, 11);
    zone_add(11, RR_CNAME, 600, 10);
    var k: u64 = 20;
    while (k <= 36) : (k += 1) zone_add(k, RR_CNAME, 600, @intCast(k + 1));
    zone_add(37, RR_A, 60, 0x12345678);

    if (zone_lookup(1, RR_A) != 0x7F000001) return error.A1;
    if (zone_lookup(2, RR_A) != 0x7F000001) return error.Cname;
    if (zone_lookup(3, RR_A) != 0x08080808) return error.Cname2;
    if (zone_lookup(10, RR_A) != NXDOMAIN) return error.Loop;
    if (zone_lookup(20, RR_A) != NXDOMAIN) return error.Deep;

    cache_init();
    const first = resolve(1, RR_A);
    if (last_status != 0) return error.FirstMiss;
    const second = resolve(1, RR_A);
    if (last_status != 1) return error.SecondHit;
    if (second != first) return error.Same;

    advance_time(301);
    const third = resolve(1, RR_A);
    if (last_status != 0) return error.Expired;
    if (third != 0x7F000001) return error.Requery;

    cache_init();
    if (resolve(99, RR_A) != NXDOMAIN) return error.Nxdomain;
    _ = resolve(99, RR_A);
    if (last_status != 1) return error.NegCache;

    if (zone_lookup(1, RR_MX) != 10) return error.MX;
    if (zone_lookup(1, RR_TXT) != 99) return error.TXT;
    if (zone_lookup(1, RR_AAAA) != NXDOMAIN) return error.AAAA;

    std.debug.print("dns: 15/15 ok\n", .{});
}
