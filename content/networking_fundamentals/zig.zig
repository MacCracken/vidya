// Vidya — Networking Fundamentals in Zig
//
// In-memory simulation of TCP socket state machine + lifecycle.

const std = @import("std");

const ST_CLOSED: u8 = 0;
const ST_LISTEN: u8 = 1;
const ST_ESTABLISHED: u8 = 3;
const ST_FIN_WAIT: u8 = 4;

const SOCK_CAP: usize = 8;
const BUF_CAP: usize = 256;

var state: [SOCK_CAP]u8 = @splat(ST_CLOSED);
var port_arr: [SOCK_CAP]u16 = @splat(0);
var peer: [SOCK_CAP]usize = @splat(0);
var rxbuf: [SOCK_CAP][BUF_CAP]u8 = @splat(@splat(0));
var rxlen: [SOCK_CAP]usize = @splat(0);
// Linear-scan port-to-sock map. It began as a workaround: on the Zig of
// vidya 2.4.0, @memset of a 65536-entry global table tripped "emit MIR
// failed: InvalidInstruction". That no longer reproduces on Zig 0.17 (a
// [65536]usize global @memset builds and runs in Debug and ReleaseFast).
// It stays because with only SOCK_CAP sockets we can never have more than
// SOCK_CAP active ports anyway: 8 entries, not 512 KiB.
var pmap_port: [SOCK_CAP]u16 = @splat(0);
var pmap_sock: [SOCK_CAP]usize = @splat(0);
var pmap_count: usize = 0;
var next_free: usize = 1;

fn pmap_lookup(p: u16) usize {
    var i: usize = 0;
    while (i < pmap_count) : (i += 1) {
        if (pmap_port[i] == p and pmap_sock[i] != 0) return pmap_sock[i];
    }
    return 0;
}

fn pmap_insert(p: u16, s: usize) void {
    var i: usize = 0;
    while (i < pmap_count) : (i += 1) {
        if (pmap_sock[i] == 0) {
            pmap_port[i] = p;
            pmap_sock[i] = s;
            return;
        }
    }
    if (pmap_count < SOCK_CAP) {
        pmap_port[pmap_count] = p;
        pmap_sock[pmap_count] = s;
        pmap_count += 1;
    }
}

fn pmap_remove(p: u16) void {
    var i: usize = 0;
    while (i < pmap_count) : (i += 1) {
        if (pmap_port[i] == p) {
            pmap_sock[i] = 0;
            return;
        }
    }
}

fn net_init() void {
    state = @splat(ST_CLOSED);
    port_arr = @splat(0);
    peer = @splat(0);
    rxlen = @splat(0);
    pmap_port = @splat(0);
    pmap_sock = @splat(0);
    pmap_count = 0;
    next_free = 1;
}

fn sock_create() usize {
    var i = next_free;
    while (i < SOCK_CAP) : (i += 1) {
        if (state[i] == ST_CLOSED and port_arr[i] == 0) {
            next_free = i + 1;
            return i;
        }
    }
    return 0;
}

fn state_get(s: usize) i32 {
    if (s == 0 or s >= SOCK_CAP) return -1;
    return @intCast(state[s]);
}

fn sock_bind(s: usize, p: u16) bool {
    if (s == 0 or s >= SOCK_CAP) return false;
    if (pmap_lookup(p) != 0) return false;
    if (port_arr[s] != 0) return false;
    port_arr[s] = p;
    pmap_insert(p, s);
    return true;
}

fn sock_listen(s: usize) bool {
    if (s == 0 or s >= SOCK_CAP) return false;
    if (state[s] != ST_CLOSED or port_arr[s] == 0) return false;
    state[s] = ST_LISTEN;
    return true;
}

fn sock_connect(client: usize, p: u16) bool {
    if (client == 0 or client >= SOCK_CAP) return false;
    const server = pmap_lookup(p);
    if (server == 0 or state[server] != ST_LISTEN) return false;
    state[client] = ST_ESTABLISHED;
    state[server] = ST_ESTABLISHED;
    peer[client] = server;
    peer[server] = client;
    return true;
}

fn sock_send_byte(s: usize, b: u8) bool {
    if (s == 0 or s >= SOCK_CAP or state[s] != ST_ESTABLISHED) return false;
    const p = peer[s];
    if (p == 0 or rxlen[p] >= BUF_CAP) return false;
    rxbuf[p][rxlen[p]] = b;
    rxlen[p] += 1;
    return true;
}

fn sock_recv_byte(s: usize) i32 {
    if (s == 0 or s >= SOCK_CAP) return -1;
    const st = state[s];
    if (st != ST_ESTABLISHED and st != ST_FIN_WAIT) return -1;
    if (rxlen[s] == 0) return -1;
    const b = rxbuf[s][0];
    var i: usize = 0;
    while (i < rxlen[s] - 1) : (i += 1) rxbuf[s][i] = rxbuf[s][i + 1];
    rxlen[s] -= 1;
    return @intCast(b);
}

fn sock_close(s: usize) bool {
    if (s == 0 or s >= SOCK_CAP or state[s] == ST_CLOSED) return false;
    if (port_arr[s] != 0) pmap_remove(port_arr[s]);
    state[s] = ST_CLOSED;
    port_arr[s] = 0;
    peer[s] = 0;
    return true;
}

pub fn main() !void {
    net_init();

    const srv = sock_create();
    if (state_get(srv) != ST_CLOSED) return error.InitClosed;

    if (!sock_bind(srv, 8080)) return error.Bind;
    if (!sock_listen(srv)) return error.Listen;
    if (state_get(srv) != ST_LISTEN) return error.ListenState;

    const cli = sock_create();
    if (!sock_connect(cli, 8080)) return error.Connect;
    if (state_get(cli) != ST_ESTABLISHED) return error.CliEst;
    if (state_get(srv) != ST_ESTABLISHED) return error.SrvEst;

    if (!sock_send_byte(cli, 65)) return error.SendA;
    if (!sock_send_byte(cli, 66)) return error.SendB;
    if (sock_recv_byte(srv) != 65) return error.RecvA;
    if (sock_recv_byte(srv) != 66) return error.RecvB;
    if (sock_recv_byte(srv) != -1) return error.Empty;
    if (!sock_send_byte(srv, 67)) return error.Echo;
    if (sock_recv_byte(cli) != 67) return error.CliRecv;

    if (!sock_close(cli)) return error.Close;
    if (state_get(cli) != ST_CLOSED) return error.Closed;

    const srv2 = sock_create();
    if (sock_bind(srv2, 8080)) return error.PortReuse;

    if (sock_recv_byte(cli) != -1) return error.RecvClosed;

    _ = sock_close(srv);
    if (!sock_bind(srv2, 8080)) return error.Rebind;

    std.debug.print("networking_fundamentals: 19/19 ok\n", .{});
}
